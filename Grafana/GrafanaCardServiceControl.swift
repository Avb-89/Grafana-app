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

    let onStart: () -> Void
    let onStop: () -> Void
    let onOpenGrafana: () -> Void

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
