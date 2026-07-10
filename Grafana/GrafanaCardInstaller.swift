//
//  GrafanaCardInstaller.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import SwiftUI

struct GrafanaCardInstaller: View {
    let isInstalling: Bool
    let installProgress: Double
    let installProgressText: String
    let installerMessage: String

    let onShowVersions: () -> Void
    let onCheckAccess: () -> Void
    let onInstall: () -> Void

    var body: some View {
        AppCard(title: "Компоненты") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Устанавливает Grafana и Prometheus внутрь Grafana.app/Contents/Workspace.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        onShowVersions()
                    } label: {
                        Label("Текущие версии", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstalling)

                    Button {
                        onCheckAccess()
                    } label: {
                        Label("Проверить доступ", systemImage: "network")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstalling)

                    Button {
                        onInstall()
                    } label: {
                        Label("Установить компоненты", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                }

                if isInstalling {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: installProgress)
                            .progressViewStyle(.linear)

                        Text(installProgressText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(installerMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
