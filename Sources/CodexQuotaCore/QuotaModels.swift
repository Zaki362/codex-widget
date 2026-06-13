import Foundation

public enum QuotaConstants {
    public static let appGroupIdentifier = "group.com.guohuaz.CodexQuota"
    public static let widgetBundleIdentifier = "com.guohuaz.CodexQuota.Widget"
    public static let supportDirectoryName = "CodexQuota"
    public static let snapshotFileName = "quota-snapshot.json"
    public static let staleAfterSeconds: TimeInterval = 5 * 60
}

public enum SnapshotStatus: String, Codable, Equatable, Sendable {
    case ready
    case empty
    case stale
    case error
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: Date
    public var status: SnapshotStatus
    public var limits: [QuotaLimit]
    public var trend: [DailyTokenUsage]
    public var dailyAverageTokens: Int
    public var source: SnapshotSource
    public var message: String?

    public init(
        version: Int = 1,
        updatedAt: Date,
        status: SnapshotStatus,
        limits: [QuotaLimit],
        trend: [DailyTokenUsage],
        dailyAverageTokens: Int,
        source: SnapshotSource,
        message: String? = nil
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.status = status
        self.limits = limits
        self.trend = trend
        self.dailyAverageTokens = dailyAverageTokens
        self.source = source
        self.message = message
    }

    public func markingStaleIfNeeded(now: Date = Date()) -> QuotaSnapshot {
        guard status == .ready, now.timeIntervalSince(updatedAt) > QuotaConstants.staleAfterSeconds else {
            return self
        }

        var copy = self
        copy.status = .stale
        copy.message = "数据已超过 5 分钟未刷新"
        return copy
    }

    public static func placeholder(now: Date = Date()) -> QuotaSnapshot {
        QuotaSnapshot(
            updatedAt: now,
            status: .empty,
            limits: QuotaLimit.defaultLimits(),
            trend: DailyTokenUsage.emptyLastFiveDays(now: now),
            dailyAverageTokens: 0,
            source: SnapshotSource(rootPath: "", scannedFileCount: 0, parsedEventCount: 0, latestEventAt: nil),
            message: "运行 Codex 后会显示额度数据"
        )
    }

    public static func error(_ message: String, now: Date = Date(), rootPath: String = "") -> QuotaSnapshot {
        QuotaSnapshot(
            updatedAt: now,
            status: .error,
            limits: QuotaLimit.defaultLimits(),
            trend: DailyTokenUsage.emptyLastFiveDays(now: now),
            dailyAverageTokens: 0,
            source: SnapshotSource(rootPath: rootPath, scannedFileCount: 0, parsedEventCount: 0, latestEventAt: nil),
            message: message
        )
    }
}

public struct QuotaLimit: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var usedPercent: Double?
    public var remainingPercent: Double?
    public var resetsAt: Date?
    public var windowMinutes: Int?

    public init(
        id: String,
        label: String,
        usedPercent: Double?,
        resetsAt: Date?,
        windowMinutes: Int?
    ) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent.map { min(100, max(0, $0)) }
        self.remainingPercent = usedPercent.map { min(100, max(0, 100 - $0)) }
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }

    public static func defaultLimits() -> [QuotaLimit] {
        [
            QuotaLimit(id: "primary", label: "5小时", usedPercent: nil, resetsAt: nil, windowMinutes: 300),
            QuotaLimit(id: "secondary", label: "周限额", usedPercent: nil, resetsAt: nil, windowMinutes: 10_080)
        ]
    }
}

public struct DailyTokenUsage: Codable, Equatable, Sendable, Identifiable {
    public var id: String { dayKey }
    public var dayKey: String
    public var label: String
    public var tokens: Int

    public init(dayKey: String, label: String, tokens: Int) {
        self.dayKey = dayKey
        self.label = label
        self.tokens = max(0, tokens)
    }

    public static func emptyLastFiveDays(now: Date = Date(), calendar: Calendar = .current) -> [DailyTokenUsage] {
        TrendCalendar.lastFiveDayStarts(now: now, calendar: calendar).map { dayStart in
            DailyTokenUsage(
                dayKey: TrendCalendar.dayKey(for: dayStart, calendar: calendar),
                label: TrendCalendar.shortLabel(for: dayStart, calendar: calendar),
                tokens: 0
            )
        }
    }
}

public struct SnapshotSource: Codable, Equatable, Sendable {
    public var rootPath: String
    public var scannedFileCount: Int
    public var parsedEventCount: Int
    public var latestEventAt: Date?
    public var generatedBy: String

    public init(
        rootPath: String,
        scannedFileCount: Int,
        parsedEventCount: Int,
        latestEventAt: Date?,
        generatedBy: String = "CodexQuotaCollector"
    ) {
        self.rootPath = rootPath
        self.scannedFileCount = scannedFileCount
        self.parsedEventCount = parsedEventCount
        self.latestEventAt = latestEventAt
        self.generatedBy = generatedBy
    }
}
