//
//  GrafanaCardTaskDetails.swift
//  Grafana
//
//  Created by SITIS on 8/20/26.
//

import SwiftUI

struct GrafanaCardTaskDetails: View {
    let task: GrafanaMonitoringTask
    let onBack: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onOpenScript: () -> Void
    let onAdjustIntervalAutomatically: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Label("Задачи", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.dashboardName)
                        .font(.title2.weight(.semibold))

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)

                        Text(task.runtime.state.title)
                            .foregroundStyle(statusColor)
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Spacer()

                if isRunning {
                    Button(action: onStop) {
                        Label("Остановить", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onStart) {
                        Label("Запустить", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(action: onOpenScript) {
                    Label("Скрипт", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            detailsSection(title: "Состояние") {
                detailRow("Последний успешный сбор", value: formattedDate(task.runtime.lastSuccessfulCollection))
                detailRow("Длительность последнего сбора", value: formattedDuration(task.runtime.lastCollectionDuration))
                detailRow("Следующий запуск", value: formattedDate(task.runtime.nextCollectionDate))
            }

            detailsSection(title: "Интервал сбора") {
                detailRow("Текущий интервал", value: task.interval)

                if let recommendedInterval {
                    detailRow("Рекомендуемый интервал", value: "\(recommendedInterval) сек")

                    Button {
                        onAdjustIntervalAutomatically(recommendedInterval)
                    } label: {
                        Label("Скорректировать запуск", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Интервал рассчитывается по длительности последнего успешного сбора: время выполнения округляется вверх и добавляется 1 секунда, чтобы новый запуск не пересекался с предыдущим.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Автокоррекция станет доступна после первого успешного сбора, когда Grafana.app узнает реальную длительность выполнения скрипта.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            detailsSection(title: "Задача") {
                detailRow("Узлов", value: String(task.hostCount))
                detailRow("Интервал", value: task.interval)
                detailRow("Dashboard UID", value: task.dashboardUID, monospaced: true)
                detailRow("Generated script", value: task.scriptPath, monospaced: true)
                detailRow("Пакет задачи", value: task.packagePath, monospaced: true)
            }

            detailsSection(title: "Диагностика") {
                if let error = task.runtime.lastError, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else {
                    Text("Ошибок нет")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func detailsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 210, alignment: .leading)

            if monospaced {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
    }

    private var recommendedInterval: Int? {
        guard let duration = task.runtime.lastCollectionDuration else {
            return nil
        }
        return Int(ceil(duration)) + 1
    }

    private var isRunning: Bool {
        task.runtime.state == .running ||
        task.runtime.state == .starting ||
        task.runtime.state == .reconnecting
    }

    private var statusColor: Color {
        switch task.runtime.state {
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

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "—"
        }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func formattedDuration(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "—"
        }
        return String(format: "%.2f сек", duration)
    }
}
