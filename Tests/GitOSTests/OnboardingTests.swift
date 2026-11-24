import Foundation
import Testing
@testable import GitOS

struct OnboardingTests {
    @Test func newUsersSeeItOnce() {
        #expect(Onboarding.showsOnLaunch(done: false, hasRepos: false, hasAccounts: false))
        #expect(!Onboarding.showsOnLaunch(done: true, hasRepos: false, hasAccounts: false))
    }

    @Test func existingUsersDoNotSeeItOnLaunch() {
        #expect(!Onboarding.showsOnLaunch(done: false, hasRepos: true, hasAccounts: false))
        #expect(!Onboarding.showsOnLaunch(done: false, hasRepos: false, hasAccounts: true))
    }

    @MainActor @Test func finishingRemembersIt() throws {
        let suite = "gitos-onboarding-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding()
        onboarding.isPresented = true
        onboarding.finish(defaults: defaults)
        #expect(!onboarding.isPresented)
        #expect(defaults.bool(forKey: Onboarding.doneKey))
    }
}
