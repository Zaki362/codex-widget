import Foundation

public final class RolloutParsedEventCache: @unchecked Sendable {
    private struct FileSignature: Equatable {
        var size: Int
        var modifiedAt: Date?
    }

    private struct Entry {
        var signature: FileSignature
        var events: [RolloutTokenEvent]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    public func events(for url: URL) -> [RolloutTokenEvent] {
        guard let signature = Self.signature(for: url) else {
            return RolloutLogParser.parseFile(at: url)
        }

        let path = url.standardizedFileURL.path
        lock.lock()
        if let entry = entries[path], entry.signature == signature {
            let cached = entry.events
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = RolloutLogParser.parseFile(at: url)

        lock.lock()
        entries[path] = Entry(signature: signature, events: parsed)
        lock.unlock()

        return parsed
    }

    public func retainOnly(paths: Set<String>) {
        lock.lock()
        entries = entries.filter { paths.contains($0.key) }
        lock.unlock()
    }

    private static func signature(for url: URL) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize
        else {
            return nil
        }

        return FileSignature(size: size, modifiedAt: values.contentModificationDate)
    }
}
