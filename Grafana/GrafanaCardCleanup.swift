//
//  GrafanaCardCleanup.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//


//
//  GrafanaCardCleanup.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import SwiftUI

struct GrafanaCardCleanup: View {
    let isCleaning: Bool
    let cleaningMessage: String

    let onCheckPrometheusTSDB: () -> Void
    let onClearPrometheusTSDB: () -> Void
    let onClearGrafanaDatabase: () -> Void
    let onClearMonitoringHistory: () -> Void
    let onResetRuntimeData: () -> Void

    var body: some View {
        AppCard(title: "Очистка") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Опасные действия для runtime-данных. Очистка переносит данные в quarantine или пересоздаёт рабочие папки через GrafanaManager.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    cleanupButton(
                        title: "Проверить Prometheus TSDB",
                        systemImage: "checkmark.shield",
                        role: nil,
                        action: onCheckPrometheusTSDB
                    )

                    cleanupButton(
                        title: "Очистить Prometheus TSDB",
                        systemImage: "chart.xyaxis.line",
                        role: .destructive,
                        action: onClearPrometheusTSDB
                    )

                    cleanupButton(
                        title: "Очистить Grafana DB",
                        systemImage: "cylinder.split.1x2",
                        role: .destructive,
                        action: onClearGrafanaDatabase
                    )

                    cleanupButton(
                        title: "Очистить Monitoring history",
                        systemImage: "folder.badge.minus",
                        role: .destructive,
                        action: onClearMonitoringHistory
                    )

                    Divider()

                    cleanupButton(
                        title: "Сбросить runtime-данные",
                        systemImage: "exclamationmark.triangle.fill",
                        role: .destructive,
                        action: onResetRuntimeData
                    )
                }

                if isCleaning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.linear)

                        Text(cleaningMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if !cleaningMessage.isEmpty {
                    Text(cleaningMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cleanupButton(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isCleaning)
    }
}
