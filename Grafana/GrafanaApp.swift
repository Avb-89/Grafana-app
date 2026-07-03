//
//  GrafanaApp.swift
//  Grafana
//
//  Created by SITIS on 7/3/26.
//

import SwiftUI
import AppKit

@main
struct GrafanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? GrafanaManager.shared.stopAll()
    }
}
