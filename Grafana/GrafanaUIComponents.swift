//
//  GrafanaUIComponents.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import AppKit
import SwiftUI

enum AppSection: Hashable {
    case overview
    case metrics
    case scripts
    case cleanup
    case update

    var title: String {
        switch self {
        case .overview:
            return "Главная"
        case .metrics:
            return "Метрики"
        case .scripts:
            return "Скрипты"
        case .cleanup:
            return "Очистка"
        case .update:
            return "Инструменты"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.67percent"
        case .metrics:
            return "chart.xyaxis.line"
        case .scripts:
            return "terminal"
        case .cleanup:
            return "trash"
        case .update:
            return "shippingbox"
        }
    }
}

enum ServiceStatus {
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

struct AppCard<Content: View>: View {
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

struct StatusPill: View {
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

struct SidebarGrafanaButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                GrafanaLogoMark(size: CGSize(width: 150, height: 120), textSize: 78, cornerRadius: 20)

                Text("Открыть Grafana")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Открыть Grafana UI")
    }
}

struct GrafanaHeaderCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            GrafanaLogoMark(size: CGSize(width: 82, height: 82), textSize: 48, cornerRadius: 22)

            VStack(alignment: .leading, spacing: 6) {
                Text("Grafana.app")
                    .font(.largeTitle.bold())

                Text("Локальный комплект Grafana + Prometheus + OpenMetrics importer внутри macOS-приложения.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }
}

struct GrafanaLogCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Журнал", systemImage: "text.alignleft")
                .font(.headline)

            ScrollView {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 150, maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct GrafanaRetentionCard: View {
    @Binding var selectedRetentionDays: Int
    @Binding var selectedRetentionSizeGb: Int
    let retentionDayOptions: [Int]
    let retentionSizeOptionsGb: [Int]

    var body: some View {
        AppCard(title: "Хранение Prometheus") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Настройки применяются при запуске Prometheus.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Picker("Дней", selection: $selectedRetentionDays) {
                        ForEach(retentionDayOptions, id: \.self) { days in
                            Text("\(days) дней").tag(days)
                        }
                    }
                    .frame(width: 180)

                    Picker("Максимум", selection: $selectedRetentionSizeGb) {
                        ForEach(retentionSizeOptionsGb, id: \.self) { size in
                            Text("\(size) GB").tag(size)
                        }
                    }
                    .frame(width: 180)
                }
            }
        }
    }
}

private struct GrafanaLogoMark: View {
    let size: CGSize
    let textSize: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.04, blue: 0.10),
                            Color(red: 0.01, green: 0.13, blue: 0.28),
                            Color(red: 0.00, green: 0.03, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.cyan.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: .blue.opacity(0.25), radius: 14, x: 0, y: 0)

            Text("G")
                .font(.system(size: textSize, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue, .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .cyan.opacity(0.75), radius: 8, x: 0, y: 0)
        }
        .frame(width: size.width, height: size.height)
    }
}
