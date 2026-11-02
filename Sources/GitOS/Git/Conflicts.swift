import Foundation

/// A working-tree file containing `<<<<<<<` / `|||||||` / `=======` / `>>>>>>>` conflict markers.
struct ConflictDocument: Sendable {
    enum Resolution: Hashable, Sendable {
        case ours, theirs, oursThenTheirs, theirsThenOurs
        case custom(String)
    }

    struct Conflict: Identifiable, Hashable, Sendable {
        var id: Int
        var oursLabel: String
        var theirsLabel: String
        var ours: String
        var base: String?
        var theirs: String

        func text(for resolution: Resolution) -> String {
            switch resolution {
            case .ours: ours
            case .theirs: theirs
            case .oursThenTheirs: ours + theirs
            case .theirsThenOurs: theirs + ours
            case .custom(let text): text
            }
        }
    }

    enum Segment: Hashable, Sendable {
        case common(String)
        case conflict(Conflict)
    }

    var segments: [Segment]

    var conflicts: [Conflict] {
        segments.compactMap { if case .conflict(let c) = $0 { c } else { nil } }
    }

    /// Lines keep their own line endings so CRLF files round-trip unchanged.
    static func parse(_ text: String) -> ConflictDocument {
        enum State { case common, ours, base, theirs }
        var segments: [Segment] = []
        var common = ""
        var state = State.common
        var current = Conflict(id: 0, oursLabel: "", theirsLabel: "", ours: "", base: nil, theirs: "")

        func marker(_ line: Substring, _ char: Character) -> String? {
            let body = line.trimmingCharacters(in: .newlines)
            guard body.count >= 7, body.prefix(7).allSatisfy({ $0 == char }),
                  body.count == 7 || body.dropFirst(7).first == " " else { return nil }
            return String(body.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }

        // Split on the newline byte: Swift treats "\r\n" as one Character, so firstIndex(of: "\n") misses it.
        var lines: [Substring] = []
        var start = text.startIndex
        var index = text.utf8.startIndex
        while index < text.utf8.endIndex {
            let next = text.utf8.index(after: index)
            if text.utf8[index] == UInt8(ascii: "\n") {
                lines.append(text[start..<next])
                start = next
            }
            index = next
        }
        if start < text.endIndex { lines.append(text[start...]) }

        for line in lines {
            switch state {
            case .common:
                if let label = marker(line, "<") {
                    if !common.isEmpty { segments.append(.common(common)); common = "" }
                    current = Conflict(id: segments.count, oursLabel: label, theirsLabel: "", ours: "", base: nil, theirs: "")
                    state = .ours
                } else {
                    common += line
                }
            case .ours:
                if marker(line, "|") != nil { current.base = ""; state = .base }
                else if marker(line, "=") != nil { state = .theirs }
                else { current.ours += line }
            case .base:
                if marker(line, "=") != nil { state = .theirs } else { current.base? += line }
            case .theirs:
                if let label = marker(line, ">") {
                    current.theirsLabel = label
                    segments.append(.conflict(current))
                    state = .common
                } else {
                    current.theirs += line
                }
            }
        }
        // An unterminated conflict is kept as plain text rather than lost.
        if state != .common {
            common += "<<<<<<< \(current.oursLabel)\n" + current.ours + "=======\n" + current.theirs
        }
        if !common.isEmpty { segments.append(.common(common)) }
        return ConflictDocument(segments: segments)
    }

    /// The file with each conflict replaced by its resolution; unresolved conflicts keep their markers.
    func render(_ resolutions: [Int: Resolution]) -> String {
        segments.map { segment in
            switch segment {
            case .common(let text): return text
            case .conflict(let c):
                if let resolution = resolutions[c.id] { return c.text(for: resolution) }
                var text = "<<<<<<< \(c.oursLabel)\n" + c.ours
                if let base = c.base { text += "|||||||\n" + base }
                return text + "=======\n" + c.theirs + ">>>>>>> \(c.theirsLabel)\n"
            }
        }
        .joined()
    }
}

extension GitRepository {
    /// Takes one side of a conflicted file wholesale and marks it resolved.
    func resolveWholeFile(_ path: String, ours: Bool) async throws {
        try await Git.run(["checkout", ours ? "--ours" : "--theirs", "--", path], in: url)
        try await Git.run(["add", "--", path], in: url)
    }

    func markResolved(_ path: String) async throws {
        try await Git.run(["add", "--", path], in: url)
    }

    func resolveByDeleting(_ path: String) async throws {
        try await Git.run(["rm", "-q", "--", path], in: url)
    }
}
