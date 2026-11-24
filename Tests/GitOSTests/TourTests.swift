import Testing
@testable import GitOS

@MainActor
struct TourTests {
    @Test func withoutARepositoryOnlyTheSidebarAndFinishShow() {
        #expect(Tour.steps(hasRepository: false) == [.sidebar, .finish])
        #expect(Tour.steps(hasRepository: true) == TourStep.allCases)
    }

    @Test func nextAndBackWalkTheStepsThenEnd() {
        let tour = Tour()
        tour.startNow(hasRepository: true)
        #expect(tour.step == .sidebar && tour.isFirst)
        tour.back()
        #expect(tour.step == .sidebar)
        tour.next()
        #expect(tour.step == .account && tour.position == 1)
        tour.back()
        #expect(tour.step == .sidebar)
        for _ in 1..<TourStep.allCases.count { tour.next() }
        #expect(tour.step == .finish && tour.isLast)
        tour.next()
        #expect(tour.step == nil && tour.steps.isEmpty)
    }

    @Test func stagingStopsOpenTheChangesTab() {
        for step in [TourStep.changes, .diff, .commit] { #expect(step.requiredTab == .changes) }
        #expect(TourStep.sidebar.requiredTab == nil)
    }

    @Test func everyStopLinksToARealGuidePage() {
        for step in TourStep.allCases { #expect(GuideTopic.topic(step.guideTopic) != nil, "\(step)") }
    }
}
