import SwiftUI

struct GrafanaCardTasks: View {
    @ObservedObject var taskManager: GrafanaTaskManager

    let onStartTask: (GrafanaMonitoringTask) -> Void
    let onStopTask: (GrafanaMonitoringTask) -> Void
    let onDeleteTask: (GrafanaMonitoringTask) -> Void
    let onShowDetails: (GrafanaMonitoringTask) -> Void
    let onStartAll: () -> Void
    let onStopAll: () -> Void
    let onOpenScripts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "list.clipboard")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Задачи мониторинга")
                        .font(.title2.weight(.semibold))
                    Text("Созданные в Конструкторе задачи: запуск, остановка, состояние, подробности и удаление.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onStartAll) {
                    Label("Запустить все задачи", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskManager.tasks.isEmpty)

                Button(action: onStopAll) {
                    Label("Остановить все задачи", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!taskManager.tasks.contains { isRunning($0) })
            }

            Divider()

            if taskManager.tasks.isEmpty {
                ContentUnavailableView(
                    "Задач пока нет",
                    systemImage: "list.clipboard",
                    description: Text("Создай новую задачу в Конструкторе.")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(taskManager.tasks) { task in
                        taskRow(task)

                        if task.id != taskManager.tasks.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: GrafanaMonitoringTask) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(task.dashboardName)
                        .font(.headline)

                    Text(task.runtime.state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor(for: task.runtime.state))
                }

                Text("\(task.hostCount) узл. · \(task.interval)s")
                    .foregroundStyle(.secondary)

                Text(task.runtime.activity)
                    .foregroundStyle(.secondary)

                Text(task.packagePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isRunning(task) {
                Button {
                    onStopTask(task)
                } label: {
                    Label("Остановить", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    onStartTask(task)
                } label: {
                    Label("Запустить", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                onShowDetails(task)
            } label: {
                Label("Подробнее", systemImage: "info.circle")
            }
            .buttonStyle(.bordered)

            Button(action: onOpenScripts) {
                Label("Скрипты", systemImage: "terminal")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                onDeleteTask(task)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 14)
    }

    private func statusColor(for state: GrafanaMonitoringTaskState) -> Color {
        switch state {
        case .running:
            return .green
        case .starting, .reconnecting:
            return .orange
        case .waitingForPassword, .waitingForSudoPassword:
            return .yellow
        case .error:
            return .red
        case .notStarted, .stopped:
            return .secondary
        }
    }

    private func isRunning(_ task: GrafanaMonitoringTask) -> Bool {
        task.runtime.state == .running ||
        task.runtime.state == .starting ||
        task.runtime.state == .reconnecting
    }
}
