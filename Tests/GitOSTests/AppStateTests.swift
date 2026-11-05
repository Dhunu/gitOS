import Testing
@testable import GitOS

struct AppStateTests {
    @Test func emptySavedClientIDUsesBuiltIn() {
        #expect(!AppState.builtInGitHubClientID.isEmpty)
        #expect(AppState.clientID(saved: "") == AppState.builtInGitHubClientID)
        #expect(AppState.clientID(saved: "  ") == AppState.builtInGitHubClientID)
    }

    @Test func savedClientIDWins() {
        #expect(AppState.clientID(saved: "Ov23custom") == "Ov23custom")
    }
}
