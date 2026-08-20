//
//  GrafanaCardConstructor.swift
//  Grafana
//
//  Created by SITIS on 8/18/26.
//

import SwiftUI

enum GrafanaConstructorProbe: String, CaseIterable, Identifiable, Hashable {
    case ping
    case latency
    case loss
    case dns
    case name
    case tcp
    case http
    case https
    case tls
    case cpu
    case ram
    case disk
    case load
    case uptime
    case swap
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: return "PING"
        case .latency: return "LATENCY"
        case .loss: return "LOSS"
        case .dns: return "DNS"
        case .name: return "NAME"
        case .tcp: return "TCP"
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .tls: return "TLS"
        case .cpu: return "CPU"
        case .ram: return "RAM"
        case .disk: return "DISK"
        case .load: return "LOAD"
        case .uptime: return "UPTIME"
        case .swap: return "SWAP"
        case .network: return "NET"
        }
    }

    var requiresSSH: Bool {
        switch self {
        case .cpu, .ram, .disk, .load, .uptime, .swap, .network:
            return true
        default:
            return false
        }
    }
}

struct GrafanaConstructorHost: Identifiable, Hashable {
    let id: UUID
    var name: String
    var target: String
    var probes: Set<GrafanaConstructorProbe>
    var sshUser: String

    init(
        id: UUID = UUID(),
        name: String = "",
        target: String = "",
        probes: Set<GrafanaConstructorProbe> = [.ping, .latency],
        sshUser: String = ""
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.probes = probes
        self.sshUser = sshUser
    }
}

struct GrafanaConstructorInterval: Identifiable, Hashable {
    var seconds: Int

    static let tenSeconds = GrafanaConstructorInterval(seconds: 10)
    static let thirtySeconds = GrafanaConstructorInterval(seconds: 30)
    static let oneMinute = GrafanaConstructorInterval(seconds: 60)
    static let fiveMinutes = GrafanaConstructorInterval(seconds: 300)

    var id: Int { seconds }
    var rawValue: String { "\(seconds)s" }

    var title: String {
        if seconds < 60 {
            return "\(seconds) сек"
        }

        if seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return "\(minutes) мин"
        }

        return "\(seconds) сек"
    }
}

struct GrafanaConstructorGeneratedItem: Identifiable, Hashable {
    let id: String
    let dashboardName: String
    let packagePath: String
    let interval: String
    let hostCount: Int
}

struct GrafanaCardConstructor: View {
    @Binding var dashboardName: String
    @Binding var interval: GrafanaConstructorInterval
    @Binding var hosts: [GrafanaConstructorHost]
    let onCreateDashboard: () -> Void

    var generatedItems: [GrafanaConstructorGeneratedItem] = []
    var onDeleteGeneratedItem: (GrafanaConstructorGeneratedItem) -> Void = { _ in }

    private let externalProbes: [GrafanaConstructorProbe] = [
        .ping, .latency, .loss, .dns, .name, .tcp, .http, .https, .tls
    ]

