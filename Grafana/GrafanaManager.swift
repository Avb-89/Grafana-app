//
//  GrafanaManager.swift
//  Grafana
//
//  Created by SITIS on 7/3/26.
//

import Foundation
import Combine

final class GrafanaManager: ObservableObject {
    static let shared = GrafanaManager()

    let fileManager = FileManager.default
    private let processRunner = ProcessRunner()
    private var metricsImportTimer: DispatchSourceTimer?
    private let metricsImportQueue = DispatchQueue(label: "grafana.metrics.importer", qos: .utility)
    private var metricsImportInProgress = false

    private init() { }

    var appBundleURL: URL {
        Bundle.main.bundleURL
    }

    var resourcesURL: URL {
        Bundle.main.resourceURL ?? appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    }


    var workspaceURL: URL {
        appBundleURL.appendingPathComponent("Contents/Workspace", isDirectory: true)
    }

    var monitoringURL: URL {
        appBundleURL.appendingPathComponent("Contents/Monitoring", isDirectory: true)
    }

    var scriptsURL: URL {
        appBundleURL.appendingPathComponent("Contents/Scripts", isDirectory: true)
    }

    var monitoringMetricsURL: URL {
        monitoringURL.appendingPathComponent("metrics", isDirectory: true)
    }

    var historyPendingURL: URL {
        historyMetricsURL.appendingPathComponent("pending", isDirectory: true)
    }

    var historyImportedURL: URL {
        historyMetricsURL.appendingPathComponent("imported", isDirectory: true)
    }

    var historyFailedURL: URL {
        historyMetricsURL.appendingPathComponent("failed", isDirectory: true)
    }

    var historyMetricsURL: URL {
        monitoringMetricsURL.appendingPathComponent("history", isDirectory: true)
    }

    var monitoringStateURL: URL {
        monitoringURL.appendingPathComponent("state", isDirectory: true)
    }

    var statusStateURL: URL {
        monitoringStateURL.appendingPathComponent("status.json")
    }

    var importedMetricsRegistryURL: URL {
        monitoringStateURL.appendingPathComponent("imported-files.json")
    }

    var grafanaURL: URL {
        workspaceURL.appendingPathComponent("grafana", isDirectory: true)
    }

    var grafanaBinaryURL: URL {
        grafanaURL.appendingPathComponent("bin/grafana")
    }

    var grafanaConfigURL: URL {
        grafanaURL.appendingPathComponent("conf/defaults.ini")
    }

    var grafanaDataURL: URL {
        grafanaURL.appendingPathComponent("data", isDirectory: true)
    }

    var grafanaLogsURL: URL {
        grafanaURL.appendingPathComponent("logs", isDirectory: true)
    }

    var grafanaPluginsURL: URL {
        grafanaURL.appendingPathComponent("plugins", isDirectory: true)
    }

    var grafanaProvisioningURL: URL {
        grafanaURL.appendingPathComponent("provisioning", isDirectory: true)
    }

    var prometheusURL: URL {
        workspaceURL.appendingPathComponent("prometheus", isDirectory: true)
    }

    var prometheusBinaryURL: URL {
        prometheusURL.appendingPathComponent("prometheus")
    }

    var promtoolBinaryURL: URL {
        prometheusURL.appendingPathComponent("promtool")
    }

    var prometheusConfigURL: URL {
        prometheusURL.appendingPathComponent("prometheus.yml")
    }

    var prometheusDataURL: URL {
        prometheusURL.appendingPathComponent("data", isDirectory: true)
    }

    

    var runtimeURL: URL {
        logsURL
    }

    var logsURL: URL {
        workspaceURL.appendingPathComponent("logs", isDirectory: true)
    }

    var updatesURL: URL {
        workspaceURL.appendingPathComponent("updates", isDirectory: true)
    }

    var updateDownloadsURL: URL {
        updatesURL.appendingPathComponent("downloads", isDirectory: true)
    }

    var updateStagingURL: URL {
        updatesURL.appendingPathComponent("staging", isDirectory: true)
    }

    var backupsURL: URL {
        workspaceURL.appendingPathComponent("backups", isDirectory: true)
    }

