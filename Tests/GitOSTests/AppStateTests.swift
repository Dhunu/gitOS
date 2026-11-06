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

    @Test func savedClientIDWins() {
        #expect(AppState.clientID(saved: "Ov23custom") == "Ov23custom")
    }
}
