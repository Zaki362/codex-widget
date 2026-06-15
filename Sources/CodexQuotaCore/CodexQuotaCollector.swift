import Foundation

public struct CodexQuotaCollector: Sendable {
    public var scanner: RolloutLogScanner
    public var eventCache: RolloutParsedEventCache?

    public init(scanner: RolloutLogScanner = RolloutLogScanner(), eventCache: RolloutParsedEventCache? = nil) {
        self.scanner = scanner
        self.eventCache = eventCache
    }

    public func collect(from codexRoot: URL, now: Date = Date(), calendar: Calendar = .current) -> QuotaSnapshot {
        let rootPath = codexRoot.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: rootPath) else {
            return .error("找不到 Codex 数据目录", now: now, rootPath: rootPath)
        }

        let files = scanner.rolloutFiles(in: codexRoot, now: now)
        eventCache?.retainOnly(paths: Set(files.map { $0.standardizedFileURL.path }))
        var events: [RolloutTokenEvent] = []
        var seen = Set<String>()

        for file in files {
            let parsedEvents = eventCache?.events(for: file) ?? RolloutLogParser.parseFile(at: file)
            for event in parsedEvents {
                guard seen.insert(event.duplicateKey).inserted else {
                    continue
                }
                events.append(event)
            }
        }

        return QuotaSnapshotBuilder.build(
            events: events,
            rootPath: rootPath,
            scannedFileCount: files.count,
            now: now,
            calendar: calendar
        )
    }
}

enum QuotaSnapshotBuilder {
    static func build(
        events: [RolloutTokenEvent],
        rootPath: String,
        scannedFileCount: Int,
        now: Date,
        calendar: Calendar
    ) -> QuotaSnapshot {
        guard !events.isEmpty else {
            return QuotaSnapshot(
                updatedAt: now,
                status: .empty,
                limits: QuotaLimit.defaultLimits(),
                trend: DailyTokenUsage.emptyLastFiveDays(now: now, calendar: calendar),
                dailyAverageTokens: 0,
                source: SnapshotSource(rootPath: rootPath, scannedFileCount: scannedFileCount, parsedEventCount: 0, latestEventAt: nil),
                message: "运行 Codex 后会显示额度数据"
            )
        }

        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let latestEventAt = sortedEvents.last?.timestamp
        let latestRateLimitEvent = latestCodexRateLimitEvent(in: sortedEvents)
        let trend = buildTrend(from: events, now: now, calendar: calendar)
        let dailyAverage = trend.isEmpty ? 0 : trend.reduce(0) { $0 + $1.tokens } / trend.count
        let limits = buildLimits(from: latestRateLimitEvent)
        let message = limits.allSatisfy { $0.usedPercent == nil } ? "已找到 token 历史，但暂无额度窗口数据" : nil

        return QuotaSnapshot(
            updatedAt: now,
            status: .ready,
            limits: limits,
            trend: trend,
            dailyAverageTokens: dailyAverage,
            source: SnapshotSource(rootPath: rootPath, scannedFileCount: scannedFileCount, parsedEventCount: events.count, latestEventAt: latestEventAt),
            message: message
        )
    }

    private static func latestCodexRateLimitEvent(in sortedEvents: [RolloutTokenEvent]) -> RolloutTokenEvent? {
        let rateLimitEvents = sortedEvents.filter { $0.primary != nil || $0.secondary != nil }
        return rateLimitEvents.last { $0.limitID == "codex" }
            ?? rateLimitEvents.last { $0.limitID == nil }
            ?? rateLimitEvents.last
    }

    private static func buildLimits(from event: RolloutTokenEvent?) -> [QuotaLimit] {
        guard let event else {
            return QuotaLimit.defaultLimits()
        }

        return [
            QuotaLimit(
                id: "primary",
                label: "5小时",
                usedPercent: event.primary?.usedPercent,
                resetsAt: event.primary?.resetsAt,
                windowMinutes: event.primary?.windowMinutes ?? 300
            ),
            QuotaLimit(
                id: "secondary",
                label: "周限额",
                usedPercent: event.secondary?.usedPercent,
                resetsAt: event.secondary?.resetsAt,
                windowMinutes: event.secondary?.windowMinutes ?? 10_080
            )
        ]
    }

    private static func buildTrend(from events: [RolloutTokenEvent], now: Date, calendar: Calendar) -> [DailyTokenUsage] {
        let dayStarts = TrendCalendar.lastFiveDayStarts(now: now, calendar: calendar)
        guard let firstDay = dayStarts.first, let lastDay = dayStarts.last else {
            return []
        }

        var buckets = Dictionary(uniqueKeysWithValues: dayStarts.map { (TrendCalendar.dayKey(for: $0, calendar: calendar), 0) })

        for event in events {
            let dayStart = calendar.startOfDay(for: event.timestamp)
            guard dayStart >= firstDay, dayStart <= lastDay else {
                continue
            }
            let key = TrendCalendar.dayKey(for: dayStart, calendar: calendar)
            buckets[key, default: 0] += event.lastTotalTokens
        }

        return dayStarts.map { dayStart in
            let key = TrendCalendar.dayKey(for: dayStart, calendar: calendar)
            return DailyTokenUsage(
                dayKey: key,
                label: TrendCalendar.shortLabel(for: dayStart, calendar: calendar),
                tokens: buckets[key, default: 0]
            )
        }
    }
}
