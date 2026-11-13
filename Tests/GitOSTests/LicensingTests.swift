import Foundation
import Testing
@testable import GitOS

struct LicensingTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let day: TimeInterval = 86_400

    func license(status: String = "granted", expires: Date? = nil, validatedDaysAgo: Double = 0) -> StoredLicense {
        StoredLicense(key: "K", activationID: "A", status: status, expiresAt: expires,
                      validatedAt: now.addingTimeInterval(-validatedDaysAgo * day))
    }

    @Test func trialGivesProUntilItEnds() {
        #expect(Licensing.entitled(license: nil, trialEndsAt: now.addingTimeInterval(day), now: now))
        #expect(!Licensing.entitled(license: nil, trialEndsAt: now.addingTimeInterval(-1), now: now))
    }

    @Test func grantedLicenseGivesProAfterTheTrial() {
        let ended = now.addingTimeInterval(-day)
        #expect(Licensing.entitled(license: license(), trialEndsAt: ended, now: now))
        #expect(!Licensing.entitled(license: license(status: "revoked"), trialEndsAt: ended, now: now))
        #expect(!Licensing.entitled(license: license(status: "disabled"), trialEndsAt: ended, now: now))
    }

    @Test func expiredSubscriptionEndsPro() {
        let ended = now.addingTimeInterval(-day)
        #expect(!Licensing.entitled(license: license(expires: now.addingTimeInterval(-1)), trialEndsAt: ended, now: now))
        #expect(Licensing.entitled(license: license(expires: now.addingTimeInterval(day)), trialEndsAt: ended, now: now))
    }

    @Test func offlineLicenseLastsThirtyDaysFromTheLastCheck() {
        #expect(Licensing.licenseIsGood(license(validatedDaysAgo: 29), now: now))
        #expect(!Licensing.licenseIsGood(license(validatedDaysAgo: 31), now: now))
    }
}
