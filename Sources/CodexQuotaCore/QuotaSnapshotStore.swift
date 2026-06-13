import Foundation
import Darwin

public struct QuotaSnapshotStore: Sendable {
    public var snapshotURL: URL
    public var mirrorURLs: [URL]

    public init(snapshotURL: URL, mirrorURLs: [URL] = []) {
        self.snapshotURL = snapshotURL
        self.mirrorURLs = mirrorURLs
    }

    public static func defaultStore(fileManager: FileManager = .default) -> QuotaSnapshotStore {
        let urls = defaultSnapshotURLs(fileManager: fileManager)
        return QuotaSnapshotStore(snapshotURL: urls[0], mirrorURLs: Array(urls.dropFirst()))
    }

    public static func defaultSnapshotURL(fileManager: FileManager = .default) -> URL {
        defaultSnapshotURLs(fileManager: fileManager)[0]
    }

    public static func defaultSnapshotURLs(fileManager: FileManager = .default) -> [URL] {
        var urls: [URL] = []

        urls.append(realHomeDirectory()
            .appendingPathComponent("Library/Containers/\(QuotaConstants.widgetBundleIdentifier)/Data/Library/Application Support/\(QuotaConstants.supportDirectoryName)", isDirectory: true)
            .appendingPathComponent(QuotaConstants.snapshotFileName))

        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(QuotaConstants.supportDirectoryName, isDirectory: true)
        let directory = supportDirectory ?? fileManager.temporaryDirectory.appendingPathComponent(QuotaConstants.supportDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        urls.append(directory.appendingPathComponent(QuotaConstants.snapshotFileName))

        return uniqueURLs(urls)
    }

    public func load() throws -> QuotaSnapshot {
        var lastError: Error?

        for url in snapshotURLs {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(QuotaSnapshot.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CocoaError(.fileNoSuchFile)
    }

    public func save(_ snapshot: QuotaSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        var savedAtLeastOnce = false
        var firstError: Error?

        for url in snapshotURLs {
            do {
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
                savedAtLeastOnce = true
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if !savedAtLeastOnce {
            throw firstError ?? CocoaError(.fileWriteUnknown)
        }
    }

    public var snapshotURLs: [URL] {
        Self.uniqueURLs([snapshotURL] + mirrorURLs)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private static func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}
