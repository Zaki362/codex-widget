import CodexQuotaCore
import Darwin
import Foundation

@main
struct CodexQuotaRefreshOnce {
    static func main() throws {
        let root = codexRoot()
        let snapshot = CodexQuotaCollector().collect(from: root)
        try QuotaSnapshotStore.defaultStore().save(snapshot)

        let primary = snapshot.limits.first { $0.id == "primary" }?.remainingPercent
        let secondary = snapshot.limits.first { $0.id == "secondary" }?.remainingPercent
        print("status=\(snapshot.status.rawValue)")
        print("updatedAt=\(snapshot.updatedAt)")
        print("root=\(snapshot.source.rootPath)")
        print("files=\(snapshot.source.scannedFileCount) events=\(snapshot.source.parsedEventCount)")
        print("primaryRemaining=\(primary.map { String(Int($0.rounded())) } ?? "nil")")
        print("secondaryRemaining=\(secondary.map { String(Int($0.rounded())) } ?? "nil")")
    }

    private static func codexRoot() -> URL {
        if let path = CommandLine.arguments.dropFirst().first {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return realHomeDirectory().appendingPathComponent(".codex", isDirectory: true)
    }

    private static func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
