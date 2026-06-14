import Foundation

public struct CodexQuotaCollector: Sendable {
    public var scanner: RolloutLogScanner

    public init(scanner: RolloutLogScanner = RolloutLogScanner()) {
        self.scanner = scanner
    }

    public func collect(from codexRoot: URL, now: Date = Date(), calendar: Calendar = .current) -> QuotaSnapshot {
        let rootPath = codexRoot.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: rootPath) else {
            return .error("找不到 Codex 数据目录", now: now, rootPath: rootPath)
        }

        let files = scanner.rolloutFiles(in: codexRoot, now: now)
        var events: [RolloutTokenEvent] = []
        var seen = Set<String>()

        for file in files {
            for event in RolloutLogParser.parseFile(at: file) {
                guard seen.insert(event.duplicateKey).inserted else {
                    continue
                }
                events.append(event)
            }
        }

        guard !events.isEmpty else {
            return QuotaSnapshot(
                updatedAt: now,
                status: .empty,
                limits: QuotaLimit.defaultLimits(),
                trend: DailyTokenUsage.emptyLastFiveDays(now: now, calendar: calendar),
                dailyAverageTokens: 0,
                source: SnapshotSource(rootPath: rootPath, scannedFileCount: files.count, parsedEventCount: 0, latestEventAt: nil),
                message: "运行 Codex 后会显示额度数据"
            )
        }

        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let latestEventAt = sortedEvents.last?.timestamp
        let latestRateLimitEvent = latestCodexRateLimitEvent(in: sortedEvents)
        let trend = buildTrend(from: events, now: now, calendar: calendar)
        let dailyAverage = trend.isEmpty ? 0 : trend.reduce(0) { $0 + $1.tokens } / trend.count

        let limits = buildLimits(from: latestRateLimitEvent)
        let status: SnapshotStatus = .ready
        let message = limits.allSatisfy { $0.usedPercent == nil } ? "已找到 token 历史，但暂无额度窗口数据" : nil

        return QuotaSnapshot(
            updatedAt: now,
            status: status,
            limits: limits,
            trend: trend,
            dailyAverageTokens: dailyAverage,
            source: SnapshotSource(rootPath: rootPath, scannedFileCount: files.count, parsedEventCount: events.count, latestEventAt: latestEventAt),
            message: message
        )
    }

    private func latestCodexRateLimitEvent(in sortedEvents: [RolloutTokenEvent]) -> RolloutTokenEvent? {
        let rateLimitEvents = sortedEvents.filter { $0.primary != nil || $0.secondary != nil }
        return rateLimitEvents.last { $0.limitID == "codex" }
            ?? rateLimitEvents.last { $0.limitID == nil }
            ?? rateLimitEvents.last
    }

    private func buildLimits(from event: RolloutTokenEvent?) -> [QuotaLimit] {
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

    private func buildTrend(from events: [RolloutTokenEvent], now: Date, calendar: Calendar) -> [DailyTokenUsage] {
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
