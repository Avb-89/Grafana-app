//
//  ContentView.swift
//  Grafana
//
//  Created by SITIS on 7/3/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var manager = GrafanaManager.shared
    @StateObject private var scriptManager = GrafanaScriptManager(manager: GrafanaManager.shared)
    private let installer = GrafanaInstaller()
    private let grafanaMetrics = GrafanaMetrics()
    private let diskManager = GrafanaDiskManager()
    @State private var grafanaStatus: ServiceStatus = .stopped
    @State private var prometheusStatus: ServiceStatus = .stopped
    @State private var appSize: String = "—"
    @State private var prometheusTSDBSizeText: String = "—"
    @State private var grafanaDatabaseSizeText: String = "—"
    @State private var metricsHistorySizeText: String = "—"
    @State private var scriptsSizeText: String = "—"
    @State private var workspaceSizeText: String = "—"
    @State private var grafanaFolderSizeText: String = "—"
    @State private var prometheusFolderSizeText: String = "—"
    @State private var updatesSizeText: String = "—"
    @State private var downloadsSizeText: String = "—"
    @State private var stagingSizeText: String = "—"
    @State private var backupsSizeText: String = "—"
    @State private var selectedRetentionDays: Int = 30
    @State private var selectedRetentionSizeGb: Int = 2
    @State private var showResetConfirmation = false
    @State private var showGrafanaWindow = false
    @State private var lastActionMessage: String = "Grafana готова к сборке. Пока это интерфейсный каркас."
    @State private var updateMessage: String = "Компоненты устанавливаются вручную внутрь Grafana.app/Contents/Workspace. Первый запуск может требовать загрузки Grafana и Prometheus."
    @State private var isUpdatingComponents = false
    @State private var updateProgress: Double = 0
    @State private var updateProgressMessage: String = ""
    @State private var updateProgressTimer: Timer?
    @State private var updateProgressStartedAt: Date?
    @State private var autoRefreshTimer: Timer?

    @State private var isCleaningData = false
    @State private var cleaningStatusMessage: String = ""

    @State private var selectedSection: AppSection = .overview
    @State private var selectedMetricsPreview: String = "Выбери history-файл, чтобы посмотреть его содержимое."
    @State private var selectedMetricsPreviewTitle: String = "Просмотр history"
    @State private var fileListRefreshToken = 0
    @State private var selectedScriptPreview: String = "Выбери скрипт, чтобы посмотреть его содержимое."
    @State private var selectedScriptPreviewTitle: String = "Просмотр скрипта"
    @State private var grafanaAutologinUsername = "admin"
    @State private var grafanaAutologinPassword = ""
    @State private var appWindowSize = CGSize(width: 1200, height: 760)

    private let retentionDaysOptions = [7, 30, 90, 365]
    private let retentionSizeOptions = [1, 2, 5, 10]

    private let syntheticInstallDuration: TimeInterval = 20 * 60
    private let syntheticInstallMaxProgress: Double = 0.99
    private let syntheticInstallFinishDuration: TimeInterval = 1.2

    private var currentHistoryFiles: [URL] {
        _ = fileListRefreshToken
        return grafanaMetrics.historyFiles()
    }

    private var currentScriptFiles: [URL] {
        _ = fileListRefreshToken
        return scriptManager.scriptFiles()
    }

    var body: some View {
        GeometryReader { proxy in
            NavigationSplitView {
                sidebar
            } detail: {
                mainPanel
            }
            .onAppear {
                appWindowSize = proxy.size
            }
            .onChange(of: proxy.size) { _, newSize in
                appWindowSize = newSize
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .alert("Сбросить все данные Grafana?", isPresented: $showResetConfirmation) {
            Button("Отмена", role: .cancel) { }
            Button("Сбросить", role: .destructive) {
                resetEverything()
            }
        } message: {
            Text("Prometheus TSDB, Grafana DB и Monitoring history будут остановлены и перенесены в quarantine внутри Workspace. Contents/Scripts не трогаются.")
        }
        .onAppear {
            prepareWorkspace()
            startAutoRefreshTimer()
        }
        .onDisappear {
            stopAutoRefreshTimer()
            terminateApplicationFromMainWindow()
        }
        .sheet(isPresented: $showGrafanaWindow) {
            GrafanaWindowView(
                username: grafanaAutologinUsername,
                password: grafanaAutologinPassword,
                preferredSize: grafanaWindowSize(),
                onClose: {
                    showGrafanaWindow = false
                }
            )
            .interactiveDismissDisabled(true)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section("Grafana") {
                    Label(AppSection.overview.title, systemImage: AppSection.overview.systemImage)
                        .tag(AppSection.overview)
                    Label(AppSection.metrics.title, systemImage: AppSection.metrics.systemImage)
                        .tag(AppSection.metrics)
                    Label(AppSection.scripts.title, systemImage: AppSection.scripts.systemImage)
                        .tag(AppSection.scripts)
                    Label(AppSection.cleanup.title, systemImage: AppSection.cleanup.systemImage)
                        .tag(AppSection.cleanup)
                    Label(AppSection.update.title, systemImage: AppSection.update.systemImage)
                        .tag(AppSection.update)
                }

                Section("Сервисы") {
                    StatusPill(name: "Grafana", status: grafanaStatus)
                    StatusPill(name: "Prometheus", status: prometheusStatus)
                }
            }
            .navigationTitle("Grafana")
            .frame(minHeight: 260, maxHeight: 360)

            GrafanaLogCard(message: lastActionMessage)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Spacer(minLength: 12)

            SidebarGrafanaButton {
                openGrafanaWindow()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
    }

    private var mainPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedSection {
                case .overview:
                    overviewPage
                case .metrics:
                    metricsPage
                case .scripts:
                    scriptsPage
                case .cleanup:
                    cleanupPage
                case .update:
                    updatePage
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var overviewPage: some View {
        GrafanaHeaderCard()
        serviceControlCard
    }

    @ViewBuilder
    private var metricsPage: some View {
        metricsPreviewCard
    }

    @ViewBuilder
    private var scriptsPage: some View {
        scriptsCard
    }

    @ViewBuilder
    private var cleanupPage: some View {
        cleanupCard
        GrafanaRetentionCard(
            selectedRetentionDays: $selectedRetentionDays,
            selectedRetentionSizeGb: $selectedRetentionSizeGb,
            retentionDayOptions: retentionDaysOptions,
            retentionSizeOptionsGb: retentionSizeOptions
        )
        storageInfoCard
    }

    @ViewBuilder
    private var updatePage: some View {
        updateCard
    }

    private var updateCard: some View {
        GrafanaCardInstaller(
            isInstalling: isUpdatingComponents,
            installProgress: updateProgress,
            installProgressText: updateProgressMessage.isEmpty ? "Готовлю установку компонентов..." : updateProgressMessage,
            installerMessage: updateMessage,
            onShowVersions: showCurrentVersions,
            onCheckAccess: checkUpdates,
            onInstall: updateComponents
        )
    }

    private var serviceControlCard: some View {
        GrafanaCardServiceControl(
            grafanaStatus: grafanaStatus,
            prometheusStatus: prometheusStatus,
            credentialsStatusText: grafanaCredentialsStatusText(),
            canOpenGrafana: grafanaStatus == .running,
            canCopyPassword: !grafanaAutologinPassword.isEmpty,
            onStart: startGrafana,
            onStop: stopGrafana,
            onOpenGrafana: openGrafanaWindow,
            onCopyPassword: copyGrafanaPassword
        )
    }

    private var metricsPreviewCard: some View {
        GrafanaCardMetricsPreview(
            historyFiles: currentHistoryFiles,
            selectedPreviewTitle: selectedMetricsPreviewTitle,
            selectedPreviewText: selectedMetricsPreview,
            onOpenHistoryFolder: openHistoryFolder,
            onRefresh: refreshFileLists,
            onClearPreview: clearMetricsPreview,
            onPreviewFile: previewMetricsFile
        )
    }

    private var scriptsCard: some View {
        GrafanaCardScripts(
            scriptFiles: currentScriptFiles,
            scriptManager: scriptManager,
            selectedPreviewTitle: selectedScriptPreviewTitle,
            selectedPreviewText: selectedScriptPreview,
            onOpenScriptsFolder: openScriptsFolder,
            onRefresh: refreshFileLists,
            onExport: exportScripts,
            onImport: importScripts,
            onStartAllSchedules: startAllScriptSchedules,
            onCancelAllSchedules: cancelAllScriptSchedules,
            onRunScript: runScriptFile,
            onStopScript: stopScriptFile,
            onStartSchedule: startScriptSchedule,
            onPreviewScript: previewScriptFile
        )
    }

    private var storageInfoCard: some View {
        GrafanaCardDiskInfo(items: diskInfoItems)
    }

    private var diskInfoItems: [GrafanaDiskInfoItem] {
        [
            GrafanaDiskInfoItem(
                title: "Всё приложение",
                path: manager.appBundleURL.path,
                sizeText: appSize
            ),
            GrafanaDiskInfoItem(
                title: "Prometheus TSDB",
                path: manager.prometheusDataURL.path,
                sizeText: prometheusTSDBSizeText,
                actionTitle: "Очистить TSDB",
                actionSystemImage: "externaldrive.badge.xmark",
                action: clearMetricsHistory
            ),
            GrafanaDiskInfoItem(
                title: "Grafana DB",
                path: manager.grafanaDatabaseURL.path,
                sizeText: grafanaDatabaseSizeText,
                actionTitle: "Очистить DB",
                actionSystemImage: "cylinder.split.1x2",
                action: clearGrafanaDatabase
            ),
            GrafanaDiskInfoItem(
                title: "Metrics history",
                path: manager.historyMetricsURL.path,
                sizeText: metricsHistorySizeText
            ),
            GrafanaDiskInfoItem(
                title: "Scripts",
                path: manager.scriptsURL.path,
                sizeText: scriptsSizeText
            ),
            GrafanaDiskInfoItem(
                title: "Workspace",
                path: manager.workspaceURL.path,
                sizeText: workspaceSizeText
            ),
            GrafanaDiskInfoItem(
                title: "Grafana",
                path: manager.grafanaURL.path,
                sizeText: grafanaFolderSizeText
            ),
            GrafanaDiskInfoItem(
                title: "Prometheus",
                path: manager.prometheusURL.path,
                sizeText: prometheusFolderSizeText
            ),
            GrafanaDiskInfoItem(
                title: "Updates",
                path: manager.updatesURL.path,
                sizeText: updatesSizeText,
                actionTitle: "Очистить кэш",
                actionSystemImage: "trash",
                action: clearUpdateCache
            ),
            GrafanaDiskInfoItem(
                title: "Downloads",
                path: manager.updateDownloadsURL.path,
                sizeText: downloadsSizeText,
                actionTitle: "Очистить",
                actionSystemImage: "trash",
                action: clearUpdateDownloads
            ),
            GrafanaDiskInfoItem(
                title: "Staging",
                path: manager.updateStagingURL.path,
                sizeText: stagingSizeText,
                actionTitle: "Очистить",
                actionSystemImage: "trash",
                action: clearUpdateStaging
            ),
            GrafanaDiskInfoItem(
                title: "Backups",
                path: manager.backupsURL.path,
                sizeText: backupsSizeText,
                actionTitle: "Очистить",
                actionSystemImage: "trash",
                action: clearBackups
            )
        ]
    }

    private var cleanupCard: some View {
        GrafanaCardCleanup(
            isCleaning: isCleaningData,
            cleaningMessage: cleaningStatusMessage,
            onCheckPrometheusTSDB: checkPrometheusTSDB,
            onClearPrometheusTSDB: clearMetricsHistory,
            onClearGrafanaDatabase: clearGrafanaDatabase,
            onClearMonitoringHistory: clearMonitoringData,
            onResetRuntimeData: {
                showResetConfirmation = true
            }
        )
    }

    private func clearMetricsPreview() {
        selectedMetricsPreview = "Выбери history-файл, чтобы посмотреть его содержимое."
        selectedMetricsPreviewTitle = "Просмотр history"
        lastActionMessage = "Просмотр history очищен."
    }

    private func openScriptsFolder() {
        NSWorkspace.shared.open(manager.scriptsURL)
        lastActionMessage = "Открываю папку Scripts:\n\(manager.scriptsURL.path)"
    }

    private func openHistoryFolder() {
        NSWorkspace.shared.open(manager.historyMetricsURL)
        lastActionMessage = "Открываю папку history:\n\(manager.historyMetricsURL.path)"
    }

    private func refreshFileLists() {
        fileListRefreshToken += 1
        refreshPrometheusTSDBSize()
        lastActionMessage = "Списки файлов обновлены."
    }

    private func refreshDiskSizes() {
        appSize = manager.appSizeText()
        prometheusTSDBSizeText = diskManager.prometheusTSDBSizeText(manager.prometheusDataURL)
        grafanaDatabaseSizeText = diskManager.fileSizeText(manager.grafanaDatabaseURL)
        metricsHistorySizeText = diskManager.folderSizeText(manager.historyMetricsURL)
        scriptsSizeText = diskManager.folderSizeText(manager.scriptsURL)
        workspaceSizeText = diskManager.folderSizeText(manager.workspaceURL)
        grafanaFolderSizeText = diskManager.folderSizeText(manager.grafanaURL)
        prometheusFolderSizeText = diskManager.folderSizeText(manager.prometheusURL)
        updatesSizeText = diskManager.folderSizeText(manager.updatesURL)
        downloadsSizeText = diskManager.folderSizeText(manager.updateDownloadsURL)
        stagingSizeText = diskManager.folderSizeText(manager.updateStagingURL)
        backupsSizeText = diskManager.folderSizeText(manager.backupsURL)
    }

    private func refreshPrometheusTSDBSize() {
        prometheusTSDBSizeText = diskManager.prometheusTSDBSizeText(manager.prometheusDataURL)
    }

    private func startAutoRefreshTimer() {
        stopAutoRefreshTimer()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            fileListRefreshToken += 1
            refreshPrometheusTSDBSize()
        }
    }

    private func stopAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    private func refreshServiceStatuses() {
        let statuses = manager.serviceStatuses()
        grafanaStatus = statuses.grafanaRunning ? .running : .stopped
        prometheusStatus = statuses.prometheusRunning ? .running : .stopped
    }

    private func refreshGrafanaAutologinCredentials() {
        do {
            let credentials = try manager.grafanaAdminCredentials()
            grafanaAutologinUsername = credentials.username
            grafanaAutologinPassword = credentials.password
        } catch {
            grafanaAutologinUsername = "admin"
            grafanaAutologinPassword = ""
        }
    }

    private func grafanaCredentialsStatusText() -> String {
        "Grafana login: \(grafanaAutologinUsername)\nGrafana password: сгенерирован, нажми “Скопировать пароль”\nCredentials file: \(manager.grafanaAdminCredentialsURL.path)"
    }

    private func copyGrafanaPassword() {
        refreshGrafanaAutologinCredentials()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(grafanaAutologinPassword, forType: .string)
        lastActionMessage = "Пароль Grafana скопирован в буфер обмена.\n\n\(grafanaCredentialsStatusText())"
    }

    private func grafanaWindowSize() -> CGSize {
        CGSize(
            width: max(appWindowSize.width - 80, 980),
            height: max(appWindowSize.height - 80, 640)
        )
    }

    private func prepareWorkspace() {
        do {
            try manager.prepareWorkspace()
            try manager.startAll(retentionDays: selectedRetentionDays, retentionSizeGb: selectedRetentionSizeGb)
            refreshGrafanaAutologinCredentials()
            refreshDiskSizes()
            refreshServiceStatuses()
            lastActionMessage = "Workspace готов. Grafana и Prometheus запущены автоматически.\nApp: \(manager.appBundleURL.path)\nResources: \(manager.resourcesURL.path)\nWorkspace: \(manager.workspaceURL.path)\nScripts: \(manager.scriptsURL.path)\nMonitoring: \(manager.monitoringURL.path)\n\n\(grafanaCredentialsStatusText())"
            updateMessage = "Компоненты Grafana и Prometheus управляются через раздел “Инструменты”."
            fileListRefreshToken += 1

            scriptManager.startAllStoredSchedules(scriptFiles: scriptManager.scriptFiles())
            if scriptManager.hasSchedules {
                lastActionMessage += "\n\nРасписания скриптов запущены автоматически."
            }
        } catch {
            grafanaStatus = .warning
            prometheusStatus = .warning
            lastActionMessage = "Не удалось автоматически подготовить и запустить Grafana/Prometheus: \(error.localizedDescription)\n\nПохоже, компоненты Grafana/Prometheus ещё не загружены или повреждены. Открой раздел “Инструменты” и нажми “Установить компоненты”, чтобы загрузить и установить Grafana и Prometheus. Это может занять до 30 минут.\n\nApp: \(manager.appBundleURL.path)\nResources: \(manager.resourcesURL.path)\nWorkspace: \(manager.workspaceURL.path)\nScripts: \(manager.scriptsURL.path)\nMonitoring: \(manager.monitoringURL.path)"
        }
    }

    private func terminateApplicationFromMainWindow() {
        stopSyntheticUpdateProgress()
        try? manager.stopAll()
        NSApplication.shared.terminate(nil)
    }

    private func startGrafana() {
        do {
            try manager.startAll(retentionDays: selectedRetentionDays, retentionSizeGb: selectedRetentionSizeGb)
            refreshGrafanaAutologinCredentials()
            refreshDiskSizes()
            refreshServiceStatuses()
            lastActionMessage = "Grafana и Prometheus запущены.\nWorkspace: \(manager.workspaceURL.path)\nScripts: \(manager.scriptsURL.path)\nMonitoring: \(manager.monitoringURL.path)\n\n\(grafanaCredentialsStatusText())"
            updateMessage = "Компоненты Grafana и Prometheus управляются через раздел “Инструменты”."
        } catch {
            refreshServiceStatuses()
            refreshDiskSizes()
            lastActionMessage = "Не удалось запустить Grafana: \(error.localizedDescription)\n\nЕсли это первый запуск или приложение только что собрано, открой раздел “Инструменты” и нажми “Установить компоненты”, чтобы загрузить и установить Grafana и Prometheus."
        }
    }

    private func stopGrafana() {
        do {
            try manager.stopAll()
            refreshServiceStatuses()
            refreshDiskSizes()
            lastActionMessage = "Grafana и Prometheus остановлены. PID-файлы в Workspace/logs очищены."
        } catch {
            refreshServiceStatuses()
            refreshDiskSizes()
            lastActionMessage = "Не удалось остановить сервисы: \(error.localizedDescription)"
        }
    }

    private func showCurrentVersions() {
        let versions = installer.currentVersions()
        updateMessage = "Текущие версии компонентов:\n\(String(describing: versions))"
        lastActionMessage = "Текущие версии компонентов показаны в разделе “Инструменты”."
    }

    private func checkUpdates() {
        do {
            try installer.checkInstallerAccess()
            updateMessage = "Доступ к загрузке компонентов проверен. Можно запускать установку."
            lastActionMessage = "Проверка доступа к репозиторию выполнена."
        } catch {
            updateMessage = "Не удалось выполнить проверку доступа к репозиторию: \(error.localizedDescription)"
            lastActionMessage = updateMessage
        }
    }

    private func updateComponents() {
        guard !isUpdatingComponents else {
            return
        }

        isUpdatingComponents = true
        updateProgress = 0.01
        updateProgressMessage = "Стартую установку компонентов..."
        updateMessage = "Это может занять до 30 минут."

        startSyntheticUpdateProgress()
        let installer = self.installer
        let manager = self.manager

        DispatchQueue.global(qos: .utility).async {
            do {
                try installer.installComponents { _, text in
                    DispatchQueue.main.async {
                        self.updateProgressMessage = text.isEmpty ? "Устанавливаю компоненты..." : text
                        self.updateMessage = "Это может занять до 30 минут."
                    }
                }

                DispatchQueue.main.async {
                    self.isUpdatingComponents = false
                    self.finishSyntheticUpdateProgress()
                    self.updateMessage = "Компоненты Grafana и Prometheus управляются через раздел “Инструменты”."
                    self.updateProgressMessage = "Готово."
                    self.refreshServiceStatuses()
                    self.refreshDiskSizes()
                    self.lastActionMessage = "Компоненты установлены. Теперь можно нажать “Запустить Grafana”."
                }
            } catch {
                DispatchQueue.main.async {
                    self.stopSyntheticUpdateProgress()
                    self.updateMessage = "Не удалось установить компоненты: \(error.localizedDescription)\n\nПроверь интернет, свободное место и попробуй снова."
                    self.isUpdatingComponents = false
                    self.updateProgressMessage = "Ошибка установки."
                    self.refreshServiceStatuses()
                    self.refreshDiskSizes()
                    self.lastActionMessage = self.updateMessage
                }
            }
        }
    }

    private func startSyntheticUpdateProgress() {
        stopSyntheticUpdateProgress()
        updateProgressStartedAt = Date()

        updateProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard isUpdatingComponents else {
                return
            }

            let elapsed = Date().timeIntervalSince(updateProgressStartedAt ?? Date())
            let syntheticProgress = min(
                syntheticInstallMaxProgress,
                max(0.01, elapsed / syntheticInstallDuration)
            )

            guard syntheticProgress > updateProgress else {
                return
            }

            if syntheticProgress >= syntheticInstallMaxProgress {
                updateProgress = syntheticInstallMaxProgress

                if updateProgressMessage.isEmpty || updateProgressMessage == "Стартую установку компонентов..." {
                    updateProgressMessage = "Завершаю установку компонентов..."
                }
            } else {
                updateProgress = syntheticProgress
            }
        }
    }

    private func finishSyntheticUpdateProgress() {
        updateProgressTimer?.invalidate()
        updateProgressTimer = nil
        updateProgressStartedAt = nil

        let startProgress = min(updateProgress, syntheticInstallMaxProgress)
        let finishStartedAt = Date()

        updateProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(finishStartedAt)
            let fraction = min(1.0, elapsed / syntheticInstallFinishDuration)
            updateProgress = startProgress + (1.0 - startProgress) * fraction

            if fraction >= 1.0 {
                updateProgressTimer?.invalidate()
                updateProgressTimer = nil
                updateProgress = 1.0
            }
        }
    }

    private func stopSyntheticUpdateProgress() {
        updateProgressTimer?.invalidate()
        updateProgressTimer = nil
        updateProgressStartedAt = nil
    }

    private func openGrafanaWindow() {
        refreshServiceStatuses()
        guard grafanaStatus == .running else {
            showGrafanaWindow = false
            lastActionMessage = "Grafana UI пока не открыт: сервер Grafana не запущен на http://127.0.0.1:3000. Сначала нажми “Запустить Grafana” и проверь сообщение об ошибке."
            return
        }
        refreshGrafanaAutologinCredentials()
        showGrafanaWindow = true
        lastActionMessage = "Открываю Grafana UI внутри приложения: http://127.0.0.1:3000\n\n\(grafanaCredentialsStatusText())"
    }

    private func previewMetricsFile(_ url: URL) {
        do {
            selectedMetricsPreview = try grafanaMetrics.previewText(for: url)
            selectedMetricsPreviewTitle = url.lastPathComponent
            lastActionMessage = "Открыт просмотр history-файла:\n\(url.path)"
        } catch {
            selectedMetricsPreview = "Не удалось прочитать файл: \(error.localizedDescription)"
            selectedMetricsPreviewTitle = url.lastPathComponent
            lastActionMessage = selectedMetricsPreview
        }
    }

    private func previewScriptFile(_ url: URL) {
        do {
            selectedScriptPreview = try scriptManager.previewText(for: url)
            selectedScriptPreviewTitle = url.lastPathComponent
            lastActionMessage = "Открыт просмотр скрипта:\n\(url.path)"
        } catch {
            selectedScriptPreview = "Не удалось прочитать скрипт: \(error.localizedDescription)"
            selectedScriptPreviewTitle = url.lastPathComponent
            lastActionMessage = selectedScriptPreview
        }
    }

    private func exportScripts() {
        let panel = NSSavePanel()
        panel.title = "Экспорт scripts.zip"
        panel.nameFieldStringValue = "Grafana-Scripts.zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            lastActionMessage = "Экспорт скриптов отменён."
            return
        }

        lastActionMessage = "Экспортирую Contents/Scripts в архив:\n\(destinationURL.path)"

        Task.detached {
            do {
                try await scriptManager.exportScriptsArchive(to: destinationURL)

                await MainActor.run {
                    refreshDiskSizes()
                    refreshFileLists()
                    lastActionMessage = "Скрипты экспортированы в архив:\n\(destinationURL.path)"
                }
            } catch {
                await MainActor.run {
                    lastActionMessage = "Не удалось экспортировать скрипты: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importScripts() {
        let panel = NSOpenPanel()
        panel.title = "Импорт скриптов"
        panel.message = "Выбери .sh/.zsh/.command, папку со скриптами или zip-архив, созданный экспортом."
        panel.prompt = "Импортировать"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.shellScript, .zip]

        guard panel.runModal() == .OK else {
            lastActionMessage = "Импорт скриптов отменён."
            return
        }

        let selectedURLs = panel.urls
        lastActionMessage = "Импортирую скрипты:\n\(selectedURLs.map(\.path).joined(separator: "\n"))"

        Task.detached {
            do {
                let importedCount = try await scriptManager.importScriptItems(selectedURLs)

                await MainActor.run {
                    refreshFileLists()
                    refreshDiskSizes()
                    lastActionMessage = "Импорт скриптов завершён. Импортировано файлов: \(importedCount).\n\nПапка Scripts:\n\(manager.scriptsURL.path)"
                }
            } catch {
                await MainActor.run {
                    refreshFileLists()
                    refreshDiskSizes()
                    lastActionMessage = "Не удалось импортировать скрипты: \(error.localizedDescription)"
                }
            }
        }
    }

    private func runScriptFile(_ url: URL) {
        scriptManager.runScript(url)
        lastActionMessage = "Запускаю скрипт:\n\(url.path)"
    }

    private func stopScriptFile(_ url: URL) {
        scriptManager.stopScriptAndSchedule(url)
        lastActionMessage = "Останавливаю скрипт и его расписание:\n\(url.path)"
    }

    private func startScriptSchedule(_ url: URL) {
        switch scriptManager.startSchedule(for: url) {
        case .started:
            lastActionMessage = "Расписание запущено для скрипта:\n\(url.path)"
        case .invalidInterval:
            lastActionMessage = "Расписание не запущено: интервал пустой или неверный. Примеры: 5s, 10m, 1h30m30s.\n\(url.path)"
        case .alreadyActive:
            lastActionMessage = "Расписание уже запущено для скрипта:\n\(url.path)"
        }
    }

    private func cancelScriptSchedule(_ url: URL) {
        scriptManager.cancelSchedule(for: url)
        lastActionMessage = "Расписание остановлено для скрипта:\n\(url.path)"
    }

    private func startAllScriptSchedules() {
        scriptManager.startAllStoredSchedules(scriptFiles: currentScriptFiles)
        lastActionMessage = "Расписания всех скриптов с заполненным интервалом запущены."
    }

    private func cancelAllScriptSchedules() {
        scriptManager.cancelAllSchedules()
        lastActionMessage = "Все расписания скриптов остановлены. Уже запущенные процессы можно остановить отдельной кнопкой “Остановить”."
    }

    private func clearMetricsHistory() {
        guard !isCleaningData else {
            return
        }

        isCleaningData = true
        cleaningStatusMessage = "Переношу Prometheus TSDB в quarantine..."
        lastActionMessage = "Останавливаю Prometheus и переношу TSDB в quarantine:\n\(manager.prometheusDataURL.path)"

        Task.detached {
            do {
                try manager.quarantinePrometheusTSDB(
                    restartPrometheus: true,
                    retentionDays: selectedRetentionDays,
                    retentionSizeGb: selectedRetentionSizeGb
                )

                await MainActor.run {
                    refreshDiskSizes()
                    refreshServiceStatuses()
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = "Prometheus TSDB перенесена в quarantine и пересоздана пустой папкой.\n\nПуть TSDB:\n\(manager.prometheusDataURL.path)"
                }
            } catch {
                await MainActor.run {
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = "Не удалось очистить Prometheus TSDB: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearMonitoringData() {
        guard !isCleaningData else {
            return
        }

        isCleaningData = true
        cleaningStatusMessage = "Переношу Monitoring history в quarantine..."
        lastActionMessage = "Переношу Monitoring history в quarantine:\n\(manager.historyMetricsURL.path)"

        Task.detached {
            do {
                try manager.quarantineMonitoringHistory()

                await MainActor.run {
                    refreshDiskSizes()
                    refreshServiceStatuses()
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    fileListRefreshToken += 1
                    lastActionMessage = "Monitoring history перенесена в quarantine и пересоздана. Prometheus TSDB и Contents/Scripts не тронуты.\n\nПуть history:\n\(manager.historyMetricsURL.path)"
                }
            } catch {
                await MainActor.run {
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = "Не удалось очистить Monitoring history: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearGrafanaDatabase() {
        guard !isCleaningData else {
            return
        }

        isCleaningData = true
        cleaningStatusMessage = "Переношу Grafana DB в quarantine..."
        lastActionMessage = "Останавливаю Grafana и переношу DB в quarantine:\n\(manager.grafanaDatabaseURL.path)"

        Task.detached {
            do {
                try manager.quarantineGrafanaDB()

                await MainActor.run {
                    refreshDiskSizes()
                    refreshServiceStatuses()
                    refreshGrafanaAutologinCredentials()
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = "Grafana DB перенесена в quarantine. При следующем запуске Grafana создаст новую базу.\n\nПуть DB:\n\(manager.grafanaDatabaseURL.path)"
                }
            } catch {
                await MainActor.run {
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = "Не удалось очистить Grafana DB: \(error.localizedDescription)"
                }
            }
        }
    }

    private func checkPrometheusTSDB() {
        lastActionMessage = manager.prometheusTSDBDiagnosticsText()
    }

    private func clearUpdateCache() {
        performCleaning(
            status: "Очищаю кэш обновлений...",
            successMessage: "Кэш обновлений очищен. Backups не тронуты."
        ) {
            try diskManager.clearUpdateCache(updatesURL: manager.updatesURL)
        }
    }

    private func clearUpdateDownloads() {
        performCleaning(
            status: "Очищаю downloads...",
            successMessage: "Downloads очищен."
        ) {
            try diskManager.clearUpdateDownloads(downloadsURL: manager.updateDownloadsURL)
        }
    }

    private func clearUpdateStaging() {
        performCleaning(
            status: "Очищаю staging...",
            successMessage: "Staging очищен."
        ) {
            try diskManager.clearUpdateStaging(stagingURL: manager.updateStagingURL)
        }
    }

    private func clearBackups() {
        performCleaning(
            status: "Очищаю backups...",
            successMessage: "Backups очищен."
        ) {
            try diskManager.clearBackups(backupsURL: manager.backupsURL)
        }
    }

    private func performCleaning(status: String, successMessage: String, operation: @escaping () throws -> Void) {
        guard !isCleaningData else {
            return
        }

        isCleaningData = true
        cleaningStatusMessage = status
        lastActionMessage = status

        Task.detached {
            do {
                try operation()

                await MainActor.run {
                    refreshDiskSizes()
                    refreshServiceStatuses()
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = successMessage
                }
            } catch {
                await MainActor.run {
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = "Не удалось выполнить очистку: \(error.localizedDescription)"
                }
            }
        }
    }

    private func resetEverything() {
        guard !isCleaningData else {
            return
        }

        grafanaStatus = .stopped
        prometheusStatus = .stopped
        isCleaningData = true
        cleaningStatusMessage = "Переношу runtime-данные в quarantine..."
        lastActionMessage = "Останавливаю службы и переношу Prometheus TSDB, Grafana DB и Monitoring history в quarantine. Contents/Scripts не трогаю."

        Task.detached {
            do {
                try manager.resetRuntimeDataToQuarantine(
                    retentionDays: selectedRetentionDays,
                    retentionSizeGb: selectedRetentionSizeGb
                )

                await MainActor.run {
                    refreshDiskSizes()
                    refreshServiceStatuses()
                    refreshGrafanaAutologinCredentials()
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    fileListRefreshToken += 1
                    lastActionMessage = "Runtime-данные перенесены в quarantine. Contents/Scripts не тронуты.\n\nPrometheus TSDB:\n\(manager.prometheusDataURL.path)\n\nGrafana DB:\n\(manager.grafanaDatabaseURL.path)\n\nMetrics history:\n\(manager.historyMetricsURL.path)"
                }
            } catch {
                await MainActor.run {
                    isCleaningData = false
                    cleaningStatusMessage = ""
                    lastActionMessage = "Не удалось выполнить полный сброс: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
