import Foundation
import CodexQuotaCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw CheckFailure.failed(message)
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CheckFailure.failed(message)
    }
    return value
}

@main
struct CodexQuotaCoreChecks {
    static func main() throws {
        let checks = CodexQuotaCoreChecks()
        try checks.parseTokenCountLineWithRateLimits()
        try checks.collectorBuildsFiveDayTrendAndDeduplicatesArchivedCopy()
        try checks.collectorPrefersCodexRateLimitOverModelSpecificLimit()
        try checks.collectorHandlesMissingRateLimitData()
        try checks.parserHandlesPayloadRateLimitsWithNullInfo()
        try checks.collectorIgnoresMalformedLinesAndReportsEmptyData()
        try checks.snapshotPreservesPreviousValuesWhenRefreshIsUnreliable()
        try checks.snapshotAcceptsQuotaResetAfterPreviousWindowExpired()
        try checks.snapshotPreservesOnlySuspiciousLimit()
        try checks.scannerKeepsRecentHistoryAndActiveLongRunningSessions()
        try checks.resetLabelUsesTimeTodayAndDateForLaterDay()
        try checks.snapshotStoreWritesAndLoadsMirrorURLs()
        print("CodexQuotaCoreChecks passed")
    }

    func parseTokenCountLineWithRateLimits() throws {
        let line = tokenLine(
            timestamp: "2026-06-13T04:31:44.529Z",
            lastTotal: 25_314,
            cumulativeTotal: 25_314,
            primaryUsed: 21,
            secondaryUsed: 9
        )

        let event = try require(RolloutLogParser.parseLine(line), "expected token_count event")
        try check(event.lastTotalTokens == 25_314, "last token count mismatch")
        try check(event.cumulativeTotalTokens == 25_314, "cumulative token count mismatch")
        try check(event.primary?.usedPercent == 21, "primary used percent mismatch")
        try check(event.primary?.windowMinutes == 300, "primary window mismatch")
        try check(event.primary?.resetsAt == Date(timeIntervalSince1970: 1_781_334_127), "primary reset mismatch")
        try check(event.secondary?.usedPercent == 9, "secondary used percent mismatch")
        try check(event.secondary?.windowMinutes == 10_080, "secondary window mismatch")
    }

    func collectorBuildsFiveDayTrendAndDeduplicatesArchivedCopy() throws {
        let root = try makeTemporaryCodexRoot()
        let active = tokenLine(timestamp: "2026-06-09T08:00:00.000Z", lastTotal: 100, cumulativeTotal: 100)
            + "\n"
            + tokenLine(timestamp: "2026-06-10T08:00:00.000Z", lastTotal: 200, cumulativeTotal: 300)
            + "\n"
            + tokenLine(
                timestamp: "2026-06-13T08:00:00.000Z",
                lastTotal: 300,
                cumulativeTotal: 600,
                primaryUsed: 42,
                secondaryUsed: 11
            )
        try writeFile(root: root, path: "sessions/2026/06/13/rollout-current.jsonl", contents: active)

        let duplicate = tokenLine(timestamp: "2026-06-10T08:00:00.000Z", lastTotal: 200, cumulativeTotal: 300)
        try writeFile(root: root, path: "archived_sessions/rollout-archived.jsonl", contents: duplicate)

        let snapshot = CodexQuotaCollector().collect(from: root, now: date("2026-06-13T12:00:00.000Z"), calendar: utcCalendar)

        try check(snapshot.status == .ready, "snapshot should be ready")
        try check(snapshot.source.scannedFileCount == 2, "scanned file count mismatch")
        try check(snapshot.source.parsedEventCount == 3, "parsed event count mismatch")
        try check(snapshot.limits[0].label == "5小时", "primary label mismatch")
        try check(snapshot.limits[0].remainingPercent == 58, "primary remaining mismatch")
        try check(snapshot.limits[1].label == "周限额", "secondary label mismatch")
        try check(snapshot.limits[1].remainingPercent == 89, "secondary remaining mismatch")
        try check(snapshot.trend.map(\.dayKey) == [
            "2026-06-09",
            "2026-06-10",
            "2026-06-11",
            "2026-06-12",
            "2026-06-13"
        ], "trend day keys mismatch")
        try check(snapshot.trend.map(\.tokens) == [100, 200, 0, 0, 300], "trend token buckets mismatch")
        try check(snapshot.dailyAverageTokens == 120, "daily average mismatch")
    }

