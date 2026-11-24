import AVKit
import CryptoKit
import SwiftUI

/// Files GitOS can show as themselves rather than as a text diff.
enum PreviewKind: Equatable {
    case image, video, json

    static func detect(path: String) -> PreviewKind? {
        switch (path as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "ico", "icns", "svg":
            .image
        case "mp4", "mov", "m4v", "avi", "3gp":
            .video
        case "json", "geojson", "webmanifest", "jsonc", "har":
            .json
        default:
            nil
        }
    }

    /// Images and videos are binary, so their text diff says nothing; JSON keeps the diff by default.
    var prefersPreview: Bool { self != .json }

    var label: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .json: "Formatted"
        }
    }
}

/// Loads a file's versions, then shows them as images, videos or formatted JSON.
struct FilePreviewLoader: View {
    let path: String
    let kind: PreviewKind
    /// Identifies what's being loaded, so a new selection reloads.
    let id: String
    let load: () async -> FileVersions?

    @State private var versions: FileVersions?
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if let versions, versions.before != nil || versions.after != nil {
                FilePreviewView(path: path, kind: kind, versions: versions)
            } else {
                ContentUnavailableView("No Preview", systemImage: "eye.slash",
                                       description: Text("GitOS couldn't read this file's contents."))
            }
        }
        .task(id: id) {
            loading = true
            versions = await load()
            loading = false
        }
    }
}

struct FilePreviewView: View {
    let path: String
    let kind: PreviewKind
    let versions: FileVersions

    var body: some View {
        switch kind {
        case .image: SideBySide(versions: versions) { data in ImagePreview(data: data, path: path) }
        case .video: SideBySide(versions: versions) { data in VideoPreview(data: data, path: path) }
        case .json: JSONPreview(versions: versions)
        }
    }
}

/// Before and after next to each other, or just the one that exists.
private struct SideBySide<Content: View>: View {
    let versions: FileVersions
    @ViewBuilder let content: (Data) -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let before = versions.before {
                side(versions.after == nil ? "Deleted" : "Before", tint: Theme.removed, data: before)
            }
            if let after = versions.after {
                side(versions.before == nil ? "Added" : "After", tint: Theme.added, data: after)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func side(_ title: String, tint: Color, data: Data) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Pill(text: title, tint: tint)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
            }
            content(data)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImagePreview: View {
    let data: Data
    let path: String

    var body: some View {
        if let image = NSImage(data: data) {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: max(image.size.width, 1), maxHeight: 520)
                    .background(Checkerboard())
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
                    .accessibilityLabel("Preview of \((path as NSString).lastPathComponent)")
                if let pixels = image.representations.first.map({ ($0.pixelsWide, $0.pixelsHigh) }), pixels.0 > 0 {
                    Text("\(pixels.0) × \(pixels.1) px").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("This image format can't be shown.").foregroundStyle(.secondary)
        }
    }
}

/// Transparent pixels show as the familiar grey checkerboard.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(.gray.opacity(0.18)))
                }
            }
        }
    }
}

private struct VideoPreview: View {
    let data: Data
    let path: String
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxHeight: 520)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: data.count) { player = AVPlayer(url: VideoPreview.file(for: data, path: path)) }
            .onDisappear { player?.pause() }
    }

    /// AVPlayer needs a file, so each version is written once to a temporary file named by its hash.
    static func file(for data: Data, path: String) -> URL {
        let hash = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
        let ext = (path as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitos-preview-\(hash)").appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url, options: .atomic) }
        return url
    }
}

private struct JSONPreview: View {
    let versions: FileVersions
    @State private var showBefore = false

    private var data: Data? { showBefore ? versions.before : (versions.after ?? versions.before) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if versions.before != nil && versions.after != nil {
                Picker("Version", selection: $showBefore) {
                    Text("After").tag(false)
                    Text("Before").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            if let data {
                let text = String(decoding: data, as: UTF8.self)
                if JSONFormatter.isValid(data) {
                    Text(JSONFormatter.highlighted(text))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label("Not valid JSON, so it's shown as written.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Theme.modified)
                    Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .padding(16)
    }
}

/// Re-indents JSON without reordering keys, and colours it by token.
enum JSONFormatter {
    enum TokenKind: Equatable { case key, string, number, literal, punctuation, whitespace }

    static func isValid(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed, .json5Allowed])) != nil
    }

    /// Pretty-printed tokens with two-space indentation. Expects valid JSON; comments are dropped.
    static func tokens(_ text: String) -> [(String, TokenKind)] {
        var out: [(String, TokenKind)] = []
        var depth = 0
        let chars = Array(text)
        var i = 0
        func newline() { out.append(("\n" + String(repeating: "  ", count: depth), .whitespace)) }

        while i < chars.count {
            let c = chars[i]
            switch c {
            case "{", "[":
                // Empty containers stay on one line.
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == (c == "{" ? "}" : "]") {
                    out.append((String(c) + String(chars[j]), .punctuation))
                    i = j + 1
                    continue
                }
                out.append((String(c), .punctuation))
                depth += 1
                newline()
            case "}", "]":
                depth = max(depth - 1, 0)
                newline()
                out.append((String(c), .punctuation))
            case ",":
                out.append((",", .punctuation))
                newline()
            case ":":
                out.append((": ", .punctuation))
            case "\"":
                var j = i + 1
                while j < chars.count, chars[j] != "\"" {
                    j += chars[j] == "\\" ? 2 : 1
                }
                let string = String(chars[i...min(j, chars.count - 1)])
                // A string followed by a colon is a key.
                var k = j + 1
                while k < chars.count, chars[k].isWhitespace { k += 1 }
                out.append((string, k < chars.count && chars[k] == ":" ? .key : .string))
                i = j + 1
                continue
            case "/" where i + 1 < chars.count && (chars[i + 1] == "/" || chars[i + 1] == "*"):
                // JSONC comments: skip them.
                let block = chars[i + 1] == "*"
                i += 2
                while i < chars.count, block ? !(chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/") : chars[i] != "\n" {
                    i += 1
                }
                i += block ? 2 : 0
                continue
            default:
                if c.isWhitespace { break }
                var j = i
                while j < chars.count, !",:{}[]\"".contains(chars[j]), !chars[j].isWhitespace { j += 1 }
                let word = String(chars[i..<j])
                out.append((word, ["true", "false", "null"].contains(word) ? .literal : .number))
                i = j
                continue
            }
            i += 1
        }
        return out
    }

    static func pretty(_ text: String) -> String {
        tokens(text).map(\.0).joined()
    }

    static func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (piece, kind) in tokens(text) {
            var part = AttributedString(piece)
            switch kind {
            case .key: part.foregroundColor = Theme.accent
            case .string: part.foregroundColor = Theme.added
            case .number: part.foregroundColor = Theme.modified
            case .literal: part.foregroundColor = Theme.conflict
            case .punctuation: part.foregroundColor = .secondary
            case .whitespace: break
            }
            result += part
        }
        return result
    }
}
