import Foundation

/// Typed wrapper over the git CLI for one working tree.
struct GitRepository: Sendable {
    let url: URL

    static func topLevel(of directory: URL) async throws -> URL {
        let path = try await Git.run(["rev-parse", "--show-toplevel"], in: directory)
        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Status & diffs

    func status() async throws -> RepoStatus {
        let output = try await Git.run(["--no-optional-locks", "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: url)
        return StatusParser.parse(output)
    }

    func diff(for change: FileChange) async throws -> FileDiff? {
        let output: String
        switch (change.area, change.kind) {
        case (.unstaged, .untracked):
            // --no-index exits 1 when the files differ.
            output = try await Git.run(["diff", "--no-ext-diff", "--no-index", "--", "/dev/null", change.path],
                                       in: url, allowedExitCodes: [0, 1])
        case (.staged, _):
            output = try await Git.run(["diff", "--no-ext-diff", "--cached", "-M", "--", change.path] + (change.originalPath.map { [$0] } ?? []), in: url)
        case (.conflicted, _), (.unstaged, _):
            output = try await Git.run(["diff", "--no-ext-diff", "--", change.path], in: url)
        }
        return DiffParser.parse(output).first
    }

    func stagedPatch() async throws -> String {
        try await Git.run(["diff", "--no-ext-diff", "--cached", "--stat", "--patch", "-M"], in: url)
    }

    func show(_ sha: String) async throws -> [FileDiff] {
        let output = try await Git.run(["show", "--no-ext-diff", "--format=", "-M", "--first-parent", "--patch", sha], in: url)
        return DiffParser.parse(output)
    }

    // MARK: Index

    func stage(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await Git.run(["add", "-A", "--"] + paths, in: url)
    }

    func unstage(_ paths: [String], unborn: Bool) async throws {
        guard !paths.isEmpty else { return }
        if unborn {
            try await Git.run(["rm", "--cached", "-r", "-q", "--"] + paths, in: url)
        } else {
            try await Git.run(["restore", "--staged", "--"] + paths, in: url)
        }
    }

    /// Discards working-tree changes. Untracked files are moved to the Trash rather than deleted.
    func discard(_ change: FileChange) async throws {
        if change.kind == .untracked {
            try FileManager.default.trashItem(at: url.appendingPathComponent(change.path), resultingItemURL: nil)
        } else {
            try await Git.run(["restore", "--worktree", "--", change.path], in: url)
        }
    }

    /// Applies a single-hunk patch. `cached` targets the index; `reverse` undoes the hunk.
    func apply(patch: String, cached: Bool, reverse: Bool) async throws {
        var args = ["apply", "--recount", "--whitespace=nowarn"]
        if cached { args.append("--cached") }
        if reverse { args.append("--reverse") }
        args.append("-")
        try await Git.run(args, in: url, input: Data(patch.utf8))
    }

    func commit(message: String, context: GitContext) async throws {
        try await Git.run(["commit", "--cleanup=strip", "-F", "-"], in: url, context: context, input: Data(message.utf8))
    }

    // MARK: History & branches

    func log(limit: Int = 500, allBranches: Bool = false) async throws -> [Commit] {
        let refs = allBranches ? ["--branches", "--remotes", "--tags", "HEAD"] : ["HEAD"]
        let output = try await Git.run(["log", "--topo-order", "-n", "\(limit)", "--format=\(LogParser.format)"] + refs, in: url)
        return LogParser.parse(output)
    }

    func branches() async throws -> [Branch] {
        let output = try await Git.run(["for-each-ref", "--format=%(HEAD)%1f%(refname:short)%1f%(upstream:short)", "refs/heads"], in: url)
        return output.split(separator: "\n").compactMap { line in
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count == 3 else { return nil }
            return Branch(name: fields[1], upstream: fields[2].isEmpty ? nil : fields[2], isCurrent: fields[0] == "*")
        }
    }

    func switchBranch(_ name: String) async throws {
        try await Git.run(["switch", name], in: url)
    }

    func createBranch(_ name: String) async throws {
        try await Git.run(["switch", "-c", name], in: url)
    }

    // MARK: Stashes

    func stashes() async throws -> [Stash] {
        StashParser.parse(try await Git.run(["stash", "list", "--format=\(StashParser.format)"], in: url))
    }

    func stash(message: String) async throws {
        var args = ["stash", "push", "--include-untracked"]
        if !message.isEmpty { args += ["-m", message] }
        try await Git.run(args, in: url)
    }

    func stashApply(_ ref: String, pop: Bool) async throws {
        try await Git.run(["stash", pop ? "pop" : "apply", "--index", ref], in: url)
    }

    func stashDrop(_ ref: String) async throws {
        try await Git.run(["stash", "drop", ref], in: url)
    }

    func stashDiff(_ ref: String) async throws -> [FileDiff] {
        DiffParser.parse(try await Git.run(["stash", "show", "--no-ext-diff", "-p", "--include-untracked", ref], in: url))
    }

    // MARK: Worktrees

    func worktrees() async throws -> [Worktree] {
        WorktreeParser.parse(try await Git.run(["worktree", "list", "--porcelain"], in: url))
    }

    /// Adds a worktree at `path`, checking out `branch`, or creating it from HEAD when `newBranch` is set.
    func addWorktree(path: String, branch: String, newBranch: Bool) async throws {
        let args = newBranch ? ["worktree", "add", "-b", branch, path] : ["worktree", "add", path, branch]
        try await Git.run(args, in: url)
    }

    func removeWorktree(path: String, force: Bool) async throws {
        try await Git.run(["worktree", "remove"] + (force ? ["--force"] : []) + [path], in: url)
    }

    // MARK: Remotes

    func remotes() async throws -> [RemoteInfo] {
        let output = try await Git.run(["remote", "-v"], in: url)
        var seen = Set<String>()
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 2, seen.insert(parts[0]).inserted else { return nil }
            return RemoteParser.parse(name: parts[0], url: parts[1])
        }
    }

    /// Checks out a pull request: same-repo PRs get a tracking branch, fork PRs a local `pr/<number>` branch.
    func checkoutPullRequest(number: Int, headRef: String, fromFork: Bool, remote: String, context: GitContext) async throws {
        if fromFork {
            let local = "pr/\(number)"
            try await Git.run(["fetch", remote, "+refs/pull/\(number)/head:refs/heads/\(local)"], in: url, context: context)
            try await Git.run(["switch", local], in: url)
            return
        }
        try await Git.run(["fetch", remote, headRef], in: url, context: context)
        let exists = (try? await Git.run(["rev-parse", "--verify", "--quiet", "refs/heads/\(headRef)"], in: url)) != nil
        if exists {
            try await Git.run(["switch", headRef], in: url)
            try await Git.run(["merge", "--ff-only", "\(remote)/\(headRef)"], in: url)
        } else {
            try await Git.run(["switch", "-c", headRef, "--track", "\(remote)/\(headRef)"], in: url)
        }
    }

    func fetch(context: GitContext) async throws {
        try await Git.run(["fetch", "--all", "--prune"], in: url, context: context)
    }

    func addRemote(name: String, url remoteURL: String) async throws {
        try await Git.run(["remote", "add", "--", name, remoteURL], in: url)
    }

    func remoteBranchExists(remote: String, branch: String) async -> Bool {
        (try? await Git.run(["rev-parse", "--verify", "--quiet", "refs/remotes/\(remote)/\(branch)"], in: url)) != nil
    }

    func setUpstream(of branch: String, to upstream: String) async throws {
        try await Git.run(["branch", "--set-upstream-to=\(upstream)", branch], in: url)
    }

    func pull(context: GitContext) async throws {
        try await Git.run(["pull", "--no-edit"], in: url, context: context)
    }

    func push(remote: String, setUpstream: Bool, force: Bool = false, context: GitContext) async throws {
        var args = ["push"]
        if force { args.append("--force-with-lease") }
        if setUpstream { args += ["--set-upstream", remote, "HEAD"] }
        try await Git.run(args, in: url, context: context)
    }

    /// Author emails of commits that haven't been pushed yet.
    func unpushedAuthorEmails(hasUpstream: Bool) async throws -> Set<String> {
        let range = hasUpstream ? ["@{upstream}..HEAD"] : ["HEAD", "--not", "--remotes"]
        let output = try await Git.run(["log", "--format=%ae"] + range, in: url)
        return Set(output.split(separator: "\n").map { $0.lowercased() })
    }
}
