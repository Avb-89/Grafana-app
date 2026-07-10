//
//  UpdateManager.swift
//  Grafana
//
//  Created by SITIS on 7/3/26.
//

import Foundation

final class GrafanaInstaller {
    private let manager: GrafanaManager
    private let fileManager = FileManager.default

    private let grafanaPackage = ComponentPackage(
        name: "Grafana Enterprise",
        version: "13.1.0",
        archiveName: "grafana-enterprise_13.1.0_28013217238_darwin_arm64.tar.gz",
        downloadURL: URL(string: "https://dl.grafana.com/grafana-enterprise/release/13.1.0/grafana-enterprise_13.1.0_28013217238_darwin_arm64.tar.gz")!,
        markerRelativePath: "bin/grafana"
    )

    private let prometheusPackage = ComponentPackage(
        name: "Prometheus",
        version: "3.13.0",
        archiveName: "prometheus-3.13.0.darwin-arm64.tar.gz",
        downloadURL: URL(string: "https://github.com/prometheus/prometheus/releases/download/v3.13.0/prometheus-3.13.0.darwin-arm64.tar.gz")!,
        markerRelativePath: "prometheus"
    )

    init(manager: GrafanaManager = .shared) {
        self.manager = manager
    }

    var updatesURL: URL {
        manager.workspaceURL.appendingPathComponent("updates", isDirectory: true)
    }

    var downloadsURL: URL {
        updatesURL.appendingPathComponent("downloads", isDirectory: true)
    }

    var stagingURL: URL {
        updatesURL.appendingPathComponent("staging", isDirectory: true)
    }

    var backupsURL: URL {
        manager.workspaceURL.appendingPathComponent("backups", isDirectory: true)
    }

    var updateLogsURL: URL {
        updatesURL.appendingPathComponent("logs", isDirectory: true)
    }

    var updateToolLogURL: URL {
        updateLogsURL.appendingPathComponent("update-tools.log")
    }

