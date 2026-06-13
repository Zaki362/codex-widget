import Foundation

public struct RolloutLogScanner: Sendable {
    public init() {}

    public func rolloutFiles(in codexRoot: URL, now: Date = Date()) -> [URL] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 24 * 60 * 60)
        var paths = Set<String>()
        var files: [URL] = []

        func appendIfRollout(_ url: URL) {
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else {
                return
            }
            if let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modifiedAt < cutoff {
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
}
