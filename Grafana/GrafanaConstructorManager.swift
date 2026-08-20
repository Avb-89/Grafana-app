//
//  GrafanaConstructorManager.swift
//  Grafana
//
//  Created by SITIS on 8/18/26.
//


import Foundation

struct GrafanaConstructorPackageResult {
    let taskID: UUID
    let directoryURL: URL
    let scriptURL: URL
    let configURL: URL
    let dashboardURL: URL
    let dashboardUID: String
}

struct GrafanaGeneratedPackage: Identifiable, Hashable {
    let id: String
    let taskID: UUID
    let dashboardName: String
    let dashboardUID: String
    let interval: String
    let hostCount: Int
    let packageURL: URL
    let scriptURL: URL
    let configURL: URL
    let dashboardURL: URL
    let desiredState: GrafanaMonitoringTaskDesiredState
    let createdAt: Date
}

enum GrafanaConstructorManagerError: LocalizedError {
    case emptyDashboardName
    case noHosts

    var errorDescription: String? {
        switch self {
        case .emptyDashboardName:
            return "Укажи название дашборда."
        case .noHosts:
            return "Добавь хотя бы один узел с адресом и выбранной проверкой."
        }
    }
}

final class GrafanaConstructorManager {
    static let shared = GrafanaConstructorManager()

    private let fileManager = FileManager.default
    private let manager = GrafanaManager.shared

    private init() {}

    func generatedPackages() -> [GrafanaGeneratedPackage] {
        let generatedRootURL = manager.scriptsURL.appendingPathComponent("Generated", isDirectory: true)

        guard let contents = try? fileManager.contentsOfDirectory(
            at: generatedRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { packageURL in
            generatedPackage(at: packageURL)
        }
        .sorted {
            $0.dashboardName.localizedStandardCompare($1.dashboardName) == .orderedAscending
        }
    }

    func deleteGeneratedPackage(_ package: GrafanaGeneratedPackage) throws {
        let generatedRootURL = manager.scriptsURL
            .appendingPathComponent("Generated", isDirectory: true)
            .standardizedFileURL
        let packageURL = package.packageURL.standardizedFileURL

        guard packageURL.path.hasPrefix(generatedRootURL.path + "/") else {
            throw NSError(
                domain: "GrafanaConstructorManager.Delete",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Отказано в удалении: пакет находится вне Scripts/Generated."]
            )
        }

        let provisioningURL = manager.grafanaGeneratedDashboardsURL
            .appendingPathComponent("\(safeDashboardFileName(package.dashboardUID)).json")

        if fileManager.fileExists(atPath: provisioningURL.path) {
            try fileManager.removeItem(at: provisioningURL)
        }

        try removePendingMetrics(forDashboardUID: package.dashboardUID)

        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
    }

    func updateDesiredState(
        _ desiredState: GrafanaMonitoringTaskDesiredState,
        for package: GrafanaGeneratedPackage
    ) throws {
        let configURL = package.configURL
        let data = try Data(contentsOf: configURL)

        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "GrafanaConstructorManager.Config",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать config.json задачи."]
            )
        }

        object["desiredState"] = desiredState.rawValue

