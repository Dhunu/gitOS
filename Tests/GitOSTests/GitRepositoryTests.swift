import Foundation
import Testing
@testable import GitOS

/// Runs against real git in a throwaway repository.
struct GitRepositoryTests {
    let repo: GitRepository
    let identity = GitContext(authorName: "Test", authorEmail: "test@example.com")

    init() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await Git.run(["init", "-q", "-b", "main"], in: dir)
        repo = GitRepository(url: dir)
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: repo.url.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test func addRemoteParsesAndFetches() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("gitos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try await Git.run(["init", "-q", "-b", "main"], in: source)
        try await Git.run(["commit", "-q", "--allow-empty", "-m", "Remote commit"], in: source, context: identity)

        try await repo.addRemote(name: "origin", url: source.path)
        let remotes = try await repo.remotes()
        #expect(remotes.map(\.name) == ["origin"])

        try await repo.fetch(context: .none)
        #expect(await repo.remoteBranchExists(remote: "origin", branch: "main"))
        await #expect(throws: GitFailure.self) { try await repo.addRemote(name: "origin", url: source.path) }
    }

    @Test(arguments: ["origin", "up-stream", "my_fork.2"])
    func acceptsRemoteName(_ name: String) { #expect(RepoModel.isValidRemoteName(name)) }

    @Test(arguments: ["", "-x", "has space", "a..b", ".hidden", "a/b", "nämé"])
    func rejectsRemoteName(_ name: String) { #expect(!RepoModel.isValidRemoteName(name)) }

    @Test func stageSingleHunkThenCommit() async throws {
        let lines = (1...30).map { "line \($0)" }
        try write("file.txt", lines.joined(separator: "\n") + "\n")
        var status = try await repo.status()
        #expect(status.isUnborn)
        #expect(status.unstaged.first?.kind == .untracked)

        try await repo.stage(["file.txt"])
        try await repo.commit(message: "Initial", context: identity)

        var edited = lines
        edited[1] = "line 2 changed"
        edited[27] = "line 28 changed"
        try write("file.txt", edited.joined(separator: "\n") + "\n")

        status = try await repo.status()
        let change = try #require(status.unstaged.first)
        let diff = try #require(try await repo.diff(for: change))
        #expect(diff.hunks.count == 2)

        try await repo.apply(patch: diff.patch(for: diff.hunks[0]), cached: true, reverse: false)
        status = try await repo.status()
        #expect(status.staged.map(\.path) == ["file.txt"])
        #expect(status.unstaged.map(\.path) == ["file.txt"])

        let staged = try #require(try await repo.diff(for: status.staged[0]))
        #expect(staged.hunks.count == 1)
        #expect(staged.hunks[0].lines.contains { $0.text == "line 2 changed" })

        try await repo.commit(message: "Change line 2", context: identity)
        let log = try await repo.log()
        #expect(log.map(\.subject) == ["Change line 2", "Initial"])
        #expect(log[0].authorEmail == "test@example.com")

        // Discard the remaining hunk.
        status = try await repo.status()
        let remaining = try #require(try await repo.diff(for: status.unstaged[0]))
        try await repo.apply(patch: remaining.patch(for: remaining.hunks[0]), cached: false, reverse: true)
        status = try await repo.status()
        #expect(!status.hasChanges)
    }

    @Test func branchesAndUnpushedEmails() async throws {
        try write("a.txt", "a\n")
        try await repo.stage(["a.txt"])
        try await repo.commit(message: "A", context: identity)
        try await repo.createBranch("feature")
        let branches = try await repo.branches()
        #expect(Set(branches.map(\.name)) == ["main", "feature"])
        #expect(branches.first { $0.isCurrent }?.name == "feature")
        let emails = try await repo.unpushedAuthorEmails(hasUpstream: false)
        #expect(emails == ["test@example.com"])
    }
}

extension GitRepositoryTests {
    @Test func stageAndUnstageSelectedLines() async throws {
        try write("f.txt", "a\nb\nc\nd\n")
        try await repo.stage(["f.txt"])
        try await repo.commit(message: "Initial", context: identity)
        try write("f.txt", "a\nB\nc\nD\ne\n")

        var status = try await repo.status()
        let diff = try #require(try await repo.diff(for: status.unstaged[0]))
        let hunk = try #require(diff.hunks.first)
        // Stage only the "B" replacement (its - and + lines).
        let picked = Set(hunk.lines.indices.filter { ["b", "B"].contains(hunk.lines[$0].text) && hunk.lines[$0].kind != .context })
        try await repo.apply(patch: diff.patch(for: hunk, selecting: picked, reverse: false), cached: true, reverse: false)

        let index = try await Git.run(["show", ":f.txt"], in: repo.url)
        #expect(index == "a\nB\nc\nd\n")

        // Unstage it again by line selection on the staged diff.
        status = try await repo.status()
        let staged = try #require(try await repo.diff(for: status.staged[0]))
        let stagedHunk = staged.hunks[0]
        let addLine = Set(stagedHunk.lines.indices.filter { stagedHunk.lines[$0].kind != .context })
        try await repo.apply(patch: staged.patch(for: stagedHunk, selecting: addLine, reverse: true), cached: true, reverse: true)
        status = try await repo.status()
        #expect(status.staged.isEmpty)
        let worktree = try String(contentsOf: repo.url.appendingPathComponent("f.txt"), encoding: .utf8)
        #expect(worktree == "a\nB\nc\nD\ne\n")
    }

    @Test func discardSelectedLinesOnly() async throws {
        try write("g.txt", "1\n2\n3\n")
        try await repo.stage(["g.txt"])
        try await repo.commit(message: "Initial", context: identity)
        try write("g.txt", "1\nTWO\n3\nfour\n")

        let status = try await repo.status()
        let diff = try #require(try await repo.diff(for: status.unstaged[0]))
        let hunk = diff.hunks[0]
        let four = Set(hunk.lines.indices.filter { hunk.lines[$0].text == "four" })
        try await repo.apply(patch: diff.patch(for: hunk, selecting: four, reverse: true), cached: false, reverse: true)
        let worktree = try String(contentsOf: repo.url.appendingPathComponent("g.txt"), encoding: .utf8)
        #expect(worktree == "1\nTWO\n3\n")
    }
}

extension GitRepositoryTests {
    @Test func stashRoundTripAndWorktrees() async throws {
        try write("s.txt", "one\n")
        try await repo.stage(["s.txt"])
        try await repo.commit(message: "Initial", context: identity)

        try write("s.txt", "two\n")
        try write("new.txt", "untracked\n")
        try await Git.run(["-c", "user.name=T", "-c", "user.email=t@e.com", "stash", "push", "--include-untracked", "-m", "wip thing"], in: repo.url)
        let stashes = try await repo.stashes()
        #expect(stashes.count == 1)
        #expect(stashes[0].ref == "stash@{0}")
        #expect(stashes[0].message.hasSuffix("wip thing"))
        let diff = try await repo.stashDiff(stashes[0].ref)
        #expect(Set(diff.map(\.path)) == ["s.txt", "new.txt"])

        try await repo.stashApply(stashes[0].ref, pop: true)
        #expect(try await repo.stashes().isEmpty)
        #expect(try await repo.status().unstaged.count == 2)

        let treePath = repo.url.path + "-wt"
        try await repo.addWorktree(path: treePath, branch: "side", newBranch: true)
        let trees = try await repo.worktrees()
        #expect(trees.count == 2)
        #expect(trees[0].isMain)
        #expect(trees[1].branch == "side")
        try await repo.removeWorktree(path: treePath, force: false)
        #expect(try await repo.worktrees().count == 1)
    }
}

extension GitRepositoryTests {
    /// A branch without an upstream can be linked to <remote>/<branch> and pulled; one missing on the remote can't.
    @Test func linksMissingUpstreamBeforePulling() async throws {
        try write("r.txt", "1\n")
        try await repo.stage(["r.txt"])
        try await repo.commit(message: "One", context: identity)

        let remoteDir = repo.url.path + "-remote.git"
        try await Git.run(["clone", "-q", "--bare", repo.url.path, remoteDir], in: repo.url.deletingLastPathComponent())
        try await Git.run(["remote", "add", "origin", remoteDir], in: repo.url)
        try await Git.run(["fetch", "-q", "origin"], in: repo.url)
        #expect(try await repo.status().upstream == nil)

        #expect(await repo.remoteBranchExists(remote: "origin", branch: "main"))
        #expect(await !repo.remoteBranchExists(remote: "origin", branch: "nope"))
        try await repo.setUpstream(of: "main", to: "origin/main")
        #expect(try await repo.status().upstream == "origin/main")
        try await repo.pull(context: identity)
    }
}
