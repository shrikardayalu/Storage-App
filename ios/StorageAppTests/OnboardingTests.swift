import XCTest
@testable import StorageApp

/// The first-run funnel's order, answers and reveal numbers (Build Plan step 12).
final class OnboardingTests: XCTestCase {
    func testStepsRunInOrderAndEndOnThePaywall() {
        var step: OnboardingStep? = .hook
        var seen: [OnboardingStep] = []
        while let current = step {
            seen.append(current)
            step = current.next(showsPaywall: true)
        }
        XCTAssertEqual(seen, OnboardingStep.allCases)
    }

    func testPaywallIsSkippedWhenNotShown() {
        XCTAssertNil(OnboardingStep.reveal.next(showsPaywall: false))
        XCTAssertEqual(OnboardingStep.reveal.next(showsPaywall: true), .paywall)
        XCTAssertNil(OnboardingStep.paywall.next(showsPaywall: true))
    }

    func testBackNeverReturnsIntoTheScan() {
        XCTAssertNil(OnboardingStep.hook.previous)
        XCTAssertEqual(OnboardingStep.goal.previous, .pain)
        XCTAssertEqual(OnboardingStep.pain.previous, .hook)
        XCTAssertEqual(OnboardingStep.privacy.previous, .shrink)
        XCTAssertNil(OnboardingStep.scan.previous)
        XCTAssertNil(OnboardingStep.reveal.previous)
    }

    func testProgressRisesAndFinishesAtTheReveal() {
        let values = OnboardingStep.tracked.map(\.progress)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(OnboardingStep.reveal.progress, 1)
    }

    func testAnswersSurviveARelaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OnboardingTests"))
        defaults.removePersistentDomain(forName: "OnboardingTests")
        let answers = OnboardingAnswers(goal: .update)
        answers.save(to: defaults)
        XCTAssertEqual(OnboardingAnswers.load(from: defaults), answers)

        XCTAssertFalse(OnboardingAnswers.isCompleted(in: defaults))
        OnboardingAnswers.markCompleted(in: defaults)
        XCTAssertTrue(OnboardingAnswers.isCompleted(in: defaults))
    }

    func testRevealAddsFreeAndPro() {
        let numbers = RevealNumbers(freeBytes: 1_000_000_000, proBytes: 2_500_000_000)
        XCTAssertEqual(numbers.totalBytes, 3_500_000_000)
        XCTAssertFalse(numbers.isEmpty)
        XCTAssertTrue(RevealNumbers(freeBytes: 0, proBytes: 0).isEmpty)
    }

    func testMorePhotosIsRoundedDownSoItNeverOverpromises() {
        // 3.5 GB / 3.5 MB = 1,000 photos exactly.
        XCTAssertEqual(RevealNumbers(freeBytes: 0, proBytes: 3_500_000_000).morePhotos, 1_000)
        // 1,024 → nearest 50 below.
        XCTAssertEqual(RevealNumbers(freeBytes: 0, proBytes: 3_584_000_000).morePhotos, 1_000)
        // Small counts stay exact.
        XCTAssertEqual(RevealNumbers(freeBytes: 0, proBytes: 35_000_000).morePhotos, 10)
        XCTAssertEqual(RevealNumbers(freeBytes: 0, proBytes: 0).morePhotos, 0)
    }

    func testRunwayCountsPhotosAndFourKMinutesLeft() {
        // 4 GB free: 1,142 photos at 3.5 MB, rounded down to 1,100; 23 minutes at 170 MB.
        let runway = StorageRunway(availableBytes: 4_000_000_000)
        XCTAssertEqual(runway.photos, 1_100)
        XCTAssertEqual(runway.videoMinutes, 23)
    }

    func testRunwayNeverGoesNegative() {
        let runway = StorageRunway(availableBytes: -5)
        XCTAssertEqual(runway.photos, 0)
        XCTAssertEqual(runway.videoMinutes, 0)
    }
}
