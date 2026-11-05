import Foundation
import Testing
@testable import GitOS

@MainActor
struct RepoWatcherTests {
    private func makeDirectory() throws -> URL {
        // FSEvents reports resolved paths, so use one without the /var symlink.
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("gitos-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ directory: URL) throws {
        try Data("x".utf8).write(to: directory.appendingPathComponent(UUID().uuidString))
    }

    @Test func reportsChanges() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var changes = 0
        let watcher = RepoWatcher(path: directory.path) { changes += 1 }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try touch(directory)
        for _ in 0..<40 where changes == 0 { try await Task.sleep(for: .milliseconds(100)) }
        #expect(changes > 0)
    }

    /// A view can go away while it's still loading, which drops the watcher without calling `stop()`.
    @Test func releasedWithoutStoppingIsSilent() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var changes = 0
        var watcher: RepoWatcher? = RepoWatcher(path: directory.path) { changes += 1 }
        try await Task.sleep(for: .milliseconds(300))
        withExtendedLifetime(watcher) {}
        watcher = nil
        try touch(directory)
        try await Task.sleep(for: .seconds(2))
        #expect(changes == 0)
    }
}
