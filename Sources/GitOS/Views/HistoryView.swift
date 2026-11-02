import SwiftUI

struct HistoryView: View {
    @Bindable var model: RepoModel

    var body: some View {
        HSplitView {
            List(selection: $model.selectedCommitID) {
                ForEach(Array(model.commits.enumerated()), id: \.element.id) { index, commit in
                CommitRow(commit: commit, graph: index < model.graph.count ? model.graph[index] : nil)
                    .tag(commit.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 8))
                    .contextMenu {
                        Button("Copy SHA") { copy(commit.sha) }
                        if let web = model.primaryRemote?.webURL {
                            Button("View on GitHub") {
                                NSWorkspace.shared.open(web.appendingPathComponent("commit/\(commit.sha)"))
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Toggle("All branches", isOn: $model.showAllBranches)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Spacer()
                    Text("\(model.commits.count) commits").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.bar)
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
    let graph: GraphRow?

    var body: some View {
        HStack(spacing: 6) {
            if let graph {
                GraphCell(row: graph, isMerge: commit.parents.count > 1)
            }
            details
        }
        .frame(height: 44)
    }

    private var details: some View {
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
    }
}

/// Draws one row of the commit graph; lines reach the row edges so rows join up.
private struct GraphCell: View {
    let row: GraphRow
    let isMerge: Bool

    nonisolated static let laneWidth: CGFloat = 14
    nonisolated static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .yellow, .indigo, .mint]

    var body: some View {
        Canvas { context, size in
            func x(_ column: Int) -> CGFloat { CGFloat(column) * Self.laneWidth + Self.laneWidth / 2 }
            func y(_ end: GraphLine.End) -> CGFloat {
                switch end {
                case .top: 0
                case .middle: size.height / 2
                case .bottom: size.height
                }
            }
            for line in row.lines {
                var path = Path()
                let start = CGPoint(x: x(line.fromColumn), y: y(line.from))
                let end = CGPoint(x: x(line.toColumn), y: y(line.to))
                path.move(to: start)
                if start.x == end.x {
                    path.addLine(to: end)
                } else {
                    let midY = (start.y + end.y) / 2
                    path.addCurve(to: end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))
                }
                let colorColumn = line.from == .top ? line.fromColumn : line.toColumn
                context.stroke(path, with: .color(Self.color(colorColumn)), lineWidth: 2)
            }
            let center = CGPoint(x: x(row.column), y: size.height / 2)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
            if isMerge {
                context.fill(dot, with: .color(.white))
                context.stroke(dot, with: .color(Self.color(row.column)), lineWidth: 2)
            } else {
                context.fill(dot, with: .color(Self.color(row.column)))
            }
        }
        .frame(width: CGFloat(max(row.width, 1)) * Self.laneWidth)
        .frame(maxHeight: .infinity)
    }

    nonisolated static func color(_ column: Int) -> Color { palette[column % palette.count] }
}
