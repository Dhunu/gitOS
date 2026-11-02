import Foundation
import Testing
@testable import GitOS

struct CommitGraphTests {
    private func commit(_ sha: String, _ parents: String...) -> Commit {
        Commit(sha: sha, parents: parents, authorName: "", authorEmail: "", date: .now, refs: [], subject: sha)
    }

    @Test func linearHistoryStaysInOneLane() {
        let rows = CommitGraph.layout([commit("c", "b"), commit("b", "a"), commit("a")])
        #expect(rows.map(\.column) == [0, 0, 0])
        #expect(rows.allSatisfy { $0.width == 1 })
    }

    @Test func mergeOpensAndClosesSecondLane() {
        // m merges feature (f) into main (b); both branch from a.
        let rows = CommitGraph.layout([
            commit("m", "b", "f"),
            commit("f", "a"),
            commit("b", "a"),
            commit("a"),
        ])
        #expect(rows.map(\.column) == [0, 1, 0, 0])
        #expect(rows[0].lines.contains(GraphLine(fromColumn: 0, from: .middle, toColumn: 1, to: .bottom)))
        // b's lane passes through f's row.
        #expect(rows[1].lines.contains(GraphLine(fromColumn: 0, from: .top, toColumn: 0, to: .middle)))
        #expect(rows[1].lines.contains(GraphLine(fromColumn: 0, from: .middle, toColumn: 0, to: .bottom)))
        // f's lane already waits for a, b's first parent: it folds back into lane 0 at b.
        #expect(rows[2].lines.contains(GraphLine(fromColumn: 1, from: .middle, toColumn: 0, to: .bottom)))
        #expect(rows[2].width == 2)
        #expect(rows[3].width == 1)
    }

    @Test func separateTipsGetSeparateLanes() {
        let rows = CommitGraph.layout([commit("x", "a"), commit("y", "a"), commit("a")])
        #expect(rows.map(\.column) == [0, 1, 0])
    }
}
