//
//  GrafanaScriptManager.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import Combine
import Foundation

struct GrafanaScriptScheduleState {
    var intervalText: String
    var isActive: Bool
    var nextRunDate: Date?
}

enum GrafanaScriptScheduleStartResult {
    case started
    case invalidInterval
    case alreadyActive
}

@MainActor
final class GrafanaScriptManager: ObservableObject {
    @Published private(set) var runningScriptPaths: Set<String> = []
    @Published private(set) var schedules: [String: GrafanaScriptScheduleState] = [:]
    @Published private(set) var lastRunTitle = "Вывод последнего запуска"
    @Published private(set) var lastRunOutput = "Запусти скрипт, чтобы увидеть вывод."
    @Published private(set) var scriptStates: [String: String] = [:]

    private let manager: GrafanaManager
    private let fileManager: FileManager
    private var scheduleTasks: [String: Task<Void, Never>] = [:]
    private var runningProcesses: [String: Process] = [:]
    private var scheduleTextStorage: [String: String] = [:]
    private let scheduleTextsDefaultsKey = "grafana.script.schedule.texts.v1"

    init(manager: GrafanaManager = .shared, fileManager: FileManager = .default) {
        self.manager = manager
        self.fileManager = fileManager
        self.scheduleTextStorage = Self.loadScheduleTexts(defaultsKey: scheduleTextsDefaultsKey)
    }

    var hasRunningScripts: Bool {
        !runningScriptPaths.isEmpty
    }

    var hasSchedules: Bool {
        !schedules.isEmpty
    }

    // MARK: - Script files

    func scriptFiles() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: manager.scriptsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { isImportableScript($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func previewText(for url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func exportScriptsArchive(to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runCommand(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", manager.scriptsURL.path, destinationURL.path]
        )
    }

    func importScriptItems(_ urls: [URL]) throws -> Int {
        var importedCount = 0

        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                importedCount += try importScriptsFromZip(url)
                continue
            }

            if isDirectory(url) {
                importedCount += try importScriptsFromDirectory(url)
                continue
            }

            if isImportableScript(url) {
                try importSingleScript(url)
                importedCount += 1
            }
        }

        return importedCount
    }

    func importScriptsFromZip(_ zipURL: URL) throws -> Int {
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("grafana-scripts-import-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        try runCommand(executable: "/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, temporaryDirectory.path])
        return try importScriptsFromDirectory(temporaryDirectory)
    }

    func importScriptsFromDirectory(_ directoryURL: URL) throws -> Int {
        let candidates = try scriptImportCandidates(in: directoryURL)
        var importedCount = 0

        for candidate in candidates {
            try importSingleScript(candidate)
            importedCount += 1
        }

        return importedCount
    }

    // MARK: - Script running

    func isRunning(_ url: URL) -> Bool {
        runningScriptPaths.contains(url.path)
    }

    func state(for url: URL) -> String {
        scriptStates[url.path] ?? "Готов"
    }

    func schedule(for url: URL) -> GrafanaScriptScheduleState? {
        schedules[url.path]
    }

    func scheduleText(for url: URL) -> String {
        scheduleTextStorage[url.path] ?? ""
    }

    func updateScheduleText(_ text: String, for url: URL) {
        scheduleTextStorage[url.path] = text
        Self.saveScheduleTexts(scheduleTextStorage, defaultsKey: scheduleTextsDefaultsKey)
    }