    func collectorPrefersCodexRateLimitOverModelSpecificLimit() throws {
        let root = try makeTemporaryCodexRoot()
        let timestamp = "2026-06-13T08:00:00.000Z"
        let contents = tokenLine(
            timestamp: timestamp,
            lastTotal: 300,
            cumulativeTotal: 600,
            primaryUsed: 0,
            secondaryUsed: 0,
            limitID: "codex_bengalfox"
        )
            + "\n"
            + tokenLine(
                timestamp: timestamp,
                lastTotal: 300,
                cumulativeTotal: 600,
                primaryUsed: 42,
                secondaryUsed: 11,
                limitID: "codex"
            )

        try writeFile(root: root, path: "sessions/2026/06/13/rollout-current.jsonl", contents: contents)

        let snapshot = CodexQuotaCollector().collect(from: root, now: date("2026-06-13T12:00:00.000Z"), calendar: utcCalendar)

        try check(snapshot.status == .ready, "snapshot should be ready")
        try check(snapshot.source.parsedEventCount == 2, "rate limits with different ids should not deduplicate")
        try check(snapshot.limits[0].remainingPercent == 58, "collector should prefer codex primary rate limit")
        try check(snapshot.limits[1].remainingPercent == 89, "collector should prefer codex secondary rate limit")
    }

    func collectorHandlesMissingRateLimitData() throws {
        let root = try makeTemporaryCodexRoot()
        try writeFile(
            root: root,
            path: "sessions/2026/06/13/rollout-no-rate.jsonl",
            contents: tokenLine(timestamp: "2026-06-13T08:00:00.000Z", lastTotal: 123, cumulativeTotal: 123, includeRateLimits: false)
        )

        let snapshot = CodexQuotaCollector().collect(from: root, now: date("2026-06-13T12:00:00.000Z"), calendar: utcCalendar)

        try check(snapshot.status == .ready, "snapshot with token history should be ready")
        try check(snapshot.limits[0].usedPercent == nil, "missing rate limits should keep primary empty")
        try check(snapshot.trend.last?.tokens == 123, "trend should include token-only event")
        try check(snapshot.message == "已找到 token 历史，但暂无额度窗口数据", "missing rate limit message mismatch")
    }

