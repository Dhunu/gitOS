import Foundation
import Testing
@testable import GitOS

struct AppStateTests {
    @Test func emptySavedClientIDUsesBuiltIn() {
        #expect(!AppState.builtInGitHubClientID.isEmpty)
        #expect(AppState.clientID(saved: "") == AppState.builtInGitHubClientID)
        #expect(AppState.clientID(saved: "  ") == AppState.builtInGitHubClientID)
    }

    @Test func gitHubRefusingTheTokenCountsAsARejectedSignIn() {
        let refused = """
        remote: Invalid username or token. Password authentication is not supported for Git operations.
        fatal: Authentication failed for 'https://github.com/twikappai-droid/twik-website.git/'
        """
        #expect(GitFailure(command: "pull", message: refused, exitCode: 128).isRejectedCredential)
        #expect(!GitFailure(command: "pull", message: "fatal: repository not found", exitCode: 128).isRejectedCredential)
        #expect(!GitFailure(command: "pull", message: "Could not resolve host: github.com", exitCode: 128).isRejectedCredential)
    }

    @Test func expiringTokenResponseKeepsTheRefreshTokenAndExpiry() throws {
        let json = #"{"access_token":"gho_a","expires_in":28800,"refresh_token":"ghr_b","refresh_token_expires_in":15897600,"scope":"repo","token_type":"bearer"}"#
        let response = try JSONDecoder().decode(GitHubDeviceFlow.TokenResponse.self, from: Data(json.utf8))
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(response.grant(now: now) == .init(accessToken: "gho_a", refreshToken: "ghr_b",
                                                  expiresAt: now.addingTimeInterval(28_800)))
    }

    @Test func nonExpiringTokenResponseHasNoExpiry() throws {
        let json = #"{"access_token":"gho_a","scope":"repo","token_type":"bearer"}"#
        let grant = try JSONDecoder().decode(GitHubDeviceFlow.TokenResponse.self, from: Data(json.utf8)).grant()
        #expect(grant?.refreshToken == nil)
        #expect(grant?.expiresAt == nil)
    }

    @Test func refusedRefreshHasNoGrant() throws {
        let json = #"{"error":"bad_refresh_token","error_description":"The refresh token passed is incorrect or expired."}"#
        #expect(try JSONDecoder().decode(GitHubDeviceFlow.TokenResponse.self, from: Data(json.utf8)).grant() == nil)
    }

    @Test func tokensRenewBeforeTheyExpireAndNonExpiringOnesNever() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(!TokenRefresher.isDue(expiresAt: nil, now: now))
        #expect(!TokenRefresher.isDue(expiresAt: now.addingTimeInterval(3_600), now: now))
        #expect(TokenRefresher.isDue(expiresAt: now.addingTimeInterval(600), now: now))
        #expect(TokenRefresher.isDue(expiresAt: now.addingTimeInterval(-600), now: now))
    }

    @Test func accountsSavedBeforeExpiryTrackingStillLoad() throws {
        let saved = try JSONEncoder().encode(Account(githubID: 1, login: "a", displayName: "a", commitName: "a", commitEmail: ""))
        var fields = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        fields.removeValue(forKey: "tokenExpiresAt")
        let account = try JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(account.tokenExpiresAt == nil)
    }

    @Test func rejectedAPICallsCountAsARejectedSignIn() {
        #expect(AppState.isRejectedSignIn(GitHubError(message: "Bad credentials", statusCode: 401)))
        #expect(!AppState.isRejectedSignIn(GitHubError(message: "Forbidden", statusCode: 403)))
        #expect(!AppState.isRejectedSignIn(GitHubError(message: "No status")))
    }

    @Test func wrongAccountFailuresSuggestSwitching() {
        let missing = GitFailure(command: "fetch", message: "remote: Repository not found.\nfatal: repository 'https://github.com/a/b.git/' not found", exitCode: 128)
        #expect(missing.accountHint(login: "Dhunu", owner: "Dhunu")?.contains("can't find this repository for @Dhunu") == true)
        #expect(missing.accountHint(login: "dhunu", owner: "Dhunu")?.contains("organization") == false)
        let denied = GitFailure(command: "push", message: "remote: Permission to a/b.git denied to Dhunu.\nfatal: unable to access 'https://github.com/a/b.git/': The requested URL returned error: 403", exitCode: 128)
        #expect(denied.accountHint(login: "Dhunu", owner: nil)?.contains("won't let @Dhunu") == true)
        let offline = GitFailure(command: "fetch", message: "fatal: unable to access: Could not resolve host: github.com", exitCode: 128)
        #expect(offline.accountHint(login: "Dhunu", owner: nil) == nil)
        #expect(!offline.isAccessDenied)
    }

    @Test func orgReposMentionApprovingGitOS() {
        let missing = GitFailure(command: "fetch", message: "remote: Repository not found.", exitCode: 128)
        let hint = missing.accountHint(login: "AngelSaikia", owner: "Bridgeness-Technologies")
        #expect(hint?.contains("“Bridgeness-Technologies” organization may need to approve GitOS") == true)
    }

    @Test func tokenLinkTicksTheScopesGitOSNeeds() {
        let url = GitHubDeviceFlow.classicTokenURL.absoluteString
        #expect(url.hasPrefix("https://github.com/settings/tokens/new?"))
        #expect(url.contains("scopes=repo,read:org,workflow,user:email"))
    }

    @Test func pagedListStopsAtAShortPage() async throws {
        let list = try await PagedList<Int>.load { page in
            page == 1 ? Array(repeating: 0, count: 100) : [1, 2]
        }
        #expect(list.items.count == 102)
        #expect(list.isComplete)
    }

    @Test func pagedListAdmitsWhenItHitsTheCap() async throws {
        let list = try await PagedList<Int>.load { _ in Array(repeating: 0, count: 100) }
        #expect(list.items.count == PagedList<Int>.maxItems)
        #expect(!list.isComplete)
    }

    @Test func savedClientIDWins() {
        #expect(AppState.clientID(saved: "Ov23custom") == "Ov23custom")
    }
}
