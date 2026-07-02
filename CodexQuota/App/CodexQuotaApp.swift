import AppKit
import SwiftUI

@main
struct CodexQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.refreshController)
                .frame(width: 320)
        } label: {
            Label("Codex", systemImage: "gauge.medium")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.refreshController)
                .frame(width: 420)
                .padding(20)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let refreshController = QuotaRefreshController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor [refreshController] in
            await refreshController.refresh()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "codexquota" && $0.host == "refresh" }) else {
            return
        }

        Task { @MainActor [refreshController] in
            await refreshController.refresh()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor [refreshController] in
            await refreshController.refresh()
        }
        return false
    }
}
