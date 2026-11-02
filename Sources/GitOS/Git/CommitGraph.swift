import Foundation

/// One segment of the graph drawn inside a single history row.
struct GraphLine: Hashable, Sendable {
    enum End: Sendable { case top, middle, bottom }
    var fromColumn: Int
    var from: End
    var toColumn: Int
    var to: End
}

struct GraphRow: Hashable, Sendable {
    var column: Int
    var lines: [GraphLine]
    /// Number of lanes that need to be visible in this row.
    var width: Int
}

/// Assigns commits to lanes for a topo-ordered log (children before parents).
enum CommitGraph {
    static func layout(_ commits: [Commit]) -> [GraphRow] {
        var lanes: [String?] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            let before = lanes
            let column: Int
            if let existing = lanes.firstIndex(of: commit.sha) {
                column = existing
            } else if let free = lanes.firstIndex(of: nil) {
                column = free
            } else {
                column = lanes.count
                lanes.append(nil)
            }

            var lines: [GraphLine] = []
            // Lanes arriving from above: ones waiting for this commit converge on it.
            for (lane, sha) in before.enumerated() where sha != nil {
                if sha == commit.sha {
                    lines.append(GraphLine(fromColumn: lane, from: .top, toColumn: column, to: .middle))
                    lanes[lane] = nil
                } else {
                    lines.append(GraphLine(fromColumn: lane, from: .top, toColumn: lane, to: .middle))
                }
            }

            for (index, parent) in commit.parents.enumerated() {
                if index == 0, let other = lanes.firstIndex(of: parent), other > column {
                    // Keep the first-parent line in this lane; pull the other lane into it.
                    lanes[other] = nil
                    lanes[column] = parent
                    lines.append(GraphLine(fromColumn: column, from: .middle, toColumn: column, to: .bottom))
                    lines.append(GraphLine(fromColumn: other, from: .middle, toColumn: column, to: .bottom))
                } else if let target = lanes.firstIndex(of: parent) {
                    lines.append(GraphLine(fromColumn: column, from: .middle, toColumn: target, to: .bottom))
                } else {
                    let target: Int
                    if index == 0 {
                        target = column
                    } else if let free = lanes.indices.first(where: { lanes[$0] == nil && $0 != column }) {
                        target = free
                    } else {
                        target = lanes.count
                        lanes.append(nil)
                    }
                    lanes[target] = parent
                    lines.append(GraphLine(fromColumn: column, from: .middle, toColumn: target, to: .bottom))
                }
            }

            // Lanes that pass straight through this row.
            for (lane, sha) in before.enumerated() where sha != nil && sha != commit.sha && lanes[lane] == sha {
                lines.append(GraphLine(fromColumn: lane, from: .middle, toColumn: lane, to: .bottom))
            }

            while lanes.last == .some(nil) { lanes.removeLast() }
            let width = max(before.count, lanes.count, column + 1)
            rows.append(GraphRow(column: column, lines: lines, width: width))
        }
        return rows
    }
}
