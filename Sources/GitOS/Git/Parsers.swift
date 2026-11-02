import Foundation

enum StatusParser {
    /// Parses `git status --porcelain=v2 --branch -z --untracked-files=all`.
    static func parse(_ output: String) -> RepoStatus {
        var status = RepoStatus()
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            index += 1

            if token.hasPrefix("# ") {
                parseHeader(token, into: &status)
                continue
            }

            switch token.first {
            case "1":
                let fields = token.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard fields.count == 9 else { continue }
                add(xy: fields[1], path: String(fields[8]), originalPath: nil, to: &status)
            case "2":
                let fields = token.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count == 10 else { continue }
                let original = index < tokens.count ? tokens[index] : nil
                index += 1
                add(xy: fields[1], path: String(fields[9]), originalPath: original, to: &status)
            case "u":
                let fields = token.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard fields.count == 11 else { continue }
                status.conflicted.append(FileChange(path: String(fields[10]), kind: .conflicted, area: .conflicted))
            case "?":
                status.unstaged.append(FileChange(path: String(token.dropFirst(2)), kind: .untracked, area: .unstaged))
            default:
                continue
            }
        }
        return status
    }

    private static func parseHeader(_ line: String, into status: inout RepoStatus) {
        let parts = line.dropFirst(2).split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "branch.oid": status.oid = parts[1] == "(initial)" ? nil : parts[1]
        case "branch.head": status.branch = parts[1] == "(detached)" ? nil : parts[1]
        case "branch.upstream": status.upstream = parts[1]
        case "branch.ab":
            let counts = parts[1].split(separator: " ")
            if counts.count == 2 {
                status.ahead = Int(counts[0].dropFirst()) ?? 0
                status.behind = Int(counts[1].dropFirst()) ?? 0
            }
        default: break
        }
    }

    private static func add(xy: Substring, path: String, originalPath: String?, to status: inout RepoStatus) {
        let chars = Array(xy)
        guard chars.count == 2 else { return }
        if let kind = FileChangeKind(statusCode: chars[0]) {
            status.staged.append(FileChange(path: path, originalPath: originalPath, kind: kind, area: .staged))
        }
        if let kind = FileChangeKind(statusCode: chars[1]) {
            status.unstaged.append(FileChange(path: path, originalPath: originalPath, kind: kind, area: .unstaged))
        }
    }
}

enum DiffParser {
    /// Parses unified diff output (`git diff`, `git show`, `git diff --no-index`) into per-file diffs.
    static func parse(_ text: String) -> [FileDiff] {
        var files: [FileDiff] = []
        var header: [String] = []
        var hunks: [DiffHunk] = []
        var current: DiffHunk?
        var oldLine = 0, newLine = 0
        var isBinary = false
        var oldPath: String?, newPath: String?
        var inFile = false

        func finishHunk() {
            if let hunk = current { hunks.append(hunk) }
            current = nil
        }

        func finishFile() {
            finishHunk()
            guard inFile else { return }
            let path = newPath ?? oldPath ?? pathFromDiffGit(header.first) ?? "unknown"
            let original = (oldPath != nil && oldPath != path) ? oldPath : nil
            files.append(FileDiff(path: path, oldPath: original, headerLines: header, hunks: hunks, isBinary: isBinary))
            header = []; hunks = []; isBinary = false; oldPath = nil; newPath = nil; inFile = false
        }

        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                finishFile()
                inFile = true
                header = [line]
                continue
            }
            guard inFile else { continue }

            if line.hasPrefix("@@") {
                finishHunk()
                guard let parsed = parseHunkHeader(line) else { continue }
                oldLine = parsed.oldStart
                newLine = parsed.newStart
                current = DiffHunk(id: hunks.count, header: line, oldStart: parsed.oldStart, newStart: parsed.newStart, lines: [])
                continue
            }

