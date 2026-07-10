//
//  GrafanaCardScripts.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import SwiftUI

struct GrafanaCardScripts: View {
    let scriptFiles: [URL]
    @ObservedObject var scriptManager: GrafanaScriptManager

    let selectedPreviewTitle: String
    let selectedPreviewText: String

    let onOpenScriptsFolder: () -> Void
    let onRefresh: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    let onStartAllSchedules: () -> Void
    let onCancelAllSchedules: () -> Void
    let onRunScript: (URL) -> Void
    let onStopScript: (URL) -> Void
    let onStartSchedule: (URL) -> Void
    let onPreviewScript: (URL) -> Void

    var body: some View {
        AppCard(title: "Скрипты") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Показывает пользовательские скрипты из Grafana.app/Contents/Scripts и позволяет запускать их вручную или по расписанию.")
                    .foregroundStyle(.secondary)

                toolbar

                if scriptFiles.isEmpty {
                    Text("Скрипты пока не найдены. Импортируй .sh, .zsh или .command файл.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    scriptsList
                }

                Divider()

                previewBlock

                Divider()

                outputBlock
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                onOpenScriptsFolder()
            } label: {
                Label("Открыть Scripts", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button {
                onRefresh()
            } label: {
                Label("Обновить", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                onExport()
            } label: {
                Label("Экспорт", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            Button {
                onImport()
            } label: {
                Label("Импорт", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                onStartAllSchedules()
            } label: {
                Label("Запустить расписания", systemImage: "timer")
            }
            .buttonStyle(.borderedProminent)
            .disabled(scriptFiles.isEmpty)

            Button {
                onCancelAllSchedules()
            } label: {
                Label("Остановить расписания", systemImage: "timer.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!scriptManager.hasSchedules)
        }
    }

    private var scriptsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Файлы скриптов")
                .font(.headline)

            ForEach(scriptFiles, id: \.path) { file in
                scriptRow(file)
            }
        }
    }

    private func scriptRow(_ file: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: scriptManager.isRunning(file) ? "terminal.fill" : "terminal")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)

                    Text(scriptManager.state(for: file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let schedule = scriptManager.schedule(for: file), schedule.isActive {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Расписание: \(schedule.intervalText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let nextRunDate = schedule.nextRunDate {
                            Text("Следующий запуск: \(nextRunDate.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(
                    "Интервал: 5s, 10m, 1h",
                    text: Binding(
                        get: { scriptManager.scheduleText(for: file) },
                        set: { scriptManager.updateScheduleText($0, for: file) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)

                Button {
                    onStartSchedule(file)
                } label: {
                    Label("По расписанию", systemImage: "timer")
                }
                .buttonStyle(.bordered)

                Button {
                    onRunScript(file)
                } label: {
                    Label("Запустить 1 раз", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(scriptManager.isRunning(file))

                Button {
                    onStopScript(file)
                } label: {
                    Label("Остановить", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!scriptManager.isRunning(file) && scriptManager.schedule(for: file) == nil)

                Button {
                    onPreviewScript(file)
                } label: {
                    Label("Просмотреть", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedPreviewTitle)
                .font(.headline)

            ScrollView {
                Text(selectedPreviewText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180)
            .padding(12)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var outputBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scriptManager.lastRunTitle)
                .font(.headline)

            ScrollView {
                Text(scriptManager.lastRunOutput)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160)
            .padding(12)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
