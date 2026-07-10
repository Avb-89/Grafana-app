//
//  GrafanaDiskManager.swift
//  Grafana
//
//  Created by SITIS on 7/10/26.
//

import Foundation

struct GrafanaDiskManager {
    func folderSize(_ url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }

        return fallbackFolderSize(url)
    }

    func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    func folderSizeText(_ url: URL) -> String {
        byteCountText(for: folderSize(url))
    }

    func fileSizeText(_ url: URL) -> String {
        byteCountText(for: fileSize(url))
    }

    func prometheusTSDBSizeText(_ prometheusDataURL: URL) -> String {
        folderSizeText(prometheusDataURL)
    }

    func byteCountText(for bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func removeItemIfExists(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    func recreateDirectory(at url: URL) throws {
        try removeItemIfExists(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func clearDirectoryContents(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in items {
            try FileManager.default.removeItem(at: item)
        }
    }

    func moveToQuarantine(itemURL: URL, quarantineRootURL: URL, name: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: itemURL.path) else {
            return nil
        }

        try FileManager.default.createDirectory(at: quarantineRootURL, withIntermediateDirectories: true)

        let timestamp = Self.timestampText()
        let quarantineURL = quarantineRootURL
            .appendingPathComponent("\(name)_\(timestamp)", isDirectory: itemIsDirectory(itemURL))

        if FileManager.default.fileExists(atPath: quarantineURL.path) {
            try FileManager.default.removeItem(at: quarantineURL)
        }

        try FileManager.default.moveItem(at: itemURL, to: quarantineURL)
        return quarantineURL
    }

    func clearUpdateCache(updatesURL: URL) throws {
        try clearDirectoryContents(at: updatesURL)
    }

    func clearUpdateDownloads(downloadsURL: URL) throws {
        try clearDirectoryContents(at: downloadsURL)
    }

    func clearUpdateStaging(stagingURL: URL) throws {
        try clearDirectoryContents(at: stagingURL)
    }

    func clearBackups(backupsURL: URL) throws {
        try clearDirectoryContents(at: backupsURL)
    }

    private func fallbackFolderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            total += Int64(values?.fileSize ?? 0)
        }

        return total
    }

    private func itemIsDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private static func timestampText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