    func runScript(_ url: URL) {
        guard !isRunning(url) else {
            scriptStates[url.path] = "Уже выполняется"
            return
        }

        runningScriptPaths.insert(url.path)
        scriptStates[url.path] = "Выполняется"
        lastRunTitle = "Выполняется: \(url.lastPathComponent)"
        lastRunOutput = "Скрипт запущен..."

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let result = await self.executeScript(url)

            await MainActor.run {
                self.runningScriptPaths.remove(url.path)
                self.runningProcesses[url.path] = nil
                self.scriptStates[url.path] = result.success ? "Готов" : "Ошибка"
                self.lastRunTitle = result.success ? "Готово: \(url.lastPathComponent)" : "Ошибка: \(url.lastPathComponent)"
                self.lastRunOutput = result.output
            }
        }
    }

    func stopScript(_ url: URL) {
        guard let process = runningProcesses[url.path] else {
            runningScriptPaths.remove(url.path)
            scriptStates[url.path] = "Остановлен"
            return
        }

        terminateProcessTree(process)
        runningScriptPaths.remove(url.path)
        runningProcesses[url.path] = nil
        scriptStates[url.path] = "Остановлен"
        lastRunTitle = "Остановлен: \(url.lastPathComponent)"
        lastRunOutput = "Скрипт остановлен пользователем."
    }

    func stopScriptAndSchedule(_ url: URL) {
        stopScript(url)
        cancelSchedule(for: url)
    }

    // MARK: - Script schedules

    func startSchedule(for url: URL) -> GrafanaScriptScheduleStartResult {
        guard scheduleTasks[url.path] == nil else {
            return .alreadyActive
        }

        let intervalText = scheduleText(for: url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let interval = parseScheduleInterval(intervalText), interval > 0 else {
            scriptStates[url.path] = "Ошибка расписания"
            return .invalidInterval
        }

        scheduleScript(url, intervalText: intervalText, interval: interval)
        return .started
    }

    func startAllStoredSchedules(scriptFiles: [URL]) {
        for file in scriptFiles {
            let intervalText = scheduleText(for: file).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !intervalText.isEmpty else { continue }
            _ = startSchedule(for: file)
        }
    }

    func cancelSchedule(for url: URL) {
        scheduleTasks[url.path]?.cancel()
        scheduleTasks[url.path] = nil
        schedules[url.path] = nil

        if !isRunning(url) {
            scriptStates[url.path] = "Расписание остановлено"
        }
    }

    func cancelAllSchedules() {
        for task in scheduleTasks.values {
            task.cancel()
        }

        scheduleTasks.removeAll()
        schedules.removeAll()

        for path in scriptStates.keys {
            if !runningScriptPaths.contains(path) {
                scriptStates[path] = "Расписание остановлено"
            }
        }
    }

    // MARK: - Private script files

    private func scriptImportCandidates(in directoryURL: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            if url.lastPathComponent.lowercased() == "logs" {
                enumerator.skipDescendants()
                return nil
            }
            return isImportableScript(url) ? url : nil
        }
    }

    private func importSingleScript(_ sourceURL: URL) throws {
        try fileManager.createDirectory(at: manager.scriptsURL, withIntermediateDirectories: true)

        let destinationURL = uniqueScriptDestinationURL(for: sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
    }

    private func uniqueScriptDestinationURL(for fileName: String) -> URL {
        let baseURL = manager.scriptsURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        var index = 1
        while true {
            let candidateName = ext.isEmpty ? "\(name)-\(index)" : "\(name)-\(index).\(ext)"
            let candidateURL = manager.scriptsURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private func isImportableScript(_ url: URL) -> Bool {
        guard !isDirectory(url) else { return false }
        return ["sh", "zsh", "command"].contains(url.pathExtension.lowercased())
    }

    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func runCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GrafanaScriptManager.Command",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Команда завершилась с ошибкой." : output]
            )
        }
    }

    // MARK: - Private script running

    private nonisolated func executeScript(_ url: URL) async -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [url.path]
        process.currentDirectoryURL = url.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        environment["GRAFANA_APP_WORKSPACE"] = GrafanaManager.shared.workspaceURL.path
        environment["GRAFANA_APP_SCRIPTS"] = GrafanaManager.shared.scriptsURL.path
        environment["GRAFANA_APP_MONITORING"] = GrafanaManager.shared.monitoringURL.path
        environment["GRAFANA_APP_METRICS_PENDING"] = GrafanaManager.shared.historyPendingURL.path
        environment["GRAFANA_APP_METRICS_HISTORY"] = GrafanaManager.shared.historyMetricsURL.path
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try await MainActor.run {
                runningProcesses[url.path] = process
                try process.run()
            }

            process.waitUntilExit()

            let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
            let stderrText = String(data: stderr, encoding: .utf8) ?? ""
            let combinedOutput = [stdoutText, stderrText].filter { !$0.isEmpty }.joined(separator: "\n")
            let output = combinedOutput.isEmpty ? "Скрипт завершился без вывода." : combinedOutput

            try? writeScriptLog(scriptURL: url, output: output)
            return (process.terminationStatus == 0, output)
        } catch {
            let output = "Не удалось запустить скрипт: \(error.localizedDescription)"
            try? writeScriptLog(scriptURL: url, output: output)
            return (false, output)
        }
    }

    private nonisolated func writeScriptLog(scriptURL: URL, output: String) throws {
        let logsURL = GrafanaManager.shared.scriptsURL.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "\(scriptURL.deletingPathExtension().lastPathComponent)-\(formatter.string(from: Date())).log"
        let logURL = logsURL.appendingPathComponent(fileName)

        try output.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func scheduleScript(_ url: URL, intervalText: String, interval: TimeInterval) {
        let nextRun = Date().addingTimeInterval(interval)
        schedules[url.path] = GrafanaScriptScheduleState(intervalText: intervalText, isActive: true, nextRunDate: nextRun)
        scriptStates[url.path] = "Расписание активно"

        let task = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.runScript(url)
                    self.schedules[url.path]?.nextRunDate = Date().addingTimeInterval(interval)
                }
            }
        }

        scheduleTasks[url.path] = task
    }

    private func parseScheduleInterval(_ text: String) -> TimeInterval? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if let seconds = TimeInterval(normalized), seconds > 0 {
            return seconds
        }

        let pattern = #"(\d+(?:\.\d+)?)([smhd])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: range)

        guard !matches.isEmpty else { return nil }

        var total: TimeInterval = 0
        var matchedText = ""

        for match in matches {
            guard
                let valueRange = Range(match.range(at: 1), in: normalized),
                let unitRange = Range(match.range(at: 2), in: normalized),
                let value = TimeInterval(normalized[valueRange])
            else {
                return nil
            }

            let unit = String(normalized[unitRange])
            matchedText += String(normalized[Range(match.range, in: normalized)!])

            switch unit {
            case "s": total += value
            case "m": total += value * 60
            case "h": total += value * 60 * 60
            case "d": total += value * 60 * 60 * 24
            default: return nil
            }
        }

        guard matchedText == normalized, total > 0 else { return nil }
        return total
    }

    private func terminateProcessTree(_ process: Process) {
        let pid = process.processIdentifier
        let childPIDs = childProcessIDs(parentPID: pid)

        for childPID in childPIDs {
            kill(childPID, SIGTERM)
        }

        process.terminate()
    }

    private func childProcessIDs(parentPID: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .split(separator: "\n")
            .compactMap { line -> Int32? in
                let parts = line.split(separator: " ").compactMap { Int32($0) }
                guard parts.count == 2, parts[1] == parentPID else { return nil }
                return parts[0]
            }
    }

    private static func loadScheduleTexts(defaultsKey: String) -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private static func saveScheduleTexts(_ values: [String: String], defaultsKey: String) {
        UserDefaults.standard.set(values, forKey: defaultsKey)
    }
}
