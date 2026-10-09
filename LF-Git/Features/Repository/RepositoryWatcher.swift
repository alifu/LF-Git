import CoreServices
import Foundation

/// Calls `onChange` (once, after things settle) when files in the repository change, so the window
/// follows edits made in an editor or a terminal.
nonisolated final class RepositoryWatcher: @unchecked Sendable {
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "lfgit.watcher")
    private let onChange: @Sendable () -> Void
    private var pending: DispatchWorkItem?
    /// Quiet time to wait for, so a build or checkout touching thousands of files refreshes once.
    private static let settleTime: TimeInterval = 0.6

    /// Directories whose churn never changes what the app shows.
    private static let ignoredFragments = ["/.git/objects", "/.git/lfs", "/.git/logs", "/.git/hooks", "/.build/", "/DerivedData/", "/node_modules/", "/.DS_Store"]

    init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.received(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func received(_ paths: [String]) {
        guard paths.contains(where: { path in !Self.ignoredFragments.contains { path.contains($0) } }) else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + Self.settleTime, execute: item)
    }
}
