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
    private let collector = CodexQuotaCollector(eventCache: RolloutParsedEventCache())
    private let store = QuotaSnapshotStore.defaultStore()
    private let logger = Logger(subsystem: "com.guohuaz.CodexQuota", category: "Refresh")
    private let widgetKind = "CodexQuotaWidget"
    private let activeRefreshInterval: TimeInterval = 60
    private let idleRefreshInterval: TimeInterval = 15 * 60
    private let activeEventWindow: TimeInterval = 5 * 60
    private let watcherDebounceSeconds: Duration = .seconds(5)
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
        timer = Timer.scheduledTimer(withTimeInterval: activeRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshIfNeeded()
            }
        }
        rebuildWatchers()
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard shouldRunScheduledRefresh(now: now) else {
            logger.debug("Skipped scheduled refresh while Codex logs are idle")
            return
        }

        await refresh()
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

        let collector = collector
        let collected = await Task.detached(priority: .utility) {
            collector.collect(from: url)
        }.value
        let stableSnapshot = collected.preservingStableValues(from: snapshot)
        logger.info("Collected snapshot status=\(collected.status.rawValue, privacy: .public) stableStatus=\(stableSnapshot.status.rawValue, privacy: .public) files=\(collected.source.scannedFileCount) events=\(collected.source.parsedEventCount)")

        do {
            try store.save(stableSnapshot)
            snapshot = stableSnapshot.markingStaleIfNeeded()
            reloadWidgetTimelines()
            logger.info("Saved snapshot and reloaded widget timelines")
        } catch {
            if snapshot.hasDisplayableQuotaData {
                snapshot = snapshot.markingStaleIfNeeded()
            } else {
                snapshot = .error("无法写入共享快照：\(error.localizedDescription)", rootPath: url.path)
            }
            logger.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func shouldRunScheduledRefresh(now: Date) -> Bool {
        switch snapshot.status {
        case .empty, .error:
            return true
        case .ready, .stale:
            break
        }

        if let latestEventAt = snapshot.source.latestEventAt,
           now.timeIntervalSince(latestEventAt) <= activeEventWindow {
            return true
        }

        return now.timeIntervalSince(snapshot.updatedAt) >= idleRefreshInterval
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
        let debounce = watcherDebounceSeconds
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
