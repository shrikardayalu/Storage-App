import UIKit
import XCTest
@testable import StorageApp

@MainActor
final class SwipePhotoStoreTests: XCTestCase {
    private final class Requests {
        var callbacks: [String: [(SwipePhotoStore.Event) -> Void]] = [:]
        var cancelled: [String] = []

        func start(_ id: String, receive: @escaping (SwipePhotoStore.Event) -> Void) -> (() -> Void)? {
            callbacks[id, default: []].append(receive)
            return { self.cancelled.append(id) }
        }
    }

    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Photo callback did not settle", file: file, line: line)
    }

    func testICloudProgressAndDegradedImageUpgradeWithoutEndingRequestEarly() async throws {
        let requests = Requests()
        let store = SwipePhotoStore(requestImage: requests.start)
        defer { store.stop() }
        store.prepare(["cloud"])
        let callback = try XCTUnwrap(requests.callbacks["cloud"]?.first)
        callback(.progress(0.4))
        try await waitFor { store.previews["cloud"]?.progress == 0.4 }
        let small = UIImage()
        callback(.image(small, final: false))
        try await waitFor { store.previews["cloud"]?.image === small }
        XCTAssertTrue(requests.cancelled.isEmpty)
        let full = UIImage()
        callback(.image(full, final: true))
        try await waitFor { store.previews["cloud"]?.image === full }
        XCTAssertEqual(requests.cancelled, ["cloud"])
        XCTAssertNil(store.previews["cloud"]?.progress)
        XCTAssertEqual(store.previews["cloud"]?.failed, false)
    }

    func testRetryIgnoresLateResultsFromThePreviousRequest() async throws {
        let requests = Requests()
        let store = SwipePhotoStore(requestImage: requests.start)
        defer { store.stop() }
        store.prepare(["photo"])
        let old = try XCTUnwrap(requests.callbacks["photo"]?.first)
        old(.failed)
        try await waitFor { store.previews["photo"]?.failed == true }
        store.retry("photo")
        let current = try XCTUnwrap(requests.callbacks["photo"]?.last)
        let full = UIImage()
        current(.image(full, final: true))
        old(.image(UIImage(), final: true))
        try await waitFor { store.previews["photo"]?.image === full }
        XCTAssertEqual(store.previews["photo"]?.failed, false)
    }

    func testMovingTheWindowCancelsOldDownloadsAndReleasesTheirImages() async throws {
        let requests = Requests()
        let store = SwipePhotoStore(requestImage: requests.start)
        store.prepare(["a", "b", "c", "d", "e"])
        let old = try XCTUnwrap(requests.callbacks["a"]?.first)
        store.prepare(["b", "c", "d", "e", "f"])
        XCTAssertEqual(requests.cancelled, ["a"])
        XCTAssertEqual(Set(store.previews.keys), Set(["b", "c", "d", "e", "f"]))
        old(.image(UIImage(), final: true))
        let current = try XCTUnwrap(requests.callbacks["f"]?.first)
        current(.failed)
        try await waitFor { store.previews["f"]?.failed == true }
        XCTAssertNil(store.previews["a"])
        store.stop()
        XCTAssertTrue(store.previews.isEmpty)
        XCTAssertEqual(Set(requests.cancelled), Set(["a", "b", "c", "d", "e", "f"]))
    }

    func testUnavailableAssetAndTimedOutDownloadLeaveTheSpinner() async throws {
        let missing = SwipePhotoStore(requestImage: { _, _ in nil })
        missing.prepare(["missing"])
        XCTAssertEqual(missing.previews["missing"]?.failed, true)
        let requests = Requests()
        let store = SwipePhotoStore(timeout: .milliseconds(10), requestImage: requests.start)
        store.prepare(["offline"])
        try await waitFor { store.previews["offline"]?.failed == true }
        XCTAssertEqual(requests.cancelled, ["offline"])
    }

    func testFailedUpgradeKeepsTheUsablePreview() async throws {
        let requests = Requests()
        let store = SwipePhotoStore(requestImage: requests.start)
        store.prepare(["photo"])
        let callback = try XCTUnwrap(requests.callbacks["photo"]?.first)
        let small = UIImage()
        callback(.image(small, final: false))
        callback(.failed)
        try await waitFor { requests.cancelled == ["photo"] }
        XCTAssertTrue(store.previews["photo"]?.image === small)
        XCTAssertEqual(store.previews["photo"]?.failed, false)
    }

    func testToursHaveSeparateFirstUseKeysAndShortInstructions() {
        XCTAssertEqual(Set(FeatureTour.allCases.map(\.storageKey)).count, FeatureTour.allCases.count)
        for tour in FeatureTour.allCases {
            XCTAssertEqual(tour.steps.count, 3, tour.rawValue)
            XCTAssertTrue(tour.steps.allSatisfy { !$0.target.isEmpty && !$0.title.isEmpty && !$0.message.isEmpty })
        }
    }
}