            if current == nil {
                header.append(line)
                if line.hasPrefix("--- ") { oldPath = stripPrefix(String(line.dropFirst(4))) }
                else if line.hasPrefix("+++ ") { newPath = stripPrefix(String(line.dropFirst(4))) }
                else if line.hasPrefix("rename from ") { oldPath = String(line.dropFirst(12)) }
                else if line.hasPrefix("rename to ") { newPath = String(line.dropFirst(10)) }
                else if line.hasPrefix("Binary files ") || line == "GIT binary patch" { isBinary = true }
                continue
            }

            switch line.first {
            case "+":
                current?.lines.append(DiffLine(kind: .addition, text: String(line.dropFirst()), oldLine: nil, newLine: newLine))
                newLine += 1
            case "-":
                current?.lines.append(DiffLine(kind: .deletion, text: String(line.dropFirst()), oldLine: oldLine, newLine: nil))
                oldLine += 1
            case "\\":
                current?.lines.append(DiffLine(kind: .noNewline, text: line, oldLine: nil, newLine: nil))
            default:
                current?.lines.append(DiffLine(kind: .context, text: String(line.dropFirst()), oldLine: oldLine, newLine: newLine))
                oldLine += 1
                newLine += 1
            }
        }
        finishFile()
        return files
    }

    static func parseHunkHeader(_ line: String) -> (oldStart: Int, newStart: Int)? {
        // @@ -oldStart[,oldCount] +newStart[,newCount] @@ optional section
        let parts = line.split(separator: " ")
        guard parts.count >= 3, parts[1].hasPrefix("-"), parts[2].hasPrefix("+") else { return nil }
        let old = parts[1].dropFirst().split(separator: ",").first.flatMap { Int($0) }
        let new = parts[2].dropFirst().split(separator: ",").first.flatMap { Int($0) }
        guard let old, let new else { return nil }
        return (old, new)
    }

    private static func stripPrefix(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed == "/dev/null" { return nil }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") { return String(trimmed.dropFirst(2)) }
        return trimmed
    }

    private static func pathFromDiffGit(_ line: String?) -> String? {
        guard let line, let range = line.range(of: " b/", options: .backwards) else { return nil }
        return String(line[range.upperBound...])
    }
}

enum LogParser {
    static let format = "%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1e"

    static func parse(_ output: String) -> [Commit] {
        output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
            guard fields.count == 7 else { return nil }
            return Commit(
                sha: fields[0],
                parents: fields[1].split(separator: " ").map(String.init),
                authorName: fields[2],
                authorEmail: fields[3],
                date: Date(timeIntervalSince1970: TimeInterval(fields[4]) ?? 0),
                refs: fields[5].isEmpty ? [] : fields[5].components(separatedBy: ", "),
                subject: fields[6]
            )
        }
    }
}

enum RemoteParser {
    /// Parses https, ssh (`git@host:owner/repo`) and `ssh://` remote URLs.
    static func parse(name: String, url: String) -> RemoteInfo {
        var info = RemoteInfo(name: name, url: url)
        var rest: Substring
        if let range = url.range(of: "://") {
            rest = url[range.upperBound...]
            if let at = rest.firstIndex(of: "@"), at < (rest.firstIndex(of: "/") ?? rest.endIndex) {
                rest = rest[rest.index(after: at)...]
            }
            guard let slash = rest.firstIndex(of: "/") else { return info }
            info.host = String(rest[..<slash]).components(separatedBy: ":").first
            rest = rest[rest.index(after: slash)...]
        } else if let colon = url.firstIndex(of: ":") {
            let hostPart = url[..<colon]
            info.host = String(hostPart.split(separator: "@").last ?? hostPart)
            rest = url[url.index(after: colon)...]
        } else {
            return info
        }
        let pathParts = rest.split(separator: "/")
        if pathParts.count >= 2 {
            info.owner = String(pathParts[pathParts.count - 2])
            var repo = String(pathParts[pathParts.count - 1])
            if repo.hasSuffix(".git") { repo.removeLast(4) }
            info.repo = repo
        }
        return info
    }
}
