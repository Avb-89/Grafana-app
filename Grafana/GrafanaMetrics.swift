//
//  GrafanaMetrics.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import Foundation

struct GrafanaMetrics {
    private let manager: GrafanaManager

    init(manager: GrafanaManager = .shared) {
        self.manager = manager
    }

    func historyFiles() -> [URL] {
        let directories = [
            manager.historyPendingURL,
            manager.historyImportedURL,
            manager.historyFailedURL
        ]

        return directories.flatMap { directory in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [URL]()
            }

            return files.filter { file in
                let ext = file.pathExtension.lowercased()
                return ext == "openmetrics" || ext == "prom" || ext == "txt"
            }
        }
        .sorted { left, right in
            modificationDate(for: left) > modificationDate(for: right)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    func previewText(for url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func metricsFormatHelpText() -> String {
        """
        Программа импортирует файлы .prom и .openmetrics из pending.

        Обязательные правила:
        - формат: Prometheus/OpenMetrics text format;
        - в конце файла должен быть # EOF;
        - timestamp обязателен;
        - timestamp должен быть Unix time в секундах, не в миллисекундах;
        - слишком старые и будущие timestamp будут отклонены;
        - после успешного импорта файл из pending удаляется;
        - ошибки попадают в failed вместе с .error.txt.
        """
    }

    func exampleMetricText() -> String {
        """
        # HELP demo_service_up Demo service availability. 1 means up, 0 means down.
        # TYPE demo_service_up gauge
        demo_service_up{service="example"} 1 1783202873
        # EOF
        """
    }
}
