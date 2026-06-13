import Foundation
import CodexQuotaCore

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "\(NSHomeDirectory())/.codex", isDirectory: true)
let snapshot = CodexQuotaCollector().collect(from: root)

print("status=\(snapshot.status.rawValue)")
print("root=\(snapshot.source.rootPath)")
print("files=\(snapshot.source.scannedFileCount) events=\(snapshot.source.parsedEventCount)")
print("latest=\(snapshot.source.latestEventAt?.description ?? "nil")")
for limit in snapshot.limits {
    print("\(limit.id) used=\(limit.usedPercent.map(String.init(describing:)) ?? "nil") remaining=\(limit.remainingPercent.map(String.init(describing:)) ?? "nil") reset=\(limit.resetsAt?.description ?? "nil")")
}
