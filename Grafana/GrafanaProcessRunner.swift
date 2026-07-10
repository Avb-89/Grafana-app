//
//  GrafanaProcessRunner.swift
//  Grafana
//
//  Created by SITIS on 7/3/26.
//

import Foundation
import Darwin

enum GrafanaManagedProcessName: String {
    case grafana
    case prometheus
    case exporter

    var displayName: String {
        switch self {
        case .grafana:
            return "Grafana"
        case .prometheus:
            return "Prometheus"
        case .exporter:
            return "Exporter"
        }
    }
}

struct GrafanaManagedProcessLaunchConfig {
    let name: GrafanaManagedProcessName
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL
    let pidFileURL: URL
    let logFileURL: URL
}

final class GrafanaProcessRunner {
    private let fileManager = FileManager.default

    func start(_ config: GrafanaManagedProcessLaunchConfig) throws -> Int32 {
        if let existingPID = readPID(from: config.pidFileURL), isProcessRunning(pid: existingPID) {
            return existingPID
        }

        try ensureExecutableExists(config.executableURL)
        try fileManager.createDirectory(at: config.workingDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: config.pidFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: config.logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = config.executableURL
        process.arguments = config.arguments
        process.currentDirectoryURL = config.workingDirectoryURL

        let logHandle = try FileHandle(forWritingTo: createLogFileIfNeeded(config.logFileURL))
        try logHandle.seekToEnd()

        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            throw GrafanaProcessRunnerError.couldNotStart(config.name.displayName, error.localizedDescription)
        }

        let pid = process.processIdentifier
        try writePID(pid, to: config.pidFileURL)

        process.terminationHandler = { _ in
            try? logHandle.close()
        }

        return pid
    }

    func stop(pidFileURL: URL) throws {
        guard let pid = readPID(from: pidFileURL) else {
            return
        }

        if isProcessRunning(pid: pid) {
            kill(pid, SIGTERM)

            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if !isProcessRunning(pid: pid) {
                    break
                }
                Thread.sleep(forTimeInterval: 0.2)
            }

            if isProcessRunning(pid: pid) {
                kill(pid, SIGKILL)
            }
        }

        try? fileManager.removeItem(at: pidFileURL)
    }

    func isRunning(pidFileURL: URL) -> Bool {
        guard let pid = readPID(from: pidFileURL) else {
            return false
        }

        return isProcessRunning(pid: pid)
    }

    func readPID(from url: URL) -> Int32? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func writePID(_ pid: Int32, to url: URL) throws {
        try "\(pid)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func isProcessRunning(pid: Int32) -> Bool {
        guard pid > 0 else {
            return false
        }

        return kill(pid, 0) == 0
    }

    private func ensureExecutableExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw GrafanaProcessRunnerError.executableNotFound(url.path)
        }

        guard fileManager.isExecutableFile(atPath: url.path) else {
            throw GrafanaProcessRunnerError.executableNotRunnable(url.path)
        }
    }

    private func createLogFileIfNeeded(_ url: URL) throws -> URL {
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        return url
    }
}

enum GrafanaProcessRunnerError: LocalizedError {
    case executableNotFound(String)
    case executableNotRunnable(String)
    case couldNotStart(String, String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Исполняемый файл не найден: \(path)"
        case .executableNotRunnable(let path):
            return "Файл найден, но не исполняемый: \(path)"
        case .couldNotStart(let name, let reason):
            return "Не удалось запустить \(name): \(reason)"
        }
    }
}
