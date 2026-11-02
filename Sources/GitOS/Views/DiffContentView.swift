import SwiftUI

struct HunkActionButton {
    let title: String
    let icon: String
    var destructive = false
    /// Called with the hunk and the selected line indexes in it (empty means the whole hunk).
    let action: (DiffHunk, Set<Int>) -> Void
}

struct DiffLineID: Hashable {
    var hunk: Int
    var line: Int
}

/// Renders one file's hunks. Has no scroll view of its own so callers can stack several files.
/// When `hunkActions` is non-empty, clicking a changed line's gutter selects it for line-level actions.
struct DiffContentView: View {
    let diff: FileDiff
    var hunkActions: [HunkActionButton] = []
    var selection: Binding<Set<DiffLineID>>?

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
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { index, line in
                        let id = DiffLineID(hunk: hunk.id, line: index)
                        DiffLineRow(
                            line: line,
                            isSelected: selection?.wrappedValue.contains(id) ?? false,
                            onGutterTap: isSelectable(line) ? { toggle(id, in: hunk) } : nil
                        )
                    }
                }
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
    }

    private func isSelectable(_ line: DiffLine) -> Bool {
        selection != nil && !hunkActions.isEmpty && (line.kind == .addition || line.kind == .deletion)
    }

    private func toggle(_ id: DiffLineID, in hunk: DiffHunk) {
        guard let selection else { return }
        if NSEvent.modifierFlags.contains(.shift),
           let anchor = selection.wrappedValue.filter({ $0.hunk == hunk.id }).map(\.line).max() {
            // Shift-click selects every changed line between the last selection and this one.
            let range = min(anchor, id.line)...max(anchor, id.line)
            for index in range where hunk.lines[index].kind == .addition || hunk.lines[index].kind == .deletion {
                selection.wrappedValue.insert(DiffLineID(hunk: hunk.id, line: index))
            }
        } else if selection.wrappedValue.contains(id) {
            selection.wrappedValue.remove(id)
        } else {
            selection.wrappedValue.insert(id)
        }
    }

    private func selectedLines(in hunk: DiffHunk) -> Set<Int> {
        Set((selection?.wrappedValue ?? []).filter { $0.hunk == hunk.id }.map(\.line))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        let selected = selectedLines(in: hunk)
        return HStack(spacing: 8) {
            Text(hunk.header)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !selected.isEmpty {
                Button("Clear") { selection?.wrappedValue.subtract(selected.map { DiffLineID(hunk: hunk.id, line: $0) }) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            ForEach(hunkActions, id: \.title) { button in
                let title = selected.isEmpty
                    ? "\(button.title) Hunk"
                    : "\(button.title) \(selected.count) Line\(selected.count == 1 ? "" : "s")"
                Button(title, systemImage: button.icon) {
                    button.action(hunk, selected)
                    selection?.wrappedValue = []
                }
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
    let isSelected: Bool
    let onGutterTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 0) {
                Text(line.oldLine.map(String.init) ?? "")
                    .frame(width: 44, alignment: .trailing)
                Text(line.newLine.map(String.init) ?? "")
                    .frame(width: 44, alignment: .trailing)
            }
            .background(isSelected ? Color.accentColor.opacity(0.35) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { onGutterTap?() }
            .help(onGutterTap == nil ? "" : "Click to select this line, Shift-click for a range")
            Text(marker)
                .frame(width: 22)
            Text(line.kind == .noNewline ? line.text : line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .noNewline ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 1)
        .background(background)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(Color.accentColor).frame(width: 3) }
        }
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
        case .addition: .green.opacity(isSelected ? 0.28 : 0.14)
        case .deletion: .red.opacity(isSelected ? 0.28 : 0.14)
        default: .clear
        }
    }
}
