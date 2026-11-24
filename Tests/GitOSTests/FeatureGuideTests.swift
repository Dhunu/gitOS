import Testing
@testable import GitOS

struct FeatureGuideTests {
    @Test func topicIDsAreUniqueAndFilledIn() {
        let ids = GuideTopic.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for topic in GuideTopic.all {
            #expect(!topic.summary.isEmpty)
            #expect(!topic.steps.isEmpty)
        }
    }

    @Test func everyRepoTabIsExplained() {
        let ids: [RepoView.Tab: String] = [.changes: "changes", .history: "history", .pulls: "pulls",
                                           .issues: "issues", .stashes: "stashes", .worktrees: "worktrees"]
        for tab in RepoView.Tab.allCases {
            let topic = ids[tab].flatMap(GuideTopic.topic)
            #expect(topic != nil, "No guide topic for \(tab.rawValue)")
            #expect(topic?.isPro == tab.isPro, "\(tab.rawValue) Pro badge doesn't match the app")
        }
    }
}
