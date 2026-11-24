import Testing
@testable import GitOS

struct UpdateStatusTests {
    func describe(_ phase: AppUpdater.Phase, received: UInt64 = 0, expected: UInt64 = 0,
                  extraction: Double? = nil) -> UpdateStatus {
        UpdateStatus.describe(phase, version: "1.2.3", currentVersion: "1.2.2",
                              received: received, expected: expected, extraction: extraction)
    }

    @Test func everyStepHasItsOwnTitle() {
        let phases: [AppUpdater.Phase] = [.idle, .checking, .downloading(fraction: nil), .preparing, .ready,
                                          .installing, .upToDate, .failed("Offline")]
        let titles = phases.map { describe($0).title }
        #expect(Set(titles).count == phases.count)
    }

    @Test func downloadShowsBytesAndFraction() {
        let status = describe(.downloading(fraction: 0.5), received: 5_000_000, expected: 10_000_000)
        #expect(status.progress == .fraction(0.5))
        #expect(status.detail.contains(" of "))
        #expect(status.title.contains("1.2.3"))
    }

    @Test func downloadWithoutSizeIsIndeterminate() {
        #expect(describe(.downloading(fraction: nil)).progress == .indeterminate)
    }

    @Test func extractionUsesSparkleProgress() {
        #expect(describe(.preparing, extraction: 0.25).progress == .fraction(0.25))
        #expect(describe(.preparing).progress == .indeterminate)
    }

    @Test func upToDateNamesTheRunningVersion() {
        #expect(describe(.upToDate).detail.contains("1.2.2"))
        #expect(describe(.upToDate).progress == .none)
    }

    @Test func failureShowsTheMessage() {
        #expect(describe(.failed("The network connection was lost.")).detail == "The network connection was lost.")
    }
}
