//
//  GrafanaTaskManager.swift
//  Grafana
//
//  Created by SITIS on 8/20/26.
//


import Foundation
import Combine

enum GrafanaMonitoringTaskDesiredState: String, Codable, Hashable {
    case running
    case stopped
}

enum GrafanaMonitoringTaskState: String, Codable, Hashable {
    case notStarted
    case starting
    case running
    case stopped
    case waitingForPassword
    case waitingForSudoPassword
    case reconnecting
    case error

    var title: String {
        switch self {
        case .notStarted:
            return "Не запущена"
        case .starting:
            return "Запускается"
        case .running:
            return "Работает"
        case .stopped:
            return "Остановлена"
        case .waitingForPassword:
            return "Ожидает пароль"
        case .waitingForSudoPassword:
            return "Ожидает sudo-пароль"
        case .reconnecting:
            return "Переподключение"
        case .error:
            return "Ошибка"
        }
    }
}

struct GrafanaMonitoringTaskRuntimeStatus: Codable, Hashable {
    var state: GrafanaMonitoringTaskState
    var activity: String
    var lastSuccessfulCollection: Date?
    var lastCollectionDuration: TimeInterval?
    var nextCollectionDate: Date?
    var lastError: String?

    static let idle = GrafanaMonitoringTaskRuntimeStatus(
        state: .notStarted,
        activity: "Ожидает запуска",
        lastSuccessfulCollection: nil,
        lastCollectionDuration: nil,
        nextCollectionDate: nil,
        lastError: nil
    )
}

struct GrafanaMonitoringTask: Identifiable, Codable, Hashable {
    let id: UUID
    var dashboardName: String
    var dashboardUID: String
    var interval: String
    var hostCount: Int
    var packagePath: String
    var scriptPath: String
    var desiredState: GrafanaMonitoringTaskDesiredState
    var runtime: GrafanaMonitoringTaskRuntimeStatus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        dashboardName: String,
        dashboardUID: String,
        interval: String,
        hostCount: Int,
        packagePath: String,
        scriptPath: String,
        desiredState: GrafanaMonitoringTaskDesiredState = .stopped,
        runtime: GrafanaMonitoringTaskRuntimeStatus = .idle,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dashboardName = dashboardName
        self.dashboardUID = dashboardUID
        self.interval = interval
        self.hostCount = hostCount
        self.packagePath = packagePath
        self.scriptPath = scriptPath
        self.desiredState = desiredState
        self.runtime = runtime
        self.createdAt = createdAt
    }
}

@MainActor
final class GrafanaTaskManager: ObservableObject {
    static let shared = GrafanaTaskManager()

    @Published private(set) var tasks: [GrafanaMonitoringTask] = []

    private init() {}

    func replaceTasks(_ tasks: [GrafanaMonitoringTask]) {
        self.tasks = tasks.sorted {
            $0.createdAt > $1.createdAt
        }
    }

    func task(dashboardUID: String) -> GrafanaMonitoringTask? {
        tasks.first { $0.dashboardUID == dashboardUID }
    }

    func upsert(_ task: GrafanaMonitoringTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else if let index = tasks.firstIndex(where: { $0.dashboardUID == task.dashboardUID }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }

        tasks.sort {
            $0.createdAt > $1.createdAt
        }
    }

    func remove(dashboardUID: String) {
        tasks.removeAll { $0.dashboardUID == dashboardUID }
    }

    func setDesiredState(
        _ desiredState: GrafanaMonitoringTaskDesiredState,
        dashboardUID: String
    ) {
        guard let index = tasks.firstIndex(where: { $0.dashboardUID == dashboardUID }) else {
            return
        }

        tasks[index].desiredState = desiredState
    }

    func updateInterval(_ interval: String, dashboardUID: String) {
        guard let index = tasks.firstIndex(where: { $0.dashboardUID == dashboardUID }) else {
            return
        }

        tasks[index].interval = interval
    }

    func updateRuntime(
        dashboardUID: String,
        state: GrafanaMonitoringTaskState,
        activity: String,
        lastSuccessfulCollection: Date? = nil,
        lastCollectionDuration: TimeInterval? = nil,
        nextCollectionDate: Date? = nil,
        lastError: String? = nil
    ) {
        guard let index = tasks.firstIndex(where: { $0.dashboardUID == dashboardUID }) else {
            return
        }

        tasks[index].runtime.state = state
        tasks[index].runtime.activity = activity

        if let lastSuccessfulCollection {
            tasks[index].runtime.lastSuccessfulCollection = lastSuccessfulCollection
        }

        if let lastCollectionDuration {
            tasks[index].runtime.lastCollectionDuration = lastCollectionDuration
        }

        tasks[index].runtime.nextCollectionDate = nextCollectionDate
        tasks[index].runtime.lastError = lastError
    }
}
