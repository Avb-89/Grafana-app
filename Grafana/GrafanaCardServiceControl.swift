//
//  GrafanaCardServiceControl.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import SwiftUI

struct GrafanaCardServiceControl: View {
    let grafanaStatus: ServiceStatus
    let prometheusStatus: ServiceStatus
    let credentialsStatusText: String
    let canOpenGrafana: Bool
    let canCopyPassword: Bool

    let onStart: () -> Void
    let onStop: () -> Void
    let onOpenGrafana: () -> Void
    let onCopyPassword: () -> Void

    var body: some View {
        AppCard(title: "Запуск") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Одна кнопка поднимает Grafana и Prometheus из Grafana.app/Contents/Workspace.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        onStart()
                    } label: {
                        Label("Запустить Grafana", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onStop()
                    } label: {
                        Label("Остановить", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onOpenGrafana()
                    } label: {
                        Label("Открыть Grafana", systemImage: "macwindow")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canOpenGrafana)

                    Button {
                        onCopyPassword()
                    } label: {
                        Label("Скопировать пароль", systemImage: "key.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canCopyPassword)
                }

                HStack(spacing: 18) {
                    StatusPill(name: "Grafana", status: grafanaStatus)
                    StatusPill(name: "Prometheus", status: prometheusStatus)
                }

                Text(credentialsStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
