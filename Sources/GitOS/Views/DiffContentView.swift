import SwiftUI

struct HunkActionButton {
    let title: String
    let icon: String
    var destructive = false
    let action: (DiffHunk) -> Void
}

/// Renders one file's hunks. Has no scroll view of its own so callers can stack several files.
struct DiffContentView: View {
    let diff: FileDiff
    var hunkActions: [HunkActionButton] = []

    private static let maxLines = 4000

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if diff.isBinary {
                note("Binary file")
            } else if diff.hunks.isEmpty {
                note(diff.headerLines.contains { $0.hasPrefix("old mode") } ? "File mode changed" : "No content changes")
            } else if diff.hunks.reduce(0, { $0 + $1.lines.count }) > Self.maxLines {
                note("This diff is too large to display (\(diff.hunks.reduce(0) { $0 + $1.lines.count }) lines).")
            } else {
                ForEach(diff.hunks) { hunk in
                    hunkHeader(hunk)
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        DiffLineRow(line: line)
                    }
                }
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            ForEach(hunkActions, id: \.title) { button in
                Button(button.title, systemImage: button.icon) { button.action(hunk) }
                    .buttonStyle(.borderless)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(button.destructive ? .red : .accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.blue.opacity(0.08))
        .padding(.top, hunk.id == 0 ? 0 : 6)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
            Text(marker)
                .frame(width: 22)
            Text(line.kind == .noNewline ? line.text : line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .noNewline ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 1)
        .background(background)
    }

    private var marker: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "−"
        default: ""
        }
    }

    private var background: Color {
        switch line.kind {
        case .addition: .green.opacity(0.14)
        case .deletion: .red.opacity(0.14)
        default: .clear
        }
    }
}
