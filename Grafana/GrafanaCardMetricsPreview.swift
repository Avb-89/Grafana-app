//
//  GrafanaCardMetricsPreview.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import SwiftUI

struct GrafanaCardMetricsPreview: View {
    let historyFiles: [URL]
    let selectedPreviewTitle: String
    let selectedPreviewText: String

    let onOpenHistoryFolder: () -> Void
    let onRefresh: () -> Void
    let onClearPreview: () -> Void
    let onPreviewFile: (URL) -> Void

    var body: some View {
        AppCard(title: "Метрики") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Показывает файлы из Monitoring/metrics/history: pending, imported и failed.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        onOpenHistoryFolder()
                    } label: {
                        Label("Открыть history", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onRefresh()
                    } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onClearPreview()
                    } label: {
                        Label("Очистить просмотр", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if historyFiles.isEmpty {
                    Text("Файлы метрик пока не найдены.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Файлы history")
                            .font(.headline)

                        ForEach(historyFiles, id: \.path) { file in
                            Button {
                                onPreviewFile(file)
                            } label: {
                                HStack {
                                    Image(systemName: iconName(for: file))
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.lastPathComponent)
                                            .lineLimit(1)

                                        Text(file.deletingLastPathComponent().lastPathComponent)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedPreviewTitle)
                        .font(.headline)

                    ScrollView {
                        Text(selectedPreviewText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 220)
                    .padding(12)
                    .background(.quaternary.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func iconName(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "prom", "openmetrics":
            return "chart.xyaxis.line"
        case "txt":
            return "doc.text"
        default:
            return "doc"
        }
    }
}
