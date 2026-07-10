//
//  GrafanaWindowView.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//


//
//  GrafanaWindowView.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import SwiftUI

struct GrafanaWindowView: View {
    let username: String
    let password: String
    let preferredSize: CGSize
    let onClose: () -> Void

    private let grafanaURL = URL(string: "http://127.0.0.1:3000/login")!

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GrafanaWebView(
                url: grafanaURL,
                username: username,
                password: password
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(14)
            .help("Закрыть окно Grafana")
        }
        .frame(
            width: preferredSize.width,
            height: preferredSize.height
        )
    }
}
