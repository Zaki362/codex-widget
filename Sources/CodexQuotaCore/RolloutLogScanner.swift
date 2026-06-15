import Foundation

public struct RolloutLogScanner: Sendable {
    private let historicalDayBuffer = 5
    private let activeModifiedWindow: TimeInterval = 24 * 60 * 60

    public init() {}

    public func rolloutFiles(in codexRoot: URL, now: Date = Date()) -> [URL] {
        let calendar = Calendar.current
        let recentDayKeys = Self.recentRolloutDayKeys(now: now, calendar: calendar, buffer: historicalDayBuffer)
        let activeModifiedCutoff = now.addingTimeInterval(-activeModifiedWindow)
        var paths = Set<String>()
        var files: [URL] = []

        func appendIfRollout(_ url: URL) {
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else {
                return
            }

            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let dayKey = Self.rolloutDayKey(for: url) {
                guard recentDayKeys.contains(dayKey) || Self.wasRecentlyModified(modifiedAt, since: activeModifiedCutoff) else {
                    return
                }
            } else if !Self.wasRecentlyModified(modifiedAt, since: activeModifiedCutoff) {
                return
            }

            let path = url.standardizedFileURL.path
            guard paths.insert(path).inserted else {
                return
            }
            files.append(url)
        }

        let sessionsURL = codexRoot.appendingPathComponent("sessions", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                appendIfRollout(fileURL)
            }
        }

        let archivedURL = codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        if let archived = try? FileManager.default.contentsOfDirectory(
            at: archivedURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            archived.forEach(appendIfRollout)
        }

        return files.sorted { $0.path < $1.path }
    }

    private static func wasRecentlyModified(_ modifiedAt: Date?, since cutoff: Date) -> Bool {
        guard let modifiedAt else {
            return false
        }

        return modifiedAt >= cutoff
    }

    private static func recentRolloutDayKeys(now: Date, calendar: Calendar, buffer: Int) -> Set<String> {
        let today = calendar.startOfDay(for: now)
        return Set((-buffer...1).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
                .map { TrendCalendar.dayKey(for: $0, calendar: calendar) }
        })
    }

    private static func rolloutDayKey(for url: URL) -> String? {
        if let filenameDay = rolloutDayKey(inFilename: url.lastPathComponent) {
            return filenameDay
        }

        return rolloutDayKey(inPathComponents: url.pathComponents)
    }

    private static func rolloutDayKey(inFilename filename: String) -> String? {
        let prefix = "rollout-"
        guard filename.hasPrefix(prefix), filename.count >= prefix.count + 10 else {
            return nil
        }

        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(start, offsetBy: 10)
        let candidate = String(filename[start..<end])
        return isDayKey(candidate) ? candidate : nil
    }

    private static func rolloutDayKey(inPathComponents components: [String]) -> String? {
        guard let sessionsIndex = components.lastIndex(of: "sessions"),
              components.count > sessionsIndex + 3
        else {
            return nil
        }

        let year = components[sessionsIndex + 1]
        let month = components[sessionsIndex + 2]
        let day = components[sessionsIndex + 3]
        let candidate = "\(year)-\(month)-\(day)"
        return isDayKey(candidate) ? candidate : nil
    }

    private static func isDayKey(_ value: String) -> Bool {
        guard value.count == 10 else {
            return false
        }

        let characters = Array(value)
        return characters.indices.allSatisfy { index in
            switch index {
            case 4, 7:
                return characters[index] == "-"
            default:
                return characters[index].isNumber
            }
        }
    }
}