    private let sshProbes: [GrafanaConstructorProbe] = [
        .cpu, .ram, .disk, .load, .uptime, .swap, .network
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            dashboardSection

            Divider()

            hostsSection

            if !generatedItems.isEmpty {
                Divider()
                generatedSection
            }

            Divider()

            HStack {
                Spacer()

                Button {
                    onCreateDashboard()
                } label: {
                    Label("Создать дашборд", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreateDashboard)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Конструктор мониторинга")
                    .font(.title2.weight(.semibold))

                Text("Добавь узлы, выбери нужные проверки — Grafana.app подготовит сбор метрик и отдельный дашборд.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Дашборд")
                .font(.headline)

            TextField("Например: Офисная инфраструктура", text: $dashboardName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Text("Интервал сбора")
                    .font(.subheadline.weight(.semibold))

                TextField("30", text: intervalSecondsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                Text("сек")
                    .foregroundStyle(.secondary)

                Button("10") {
                    interval = .tenSeconds
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("30") {
                    interval = .thirtySeconds
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("60") {
                    interval = .oneMinute
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("300") {
                    interval = .fiveMinutes
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }

            Text("Интервал задаётся в секундах и определяет частоту запуска generated-скрипта. После первого успешного сбора его можно автоматически скорректировать по реальной длительности выполнения задачи.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var intervalSecondsText: Binding<String> {
        Binding(
            get: {
                String(interval.seconds)
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard let seconds = Int(digits), seconds > 0 else {
                    return
                }
                interval = GrafanaConstructorInterval(seconds: seconds)
            }
        )
    }

    private var hostsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Узлы")
                    .font(.headline)

                Spacer()

                Button {
                    hosts.append(GrafanaConstructorHost())
                } label: {
                    Label("Добавить узел", systemImage: "plus")
                }
            }

            ForEach($hosts) { $host in
                hostCard(host: $host)
            }
        }
    }

    private func hostCard(host: Binding<GrafanaConstructorHost>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Имя узла", text: host.name)
                    .textFieldStyle(.roundedBorder)

                TextField("IP, hostname или NetBIOS-имя", text: host.target)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                    removeHost(host.wrappedValue.id)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(hosts.count <= 1)
                .help("Удалить узел")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Быстрый выбор")
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }

                HStack(spacing: 8) {
                    presetButton("Доступность", probes: [.ping, .latency, .loss, .dns], host: host)
                    presetButton("Сервер", probes: [.ping, .latency, .loss, .cpu, .ram, .disk, .load, .uptime, .network], host: host)
                    presetButton("Веб-сервис", probes: [.ping, .latency, .http, .https, .tls], host: host)
                    presetButton("Всё", probes: Set(GrafanaConstructorProbe.allCases), host: host)
                }
            }

            probeSection(
                title: "Без авторизации",
                subtitle: "Проверки, которые можно выполнить снаружи.",
                probes: externalProbes,
                host: host
            )

            probeSection(
                title: "Через SSH",
                subtitle: "Для CPU, RAM, дисков и других внутренних показателей нужен доступ по SSH-ключу.",
                probes: sshProbes,
                host: host
            )

            if host.wrappedValue.probes.contains(where: { $0.requiresSSH }) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("SSH-доступ", systemImage: "key")
                        .font(.subheadline.weight(.semibold))

                    TextField("SSH user, например root или admin", text: host.sshUser)
                        .textFieldStyle(.roundedBorder)

                    if host.wrappedValue.sshUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Для выбранных SSH-проверок укажи пользователя. Доступ по ключу должен быть настроен заранее.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Grafana.app будет использовать уже настроенный SSH-доступ по ключу. Пароль в Конструкторе не сохраняется.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func probeSection(
        title: String,
        subtitle: String,
        probes: [GrafanaConstructorProbe],
        host: Binding<GrafanaConstructorHost>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(probes) { probe in
                    probeButton(probe, host: host)
                }
            }
        }
    }

    private func probeButton(
        _ probe: GrafanaConstructorProbe,
        host: Binding<GrafanaConstructorHost>
    ) -> some View {
        let selected = host.wrappedValue.probes.contains(probe)

        return Button {
            if selected {
                host.wrappedValue.probes.remove(probe)
            } else {
                host.wrappedValue.probes.insert(probe)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(probe.title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func presetButton(
        _ title: String,
        probes: Set<GrafanaConstructorProbe>,
        host: Binding<GrafanaConstructorHost>
    ) -> some View {
        Button(title) {
            host.wrappedValue.probes = probes
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func removeHost(_ id: UUID) {
        guard hosts.count > 1 else {
            return
        }
        hosts.removeAll { $0.id == id }
    }

    private var canCreateDashboard: Bool {
        let trimmedDashboardName = dashboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDashboardName.isEmpty else {
            return false
        }

        let configuredHosts = hosts.filter { host in
            !host.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !host.probes.isEmpty
        }

        guard !configuredHosts.isEmpty else {
            return false
        }

        return configuredHosts.allSatisfy { host in
            let requiresSSH = host.probes.contains(where: { $0.requiresSSH })
            if requiresSSH {
                return !host.sshUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
    }

    private var generatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Сгенерированные мониторинги")
                        .font(.headline)

                    Text("Удаление отсюда должно убрать весь комплект: расписание, generated-скрипт, config.json, dashboard JSON и provisioning-копию Grafana.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ForEach(generatedItems) { item in
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.dashboardName)
                            .font(.subheadline.weight(.semibold))

                        Text("\(item.hostCount) узл. · \(item.interval)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(item.packagePath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        onDeleteGeneratedItem(item)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

