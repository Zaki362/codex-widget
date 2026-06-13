import AppKit
import Darwin
import Foundation

final class FolderAccessManager {
    private let bookmarkKey = "codexFolderBookmark"

    func resolvedCodexFolder() -> URL {
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return url
            }
        }

        return realHomeDirectory().appendingPathComponent(".codex", isDirectory: true)
    }

    @MainActor
    func chooseCodexFolder(currentURL: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 数据目录"
        panel.message = "请选择 .codex 文件夹"
        panel.prompt = "授权"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            return url
        } catch {
            return url
        }
    }

    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    private func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