    func prepareUpdateWorkspace() throws {
        let directories = [
            updatesURL,
            downloadsURL,
            stagingURL,
            backupsURL,
            updateLogsURL
        ]

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func currentVersions() -> ComponentVersions {
        ComponentVersions(
            grafana: runVersionCommand(executableURL: manager.grafanaBinaryURL),
            prometheus: runVersionCommand(executableURL: manager.prometheusBinaryURL)
        )
    }

    func updatePlanText() -> String {
        let versions = currentVersions()

        return """
        Текущие версии:
        Grafana: \(versions.grafana ?? "не найдена")
        Prometheus: \(versions.prometheus ?? "не найден")

        Обновление будет выполняться только вручную и только внутри Grafana.app:
        \(manager.workspaceURL.path)

        Папки обновления:
        downloads: \(downloadsURL.path)
        staging:   \(stagingURL.path)
        backups:   \(backupsURL.path)
        logs:      \(updateLogsURL.path)
        """
    }

    func checkUpdatesPlaceholder() throws -> String {
        try prepareUpdateWorkspace()

        let versions = currentVersions()

        return """
        Проверка готова.

        Целевые версии для установки внутрь Grafana.app:
        Grafana Enterprise: \(grafanaPackage.version)
        Prometheus: \(prometheusPackage.version)

        Сейчас установлено:
        Grafana: \(versions.grafana ?? "не найдена")
        Prometheus: \(versions.prometheus ?? "не найден")

        Архивы будут скачаны сюда:
        \(downloadsURL.path)

        Распаковка будет только тут:
        \(stagingURL.path)

        Установка будет только сюда:
        \(manager.workspaceURL.path)

        Логи обновления:
        \(updateLogsURL.path)
        """
    }

    func updateComponentsPlaceholder(progress: ((Double, String) -> Void)? = nil) throws -> String {
        progress?(0.01, "Готовлю папки обновления...")
        try prepareUpdateWorkspace()
        resetUpdateToolLog()
        appendUpdateToolLog("=== Start component update: \(Date()) ===")

        progress?(0.04, "Останавливаю Grafana и Prometheus...")
        try manager.stopAll()

        progress?(0.08, "Делаю backup текущих компонентов...")
        let backupURL = try makeBackup()

        progress?(0.14, "Скачиваю Grafana Enterprise \(grafanaPackage.version). Это может занять до 30 минут...")
        let grafanaArchiveURL = try downloadArchiveIfNeeded(
            grafanaPackage,
            progress: progress,
            progressStartValue: 0.14,
            progressEndValue: 0.30,
            message: "Grafana Enterprise \(grafanaPackage.version) скачана или уже была в кэше."
        )

        progress?(0.32, "Скачиваю Prometheus \(prometheusPackage.version). Это может занять до 30 минут...")
        let prometheusArchiveURL = try downloadArchiveIfNeeded(
            prometheusPackage,
            progress: progress,
            progressStartValue: 0.32,
            progressEndValue: 0.48,
            message: "Prometheus \(prometheusPackage.version) скачан или уже был в кэше."
        )

        progress?(0.50, "Распаковываю Grafana Enterprise \(grafanaPackage.version)...")
        let grafanaSourceURL = try extractArchive(grafanaArchiveURL, package: grafanaPackage)

        progress?(0.62, "Распаковываю Prometheus \(prometheusPackage.version)...")
        let prometheusSourceURL = try extractArchive(prometheusArchiveURL, package: prometheusPackage)

        progress?(0.72, "Обновляю Grafana внутри приложения...")
        try replaceDirectory(
            at: manager.grafanaURL,
            with: grafanaSourceURL,
            preservingChildren: ["data", "logs", "plugins", "provisioning"]
        )

        progress?(0.82, "Обновляю Prometheus внутри приложения...")
        try replaceDirectory(
            at: manager.prometheusURL,
            with: prometheusSourceURL,
            preservingChildren: ["data", "prometheus.yml"]
        )

        progress?(0.90, "Выставляю права запуска для Grafana и Prometheus...")
        try makeExecutable(manager.grafanaBinaryURL)
        try makeExecutable(manager.prometheusBinaryURL)

        progress?(0.95, "Проверяю установленные версии...")
        let versions = currentVersions()

        progress?(0.98, "Очищаю временную распаковку staging...")
        try clearStagingAfterSuccessfulUpdate()

        appendUpdateToolLog("=== Component update finished: \(Date()) ===")
        progress?(1.0, "Компоненты установлены. Можно запускать Grafana.")

        return """
        Компоненты установлены внутрь Grafana.app.

        Backup старых компонентов:
        \(backupURL.path)

        Установлено:
        Grafana: \(versions.grafana ?? "не найдена")
        Prometheus: \(versions.prometheus ?? "не найден")

        Workspace:
        \(manager.workspaceURL.path)

        Лог обновления:
        \(updateToolLogURL.path)

        Временная staging-папка очищена после успешной установки.
        """
    }

    func makeBackup() throws -> URL {
        try prepareUpdateWorkspace()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let backupURL = backupsURL.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)

        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: manager.grafanaURL.path) {
            try copyDirectoryIfExists(from: manager.grafanaURL, to: backupURL.appendingPathComponent("grafana", isDirectory: true))
        }

        if fileManager.fileExists(atPath: manager.prometheusURL.path) {
            try copyDirectoryIfExists(from: manager.prometheusURL, to: backupURL.appendingPathComponent("prometheus", isDirectory: true))
        }