        let updatedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedData.write(to: configURL, options: .atomic)
    }

    func updateInterval(
        seconds: Int,
        for package: GrafanaGeneratedPackage
    ) throws {
        guard seconds > 0 else {
            throw NSError(
                domain: "GrafanaConstructorManager.Interval",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Интервал должен быть больше нуля."]
            )
        }

        let intervalValue = "\(seconds)s"
        let dashboardRefreshValue = "\(seconds + 10)s"

        let configData = try Data(contentsOf: package.configURL)
        guard var configObject = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw NSError(
                domain: "GrafanaConstructorManager.Config",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать config.json задачи."]
            )
        }

        configObject["interval"] = intervalValue

        let updatedConfigData = try JSONSerialization.data(
            withJSONObject: configObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedConfigData.write(to: package.configURL, options: .atomic)

        let dashboardData = try Data(contentsOf: package.dashboardURL)
        guard var dashboardObject = try JSONSerialization.jsonObject(with: dashboardData) as? [String: Any] else {
            throw NSError(
                domain: "GrafanaConstructorManager.Dashboard",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось прочитать dashboard JSON задачи."]
            )
        }

        dashboardObject["refresh"] = dashboardRefreshValue

        let updatedDashboardData = try JSONSerialization.data(
            withJSONObject: dashboardObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedDashboardData.write(to: package.dashboardURL, options: .atomic)
    }

    func generatePackage(
        dashboardName: String,
        interval: GrafanaConstructorInterval,
        hosts: [GrafanaConstructorHost]
    ) throws -> GrafanaConstructorPackageResult {
        let cleanDashboardName = dashboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDashboardName.isEmpty else {
            throw GrafanaConstructorManagerError.emptyDashboardName
        }

        let configuredHosts = hosts.filter {
            !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.probes.isEmpty
        }

        guard !configuredHosts.isEmpty else {
            throw GrafanaConstructorManagerError.noHosts
        }

        let slug = makeSlug(from: cleanDashboardName)
        let dashboardUID = makeDashboardUID(slug: slug)
        let taskID = UUID()
        let createdAt = Date()

        let generatedRootURL = manager.scriptsURL.appendingPathComponent("Generated", isDirectory: true)
        let packageURL = uniquePackageURL(rootURL: generatedRootURL, preferredSlug: slug)

        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let scriptURL = packageURL.appendingPathComponent("SCR_\(slug)_GEN.sh")
        let configURL = packageURL.appendingPathComponent("config.json")
        let dashboardURL = packageURL.appendingPathComponent("dashboard_\(slug).json")

        let configData = try makeConfigData(
            taskID: taskID,
            dashboardName: cleanDashboardName,
            dashboardUID: dashboardUID,
            slug: slug,
            interval: interval,
            desiredState: .stopped,
            createdAt: createdAt,
            hosts: configuredHosts
        )
        try configData.write(to: configURL, options: .atomic)

        let script = makeScript(
            dashboardName: cleanDashboardName,
            dashboardUID: dashboardUID,
            hosts: configuredHosts
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let dashboardData = try makeDashboardData(
            dashboardName: cleanDashboardName,
            dashboardUID: dashboardUID,
            interval: interval,
            hosts: configuredHosts
        )
        try dashboardData.write(to: dashboardURL, options: .atomic)

        return GrafanaConstructorPackageResult(
            taskID: taskID,
            directoryURL: packageURL,
            scriptURL: scriptURL,
            configURL: configURL,
            dashboardURL: dashboardURL,
            dashboardUID: dashboardUID
        )
    }

    private func generatedPackage(at packageURL: URL) -> GrafanaGeneratedPackage? {
        let configURL = packageURL.appendingPathComponent("config.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dashboardName = object["dashboardName"] as? String,
            let dashboardUID = object["dashboardUID"] as? String
        else {
            return nil
        }

        let taskID: UUID
        if let taskIDString = object["taskID"] as? String,
           let parsedTaskID = UUID(uuidString: taskIDString) {
            taskID = parsedTaskID
        } else {
            taskID = UUID()
        }

        let interval = object["interval"] as? String ?? "—"
        let hosts = object["hosts"] as? [[String: Any]] ?? []

        let desiredState = GrafanaMonitoringTaskDesiredState(
            rawValue: object["desiredState"] as? String ?? "stopped"
        ) ?? .stopped

        let createdAt: Date
        if let createdAtString = object["createdAt"] as? String,
           let parsedCreatedAt = ISO8601DateFormatter().date(from: createdAtString) {
            createdAt = parsedCreatedAt
        } else if let generatedAtString = object["generatedAt"] as? String,
                  let parsedGeneratedAt = ISO8601DateFormatter().date(from: generatedAtString) {
            createdAt = parsedGeneratedAt
        } else {
            createdAt = Date.distantPast
        }

        let files = (try? fileManager.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        guard let scriptURL = files.first(where: {
            $0.pathExtension.lowercased() == "sh" && $0.lastPathComponent.hasSuffix("_GEN.sh")
        }) else {
            return nil
        }

        let dashboardURL = files.first(where: {
            $0.pathExtension.lowercased() == "json" && $0.lastPathComponent.hasPrefix("dashboard_")
        }) ?? packageURL.appendingPathComponent("dashboard.json")

        return GrafanaGeneratedPackage(
            id: dashboardUID,
            taskID: taskID,
            dashboardName: dashboardName,
            dashboardUID: dashboardUID,
            interval: interval,
            hostCount: hosts.count,
            packageURL: packageURL,
            scriptURL: scriptURL,
            configURL: configURL,
            dashboardURL: dashboardURL,
            desiredState: desiredState,
            createdAt: createdAt
        )
    }

    private func safeDashboardFileName(_ dashboardUID: String) -> String {
        let characters = dashboardUID
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
            }
        let value = String(characters)
        return value.isEmpty ? "generated-dashboard" : value
    }

    private func removePendingMetrics(forDashboardUID dashboardUID: String) throws {
        guard let files = try? fileManager.contentsOfDirectory(
            at: manager.historyPendingURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let prefix = "constructor_\(dashboardUID)_"
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension.lowercased() == "prom" {
            try fileManager.removeItem(at: file)
        }
    }

    private func makeSlug(from value: String) -> String {
        let lowercased = value.lowercased()
        let allowed = CharacterSet.alphanumerics

        let scalars = lowercased.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(String(scalar))
            }
            return "-"
        }

        var slug = String(scalars)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if slug.isEmpty {
            return "dashboard"
        }

        return String(slug.prefix(48))
    }

    private func makeDashboardUID(slug: String) -> String {
        let suffix = UUID().uuidString.lowercased().prefix(8)
        return String("gapp-\(slug)-\(suffix)".prefix(40))
    }

    private func uniquePackageURL(rootURL: URL, preferredSlug: String) -> URL {
        var candidate = rootURL.appendingPathComponent(preferredSlug, isDirectory: true)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(preferredSlug)-\(index)", isDirectory: true)
            index += 1
        }

        return candidate
    }

    private func makeConfigData(
        taskID: UUID,
        dashboardName: String,
        dashboardUID: String,
        slug: String,
        interval: GrafanaConstructorInterval,
        desiredState: GrafanaMonitoringTaskDesiredState,
        createdAt: Date,
        hosts: [GrafanaConstructorHost]
    ) throws -> Data {
        let hostObjects: [[String: Any]] = hosts.map { host in
            [
                "id": host.id.uuidString,
                "name": host.name,
                "target": host.target,
                "probes": host.probes.map(\.rawValue).sorted(),
                "sshUser": host.sshUser
            ]
        }

        let object: [String: Any] = [
            "schemaVersion": 2,
            "taskID": taskID.uuidString,
            "dashboardName": dashboardName,
            "dashboardUID": dashboardUID,
            "slug": slug,
            "interval": interval.rawValue,
            "desiredState": desiredState.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "generatedAt": ISO8601DateFormatter().string(from: createdAt),
            "hosts": hostObjects
        ]

        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func makeScript(
        dashboardName: String,
        dashboardUID: String,
        hosts: [GrafanaConstructorHost]
    ) -> String {
        let hostBlocks = hosts.compactMap { host in
            makeHostScriptBlock(host: host, dashboardUID: dashboardUID)
        }.joined(separator: "\n\n")

        return """
        #!/bin/bash
        set -u
        export LC_ALL=C
        export LANG=C

        # Generated by Grafana.app Constructor
        # Dashboard: \(shellCommentEscaped(dashboardName))
        # UID: \(dashboardUID)

        METRICS_DIR="${GRAFANA_APP_METRICS_PENDING:-}"

        if [ -z "$METRICS_DIR" ]; then
          echo "GRAFANA_APP_METRICS_PENDING is not set" >&2
          exit 1
        fi

        mkdir -p "$METRICS_DIR"

        NOW="$(date +%s)"
        FINAL_OUTPUT_FILE="$METRICS_DIR/constructor_\(dashboardUID)_${NOW}_$$.prom"
        OUTPUT_FILE="$METRICS_DIR/.constructor_\(dashboardUID)_${NOW}_$$.tmp"

        trap 'rm -f "$OUTPUT_FILE"' EXIT

        cat > "$OUTPUT_FILE" <<'EOF_HEADER'
        # TYPE grafana_app_constructor_host_up gauge
        # TYPE grafana_app_constructor_latency_ms gauge
        # TYPE grafana_app_constructor_packet_loss_percent gauge
        # TYPE grafana_app_constructor_dns_resolved gauge
        # TYPE grafana_app_constructor_tcp_open gauge
        # TYPE grafana_app_constructor_http_up gauge
        # TYPE grafana_app_constructor_tls_days_remaining gauge
        # TYPE grafana_app_constructor_ssh_up gauge
        # TYPE grafana_app_constructor_cpu_percent gauge
        # TYPE grafana_app_constructor_ram_percent gauge
        # TYPE grafana_app_constructor_disk_percent gauge
        # TYPE grafana_app_constructor_load1 gauge
        # TYPE grafana_app_constructor_uptime_seconds gauge
        # TYPE grafana_app_constructor_swap_percent gauge
        # TYPE grafana_app_constructor_network_rx_bytes gauge
        # TYPE grafana_app_constructor_network_tx_bytes gauge
        EOF_HEADER

        \(hostBlocks)

        echo "# EOF" >> "$OUTPUT_FILE"

        /bin/mv "$OUTPUT_FILE" "$FINAL_OUTPUT_FILE"
        trap - EXIT

        echo "Generated metrics: $FINAL_OUTPUT_FILE"
        """
    }

    private func makeHostScriptBlock(
        host: GrafanaConstructorHost,
        dashboardUID: String
    ) -> String? {
        let target = host.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !host.probes.isEmpty else {
            return nil
        }

        let displayName = host.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? target
            : host.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let dashboardLabel = prometheusLabelEscaped(dashboardUID)
        let hostLabel = prometheusLabelEscaped(displayName)
        let targetLabel = prometheusLabelEscaped(target)
        let shellTarget = shellSingleQuoteEscaped(target)
        let labels = "dashboard=\\\"\(dashboardLabel)\\\",host=\\\"\(hostLabel)\\\",target=\\\"\(targetLabel)\\\""
        let sshUser = host.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let shellSSHUser = shellSingleQuoteEscaped(sshUser)

        var lines: [String] = []
        lines.append("# Host: \(shellCommentEscaped(displayName))")
        lines.append("TARGET='\(shellTarget)'" )

        if host.probes.contains(.ping) || host.probes.contains(.latency) || host.probes.contains(.loss) {
            lines.append("PING_OUTPUT=\"$(/sbin/ping -c 3 -W 1000 \"$TARGET\" 2>/dev/null || true)\"")
        }

        if host.probes.contains(.ping) {
            lines.append("if printf '%s\\n' \"$PING_OUTPUT\" | /usr/bin/grep -q 'bytes from'; then HOST_UP=1; else HOST_UP=0; fi")
            lines.append("echo \"grafana_app_constructor_host_up{\(labels)} $HOST_UP $NOW\" >> \"$OUTPUT_FILE\"")
        }

        if host.probes.contains(.latency) {
            lines.append("LATENCY=\"$(printf '%s\\n' \"$PING_OUTPUT\" | /usr/bin/awk -F'/' '/round-trip|rtt/ {print $(NF-2)}' | /usr/bin/tail -n 1)\"")
            lines.append("[ -n \"$LATENCY\" ] || LATENCY=0")
            lines.append("echo \"grafana_app_constructor_latency_ms{\(labels)} $LATENCY $NOW\" >> \"$OUTPUT_FILE\"")
        }

        if host.probes.contains(.loss) {
            lines.append("LOSS=\"$(printf '%s\\n' \"$PING_OUTPUT\" | /usr/bin/awk -F', ' '/packet loss/ {gsub(/% packet loss/,\"\",$3); print $3}' | /usr/bin/tail -n 1)\"")
            lines.append("[ -n \"$LOSS\" ] || LOSS=100")
            lines.append("echo \"grafana_app_constructor_packet_loss_percent{\(labels)} $LOSS $NOW\" >> \"$OUTPUT_FILE\"")
        }

        if host.probes.contains(.dns) || host.probes.contains(.name) {
            lines.append("if /usr/bin/dscacheutil -q host -a name \"$TARGET\" 2>/dev/null | /usr/bin/grep -q '^ip_address:'; then DNS_OK=1; else DNS_OK=0; fi")
            lines.append("echo \"grafana_app_constructor_dns_resolved{\(labels)} $DNS_OK $NOW\" >> \"$OUTPUT_FILE\"")
        }

        if host.probes.contains(.tcp) {
            for port in [22, 80, 443] {
                lines.append("if /usr/bin/nc -G 2 -z \"$TARGET\" \(port) >/dev/null 2>&1; then TCP_OK=1; else TCP_OK=0; fi")
                lines.append("echo \"grafana_app_constructor_tcp_open{\(labels),port=\\\"\(port)\\\"} $TCP_OK $NOW\" >> \"$OUTPUT_FILE\"")
            }
        }

        if host.probes.contains(.http) {
            lines.append("if /usr/bin/curl -L --max-time 5 --silent --output /dev/null \"http://$TARGET\"; then HTTP_OK=1; else HTTP_OK=0; fi")
            lines.append("echo \"grafana_app_constructor_http_up{\(labels),scheme=\\\"http\\\"} $HTTP_OK $NOW\" >> \"$OUTPUT_FILE\"")
        }

        if host.probes.contains(.https) {
            lines.append("if /usr/bin/curl -L --max-time 5 --silent --output /dev/null \"https://$TARGET\"; then HTTPS_OK=1; else HTTPS_OK=0; fi")
            lines.append("echo \"grafana_app_constructor_http_up{\(labels),scheme=\\\"https\\\"} $HTTPS_OK $NOW\" >> \"$OUTPUT_FILE\"")
        }

        if host.probes.contains(.tls) {
            lines.append("TLS_END=\"$(/usr/bin/openssl s_client -servername \"$TARGET\" -connect \"$TARGET:443\" </dev/null 2>/dev/null | /usr/bin/openssl x509 -noout -enddate 2>/dev/null | /usr/bin/cut -d= -f2-)\"")
            lines.append("if [ -n \"$TLS_END\" ]; then TLS_END_TS=\"$(/bin/date -j -f '%b %e %T %Y %Z' \"$TLS_END\" '+%s' 2>/dev/null || echo 0)\"; else TLS_END_TS=0; fi")
            lines.append("if [ \"$TLS_END_TS\" -gt 0 ] 2>/dev/null; then TLS_DAYS=$(( (TLS_END_TS - NOW) / 86400 )); else TLS_DAYS=-1; fi")
            lines.append("echo \"grafana_app_constructor_tls_days_remaining{\(labels)} $TLS_DAYS $NOW\" >> \"$OUTPUT_FILE\"")
        }

        if host.probes.contains(where: { $0.requiresSSH }) {
            lines.append("SSH_USER='\(shellSSHUser)'")
            lines.append("if [ -n \"$SSH_USER\" ]; then SSH_DEST=\"$SSH_USER@$TARGET\"; else SSH_DEST=\"$TARGET\"; fi")
            lines.append("SSH_OUTPUT=\"$(/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \"$SSH_DEST\" 'sh -s' 2>/dev/null <<'EOF_SSH'\nset +e\nexport LC_ALL=C\nexport LANG=C\nif [ -r /proc/stat ]; then\n  read cpu user nice system idle iowait irq softirq steal rest < /proc/stat\n  total1=$((user+nice+system+idle+iowait+irq+softirq+steal))\n  idle1=$((idle+iowait))\n  sleep 1\n  read cpu user nice system idle iowait irq softirq steal rest < /proc/stat\n  total2=$((user+nice+system+idle+iowait+irq+softirq+steal))\n  idle2=$((idle+iowait))\n  dt=$((total2-total1)); di=$((idle2-idle1))\n  if [ \"$dt\" -gt 0 ]; then awk -v dt=\"$dt\" -v di=\"$di\" 'BEGIN { printf \"CPU=%.2f\\n\", (dt-di)*100/dt }'; fi\nfi\nif [ -r /proc/meminfo ]; then\n  awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} END {if (t>0) printf \"RAM=%.2f\\n\", (t-a)*100/t}' /proc/meminfo\n  awk '/SwapTotal:/ {t=$2} /SwapFree:/ {f=$2} END {if (t>0) printf \"SWAP=%.2f\\n\", (t-f)*100/t; else print \"SWAP=0\"}' /proc/meminfo\nfi\ndf -Pk / 2>/dev/null | awk 'NR==2 {gsub(/%/,\"\",$5); print \"DISK=\"$5}'\nif [ -r /proc/loadavg ]; then awk '{print \"LOAD1=\"$1}' /proc/loadavg; else uptime | awk -F'load averages?: ' '{print \"LOAD1=\"$2}' | awk -F',' '{print $1}'; fi\nif [ -r /proc/uptime ]; then awk '{print \"UPTIME=\"int($1)}' /proc/uptime; else sysctl -n kern.boottime 2>/dev/null | awk -v now=\"$(date +%s)\" -F'[=,]' '{gsub(/ /,\"\",$2); print \"UPTIME=\" now-$2}'; fi\nif [ -r /proc/net/dev ]; then\n  awk -F'[: ]+' 'NR>2 && $1 != \"lo\" {rx+=$3; tx+=$11} END {print \"NETRX=\"rx; print \"NETTX=\"tx}' /proc/net/dev\nfi\nEOF_SSH\n)\"")
            lines.append("if [ -n \"$SSH_OUTPUT\" ]; then SSH_OK=1; else SSH_OK=0; fi")
            lines.append("echo \"grafana_app_constructor_ssh_up{\(labels)} $SSH_OK $NOW\" >> \"$OUTPUT_FILE\"")

            if host.probes.contains(.cpu) {
                lines.append("CPU_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^CPU=/ {print $2; exit}')\"")
                lines.append("[ -n \"$CPU_VALUE\" ] || CPU_VALUE=0")
                lines.append("echo \"grafana_app_constructor_cpu_percent{\(labels)} $CPU_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
            }

            if host.probes.contains(.ram) {
                lines.append("RAM_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^RAM=/ {print $2; exit}')\"")
                lines.append("[ -n \"$RAM_VALUE\" ] || RAM_VALUE=0")
                lines.append("echo \"grafana_app_constructor_ram_percent{\(labels)} $RAM_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
            }

            if host.probes.contains(.disk) {
                lines.append("DISK_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^DISK=/ {print $2; exit}')\"")
                lines.append("[ -n \"$DISK_VALUE\" ] || DISK_VALUE=0")
                lines.append("echo \"grafana_app_constructor_disk_percent{\(labels),mount=\\\"/\\\"} $DISK_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
            }

            if host.probes.contains(.load) {
                lines.append("LOAD_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^LOAD1=/ {print $2; exit}')\"")
                lines.append("[ -n \"$LOAD_VALUE\" ] || LOAD_VALUE=0")
                lines.append("echo \"grafana_app_constructor_load1{\(labels)} $LOAD_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
            }

            if host.probes.contains(.uptime) {
                lines.append("UPTIME_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^UPTIME=/ {print $2; exit}')\"")
                lines.append("[ -n \"$UPTIME_VALUE\" ] || UPTIME_VALUE=0")
                lines.append("echo \"grafana_app_constructor_uptime_seconds{\(labels)} $UPTIME_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
            }

            if host.probes.contains(.swap) {
                lines.append("SWAP_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^SWAP=/ {print $2; exit}')\"")
                lines.append("[ -n \"$SWAP_VALUE\" ] || SWAP_VALUE=0")
                lines.append("echo \"grafana_app_constructor_swap_percent{\(labels)} $SWAP_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
            }

            if host.probes.contains(.network) {
                lines.append("NETRX_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^NETRX=/ {print $2; exit}')\"")
                lines.append("NETTX_VALUE=\"$(printf '%s\\n' \"$SSH_OUTPUT\" | /usr/bin/awk -F= '/^NETTX=/ {print $2; exit}')\"")
                lines.append("[ -n \"$NETRX_VALUE\" ] || NETRX_VALUE=0")
                lines.append("[ -n \"$NETTX_VALUE\" ] || NETTX_VALUE=0")
                lines.append("echo \"grafana_app_constructor_network_rx_bytes{\(labels)} $NETRX_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
                lines.append("echo \"grafana_app_constructor_network_tx_bytes{\(labels)} $NETTX_VALUE $NOW\" >> \"$OUTPUT_FILE\"")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func makeDashboardData(
        dashboardName: String,
        dashboardUID: String,
        interval: GrafanaConstructorInterval,
        hosts: [GrafanaConstructorHost]
    ) throws -> Data {
        let selectedProbes = Set(hosts.flatMap { $0.probes })
        var panels: [[String: Any]] = []
        var panelID = 1
        var y = 0

        if selectedProbes.contains(where: { $0.requiresSSH }) {
            panels.append(makeStatPanel(
                id: panelID,
                title: "SSH-доступ",
                expression: "grafana_app_constructor_ssh_up{dashboard=\"\(dashboardUID)\"}",
                y: y,
                height: 5,
                unit: "none",
                thresholds: [0, 1]
            ))
            panelID += 1
            y += 5
        }

        if selectedProbes.contains(.cpu) {
            panels.append(makeTimeSeriesPanel(id: panelID, title: "CPU", expression: "grafana_app_constructor_cpu_percent{dashboard=\"\(dashboardUID)\"}", y: y, unit: "percent"))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.ram) {
            panels.append(makeTimeSeriesPanel(id: panelID, title: "RAM", expression: "grafana_app_constructor_ram_percent{dashboard=\"\(dashboardUID)\"}", y: y, unit: "percent"))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.disk) {
            panels.append(makeTimeSeriesPanel(id: panelID, title: "Заполнение диска /", expression: "grafana_app_constructor_disk_percent{dashboard=\"\(dashboardUID)\"}", y: y, unit: "percent"))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.load) {
            panels.append(makeTimeSeriesPanel(id: panelID, title: "Load average (1m)", expression: "grafana_app_constructor_load1{dashboard=\"\(dashboardUID)\"}", y: y, unit: "short"))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.uptime) {
            panels.append(makeStatPanel(id: panelID, title: "Uptime", expression: "grafana_app_constructor_uptime_seconds{dashboard=\"\(dashboardUID)\"}", y: y, height: 5, unit: "s", thresholds: [0]))
            panelID += 1
            y += 5
        }

        if selectedProbes.contains(.swap) {
            panels.append(makeTimeSeriesPanel(id: panelID, title: "SWAP", expression: "grafana_app_constructor_swap_percent{dashboard=\"\(dashboardUID)\"}", y: y, unit: "percent"))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.network) {
            panels.append(makeTimeSeriesPanel(id: panelID, title: "Network RX", expression: "rate(grafana_app_constructor_network_rx_bytes{dashboard=\"\(dashboardUID)\"}[2m])", y: y, unit: "Bps"))
            panelID += 1
            y += 8
            panels.append(makeTimeSeriesPanel(id: panelID, title: "Network TX", expression: "rate(grafana_app_constructor_network_tx_bytes{dashboard=\"\(dashboardUID)\"}[2m])", y: y, unit: "Bps"))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.ping) {
            panels.append(makeStatPanel(
                id: panelID,
                title: "Доступность узлов",
                expression: "grafana_app_constructor_host_up{dashboard=\"\(dashboardUID)\"}",
                y: y,
                height: 7,
                unit: "none",
                thresholds: [0, 1]
            ))
            panelID += 1
            y += 7
        }

        if selectedProbes.contains(.latency) {
            panels.append(makeTimeSeriesPanel(
                id: panelID,
                title: "Задержка",
                expression: "grafana_app_constructor_latency_ms{dashboard=\"\(dashboardUID)\"}",
                y: y,
                unit: "ms"
            ))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.loss) {
            panels.append(makeTimeSeriesPanel(
                id: panelID,
                title: "Потери пакетов",
                expression: "grafana_app_constructor_packet_loss_percent{dashboard=\"\(dashboardUID)\"}",
                y: y,
                unit: "percent"
            ))
            panelID += 1
            y += 8
        }

        if selectedProbes.contains(.dns) || selectedProbes.contains(.name) {
            panels.append(makeStatPanel(
                id: panelID,
                title: "DNS / имя узла",
                expression: "grafana_app_constructor_dns_resolved{dashboard=\"\(dashboardUID)\"}",
                y: y,
                height: 6,
                unit: "none",
                thresholds: [0, 1]
            ))
            panelID += 1
            y += 6
        }

        if selectedProbes.contains(.tcp) {
            panels.append(makeStatPanel(
                id: panelID,
                title: "TCP-порты",
                expression: "grafana_app_constructor_tcp_open{dashboard=\"\(dashboardUID)\"}",
                y: y,
                height: 7,
                unit: "none",
                thresholds: [0, 1]
            ))
            panelID += 1
            y += 7
        }

        if selectedProbes.contains(.http) || selectedProbes.contains(.https) {
            panels.append(makeStatPanel(
                id: panelID,
                title: "HTTP / HTTPS",
                expression: "grafana_app_constructor_http_up{dashboard=\"\(dashboardUID)\"}",
                y: y,
                height: 7,
                unit: "none",
                thresholds: [0, 1]
            ))
            panelID += 1
            y += 7
        }

        if selectedProbes.contains(.tls) {
            panels.append(makeStatPanel(
                id: panelID,
                title: "TLS: дней до окончания сертификата",
                expression: "grafana_app_constructor_tls_days_remaining{dashboard=\"\(dashboardUID)\"}",
                y: y,
                height: 7,
                unit: "d",
                thresholds: [7, 30]
            ))
        }

        let dashboard: [String: Any] = [
            "annotations": ["list": []],
            "editable": true,
            "fiscalYearStartMonth": 0,
            "graphTooltip": 1,
            "id": NSNull(),
            "links": [],
            "panels": panels,
            "refresh": "\(interval.seconds + 10)s",
            "schemaVersion": 41,
            "tags": ["Grafana.app", "Constructor"],
            "templating": ["list": []],
            "time": ["from": "now-6h", "to": "now"],
            "timezone": "browser",
            "title": dashboardName,
            "uid": dashboardUID,
            "version": 1
        ]

        return try JSONSerialization.data(withJSONObject: dashboard, options: [.prettyPrinted, .sortedKeys])
    }

    private func makeStatPanel(
        id: Int,
        title: String,
        expression: String,
        y: Int,
        height: Int,
        unit: String,
        thresholds: [Double]
    ) -> [String: Any] {
        [
            "id": id,
            "type": "stat",
            "title": title,
            "datasource": ["type": "prometheus", "uid": "prometheus"],
            "gridPos": ["h": height, "w": 24, "x": 0, "y": y],
            "targets": [[
                "expr": expression,
                "legendFormat": "{{host}} {{target}}",
                "refId": "A"
            ]],
            "options": [
                "colorMode": "background",
                "graphMode": "area",
                "justifyMode": "auto",
                "orientation": "auto",
                "reduceOptions": ["calcs": ["lastNotNull"], "fields": "", "values": false]
            ],
            "fieldConfig": [
                "defaults": [
                    "unit": unit,
                    "thresholds": [
                        "mode": "absolute",
                        "steps": [
                            ["color": "red", "value": NSNull()],
                            ["color": "green", "value": thresholds.last ?? 1]
                        ]
                    ]
                ],
                "overrides": []
            ]
        ]
    }

    private func makeTimeSeriesPanel(
        id: Int,
        title: String,
        expression: String,
        y: Int,
        unit: String
    ) -> [String: Any] {
        [
            "id": id,
            "type": "timeseries",
            "title": title,
            "datasource": ["type": "prometheus", "uid": "prometheus"],
            "gridPos": ["h": 8, "w": 24, "x": 0, "y": y],
            "targets": [[
                "expr": expression,
                "legendFormat": "{{host}} {{target}}",
                "refId": "A"
            ]],
            "fieldConfig": [
                "defaults": ["unit": unit],
                "overrides": []
            ],
            "options": [
                "legend": ["displayMode": "table", "placement": "bottom", "showLegend": true],
                "tooltip": ["mode": "multi", "sort": "desc"]
            ]
        ]
    }

    private func prometheusLabelEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func shellSingleQuoteEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func shellCommentEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}
