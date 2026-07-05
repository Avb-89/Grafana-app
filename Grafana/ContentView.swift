//
//  ContentView.swift
//  Grafana
//
//  Created by SITIS on 7/3/26.
//

import SwiftUI
import AppKit
import Combine
import Darwin

struct ContentView: View {
    @StateObject private var manager = GrafanaManager.shared
    @StateObject private var scriptScheduler = ScriptScheduler(manager: GrafanaManager.shared)
    private let updateManager = UpdateManager()
    @State private var grafanaStatus: ServiceStatus = .stopped
    @State private var prometheusStatus: ServiceStatus = .stopped
    @State private var metricsFilePath: String = "—"
    @State private var appSize: String = "—"
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

    private var currentHistoryFiles: [URL] {
        _ = fileListRefreshToken
        return historyFiles()
    }

    private var currentScriptFiles: [URL] {
        _ = fileListRefreshToken
        return scriptFiles()
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
        }
        .onDisappear {
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
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSection) {
            Section("Grafana") {
                Label("Обзор", systemImage: "shippingbox")
                    .tag(AppSection.overview)
                Label("Метрики", systemImage: "waveform.path.ecg")
                    .tag(AppSection.metrics)
                Label("Скрипты", systemImage: "terminal")
                    .tag(AppSection.scripts)
                Label("Очистка", systemImage: "trash")
                    .tag(AppSection.cleanup)
                Label("Инструменты", systemImage: "wrench.and.screwdriver")
                    .tag(AppSection.update)
            }

            Section("Сервисы") {
                ServiceRow(name: "Grafana", status: grafanaStatus)
                ServiceRow(name: "Prometheus", status: prometheusStatus)
            }
        }
        .navigationTitle("Grafana")
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
        header
        serviceControlCard
        logCard
        overviewInfoCard
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
        retentionCard
        storageInfoCard
    }

    @ViewBuilder
    private var updatePage: some View {
        updateCard
    }
    private var overviewInfoCard: some View {
        AppCard(title: "Что внутри") {
            VStack(alignment: .leading, spacing: 10) {
                StoragePathInfoRow(
                    title: "Grafana",
                    path: manager.grafanaURL.path,
                    size: byteCountText(for: folderSize(manager.grafanaURL))
                )
                StoragePathInfoRow(
                    title: "Prometheus",
                    path: manager.prometheusURL.path,
                    size: byteCountText(for: folderSize(manager.prometheusURL))
                )
                StoragePathInfoRow(
                    title: "Скрипты",
                    path: manager.scriptsURL.path,
                    size: byteCountText(for: folderSize(manager.scriptsURL))
                )
                StoragePathInfoRow(
                    title: "История",
                    path: manager.historyMetricsURL.path,
                    size: byteCountText(for: folderSize(manager.historyMetricsURL))
                )
                StoragePathInfoRow(
                    title: "БД Grafana",
                    path: manager.grafanaDatabaseURL.path,
                    size: byteCountText(for: fileSize(manager.grafanaDatabaseURL))
                )
            }
        }
    }

    private var updateCard: some View {
        AppCard(title: "Инструменты") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Установка ручная: приложение скачивает Grafana, Prometheus и нужные компоненты во временную папку внутри Grafana.app/Contents/Workspace, проверяет доступность архивов, останавливает сервисы и заменяет файлы только внутри этого .app. Первый запуск или медленный интернет могут занять до 30 минут.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        showCurrentVersions()
                    } label: {
                        Label("Текущие версии", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdatingComponents)

                    Button {
                        checkUpdates()
                    } label: {
                        Label("Проверка доступа к репозиторию", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdatingComponents)

                    Button {
                        updateComponents()
                    } label: {
                        Label("Установить компоненты", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpdatingComponents)
                }

                if isUpdatingComponents {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: updateProgress, total: 1.0) {
                            Text(updateProgressMessage.isEmpty ? "Готовлю установку компонентов..." : updateProgressMessage)
                        }

                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)

                            Text("\(Int(updateProgress * 100))%. Не закрывай приложение. Загрузка и распаковка могут занять до 30 минут, особенно при медленном интернете.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Стадии: скачать Grafana → распаковать Grafana → скачать Prometheus → распаковать Prometheus → установить в Workspace → проверить запуск.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(updateMessage)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }


    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Grafana")
                        .font(.largeTitle.bold())
                    Text("Локальная переносная Grafana без brew, /etc, /var и системных хвостов.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Размер приложения")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appSize)
                        .font(.title3.monospacedDigit().bold())
                }
            }
        }
    }

    private var serviceControlCard: some View {
        AppCard(title: "Запуск") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Одна кнопка поднимает Grafana и Prometheus из Grafana.app/Contents/Workspace. Скрипты, history и state лежат внутри самого приложения, чтобы весь зоопарк был в одном .app.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        startGrafana()
                    } label: {
                        Label("Запустить Grafana", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        stopGrafana()
                    } label: {
                        Label("Остановить", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openGrafanaWindow()
                    } label: {
                        Label("Открыть Grafana", systemImage: "macwindow")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyGrafanaPassword()
                    } label: {
                        Label("Скопировать пароль", systemImage: "key")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 18) {
                    StatusPill(name: "Grafana", status: grafanaStatus)
                    StatusPill(name: "Prometheus", status: prometheusStatus)
                }
            }
        }
    }

    private var metricsCard: some View {
        AppCard(title: "История метрик") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Скрипты живут внутри Grafana.app/Contents/Scripts. Единственный источник метрик — исторические .openmetrics-файлы в Contents/Monitoring/metrics/history. Live/scrape/exporter больше не используем, чтобы старые значения не размазывались по текущему времени.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        openScriptsFolder()
                    } label: {
                        Label("Открыть Scripts", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openMonitoringFolder()
                    } label: {
                        Label("Открыть Monitoring", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    TextField("Internal paths", text: $metricsFilePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        copyMetricsPath()
                    } label: {
                        Label("Скопировать", systemImage: "doc.on.doc")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Пример исторической точки для индикатора")
                        .font(.headline)

                    Text("""
# TYPE service_up gauge
service_up{service=\"Server\"} 1 1783072800
service_up{service=\"Postgres PPA\"} 0 1783073100
# EOF
""")
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var metricsPreviewCard: some View {
        AppCard(title: "Просмотр history") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button {
                        openHistoryFolder()
                    } label: {
                        Label("Открыть history", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        refreshFileLists()
                    } label: {
                        Label("Обновить список", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        selectedMetricsPreview = "Выбери history-файл, чтобы посмотреть его содержимое."
                        selectedMetricsPreviewTitle = "Просмотр history"
                    } label: {
                        Label("Очистить просмотр", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if currentHistoryFiles.isEmpty {
                    Text("History-файлов пока нет. Скрипты будут складывать .openmetrics в pending, а importer переносить успешные файлы в imported.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(currentHistoryFiles, id: \.path) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                    Text(file.deletingLastPathComponent().lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Просмотреть") {
                                    previewMetricsFile(file)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedMetricsPreviewTitle)
                        .font(.headline)

                    ScrollView {
                        Text(selectedMetricsPreview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 160, maxHeight: 260)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
    private var scriptsCard: some View {
        AppCard(title: "Скрипты") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Скрипты лежат внутри Contents/Scripts. Их можно просматривать, запускать вручную и ставить во временное расписание. .openmetrics автоматически подхватывает importer.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        openScriptsFolder()
                    } label: {
                        Label("Открыть Scripts", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        refreshFileLists()
                    } label: {
                        Label("Обновить список", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        cancelAllScriptSchedules()
                    } label: {
                        Label("Отменить все запуски", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!scriptScheduler.hasSchedules)
                }

                if currentScriptFiles.isEmpty {
                    Text("Скриптов пока нет. Когда появятся .sh-файлы, они будут показаны здесь.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(currentScriptFiles, id: \.path) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(file.lastPathComponent)
                                            .font(.system(.body, design: .monospaced))

                                        if scriptScheduler.isRunning(file) {
                                            ProgressView()
                                                .controlSize(.small)
                                        }

                                        if let state = scriptScheduler.state(for: file) {
                                            Text(state)
                                                .font(.caption.bold())
                                                .foregroundStyle(scriptScheduler.stateColor(for: file))
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Text(file.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        if let schedule = scriptScheduler.schedule(for: file) {
                                            Text("каждые \(schedule.label)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                Menu("Запускать каждые") {
                                    ForEach(ScriptScheduleOption.defaults) { option in
                                        Button(option.label) {
                                            scheduleScriptFile(file, every: option)
                                        }
                                    }

                                    Divider()

                                    Button("Отменить для скрипта", role: .destructive) {
                                        cancelScriptSchedule(file)
                                    }
                                    .disabled(scriptScheduler.schedule(for: file) == nil)
                                }

                                Button("Запустить") {
                                    runScriptFile(file)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(scriptScheduler.isRunning(file))

                                Button("Остановить") {
                                    stopScriptFile(file)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!scriptScheduler.isRunning(file))

                                Button("Просмотреть") {
                                    previewScriptFile(file)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedScriptPreviewTitle)
                        .font(.headline)

                    ScrollView {
                        Text(selectedScriptPreview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 180, maxHeight: 320)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(scriptScheduler.lastRunTitle)
                            .font(.headline)

                        Spacer()

                        if scriptScheduler.hasRunningScripts {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    ScrollView {
                        Text(scriptScheduler.lastRunOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 160, maxHeight: 320)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }


    private var retentionCard: some View {
        AppCard(title: "Ограничение роста") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Чтобы через год приложение не превратилось в десятигигабайтного дракона, Prometheus должен иметь retention по времени и размеру.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Picker("Хранить", selection: $selectedRetentionDays) {
                        ForEach(retentionDaysOptions, id: \.self) { days in
                            Text("\(days) дней").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Максимум", selection: $selectedRetentionSizeGb) {
                        ForEach(retentionSizeOptions, id: \.self) { gb in
                            Text("\(gb) ГБ").tag(gb)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text("Будущий запуск Prometheus: --storage.tsdb.retention.time=\(selectedRetentionDays)d --storage.tsdb.retention.size=\(selectedRetentionSizeGb)GB")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageInfoCard: some View {
        AppCard(title: "Реальные пути") {
            VStack(alignment: .leading, spacing: 10) {
                PathInfoRow(title: "Всё приложение", value: appSize)
                StorageActionPathInfoRow(
                    title: "Prometheus TSDB",
                    path: manager.prometheusDataURL.path,
                    size: byteCountText(for: folderSize(manager.prometheusDataURL)),
                    buttonTitle: "Удалить",
                    isDisabled: isCleaningData,
                    action: clearMetricsHistory
                )
                StorageActionPathInfoRow(
                    title: "Grafana DB",
                    path: manager.grafanaDatabaseURL.path,
                    size: byteCountText(for: fileSize(manager.grafanaDatabaseURL)),
                    buttonTitle: "Удалить",
                    isDisabled: isCleaningData,
                    action: clearGrafanaDatabase
                )
                StoragePathInfoRow(title: "Metrics history", path: manager.historyMetricsURL.path, size: byteCountText(for: folderSize(manager.historyMetricsURL)))
                StoragePathInfoRow(title: "Scripts", path: manager.scriptsURL.path, size: byteCountText(for: folderSize(manager.scriptsURL)))
                StoragePathInfoRow(title: "Workspace", path: manager.workspaceURL.path, size: byteCountText(for: folderSize(manager.workspaceURL)))
                StoragePathInfoRow(title: "Grafana", path: manager.grafanaURL.path, size: byteCountText(for: folderSize(manager.grafanaURL)))
                StoragePathInfoRow(title: "Prometheus", path: manager.prometheusURL.path, size: byteCountText(for: folderSize(manager.prometheusURL)))
                StorageActionPathInfoRow(
                    title: "Updates",
                    path: manager.updatesURL.path,
                    size: byteCountText(for: folderSize(manager.updatesURL)),
                    buttonTitle: "Очистить кэш",
                    isDisabled: isCleaningData,
                    action: clearUpdateCache
                )
                StorageActionPathInfoRow(
                    title: "Downloads",
                    path: manager.updateDownloadsURL.path,
                    size: byteCountText(for: folderSize(manager.updateDownloadsURL)),
                    buttonTitle: "Очистить",
                    isDisabled: isCleaningData,
                    action: clearUpdateDownloads
                )
                StorageActionPathInfoRow(
                    title: "Staging",
                    path: manager.updateStagingURL.path,
                    size: byteCountText(for: folderSize(manager.updateStagingURL)),
                    buttonTitle: "Очистить",
                    isDisabled: isCleaningData,
                    action: clearUpdateStaging
                )
                StorageActionPathInfoRow(
                    title: "Backups",
                    path: manager.backupsURL.path,
                    size: byteCountText(for: folderSize(manager.backupsURL)),
                    buttonTitle: "Очистить",
                    isDisabled: isCleaningData,
                    action: clearBackups
                )
            }
        }
    }

    private var cleanupCard: some View {
        AppCard(title: "Очистка") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Очистка не удаляет данные сразу: опасные папки и файлы переносятся в quarantine внутри Workspace. Перед очисткой Prometheus/Grafana сервисы останавливаются. Contents/Scripts не трогаем.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prometheus DB / TSDB")
                        .font(.headline)
                    Text(manager.prometheusDataURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Button {
                            checkPrometheusTSDB()
                        } label: {
                            Label("Проверить Prometheus TSDB", systemImage: "stethoscope")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCleaningData)

                        Button(role: .destructive) {
                            clearMetricsHistory()
                        } label: {
                            Label("Очистить Prometheus TSDB", systemImage: "externaldrive.badge.xmark")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCleaningData)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Grafana DB")
                        .font(.headline)
                    Text(manager.grafanaDatabaseURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Удалит datasource, dashboards, users/settings. Файл будет перенесён в quarantine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        clearGrafanaDatabase()
                    } label: {
                        Label("Очистить Grafana DB", systemImage: "cylinder.split.1x2")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCleaningData)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Monitoring history")
                        .font(.headline)
                    Text(manager.historyMetricsURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Чистит pending/failed/imported и state, но не трогает Prometheus TSDB и Scripts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        clearMonitoringData()
                    } label: {
                        Label("Очистить Monitoring history", systemImage: "folder.badge.minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCleaningData)
                }

                Divider()

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Сбросить всё", systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCleaningData)

                    Text("Сбросит Prometheus TSDB, Grafana DB и Monitoring history в quarantine. Scripts останутся на месте.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isCleaningData {
                    ProgressView(cleaningStatusMessage.isEmpty ? "Выполняю очистку..." : cleaningStatusMessage)
                }
            }
        }
    }

    private var logCard: some View {
        AppCard(title: "Состояние") {
            Text(lastActionMessage)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func openScriptsFolder() {
        NSWorkspace.shared.open(manager.scriptsURL)
        lastActionMessage = "Открываю папку Scripts:\n\(manager.scriptsURL.path)"
    }

    private func openHistoryFolder() {
        NSWorkspace.shared.open(manager.historyMetricsURL)
        lastActionMessage = "Открываю папку history:\n\(manager.historyMetricsURL.path)"
    }

    private func openMonitoringFolder() {
        NSWorkspace.shared.open(manager.monitoringURL)
        lastActionMessage = "Открываю папку Monitoring:\n\(manager.monitoringURL.path)"
    }

    private func refreshFileLists() {
        fileListRefreshToken += 1
        appSize = manager.appSizeText()
        lastActionMessage = "Списки файлов обновлены."
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
            metricsFilePath = manager.metricsFilePath()
            appSize = manager.appSizeText()
            refreshServiceStatuses()
            lastActionMessage = "Workspace готов. Grafana и Prometheus запущены автоматически.\nApp: \(manager.appBundleURL.path)\nResources: \(manager.resourcesURL.path)\nWorkspace: \(manager.workspaceURL.path)\nScripts: \(manager.scriptsURL.path)\nMonitoring: \(manager.monitoringURL.path)\n\n\(grafanaCredentialsStatusText())"
            updateMessage = updateManager.updatePlanText()
            fileListRefreshToken += 1
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
            metricsFilePath = manager.metricsFilePath()
            appSize = manager.appSizeText()
            refreshServiceStatuses()
            lastActionMessage = "Grafana и Prometheus запущены.\nWorkspace: \(manager.workspaceURL.path)\nScripts: \(manager.scriptsURL.path)\nMonitoring: \(manager.monitoringURL.path)\n\n\(grafanaCredentialsStatusText())"
            updateMessage = updateManager.updatePlanText()
        } catch {
            refreshServiceStatuses()
            appSize = manager.appSizeText()
            lastActionMessage = "Не удалось запустить Grafana: \(error.localizedDescription)\n\nЕсли это первый запуск или приложение только что собрано, открой раздел “Инструменты” и нажми “Установить компоненты”, чтобы загрузить и установить Grafana и Prometheus."
            metricsFilePath = manager.metricsFilePath()
        }
    }

    private func stopGrafana() {
        do {
            try manager.stopAll()
            refreshServiceStatuses()
            appSize = manager.appSizeText()
            lastActionMessage = "Grafana и Prometheus остановлены. PID-файлы в Workspace/logs очищены."
        } catch {
            refreshServiceStatuses()
            appSize = manager.appSizeText()
            lastActionMessage = "Не удалось остановить сервисы: \(error.localizedDescription)"
        }
    }

    private func showCurrentVersions() {
        updateMessage = updateManager.updatePlanText()
        lastActionMessage = "Текущие версии компонентов показаны в разделе “Инструменты”."
    }

    private func checkUpdates() {
        do {
            updateMessage = try updateManager.checkUpdatesPlaceholder()
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
        let updateManager = self.updateManager
        let manager = self.manager

        DispatchQueue.global(qos: .utility).async {
            do {
                let message = try updateManager.updateComponentsPlaceholder { progress, text in
                    DispatchQueue.main.async {
                        self.updateProgressMessage = text.isEmpty ? "Устанавливаю компоненты..." : text
                        self.updateMessage = "Это может занять до 30 минут."
                    }
                }

                DispatchQueue.main.async {
                    self.finishSyntheticUpdateProgress()
                    self.updateMessage = message
                    self.isUpdatingComponents = false
                    self.updateProgress = 1.0
                    self.updateProgressMessage = "Готово."
                    self.refreshServiceStatuses()
                    self.appSize = manager.appSizeText()
                    self.lastActionMessage = "Компоненты установлены. Теперь можно нажать “Запустить Grafana”."
                }
            } catch {
                DispatchQueue.main.async {
                    self.stopSyntheticUpdateProgress()
                    self.updateMessage = "Не удалось установить компоненты: \(error.localizedDescription)\n\nПроверь интернет, свободное место и попробуй снова."
                    self.isUpdatingComponents = false
                    self.updateProgressMessage = "Ошибка установки."
                    self.refreshServiceStatuses()
                    self.appSize = manager.appSizeText()
                    self.lastActionMessage = self.updateMessage
                }
            }
        }
    }
    private func startSyntheticUpdateProgress() {
        stopSyntheticUpdateProgress()
        updateProgressStartedAt = Date()

        updateProgressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard isUpdatingComponents else {
                stopSyntheticUpdateProgress()
                return
            }

            let elapsed = Date().timeIntervalSince(updateProgressStartedAt ?? Date())
            let twentyMinutes: TimeInterval = 20 * 60
            let syntheticProgress = min(0.99, max(0.01, elapsed / twentyMinutes * 0.99))

            if syntheticProgress >= 0.99 {
                updateProgress = 0.99

                if updateProgressMessage.isEmpty || updateProgressMessage == "Стартую установку компонентов..."  {
                    updateProgressMessage = "Завершаю установку компонентов..."
                }
            } else if syntheticProgress > updateProgress {
                updateProgress = syntheticProgress
            }
        }
    }

    private func finishSyntheticUpdateProgress() {
        stopSyntheticUpdateProgress()
        updateProgress = 1.0
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

    private func copyMetricsPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(metricsFilePath, forType: .string)
        lastActionMessage = "Пути внутри приложения скопированы. Cron запускает скрипты из Contents/Scripts, а скрипты пишут .openmetrics в Contents/Monitoring/metrics/history."
    }

    private func historyFiles() -> [URL] {
        let folders = [manager.historyPendingURL, manager.historyImportedURL, manager.historyFailedURL]
        var files: [URL] = []

        for folder in folders {
            let folderFiles = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            files.append(contentsOf: folderFiles)
        }

        let allowedExtensions: Set<String> = ["openmetrics", "prom", "txt"]
        let metricFiles = files.filter { file in
            allowedExtensions.contains(file.pathExtension.lowercased())
        }

        return metricFiles.sorted { lhs, rhs in
            modificationDate(for: lhs) > modificationDate(for: rhs)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func scriptFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: manager.scriptsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let allowedExtensions: Set<String> = ["sh", "command", "zsh"]
        let scripts = files.filter { file in
            allowedExtensions.contains(file.pathExtension.lowercased())
        }

        return scripts.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    private func previewMetricsFile(_ url: URL) {
        do {
            selectedMetricsPreview = try String(contentsOf: url, encoding: .utf8)
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
            selectedScriptPreview = try String(contentsOf: url, encoding: .utf8)
            selectedScriptPreviewTitle = url.lastPathComponent
            lastActionMessage = "Открыт просмотр скрипта:\n\(url.path)"
        } catch {
            selectedScriptPreview = "Не удалось прочитать скрипт: \(error.localizedDescription)"
            selectedScriptPreviewTitle = url.lastPathComponent
            lastActionMessage = selectedScriptPreview
        }
    }

    private func runScriptFile(_ url: URL) {
        scriptScheduler.runScript(url)
        lastActionMessage = "Запускаю скрипт:\n\(url.path)"
    }

    private func stopScriptFile(_ url: URL) {
        scriptScheduler.stopScript(url)
        lastActionMessage = "Останавливаю скрипт:\n\(url.path)"
    }

    private func scheduleScriptFile(_ url: URL, every option: ScriptScheduleOption) {
        scriptScheduler.scheduleScript(url, every: option.interval, label: option.label)
        lastActionMessage = "Скрипт поставлен в расписание каждые \(option.label):\n\(url.path)"
    }

    private func cancelScriptSchedule(_ url: URL) {
        scriptScheduler.cancelSchedule(for: url)
        lastActionMessage = "Расписание отменено для скрипта:\n\(url.path)"
    }

    private func cancelAllScriptSchedules() {
        scriptScheduler.cancelAllSchedules()
        lastActionMessage = "Все расписания скриптов отменены. Уже запущенные скрипты можно остановить отдельной кнопкой “Остановить”."
    }

    private func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func byteCountText(for bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
                    appSize = manager.appSizeText()
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
                    metricsFilePath = manager.metricsFilePath()
                    appSize = manager.appSizeText()
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
                    metricsFilePath = manager.metricsFilePath()
                    appSize = manager.appSizeText()
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
            successMessage: "Кэш обновлений очищен: downloads и staging пересозданы. Backups не тронуты."
        ) {
            try manager.clearUpdateCache()
        }
    }

    private func clearUpdateDownloads() {
        performCleaning(
            status: "Очищаю downloads...",
            successMessage: "Downloads очищен и пересоздан."
        ) {
            try manager.clearUpdateDownloads()
        }
    }

    private func clearUpdateStaging() {
        performCleaning(
            status: "Очищаю staging...",
            successMessage: "Staging очищен и пересоздан."
        ) {
            try manager.clearUpdateStaging()
        }
    }

    private func clearBackups() {
        performCleaning(
            status: "Очищаю backups...",
            successMessage: "Backups очищен и пересоздан."
        ) {
            try manager.clearBackups()
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
                    appSize = manager.appSizeText()
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
                    metricsFilePath = manager.metricsFilePath()
                    appSize = manager.appSizeText()
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

private struct ScriptScheduleOption: Identifiable {
    let id = UUID()
    let label: String
    let interval: TimeInterval

    static let defaults: [ScriptScheduleOption] = [
        ScriptScheduleOption(label: "5 сек", interval: 5),
        ScriptScheduleOption(label: "10 сек", interval: 10),
        ScriptScheduleOption(label: "30 сек", interval: 30),
        ScriptScheduleOption(label: "1 мин", interval: 60),
        ScriptScheduleOption(label: "5 мин", interval: 300),
        ScriptScheduleOption(label: "15 мин", interval: 900),
        ScriptScheduleOption(label: "1 час", interval: 3600),
        ScriptScheduleOption(label: "6 часов", interval: 21600),
        ScriptScheduleOption(label: "24 часа", interval: 86400)
    ]
}

private struct ScriptScheduleState {
    let path: String
    let label: String
    let interval: TimeInterval
}

@MainActor
private final class ScriptScheduler: ObservableObject {
    @Published private(set) var runningScriptPaths: Set<String> = []
    @Published private(set) var schedules: [String: ScriptScheduleState] = [:]
    @Published private(set) var lastRunTitle = "Вывод последнего запуска"
    @Published private(set) var lastRunOutput = "Запусти скрипт, чтобы увидеть вывод."
    @Published private(set) var scriptStates: [String: String] = [:]

    private let manager: GrafanaManager
    private var timers: [String: Timer] = [:]
    private var processes: [String: Process] = [:]
    private var processLogFiles: [String: URL] = [:]

    init(manager: GrafanaManager) {
        self.manager = manager
    }

    var hasRunningScripts: Bool {
        !runningScriptPaths.isEmpty
    }

    var hasSchedules: Bool {
        !schedules.isEmpty
    }

    func isRunning(_ url: URL) -> Bool {
        runningScriptPaths.contains(url.path)
    }

    func schedule(for url: URL) -> ScriptScheduleState? {
        schedules[url.path]
    }

    func state(for url: URL) -> String? {
        scriptStates[url.path]
    }

    func stateColor(for url: URL) -> Color {
        switch scriptStates[url.path] {
        case "Running":
            return .blue
        case "OK":
            return .green
        case "Error":
            return .red
        case "Stopped":
            return .orange
        default:
            return .secondary
        }
    }

    func runScript(_ url: URL) {
        let path = url.path
        guard !runningScriptPaths.contains(path) else {
            lastRunTitle = "Пропущен: \(url.lastPathComponent)"
            lastRunOutput = "Скрипт уже выполняется, повторный запуск пропущен.\n\(path)"
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            lastRunTitle = "Ошибка: \(url.lastPathComponent)"
            lastRunOutput = "Скрипт не найден:\n\(path)"
            return
        }

        runningScriptPaths.insert(path)
        scriptStates[path] = "Running"
        lastRunTitle = "Запуск: \(url.lastPathComponent)"
        lastRunOutput = "Запускаю скрипт...\n\(path)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [path]
        process.currentDirectoryURL = manager.scriptsURL

        var environment = ProcessInfo.processInfo.environment
        environment["GRAFANA_APP_CONTENTS"] = manager.appBundleURL.appendingPathComponent("Contents", isDirectory: true).path
        environment["GRAFANA_SCRIPTS_DIR"] = manager.scriptsURL.path
        environment["GRAFANA_METRICS_PENDING_DIR"] = manager.historyPendingURL.path
        environment["GRAFANA_MONITORING_DIR"] = manager.monitoringURL.path
        process.environment = environment

        let logDirectory = manager.scriptsURL.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let safeName = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let logURL = logDirectory.appendingPathComponent("\(safeName).log")

        if FileManager.default.fileExists(atPath: logURL.path) {
            try? FileManager.default.removeItem(at: logURL)
        }
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            runningScriptPaths.remove(path)
            scriptStates[path] = "Error"
            lastRunTitle = "Ошибка запуска: \(url.lastPathComponent)"
            lastRunOutput = "Не удалось создать log-файл:\n\(logURL.path)"
            return
        }

        process.standardOutput = logHandle
        process.standardError = logHandle

        processes[path] = process
        processLogFiles[path] = logURL

        process.terminationHandler = { [weak self, weak process] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            let reason = terminatedProcess.terminationReason
            try? logHandle.close()
            let logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""

            DispatchQueue.main.async {
                guard let self else { return }

                self.runningScriptPaths.remove(path)
                if self.processes[path] === process {
                    self.processes.removeValue(forKey: path)
                }
                self.processLogFiles.removeValue(forKey: path)

                if status == 0 && reason == .exit {
                    self.scriptStates[path] = "OK"
                    self.lastRunTitle = "Вывод: \(url.lastPathComponent)"
                    self.lastRunOutput = logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Скрипт выполнен успешно без вывода.\nLog: \(logURL.path)"
                        : "\(logText)\n\nLog: \(logURL.path)"
                } else {
                    self.scriptStates[path] = reason == .uncaughtSignal ? "Stopped" : "Error"
                    let reasonText = reason == .uncaughtSignal ? "signal" : "exit"
                    self.lastRunTitle = "Ошибка: \(url.lastPathComponent)"
                    self.lastRunOutput = "Скрипт завершился с кодом \(status).\nReason: \(reasonText)\n\n\(logText)\n\nLog: \(logURL.path)"
                }
            }
        }

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            runningScriptPaths.remove(path)
            scriptStates[path] = "Error"
            processes.removeValue(forKey: path)
            processLogFiles.removeValue(forKey: path)
            lastRunTitle = "Ошибка запуска: \(url.lastPathComponent)"
            lastRunOutput = error.localizedDescription
        }
    }

    func stopScript(_ url: URL) {
        let path = url.path
        guard let process = processes[path] else {
            lastRunTitle = "Остановка: \(url.lastPathComponent)"
            lastRunOutput = "Скрипт сейчас не выполняется."
            return
        }

        terminateProcessTree(process)
        scriptStates[path] = "Stopped"
        lastRunTitle = "Остановка: \(url.lastPathComponent)"
        lastRunOutput = "Отправлен terminate для процесса скрипта и его дочерних процессов.\n\(path)"
    }

    private func terminateProcessTree(_ process: Process) {
        let pid = process.processIdentifier
        terminateChildren(of: pid)
        process.terminate()
    }

    private func terminateChildren(of pid: Int32) {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", "\(pid)"]

        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = Pipe()

        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let childPids = output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        for childPid in childPids {
            terminateChildren(of: childPid)
            kill(childPid, SIGTERM)
        }
    }

    func scheduleScript(_ url: URL, every interval: TimeInterval, label: String) {
        let path = url.path
        timers[path]?.invalidate()

        schedules[path] = ScriptScheduleState(path: path, label: label, interval: interval)

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runScript(url)
            }
        }
        timer.tolerance = min(interval * 0.1, 30)
        timers[path] = timer

        runScript(url)
    }

    func cancelSchedule(for url: URL) {
        let path = url.path
        timers[path]?.invalidate()
        timers.removeValue(forKey: path)
        schedules.removeValue(forKey: path)
    }

    func cancelAllSchedules() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
        schedules.removeAll()
        scriptStates = scriptStates.filter { runningScriptPaths.contains($0.key) }
        lastRunTitle = "Расписания отменены"
        lastRunOutput = "Все расписания скриптов отменены. Уже выполняющиеся скрипты продолжают работать, их можно остановить отдельной кнопкой “Остановить”."
    }
}

private enum AppSection: Hashable {
    case overview
    case metrics
    case scripts
    case cleanup
    case update
}

private enum ServiceStatus {
    case running
    case stopped
    case warning

    var title: String {
        switch self {
        case .running:
            return "работает"
        case .stopped:
            return "остановлен"
        case .warning:
            return "внимание"
        }
    }

    var systemImage: String {
        switch self {
        case .running:
            return "checkmark.circle.fill"
        case .stopped:
            return "pause.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .running:
            return .green
        case .stopped:
            return .secondary
        case .warning:
            return .orange
        }
    }
}

private struct PathInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)
                .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


private struct StoragePathInfoRow: View {
    let title: String
    let path: String
    let size: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)
                .frame(width: 110, alignment: .leading)

            Text(path)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(size)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
    }
}

private struct StorageActionPathInfoRow: View {
    let title: String
    let path: String
    let size: String
    let buttonTitle: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)
                .frame(width: 110, alignment: .leading)

            Text(path)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(size)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)
        }
    }
}

private struct ServiceRow: View {
    let name: String
    let status: ServiceStatus

    var body: some View {
        Label {
            HStack {
                Text(name)
                Spacer()
                Text(status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
        }
    }
}

private struct StatusPill: View {
    let name: String
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
            Text(name)
                .fontWeight(.medium)
            Text(status.title)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
    }
}

private struct AppCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    ContentView()
}