        return backupURL
    }

    private func runVersionCommand(executableURL: URL) -> String? {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "ошибка запуска: \(error.localizedDescription)"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return output?.isEmpty == false ? output : nil
    }

    private func downloadArchiveIfNeeded(
        _ package: ComponentPackage,
        progress: ((Double, String) -> Void)? = nil,
        progressStartValue: Double,
        progressEndValue: Double,
        message: String
    ) throws -> URL {
        let archiveURL = downloadsURL.appendingPathComponent(package.archiveName)

        if fileManager.fileExists(atPath: archiveURL.path) {
            appendUpdateToolLog("Archive already exists: \(archiveURL.path)")
            progress?(progressEndValue, message)
            return archiveURL
        }

        appendUpdateToolLog("Downloading \(package.name) from \(package.downloadURL.absoluteString)")
        progress?(progressStartValue, "Скачиваю \(package.name) \(package.version)...")

        try runCurlDownload(
            package: package,
            destinationURL: archiveURL,
            progress: progress,
            progressStartValue: progressStartValue,
            progressEndValue: progressEndValue
        )

        appendUpdateToolLog("Downloaded archive: \(archiveURL.path)")
        progress?(progressEndValue, message)
        return archiveURL
    }

    private func runCurlDownload(
        package: ComponentPackage,
        destinationURL: URL,
        progress: ((Double, String) -> Void)?,
        progressStartValue: Double,
        progressEndValue: Double
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--location",
            "--fail",
            "--show-error",
            "--progress-meter",
            "--output", destinationURL.path,
            package.downloadURL.absoluteString
        ]
        process.currentDirectoryURL = downloadsURL

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        let logQueue = DispatchQueue(label: "grafana.update.curl.log")
        var lastProgressText = ""

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                logQueue.async {
                    self?.appendUpdateToolLog(text)
                }

                let visibleProgress = self?.visibleCurlProgress(from: text) ?? text
                if !visibleProgress.isEmpty {
                    lastProgressText = visibleProgress
                    let percent = self?.curlPercent(from: visibleProgress)
                    let mappedProgress: Double
                    if let percent {
                        let boundedPercent = min(max(percent, 0), 100)
                        mappedProgress = progressStartValue + (progressEndValue - progressStartValue) * (boundedPercent / 100.0)
                    } else {
                        mappedProgress = progressStartValue
                    }

                    DispatchQueue.main.async {
                        progress?(mappedProgress, "Скачиваю \(package.name) \(package.version)...\n\(visibleProgress)")
                    }
                }
            }
        }

        appendUpdateToolLog("RUN: /usr/bin/curl \(process.arguments?.joined(separator: " ") ?? "")")

        try process.run()
        process.waitUntilExit()
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            let output = (try? String(contentsOf: updateToolLogURL, encoding: .utf8)) ?? lastProgressText
            throw GrafanaInstallerError.toolFailed("/usr/bin/curl", process.terminationStatus, output)
        }
    }

    private func visibleCurlProgress(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return normalized.last ?? ""
    }

    private func curlPercent(from text: String) -> Double? {
        guard let percentRange = text.range(of: #"\d+(\.\d+)?%"#, options: .regularExpression) else {
            return nil
        }

        let raw = text[percentRange]
            .replacingOccurrences(of: "%", with: "")

        return Double(raw)
    }

    private func extractArchive(_ archiveURL: URL, package: ComponentPackage) throws -> URL {
        appendUpdateToolLog("Extracting \(package.name): \(archiveURL.path)")
        let packageStagingURL = stagingURL.appendingPathComponent(package.safeFolderName, isDirectory: true)

        if fileManager.fileExists(atPath: packageStagingURL.path) {
            try fileManager.removeItem(at: packageStagingURL)
        }

        try fileManager.createDirectory(at: packageStagingURL, withIntermediateDirectories: true)

        _ = try runTool(
            executablePath: "/usr/bin/tar",
            arguments: ["-xzf", archiveURL.path, "-C", packageStagingURL.path],
            currentDirectoryURL: packageStagingURL
        )

        let extractedURL = try firstDirectory(in: packageStagingURL, containing: package.markerRelativePath)
        appendUpdateToolLog("Extracted \(package.name) to \(extractedURL.path)")
        return extractedURL
    }

    private func firstDirectory(in rootURL: URL, containing relativePath: String) throws -> URL {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw GrafanaInstallerError.directoryEnumerationFailed(rootURL.path)
        }

        for case let candidateURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let markerURL = candidateURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: markerURL.path) {
                return candidateURL
            }
        }

        throw GrafanaInstallerError.markerNotFound(relativePath, rootURL.path)
    }

    private func replaceDirectory(at destinationURL: URL, with sourceURL: URL, preservingChildren namesToPreserve: [String]) throws {
        appendUpdateToolLog("Replacing \(destinationURL.path) with \(sourceURL.path)")
        let preserveRootURL = stagingURL
            .appendingPathComponent("preserve", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: preserveRootURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            for childName in namesToPreserve {
                let currentChildURL = destinationURL.appendingPathComponent(childName)
                guard fileManager.fileExists(atPath: currentChildURL.path) else {
                    continue
                }

                let preservedChildURL = preserveRootURL.appendingPathComponent(childName)
                try fileManager.moveItem(at: currentChildURL, to: preservedChildURL)
            }

            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let preservedChildren = try fileManager.contentsOfDirectory(at: preserveRootURL, includingPropertiesForKeys: nil)
        for preservedChildURL in preservedChildren {
            let targetURL = destinationURL.appendingPathComponent(preservedChildURL.lastPathComponent)

            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }

            try fileManager.moveItem(at: preservedChildURL, to: targetURL)
        }

        appendUpdateToolLog("Replaced directory: \(destinationURL.path)")
    }

    private func makeExecutable(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw GrafanaInstallerError.executableNotFound(url.path)
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func runTool(executablePath: String, arguments: [String], currentDirectoryURL: URL? = nil) throws -> String {
        appendUpdateToolLog("RUN: \(executablePath) \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        guard let logHandle = try? FileHandle(forWritingTo: updateToolLogURL) else {
            throw GrafanaInstallerError.logFileOpenFailed(updateToolLogURL.path)
        }
        try logHandle.seekToEnd()

        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()
        try? logHandle.close()

        guard process.terminationStatus == 0 else {
            let output = (try? String(contentsOf: updateToolLogURL, encoding: .utf8)) ?? ""
            throw GrafanaInstallerError.toolFailed(executablePath, process.terminationStatus, output)
        }

        return (try? String(contentsOf: updateToolLogURL, encoding: .utf8)) ?? ""
    }

    private func clearStagingAfterSuccessfulUpdate() throws {
        appendUpdateToolLog("Cleaning staging after successful update: \(stagingURL.path)")
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
    }

    private func resetUpdateToolLog() {
        try? fileManager.createDirectory(at: updateLogsURL, withIntermediateDirectories: true)
        try? "".write(to: updateToolLogURL, atomically: true, encoding: .utf8)
    }

    private func appendUpdateToolLog(_ text: String) {
        try? fileManager.createDirectory(at: updateLogsURL, withIntermediateDirectories: true)
        let normalizedText = text.hasSuffix("\n") ? text : "\(text)\n"

        if !fileManager.fileExists(atPath: updateToolLogURL.path) {
            try? normalizedText.write(to: updateToolLogURL, atomically: true, encoding: .utf8)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: updateToolLogURL) else {
            return
        }

        try? handle.seekToEnd()
        if let data = normalizedText.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
        try? handle.close()
    }

    private func copyDirectoryIfExists(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
    }
}

struct ComponentVersions {
    let grafana: String?
    let prometheus: String?
}

private struct ComponentPackage {
    let name: String
    let version: String
    let archiveName: String
    let downloadURL: URL
    let markerRelativePath: String

    var safeFolderName: String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}

enum GrafanaInstallerError: LocalizedError {
    case directoryEnumerationFailed(String)
    case markerNotFound(String, String)
    case executableNotFound(String)
    case logFileOpenFailed(String)
    case toolFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .directoryEnumerationFailed(let path):
            return "Не удалось прочитать папку: \(path)"
        case .markerNotFound(let marker, let root):
            return "Не найден ожидаемый файл \(marker) после распаковки в \(root)"
        case .executableNotFound(let path):
            return "Исполняемый файл не найден после установки: \(path)"
        case .logFileOpenFailed(let path):
            return "Не удалось открыть лог обновления: \(path)"
        case .toolFailed(let tool, let code, let output):
            return "Команда \(tool) завершилась с кодом \(code):\n\(output)"
        }
    }
}
