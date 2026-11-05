import StorageCore
import XCTest
@testable import StorageApp

/// The first-run funnel, the picks it keeps, the suggestions it shows, and
/// the order Home's plan walks through them.
final class OnboardingTests: XCTestCase {
    func testTwoScreensThenTheScanThenThePicksAndNoPaywall() {
        var step: OnboardingStep? = .hook
        var seen: [OnboardingStep] = []
        while let current = step {
            seen.append(current)
            step = current.next
        }
        XCTAssertEqual(seen, [.hook, .pain, .scan, .picks])
    }

    func testBackNeverReturnsIntoTheScan() {
        XCTAssertNil(OnboardingStep.hook.previous)
        XCTAssertEqual(OnboardingStep.pain.previous, .hook)
        XCTAssertNil(OnboardingStep.scan.previous)
        XCTAssertNil(OnboardingStep.picks.previous)
    }

    func testProgressRisesAndFinishesAtThePicks() {
        let values = OnboardingStep.tracked.map(\.progress)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(OnboardingStep.picks.progress, 1)
    }

    func testPicksSurviveARelaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OnboardingTests"))
        defaults.removePersistentDomain(forName: "OnboardingTests")
        let answers = OnboardingAnswers(picks: [.shrinkVideos, .swipe])
        answers.save(to: defaults)
        XCTAssertEqual(OnboardingAnswers.load(from: defaults), answers)

        XCTAssertFalse(OnboardingAnswers.isCompleted(in: defaults))
        OnboardingAnswers.markCompleted(in: defaults)
        XCTAssertTrue(OnboardingAnswers.isCompleted(in: defaults))
    }

    // MARK: Free and Pro

    func testFreeDoesItByHandAndProDoesTheHeavyHitters() {
        XCTAssertEqual(CleanupMethod.allCases.filter(\.isPro), [.shrinkVideos, .photoCleanup, .duplicates, .livePhotos])
        XCTAssertEqual(CleanupMethod.allCases.filter { !$0.isPro }, [.swipe, .bursts, .chatAttachments])
    }

    func testSuggestionsRankBiggestFirstAndDropNothingToDo() {
        let ranked = Suggestion.ranked([
            Suggestion(method: .shrinkVideos, bytes: 100),
            Suggestion(method: .photoCleanup, bytes: nil),
            Suggestion(method: .swipe, bytes: 900),
            Suggestion(method: .bursts, bytes: 0),
            Suggestion(method: .chatAttachments, bytes: nil),
        ])
        // Bursts free nothing; Photo Cleanup wasn't measured and isn't a guide.
        XCTAssertEqual(ranked.map(\.method), [.swipe, .shrinkVideos, .chatAttachments])
    }

    func testTotalsCountTheSamePhotosOnce() {
        // Swipe reviews the same photos Photo Cleanup removes.
        let both = [Suggestion(method: .photoCleanup, bytes: 1_000), Suggestion(method: .swipe, bytes: 600)]
        XCTAssertEqual(both.totalBytes, 1_000)
        let alone = [Suggestion(method: .swipe, bytes: 600), Suggestion(method: .bursts, bytes: 50)]
        XCTAssertEqual(alone.totalBytes, 650)
    }

    // MARK: The plan's order

    private let album: Int64 = 10_000_000_000  // 10 GB: a free fix needs 100 MB to lead.

    private func order(_ picks: [CleanupMethod], _ savings: [CleanupMethod: Int64]) -> [CleanupMethod] {
        PlanOrder.build(picks: picks, saving: { savings[$0] }, albumBytes: album)
    }

    func testTheBiggestFreeFixLeadsAndProWaitsBehindIt() {
        let plan = order([.shrinkVideos, .bursts, .swipe], [.shrinkVideos: 3_000_000_000, .bursts: 200_000_000, .swipe: 900_000_000])
        XCTAssertEqual(plan, [.swipe, .bursts, .shrinkVideos])
    }

    func testATinyFreeFixNeverLeads() {
        // One burst worth 40 KB: the swipe feed leads instead, and the burst goes last.
        let plan = order([.shrinkVideos, .bursts], [.shrinkVideos: 3_000_000_000, .bursts: 40_000, .swipe: 500_000_000])
        XCTAssertEqual(plan, [.swipe, .shrinkVideos, .bursts])
    }

    func testOnlyProPicksStillStartWithSomethingFree() {
        let plan = order([.shrinkVideos, .photoCleanup], [.shrinkVideos: 3_000_000_000, .photoCleanup: 1_000_000_000, .swipe: 400_000_000])
        XCTAssertEqual(plan, [.swipe, .shrinkVideos, .photoCleanup])
    }

    func testNothingToSwipeMeansNoSwipeLead() {
        let plan = order([.shrinkVideos], [.shrinkVideos: 3_000_000_000, .swipe: 0])
        XCTAssertEqual(plan, [.shrinkVideos])
    }

    func testGuidesComeAfterTheMeasuredFreeFixes() {
        let plan = order([.chatAttachments, .bursts, .shrinkVideos], [.bursts: 300_000_000, .shrinkVideos: 1])
        XCTAssertEqual(plan, [.bursts, .chatAttachments, .shrinkVideos])
    }

    func testTheLeadLineIsOnePercentCappedAt250MB() {
        XCTAssertEqual(PlanOrder.threshold(albumBytes: 1_000_000_000), 10_000_000)
        XCTAssertEqual(PlanOrder.threshold(albumBytes: 100_000_000_000), 250_000_000)
        XCTAssertEqual(PlanOrder.threshold(albumBytes: 0), 1)
    }

    // MARK: Scan numbers

    func testBloatIsTheBiggestKindOfThing() throws {
        let scan = LibraryScan(items: [
            MediaItem(id: "v", category: .video, format: .hevc, filename: "v.MOV", creationDate: Date(),
                      pixelWidth: 1920, pixelHeight: 1080, duration: 60, originalBytes: 600, thumbnailSeed: 0),
            MediaItem(id: "p", category: .photo, format: .heic, filename: "p.HEIC", creationDate: Date(),
                      pixelWidth: 4032, pixelHeight: 3024, duration: nil, originalBytes: 400, thumbnailSeed: 0),
        ])
        let bloat = try XCTUnwrap(Bloat(scan: scan))
        XCTAssertEqual(bloat.group, .videos)
        XCTAssertEqual(bloat.percent, 60)
        XCTAssertNil(Bloat(scan: LibraryScan(items: [])))
    }

    func testMorePhotosIsRoundedDownSoItNeverOverpromises() {
        XCTAssertEqual(morePhotos(3_500_000_000), 1_000)
        XCTAssertEqual(morePhotos(3_584_000_000), 1_000)
        XCTAssertEqual(morePhotos(35_000_000), 10)
        XCTAssertEqual(morePhotos(0), 0)
        XCTAssertEqual(morePhotos(-5), 0)
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