    var grafanaPIDURL: URL {
        runtimeURL.appendingPathComponent("grafana.pid")
    }

    var prometheusPIDURL: URL {
        runtimeURL.appendingPathComponent("prometheus.pid")
    }

    var grafanaAdminCredentialsURL: URL {
        grafanaDataURL.appendingPathComponent("admin-credentials.txt")
    }

    func prepareWorkspace() throws {
        let directories = [
            workspaceURL,
            grafanaDataURL,
            grafanaLogsURL,
            grafanaPluginsURL,
            grafanaProvisioningURL,
            prometheusDataURL,
            logsURL,
            updatesURL,
            updateDownloadsURL,
            updateStagingURL,
            backupsURL,
            monitoringURL,
            scriptsURL,
            monitoringMetricsURL,
            historyMetricsURL,
            historyPendingURL,
            historyImportedURL,
            historyFailedURL,
            monitoringStateURL
        ]

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: statusStateURL.path) {
            try defaultStatusStateText.write(to: statusStateURL, atomically: true, encoding: .utf8)
        }

        if !fileManager.fileExists(atPath: importedMetricsRegistryURL.path) {
            try "[]".write(to: importedMetricsRegistryURL, atomically: true, encoding: .utf8)
        }

        _ = try ensureGrafanaAdminCredentials()
    }

    func metricsFilePath() -> String {
        "Scripts: \(scriptsURL.path)\nHistory pending: \(historyPendingURL.path)\nHistory imported: \(historyImportedURL.path)\nHistory failed: \(historyFailedURL.path)\nState: \(statusStateURL.path)"
    }

    func grafanaAdminCredentialsText() -> String {
        do {
            let credentials = try ensureGrafanaAdminCredentials()
            return "Grafana login: \(credentials.username)\nGrafana password: \(credentials.password)\nCredentials file: \(grafanaAdminCredentialsURL.path)"
        } catch {
            return "Не удалось подготовить Grafana admin credentials: \(error.localizedDescription)"
        }
    }

    func grafanaAdminCredentials() throws -> GrafanaAdminCredentials {
        try ensureGrafanaAdminCredentials()
    }

    func runScript(_ scriptURL: URL) throws -> String {
        throw NSError(
            domain: "GrafanaManager",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "runScript устарел. Скрипты запускаются через ScriptScheduler в ContentView."]
        )
    }
    func clearMonitoringData() throws {
        let targets = [
            historyPendingURL,
            historyImportedURL,
            historyFailedURL,
            monitoringStateURL
        ]

        for target in targets where fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }

        try fileManager.createDirectory(at: historyPendingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: historyImportedURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: historyFailedURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: monitoringStateURL, withIntermediateDirectories: true)
        try defaultStatusStateText.write(to: statusStateURL, atomically: true, encoding: .utf8)
        try "[]".write(to: importedMetricsRegistryURL, atomically: true, encoding: .utf8)
    }

    func clearUpdateCache() throws {
        try clearUpdateDownloads()
        try clearUpdateStaging()
    }

    func clearUpdateDownloads() throws {
        try removeDirectoryContents(at: updateDownloadsURL)
        try fileManager.createDirectory(at: updateDownloadsURL, withIntermediateDirectories: true)
    }

    func clearUpdateStaging() throws {
        try removeDirectoryContents(at: updateStagingURL)
        try fileManager.createDirectory(at: updateStagingURL, withIntermediateDirectories: true)
    }

    func clearBackups() throws {
        try removeDirectoryContents(at: backupsURL)
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    func appSizeText() -> String {
        do {
            let size = try directorySize(at: appBundleURL)
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } catch {
            return "не удалось посчитать"
        }
    }

    func clearPrometheusHistory() throws {
        try removeDirectoryContents(at: prometheusDataURL)
        try fileManager.createDirectory(at: prometheusDataURL, withIntermediateDirectories: true)
    }

    func resetAllMutableData() throws {
        let targets = [
            grafanaDataURL,
            grafanaLogsURL,
            grafanaPluginsURL,
            grafanaProvisioningURL,
            prometheusDataURL,
            logsURL
        ]

        for target in targets {
            try removeDirectoryContents(at: target)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        }
    }

    func requiredFilesReport() -> [RequiredFileStatus] {
        [
            RequiredFileStatus(name: "Grafana binary", url: grafanaBinaryURL, exists: fileManager.fileExists(atPath: grafanaBinaryURL.path)),
            RequiredFileStatus(name: "Grafana config", url: grafanaConfigURL, exists: fileManager.fileExists(atPath: grafanaConfigURL.path)),
            RequiredFileStatus(name: "Prometheus binary", url: prometheusBinaryURL, exists: fileManager.fileExists(atPath: prometheusBinaryURL.path)),
            RequiredFileStatus(name: "Promtool binary", url: promtoolBinaryURL, exists: fileManager.fileExists(atPath: promtoolBinaryURL.path)),
            RequiredFileStatus(name: "Prometheus config", url: prometheusConfigURL, exists: fileManager.fileExists(atPath: prometheusConfigURL.path)),
            RequiredFileStatus(name: "Scripts folder", url: scriptsURL, exists: fileManager.fileExists(atPath: scriptsURL.path)),
            RequiredFileStatus(name: "History pending folder", url: historyPendingURL, exists: fileManager.fileExists(atPath: historyPendingURL.path)),
            RequiredFileStatus(name: "History imported folder", url: historyImportedURL, exists: fileManager.fileExists(atPath: historyImportedURL.path)),
            RequiredFileStatus(name: "History failed folder", url: historyFailedURL, exists: fileManager.fileExists(atPath: historyFailedURL.path)),
            RequiredFileStatus(name: "State file", url: statusStateURL, exists: fileManager.fileExists(atPath: statusStateURL.path))
        ]
    }

    func startAll(retentionDays: Int, retentionSizeGb: Int) throws {
        do {
            try prepareWorkspace()
            try ensurePrometheusConfigExists()
            _ = try startPrometheus(retentionDays: retentionDays, retentionSizeGb: retentionSizeGb)
            _ = try startGrafana()
            startMetricsImporter(retentionDays: retentionDays, retentionSizeGb: retentionSizeGb)
        } catch {
            try? stopAll()
            throw error
        }
    }

    func stopAll() throws {
        stopMetricsImporter()
        stopManagedProcess(pidFileURL: grafanaPIDURL, tcpPort: 3000)
        stopManagedProcess(pidFileURL: prometheusPIDURL, tcpPort: 9090)
    }

    func serviceStatuses() -> GrafanaServiceStatuses {
        let grafanaPortPID = pidListening(onTCPPort: 3000)
        let prometheusPortPID = pidListening(onTCPPort: 9090)

        if let grafanaPortPID {
            writePIDFileIfNeeded(pidFileURL: grafanaPIDURL, pid: grafanaPortPID)
        }

        if let prometheusPortPID {
            writePIDFileIfNeeded(pidFileURL: prometheusPIDURL, pid: prometheusPortPID)
        }

        return GrafanaServiceStatuses(
            grafanaRunning: processRunner.isRunning(pidFileURL: grafanaPIDURL) || grafanaPortPID != nil,
            prometheusRunning: processRunner.isRunning(pidFileURL: prometheusPIDURL) || prometheusPortPID != nil,
            exporterRunning: false
        )
    }

    private func startGrafana() throws -> Int32 {
        if let existingPID = pidListening(onTCPPort: 3000) {
            writePIDFileIfNeeded(pidFileURL: grafanaPIDURL, pid: existingPID)
            return existingPID
        }

        let adminCredentials = try ensureGrafanaAdminCredentials()

        let arguments = [
            "server",
            "--homepath", grafanaURL.path,
            "--config", grafanaConfigURL.path,
            "cfg:default.paths.data=\(grafanaDataURL.path)",
            "cfg:default.paths.logs=\(grafanaLogsURL.path)",
            "cfg:default.paths.plugins=\(grafanaPluginsURL.path)",
            "cfg:default.paths.provisioning=\(grafanaProvisioningURL.path)",
            "cfg:server.http_addr=127.0.0.1",
            "cfg:server.http_port=3000",
            "cfg:security.admin_user=\(adminCredentials.username)",
            "cfg:security.admin_password=\(adminCredentials.password)",
            "cfg:analytics.reporting_enabled=false",
            "cfg:analytics.check_for_updates=false",
            "cfg:analytics.check_for_plugin_updates=false",
            "cfg:news.news_feed_enabled=false",
            "cfg:plugins.plugin_admin_enabled=false",
            "cfg:plugins.plugin_admin_external_manage_enabled=false",
            "cfg:plugins.preinstall_disabled=true",
            "cfg:plugins.public_key_retrieval_disabled=true"
        ]

        let config = ManagedProcessLaunchConfig(
            name: .grafana,
            executableURL: grafanaBinaryURL,
            arguments: arguments,
            workingDirectoryURL: grafanaURL,
            pidFileURL: grafanaPIDURL,
            logFileURL: logsURL.appendingPathComponent("grafana.log")
        )

        return try processRunner.start(config)
    }

    private func startPrometheus(retentionDays: Int, retentionSizeGb: Int) throws -> Int32 {
        if let existingPID = pidListening(onTCPPort: 9090) {
            writePIDFileIfNeeded(pidFileURL: prometheusPIDURL, pid: existingPID)
            return existingPID
        }
        let arguments = [
            "--config.file=\(prometheusConfigURL.path)",
            "--storage.tsdb.path=\(prometheusDataURL.path)",
            "--storage.tsdb.retention.time=\(retentionDays)d",
            "--storage.tsdb.retention.size=\(retentionSizeGb)GB",
            "--web.listen-address=127.0.0.1:9090",
            "--web.enable-lifecycle"
        ]

        let config = ManagedProcessLaunchConfig(
            name: .prometheus,
            executableURL: prometheusBinaryURL,
            arguments: arguments,
            workingDirectoryURL: prometheusURL,
            pidFileURL: prometheusPIDURL,
            logFileURL: logsURL.appendingPathComponent("prometheus.log")
        )

        return try processRunner.start(config)
    }


    private func startMetricsImporter(retentionDays: Int, retentionSizeGb: Int) {
        metricsImportTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: metricsImportQueue)
        timer.schedule(deadline: .now() + 3, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.importPendingMetricsIfNeeded(retentionDays: retentionDays, retentionSizeGb: retentionSizeGb)
        }
        metricsImportTimer = timer
        timer.resume()
    }

    private func stopMetricsImporter() {
        metricsImportTimer?.cancel()
        metricsImportTimer = nil
    }

    private func importPendingMetricsIfNeeded(retentionDays: Int, retentionSizeGb: Int) {
        guard !metricsImportInProgress else {
            return
        }

        metricsImportInProgress = true
        defer { metricsImportInProgress = false }

        do {
            try prepareWorkspace()
            let pendingFiles = try pendingMetricsFiles(in: historyPendingURL)
            guard !pendingFiles.isEmpty else {
                return
            }

            var registry = try loadImportedMetricsRegistry()
            var filesToImport: [URL] = []
            var skippedCount = 0

            for file in pendingFiles {
                let fingerprint = try metricsFileFingerprint(file)
                if registry.contains(fingerprint) {
                    skippedCount += 1
                    try fileManager.removeItem(at: file)
                } else {
                    filesToImport.append(file)
                }
            }

            guard !filesToImport.isEmpty else {
                try importerStatusText(imported: 0, failed: 0, skipped: skippedCount).write(
                    to: monitoringStateURL.appendingPathComponent("last-importer-scan.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                return
            }

            stopManagedProcess(pidFileURL: prometheusPIDURL, tcpPort: 9090)

            var importedCount = 0
            var failedCount = 0

            for file in filesToImport {
                do {
                    try importMetricsFile(file)
                    let fingerprint = try metricsFileFingerprint(file)
                    registry.insert(fingerprint)
                    try saveImportedMetricsRegistry(registry)

                    try fileManager.removeItem(at: file)
                    importedCount += 1
                } catch {
                    failedCount += 1
                    let destination = uniqueDestinationURL(for: file.lastPathComponent, in: historyFailedURL)
                    try? moveReplacingIfNeeded(file, to: destination)
                    try? writeImporterError(error, for: destination)
                }
            }

            _ = try startPrometheus(retentionDays: retentionDays, retentionSizeGb: retentionSizeGb)

            try importerStatusText(imported: importedCount, failed: failedCount, skipped: skippedCount).write(
                to: monitoringStateURL.appendingPathComponent("last-importer-scan.txt"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            try? writeImporterError(error, for: monitoringStateURL.appendingPathComponent("last-import-error.txt"))
            if pidListening(onTCPPort: 9090) == nil {
                _ = try? startPrometheus(retentionDays: retentionDays, retentionSizeGb: retentionSizeGb)
            }
        }
    }

    private func pendingMetricsFiles(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return files
            .filter { file in
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
                let allowedExtensions = ["openmetrics", "prom"]
                return values?.isRegularFile == true && allowedExtensions.contains(file.pathExtension.lowercased())
            }
            .sorted { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }

    }

    private func importMetricsFile(_ file: URL) throws {
        guard fileManager.fileExists(atPath: promtoolBinaryURL.path) else {
            throw NSError(
                domain: "GrafanaManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "promtool не найден: \(promtoolBinaryURL.path)"]
            )
        }

        let process = Process()
        process.executableURL = promtoolBinaryURL
        process.arguments = [
            "tsdb",
            "create-blocks-from",
            "openmetrics",
            file.path,
            prometheusDataURL.path
        ]
        process.currentDirectoryURL = prometheusURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "GrafanaManager",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "promtool import failed for \(file.lastPathComponent):\n\(output)\n\(error)"]
            )
        }
    }

    private func metricsFileFingerprint(_ file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        var hash: UInt64 = 1469598103934665603

        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        return "\(file.lastPathComponent):\(data.count):\(String(hash, radix: 16))"
    }

    private func loadImportedMetricsRegistry() throws -> Set<String> {
        guard fileManager.fileExists(atPath: importedMetricsRegistryURL.path) else {
            return []
        }

        let data = try Data(contentsOf: importedMetricsRegistryURL)
        let items = try JSONDecoder().decode([String].self, from: data)
        return Set(items)
    }

    private func saveImportedMetricsRegistry(_ registry: Set<String>) throws {
        let items = registry.sorted()
        let data = try JSONEncoder().encode(items)
        try data.write(to: importedMetricsRegistryURL, options: .atomic)
    }

    private func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let baseURL = directory.appendingPathComponent(fileName)
        guard !fileManager.fileExists(atPath: baseURL.path) else {
            let baseName = baseURL.deletingPathExtension().lastPathComponent
            let pathExtension = baseURL.pathExtension

            for index in 1...9999 {
                let candidateName: String
                if pathExtension.isEmpty {
                    candidateName = "\(baseName)-\(index)"
                } else {
                    candidateName = "\(baseName)-\(index).\(pathExtension)"
                }

                let candidate = directory.appendingPathComponent(candidateName)
                if !fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }

            return directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        }

        return baseURL
    }

    private func moveReplacingIfNeeded(_ source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: source, to: destination)
    }

    private func writeImporterError(_ error: Error, for file: URL) throws {
        let errorFile: URL
        if file.pathExtension == "txt" {
            errorFile = file
        } else {
            errorFile = file.deletingPathExtension().appendingPathExtension("error.txt")
        }

        let text = "\(Date())\n\(error.localizedDescription)\n"
        try text.write(to: errorFile, atomically: true, encoding: .utf8)
    }

    private func importerStatusText(imported: Int, failed: Int, skipped: Int) -> String {
        """
        Last importer scan: \(Date())
        Imported: \(imported)
        Failed: \(failed)
        Skipped already imported: \(skipped)
        Pending folder: \(historyPendingURL.path)
        Imported files are deleted after successful import. Registry: \(importedMetricsRegistryURL.path)
        Failed folder: \(historyFailedURL.path)
        """
    }


    private func ensurePrometheusConfigExists() throws {
        if fileManager.fileExists(atPath: prometheusConfigURL.path) {
            return
        }

        let config = """
        global:
          scrape_interval: 30s
          evaluation_interval: 30s

        scrape_configs: []
        """

        try config.write(to: prometheusConfigURL, atomically: true, encoding: .utf8)
    }

    private func directorySize(at url: URL) throws -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: UInt64 = 0

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])

            guard values.isRegularFile == true else {
                continue
            }

            let allocatedSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += UInt64(allocatedSize)
        }

        return total
    }

    private func removeDirectoryContents(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)

        for item in contents {
            try fileManager.removeItem(at: item)
        }
    }


    private func pidListening(onTCPPort port: Int) -> Int32? {
        let lsofURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard fileManager.fileExists(atPath: lsofURL.path) else {
            return nil
        }

        let process = Process()
        process.executableURL = lsofURL
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let firstLine = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstLine, let pid = Int32(firstLine) else {
            return nil
        }

        return pid
    }

    private func writePIDFileIfNeeded(pidFileURL: URL, pid: Int32) {
        let pidText = "\(pid)"
        let currentText = (try? String(contentsOf: pidFileURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentText != pidText else {
            return
        }

        try? fileManager.createDirectory(at: pidFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? pidText.write(to: pidFileURL, atomically: true, encoding: .utf8)
    }


    private func stopManagedProcess(pidFileURL: URL, tcpPort: Int) {
        try? processRunner.stop(pidFileURL: pidFileURL)

        if let portPID = pidListening(onTCPPort: tcpPort) {
            terminatePID(portPID)
        }

        try? fileManager.removeItem(at: pidFileURL)
    }

    private func terminatePID(_ pid: Int32) {
        guard pid > 0 else {
            return
        }

        let killURL = URL(fileURLWithPath: "/bin/kill")
        guard fileManager.fileExists(atPath: killURL.path) else {
            return
        }

        let terminateProcess = Process()
        terminateProcess.executableURL = killURL
        terminateProcess.arguments = ["-TERM", "\(pid)"]

        do {
            try terminateProcess.run()
            terminateProcess.waitUntilExit()
        } catch {
            return
        }

        Thread.sleep(forTimeInterval: 0.5)

        guard isProcessAlive(pid) else {
            return
        }

        let killProcess = Process()
        killProcess.executableURL = killURL
        killProcess.arguments = ["-KILL", "\(pid)"]

        do {
            try killProcess.run()
            killProcess.waitUntilExit()
        } catch {
            return
        }
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        let killURL = URL(fileURLWithPath: "/bin/kill")
        guard fileManager.fileExists(atPath: killURL.path) else {
            return false
        }

        let process = Process()
        process.executableURL = killURL
        process.arguments = ["-0", "\(pid)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }


    private func ensureGrafanaAdminCredentials() throws -> GrafanaAdminCredentials {
        if fileManager.fileExists(atPath: grafanaAdminCredentialsURL.path) {
            let text = try String(contentsOf: grafanaAdminCredentialsURL, encoding: .utf8)
            if let credentials = parseGrafanaAdminCredentials(text) {
                return credentials
            }
        }

        let credentials = GrafanaAdminCredentials(username: "admin", password: generateGrafanaAdminPassword())
        let text = """
        username=\(credentials.username)
        password=\(credentials.password)
        """

        try fileManager.createDirectory(at: grafanaAdminCredentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: grafanaAdminCredentialsURL, atomically: true, encoding: .utf8)

        return credentials
    }

    private func parseGrafanaAdminCredentials(_ text: String) -> GrafanaAdminCredentials? {
        var username: String?
        var password: String?

        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            switch parts[0].trimmingCharacters(in: .whitespacesAndNewlines) {
            case "username":
                username = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            case "password":
                password = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                continue
            }
        }

        guard let username, let password, !username.isEmpty, !password.isEmpty else {
            return nil
        }

        return GrafanaAdminCredentials(username: username, password: password)
    }

    private func generateGrafanaAdminPassword() -> String {
        let first = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let second = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        return "grafana-\(first)-\(second)"
    }

    private var defaultStatusStateText: String {
        """
        {
          "items": []
        }
        """
    }
}

struct GrafanaAdminCredentials {
    let username: String
    let password: String
}

struct RequiredFileStatus: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let exists: Bool
}

struct GrafanaServiceStatuses {
    let grafanaRunning: Bool
    let prometheusRunning: Bool
    let exporterRunning: Bool
}

