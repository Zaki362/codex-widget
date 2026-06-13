import Darwin
import Foundation

final class FolderWatcher {
    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
