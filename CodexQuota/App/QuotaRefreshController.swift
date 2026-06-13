import AppKit
import Foundation
import OSLog
import WidgetKit

@MainActor
final class QuotaRefreshController: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot
    @Published private(set) var codexFolderURL: URL
    @Published private(set) var isRefreshing = false
    @Published var launchAtLoginEnabled: Bool

    private let folderAccess = FolderAccessManager()
    private let collector = CodexQuotaCollector()
    private let store = QuotaSnapshotStore.defaultStore()
    private let logger = Logger(subsystem: "com.guohuaz.CodexQuota", category: "Refresh")
    private var timer: Timer?
    private var watchers: [FolderWatcher] = []
    private var pendingRefreshTask: Task<Void, Never>?

    init() {
        let loadedSnapshot = try? store.load().markingStaleIfNeeded()
        snapshot = loadedSnapshot ?? .placeholder()
        codexFolderURL = folderAccess.resolvedCodexFolder()
        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
        start()
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            Task { @MainActor in
                self?.logger.info("Initial refresh requested")
                await self?.refresh()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        rebuildWatchers()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let url = codexFolderURL
        let accessGranted = folderAccess.startAccessing(url)
        defer {
            if accessGranted {
                folderAccess.stopAccessing(url)
            }
        }

        let collected = await Task.detached(priority: .utility) {
            CodexQuotaCollector().collect(from: url)
        }.value
        logger.info("Collected snapshot status=\(collected.status.rawValue, privacy: .public) files=\(collected.source.scannedFileCount) events=\(collected.source.parsedEventCount)")

        do {
            try store.save(collected)
            snapshot = collected.markingStaleIfNeeded()
            WidgetCenter.shared.reloadAllTimelines()
            logger.info("Saved snapshot and reloaded widget timelines")
        } catch {
            snapshot = .error("无法写入共享快照：\(error.localizedDescription)", rootPath: url.path)
            logger.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    func chooseCodexFolder() {
        guard let selectedURL = folderAccess.chooseCodexFolder(currentURL: codexFolderURL) else {
            return
        }
        codexFolderURL = selectedURL
        rebuildWatchers()
        Task {
            await refresh()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
        } catch {
            launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
            snapshot = .error("无法更新开机启动：\(error.localizedDescription)", rootPath: codexFolderURL.path)
        }
    }

    func revealSnapshotInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.snapshotURL])
    }

    private func rebuildWatchers() {
        watchers.removeAll()
        let sessions = codexFolderURL.appendingPathComponent("sessions", isDirectory: true)
        let archived = codexFolderURL.appendingPathComponent("archived_sessions", isDirectory: true)
        for url in [codexFolderURL, sessions, archived] where FileManager.default.fileExists(atPath: url.path) {
            if let watcher = FolderWatcher(url: url, onChange: { [weak self] in
                Task { @MainActor in
                    self?.scheduleRefreshSoon()
                }
            }) {
                watchers.append(watcher)
            }
        }
    }

    private func scheduleRefreshSoon() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
