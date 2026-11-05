import CoreServices
import Foundation

/// Watches a working tree with FSEvents and calls `onChange` (on the main actor, coalesced)
/// whenever files or the repository's refs change.
@MainActor
final class RepoWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            guard changed.prefix(count).contains(where: RepoWatcher.isRelevant) else { return }
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated { watcher.onChange() }
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.4,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    // The stream holds an unretained pointer to self, so it can't outlive the watcher.
    isolated deinit { stop() }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Ignores git's internal churn that doesn't change what GitOS shows.
    nonisolated static func isRelevant(_ path: String) -> Bool {
        !(path.contains("/.git/objects/") || path.contains("/.git/logs/") || path.hasSuffix(".lock"))
    }
}
