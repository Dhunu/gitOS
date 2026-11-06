import Foundation
import Testing
@testable import GitOS

struct StatusParserTests {
    @Test func parsesBranchAndEntries() {
        let output = [
            "# branch.oid 1234567890abcdef",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +2 -1",
            "1 M. N... 100644 100644 100644 aaa bbb src/staged.swift",
            "1 .M N... 100644 100644 100644 aaa bbb src/unstaged file.swift",
            "1 MM N... 100644 100644 100644 aaa bbb both.swift",
            "2 R. N... 100644 100644 100644 aaa bbb R100 new.swift", "old.swift",
            "u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.swift",
            "? untracked.txt",
        ].joined(separator: "\0") + "\0"

        let status = StatusParser.parse(output)
        #expect(status.branch == "main")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 2 && status.behind == 1)
        #expect(status.staged.map(\.path) == ["src/staged.swift", "both.swift", "new.swift"])
        #expect(status.staged.last?.originalPath == "old.swift")
        #expect(status.staged.last?.kind == .renamed)
        #expect(status.unstaged.map(\.path) == ["src/unstaged file.swift", "both.swift", "untracked.txt"])
        #expect(status.unstaged.last?.kind == .untracked)
        #expect(status.conflicted.map(\.path) == ["conflict.swift"])
    }

    @Test func parsesUnbornAndDetached() {
        let status = StatusParser.parse("# branch.oid (initial)\0# branch.head (detached)\0")
        #expect(status.isUnborn)
        #expect(status.branch == nil)
    }
}

struct DiffParserTests {
    static let sample = """
    diff --git a/a.txt b/a.txt
    index 1111111..2222222 100644
    --- a/a.txt
    +++ b/a.txt
    @@ -1,3 +1,3 @@
     one
    -two
    +TWO
     three
    @@ -10,2 +10,3 @@ func x()
     ten
    +ten and a half
     eleven
    diff --git a/new.txt b/new.txt
    new file mode 100644
    index 0000000..3333333
    --- /dev/null
    +++ b/new.txt
    @@ -0,0 +1 @@
    +hello
    \\ No newline at end of file
    diff --git a/img.png b/img.png
    index 1..2 100644
    Binary files a/img.png and b/img.png differ

    """

    @Test func parsesFilesAndHunks() {
        let files = DiffParser.parse(Self.sample)
        #expect(files.map(\.path) == ["a.txt", "new.txt", "img.png"])
        #expect(files[0].hunks.count == 2)
        #expect(files[0].hunks[0].lines.map(\.kind) == [.context, .deletion, .addition, .context])
        #expect(files[0].hunks[1].lines[1].newLine == 11)
        #expect(files[1].hunks[0].lines.last?.kind == .noNewline)
        #expect(files[2].isBinary)
    }

    @Test func hunkPatchRoundTrips() {
        let file = DiffParser.parse(Self.sample)[0]
        let patch = file.patch(for: file.hunks[1])
        #expect(patch.hasPrefix("diff --git a/a.txt b/a.txt\n"))
        #expect(patch.contains("@@ -10,2 +10,3 @@ func x()\n ten\n+ten and a half\n eleven\n"))
        #expect(!patch.contains("TWO"))
    }
}

struct RemoteParserTests {
    @Test(arguments: [
        ("https://github.com/apple/swift.git", "github.com"),
        ("git@github.com:apple/swift.git", "github.com"),
        ("ssh://git@github.com/apple/swift", "github.com"),
        ("https://user@github.com/apple/swift", "github.com"),
    ])
    func parsesGitHubRemotes(url: String, host: String) {
        let info = RemoteParser.parse(name: "origin", url: url)
        #expect(info.host == host)
        #expect(info.owner == "apple")
        #expect(info.repo == "swift")
    }
}

struct AccountTests {
    @Test func folderRuleMatchesOnPathBoundary() {
        let rule = FolderRule(folder: "/Users/me/Work", accountID: UUID())
        #expect(rule.matches("/Users/me/Work/api"))
        #expect(rule.matches("/Users/me/Work"))
        #expect(!rule.matches("/Users/me/Workshop/api"))
    }

    @Test func contextInjectsScopedCredentialHelper() {
        let context = GitContext(authorName: "A", authorEmail: "a@x.com", signing: nil, githubUser: "a", githubToken: "t")
        let args = context.configArgs
        #expect(args.contains("credential.https://github.com.helper="))
        #expect(args.contains("user.email=a@x.com"))
        #expect(context.environment["GITOS_GH_TOKEN"] == "t")
        #expect(GitContext.none.configArgs.isEmpty)
    }
}

struct PersonTests {
    @Test func parsesNameAndEmail() {
        let person = Person(parsing: "  Ada Lovelace <ada@example.com> ")
        #expect(person?.name == "Ada Lovelace")
        #expect(person?.trailer == "Co-authored-by: Ada Lovelace <ada@example.com>")
        #expect(Person(parsing: "no email here") == nil)
        #expect(Person(parsing: "<ada@example.com>") == nil)
    }
}

struct WorktreeParserTests {
    @Test func parsesPorcelain() {
        let output = """
        worktree /src/app
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /src/app-feature
        HEAD 2222222222222222222222222222222222222222
        detached
        locked

        """
        let trees = WorktreeParser.parse(output)
        #expect(trees.count == 2)
        #expect(trees[0].isMain && trees[0].branch == "main")
        #expect(!trees[1].isMain && trees[1].branch == nil && trees[1].isLocked)
    }

    @Test func remoteBranchesSkipHEADAndBranchesAlreadyLocal() {
        let output = """
        origin/HEAD\u{1f}refs/remotes/origin/main
        origin/main\u{1f}
        origin/newdesign\u{1f}
        origin/feat/billing\u{1f}
        my/fork/topic\u{1f}
        unknown/thing\u{1f}
        """
        let local = [Branch(name: "main", upstream: "origin/main", isCurrent: true)]
        let branches = RemoteBranchParser.parse(output, remotes: ["origin", "my", "my/fork"], excluding: local)
        #expect(branches.map(\.ref) == ["origin/newdesign", "origin/feat/billing", "my/fork/topic"])
        #expect(branches[1].name == "feat/billing")
        #expect(branches[2].remote == "my/fork")
    }

    @Test func branchSearchIgnoresCaseAndMatchesEveryWord() {
        #expect(BranchChoice.matches("feat/mac-download", query: ""))
        #expect(BranchChoice.matches("newdesign", query: "NewDes"))
        #expect(BranchChoice.matches("feat/mac-download", query: "mac feat"))
        #expect(!BranchChoice.matches("feat/mac-download", query: "mac windows"))
    }
}
