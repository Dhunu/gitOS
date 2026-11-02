import SwiftUI

struct HistoryView: View {
    @Bindable var model: RepoModel

    var body: some View {
        HSplitView {
            List(model.commits, selection: $model.selectedCommitID) { commit in
                CommitRow(commit: commit)
                    .tag(commit.id)
                    .contextMenu {
                        Button("Copy SHA") { copy(commit.sha) }
                        if let web = model.primaryRemote?.webURL {
                            Button("View on GitHub") {
                                NSWorkspace.shared.open(web.appendingPathComponent("commit/\(commit.sha)"))
                            }
                        }
                    }
            }
            .overlay {
                if model.commits.isEmpty {
                    ContentUnavailableView("No Commits Yet", systemImage: "clock")
                }
            }
            .frame(minWidth: 280, idealWidth: 360, maxWidth: 560)

            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let commit = model.commits.first(where: { $0.id == model.selectedCommitID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(commit.subject).font(.title3.weight(.semibold)).textSelection(.enabled)
                        HStack(spacing: 12) {
                            Label("\(commit.authorName) <\(commit.authorEmail)>", systemImage: "person")
                            Label(commit.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            Button(commit.shortSHA) { copy(commit.sha) }
                                .buttonStyle(.borderless)
                                .font(.callout.monospaced())
                                .help("Copy full SHA")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        Text("\(model.commitDiffs.count) changed file\(model.commitDiffs.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)

                    ForEach(model.commitDiffs) { diff in
                        Divider()
                        HStack {
                            Text(diff.path).font(.headline)
                            if let old = diff.oldPath { Text("← \(old)").foregroundStyle(.secondary) }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.bar)
                        DiffContentView(diff: diff)
                    }
                }
            }
        } else {
            ContentUnavailableView("Select a Commit", systemImage: "clock.arrow.circlepath")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct CommitRow: View {
    let commit: Commit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                ForEach(commit.refs.prefix(3), id: \.self) { ref in
                    Text(ref.replacingOccurrences(of: "HEAD -> ", with: ""))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ref.hasPrefix("tag:") ? Color.yellow.opacity(0.3) : Color.accentColor.opacity(0.2),
                                    in: Capsule())
                        .lineLimit(1)
                }
                Text(commit.subject).lineLimit(1)
            }
            HStack {
                Text(commit.authorName)
                Text("·")
                Text(commit.date, format: .relative(presentation: .named))
                Spacer()
                Text(commit.shortSHA).monospaced()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