    func parserHandlesPayloadRateLimitsWithNullInfo() throws {
        let root: [String: Any] = [
            "timestamp": "2026-06-13T02:30:03.157Z",
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": NSNull(),
                "rate_limits": [
                    "limit_id": "codex",
                    "primary": [
                        "used_percent": 2.0,
                        "window_minutes": 300,
                        "resets_at": 1_781_334_127
                    ],
                    "secondary": [
                        "used_percent": 6.0,
                        "window_minutes": 10_080,
                        "resets_at": 1_781_765_477
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let line = String(data: data, encoding: .utf8)!
        let event = try require(RolloutLogParser.parseLine(line), "expected payload rate limit event")

        try check(event.lastTotalTokens == 0, "null info should not add tokens")
        try check(event.primary?.usedPercent == 2, "payload primary rate limit mismatch")
        try check(event.secondary?.usedPercent == 6, "payload secondary rate limit mismatch")
    }

    func collectorIgnoresMalformedLinesAndReportsEmptyData() throws {
        let root = try makeTemporaryCodexRoot()
        try writeFile(root: root, path: "sessions/2026/06/13/rollout-bad.jsonl", contents: "{not json}\n\n[]")

        let snapshot = CodexQuotaCollector().collect(from: root, now: date("2026-06-13T12:00:00.000Z"), calendar: utcCalendar)

        try check(snapshot.status == .empty, "bad-only logs should be empty")
        try check(snapshot.source.scannedFileCount == 1, "bad-only scanned file count mismatch")
        try check(snapshot.source.parsedEventCount == 0, "bad-only parsed event count mismatch")
    }

    func snapshotPreservesPreviousValuesWhenRefreshIsUnreliable() throws {
        let previous = QuotaSnapshot(
            updatedAt: date("2026-06-13T08:00:00.000Z"),
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 25, resetsAt: date("2026-06-13T12:15:34.000Z"), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 24, resetsAt: date("2026-06-18T06:51:17.000Z"), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-06-13", label: "06-13", tokens: 140_415_700)
            ],
            dailyAverageTokens: 140_415_700,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 77, parsedEventCount: 12_962, latestEventAt: date("2026-06-13T07:54:49.000Z"))
        )

        let emptyRefresh = QuotaSnapshot.placeholder(now: date("2026-06-13T08:05:00.000Z"))
        let preservedEmpty = emptyRefresh.preservingStableValues(from: previous, now: date("2026-06-13T08:05:00.000Z"))
        try check(preservedEmpty.limits[0].remainingPercent == 75, "empty refresh should preserve previous primary quota")
        try check(preservedEmpty.dailyAverageTokens == 140_415_700, "empty refresh should preserve previous trend data")

        let suspiciousFullRefresh = QuotaSnapshot(
            updatedAt: date("2026-06-13T08:05:00.000Z"),
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 0, resetsAt: date("2026-06-13T12:15:34.000Z"), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 24, resetsAt: date("2026-06-18T06:51:17.000Z"), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-06-13", label: "06-13", tokens: 140_500_000)
            ],
            dailyAverageTokens: 140_500_000,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 78, parsedEventCount: 12_963, latestEventAt: date("2026-06-13T08:04:59.000Z"))
        )
        let preservedSuspicious = suspiciousFullRefresh.preservingStableValues(from: previous, now: date("2026-06-13T08:05:00.000Z"))
        try check(preservedSuspicious.limits[0].remainingPercent == 75, "suspicious full refresh should preserve previous primary quota")
    }

    func snapshotAcceptsQuotaResetAfterPreviousWindowExpired() throws {
        let previous = QuotaSnapshot(
            updatedAt: date("2026-07-01T01:38:14.000Z"),
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 7, resetsAt: date("2026-06-30T11:46:48.000Z"), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 8, resetsAt: date("2026-07-07T01:45:18.000Z"), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-07-01", label: "07-01", tokens: 24_000_000)
            ],
            dailyAverageTokens: 24_000_000,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 27, parsedEventCount: 3_067, latestEventAt: date("2026-07-01T01:38:06.000Z"))
        )

        let current = QuotaSnapshot(
            updatedAt: date("2026-07-01T01:39:14.000Z"),
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 0, resetsAt: date("2026-07-01T06:37:05.000Z"), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 26, resetsAt: date("2026-07-07T01:45:18.000Z"), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-07-01", label: "07-01", tokens: 25_000_000)
            ],
            dailyAverageTokens: 25_000_000,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 28, parsedEventCount: 3_070, latestEventAt: date("2026-07-01T01:38:33.000Z"))
        )

        let stable = current.preservingStableValues(from: previous, now: date("2026-07-01T01:39:14.000Z"))
        try check(stable.limits[0].remainingPercent == 100, "expired previous window should accept new primary reset")
        try check(stable.limits[1].remainingPercent == 74, "expired previous window should accept current secondary quota")
        try check(stable.source.parsedEventCount == 3_070, "current source should be kept after real reset")
    }

    func snapshotPreservesOnlySuspiciousLimit() throws {
        let previous = QuotaSnapshot(
            updatedAt: date("2026-06-13T08:00:00.000Z"),
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 25, resetsAt: date("2026-06-13T12:15:34.000Z"), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 8, resetsAt: date("2026-06-18T06:51:17.000Z"), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-06-13", label: "06-13", tokens: 140_415_700)
            ],
            dailyAverageTokens: 140_415_700,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 77, parsedEventCount: 12_962, latestEventAt: date("2026-06-13T07:54:49.000Z"))
        )

        let current = QuotaSnapshot(
            updatedAt: date("2026-06-13T08:05:00.000Z"),
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 0, resetsAt: date("2026-06-13T12:15:34.000Z"), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 26, resetsAt: date("2026-06-18T06:51:17.000Z"), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-06-13", label: "06-13", tokens: 140_500_000)
            ],
            dailyAverageTokens: 140_500_000,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 78, parsedEventCount: 12_963, latestEventAt: date("2026-06-13T08:04:59.000Z"))
        )

        let stable = current.preservingStableValues(from: previous, now: date("2026-06-13T08:05:00.000Z"))
        try check(stable.limits[0].remainingPercent == 75, "suspicious primary reset should preserve only primary")
        try check(stable.limits[1].remainingPercent == 74, "non-suspicious secondary should keep current quota")
        try check(stable.dailyAverageTokens == 140_500_000, "current trend should not be rolled back by one suspicious limit")
    }

    func scannerKeepsRecentHistoryAndActiveLongRunningSessions() throws {
        let root = try makeTemporaryCodexRoot()
        let now = date("2026-06-13T12:00:00.000Z")
        let inactiveModifiedAt = date("2026-06-12T10:59:00.000Z")
        let activeModifiedAt = date("2026-06-13T11:59:00.000Z")

        try writeFile(root: root, path: "sessions/2026/06/13/rollout-current.jsonl", contents: "{}")
        try writeFile(root: root, path: "sessions/2026/05/10/rollout-2026-05-10T08-00-00-inactive.jsonl", contents: "{}")
        try setModificationDate(root: root, path: "sessions/2026/05/10/rollout-2026-05-10T08-00-00-inactive.jsonl", date: inactiveModifiedAt)
        try writeFile(root: root, path: "sessions/2026/05/10/rollout-2026-05-10T08-00-00-active.jsonl", contents: "{}")
        try setModificationDate(root: root, path: "sessions/2026/05/10/rollout-2026-05-10T08-00-00-active.jsonl", date: activeModifiedAt)
        try writeFile(root: root, path: "archived_sessions/rollout-archived.jsonl", contents: "{}")

        let files = RolloutLogScanner().rolloutFiles(in: root, now: now)
        let paths = files.map(\.path)

        try check(paths.contains { $0.contains("sessions/2026/06/13/rollout-current.jsonl") }, "recent session rollout should be included")
        try check(paths.contains { $0.contains("sessions/2026/05/10/rollout-2026-05-10T08-00-00-active.jsonl") }, "active long-running session should be included")
        try check(paths.contains { $0.contains("archived_sessions/rollout-archived.jsonl") }, "undated recent archived rollout should use mtime fallback")
        try check(!paths.contains { $0.contains("rollout-2026-05-10T08-00-00-inactive.jsonl") }, "inactive old rollout date should be skipped")
    }

    func resetLabelUsesTimeTodayAndDateForLaterDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let now = date("2026-06-13T04:00:00.000Z")
        let sameDayReset = date("2026-06-13T07:30:00.000Z")
        let laterReset = date("2026-06-18T01:00:00.000Z")

        try check(TrendCalendar.resetLabel(for: sameDayReset, now: now, calendar: calendar) == "15:30", "same-day reset label mismatch")
        try check(TrendCalendar.resetLabel(for: laterReset, now: now, calendar: calendar) == "6月18日", "later reset label mismatch")
    }

    func snapshotStoreWritesAndLoadsMirrorURLs() throws {
        let root = try makeTemporaryCodexRoot()
        let primaryURL = root.appendingPathComponent("group/quota-snapshot.json")
        let mirrorURL = root.appendingPathComponent("widget/quota-snapshot.json")
        let store = QuotaSnapshotStore(snapshotURL: primaryURL, mirrorURLs: [mirrorURL])
        let snapshot = QuotaSnapshot(
            updatedAt: date("2026-06-13T08:00:00.000Z"),
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 25, resetsAt: date("2026-06-13T12:15:34.000Z"), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 24, resetsAt: date("2026-06-18T06:51:17.000Z"), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-06-13", label: "06-13", tokens: 140_415_700)
            ],
            dailyAverageTokens: 140_415_700,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 77, parsedEventCount: 12_962, latestEventAt: date("2026-06-13T07:54:49.000Z"))
        )

        try store.save(snapshot)
        try check(FileManager.default.fileExists(atPath: primaryURL.path), "primary snapshot was not written")
        try check(FileManager.default.fileExists(atPath: mirrorURL.path), "mirror snapshot was not written")

        try FileManager.default.removeItem(at: primaryURL)
        let loaded = try store.load()
        try check(loaded.status == .ready, "mirror snapshot should load after primary is missing")
        try check(loaded.limits[0].remainingPercent == 75, "mirror primary remaining mismatch")
        try check(loaded.dailyAverageTokens == 140_415_700, "mirror daily average mismatch")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeTemporaryCodexRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexQuotaChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFile(root: URL, path: String, contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func setModificationDate(root: URL, path: String, date: Date) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func date(_ value: String) -> Date {
        CodexDateParser.parseTimestamp(value)!
    }

    private func tokenLine(
        timestamp: String,
        lastTotal: Int,
        cumulativeTotal: Int,
        primaryUsed: Double? = nil,
        secondaryUsed: Double? = nil,
        includeRateLimits: Bool = true,
        limitID: String = "codex"
    ) -> String {
        var root: [String: Any] = [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": ["total_tokens": cumulativeTotal],
                    "last_token_usage": ["total_tokens": lastTotal],
                    "model_context_window": 258_400
                ]
            ]
        ]

        if includeRateLimits {
            var rateLimits: [String: Any] = [:]
            rateLimits["limit_id"] = limitID
            if let primaryUsed {
                rateLimits["primary"] = [
                    "used_percent": primaryUsed,
                    "window_minutes": 300,
                    "resets_at": 1_781_334_127
                ]
            }
            if let secondaryUsed {
                rateLimits["secondary"] = [
                    "used_percent": secondaryUsed,
                    "window_minutes": 10_080,
                    "resets_at": 1_781_765_477
                ]
            }
            root["rate_limits"] = rateLimits
        }

        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
