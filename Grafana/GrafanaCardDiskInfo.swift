//
//  GrafanaCardDiskInfo.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import SwiftUI

struct GrafanaDiskInfoItem: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    let sizeText: String
    let actionTitle: String?
    let actionSystemImage: String?
    let action: (() -> Void)?

    init(
        title: String,
        path: String,
        sizeText: String,
        actionTitle: String? = nil,
        actionSystemImage: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.path = path
        self.sizeText = sizeText
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.action = action
    }
}

struct GrafanaCardDiskInfo: View {
    let items: [GrafanaDiskInfoItem]

    var body: some View {
        AppCard(title: "Реальные пути") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Показывает фактические папки и размеры данных внутри Grafana.app.")
                    .foregroundStyle(.secondary)

                if items.isEmpty {
                    Text("Нет данных о папках и размерах.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            diskInfoRow(item)
                        }
                    }
                }
            }
        }
    }

    private func diskInfoRow(_ item: GrafanaDiskInfoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)

                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()

                Text(item.sizeText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let action = item.action,
               let actionTitle = item.actionTitle,
               let actionSystemImage = item.actionSystemImage {
                Button {
                    action()
                } label: {
                    Label(actionTitle, systemImage: actionSystemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
