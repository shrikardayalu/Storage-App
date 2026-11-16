import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import StorageApp

@MainActor
final class AcquisitionReporterTests: XCTestCase {
    private let appID = "D3C0724A-3429-476D-882F-3450CA8D75DB"

    func testRequestContainsOnlyTheSurveyAndSharedConstantIdentity() async throws {
        let request = try XCTUnwrap(AcquisitionReporter.request(source: .website, appID: appID))
        XCTAssertEqual(request.url?.absoluteString, "https://nom.telemetrydeck.com/v2/namespace/com.simpleshrink/")
        XCTAssertEqual(request.httpMethod, "POST")
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [[String: Any]])
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(Set(event.keys), ["appID", "clientUser", "type", "isTestMode", "payload"])
        XCTAssertEqual(event["clientUser"] as? String, "anonymous-acquisition-survey")
        XCTAssertEqual(event["type"] as? String, AcquisitionReporter.eventName)
        XCTAssertEqual(event["payload"] as? [String: String], ["Acquisition.source": "simpleshrink_website"])
        #if DEBUG
        XCTAssertEqual(event["isTestMode"] as? Bool, true)
        #endif
        XCTAssertNil(AcquisitionReporter.request(source: .tiktok, appID: nil))
        XCTAssertNil(AcquisitionReporter.request(source: .tiktok, appID: ""))
        XCTAssertNil(AcquisitionReporter.request(source: .tiktok, appID: "not-an-app-id"))
    }

    func testSkipAndReplayMakeNoRequest() async throws {
        let name = "AcquisitionSkipTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var requests = 0
        let reporter = AcquisitionReporter(defaults: defaults, appID: { self.appID }) { _ in
            requests += 1
            return 200
        }
        reporter.record(nil)
        await reporter.flush()
        reporter.record(.tiktok)
        await reporter.flush()
        XCTAssertEqual(requests, 0)
    }

    func testSuccessClearsPendingAndReplayDoesNotDoubleCount() async throws {
        let name = "AcquisitionSuccessTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var requests = 0
        let reporter = AcquisitionReporter(defaults: defaults, appID: { self.appID }) { _ in
            requests += 1
            return 200
        }
        reporter.record(.instagram)
        await reporter.flush()
        reporter.record(.facebook)
        await reporter.flush()
        let relaunched = AcquisitionReporter(defaults: defaults, appID: { self.appID }) { _ in
            requests += 1
            return 200
        }
        await relaunched.flush()
        XCTAssertEqual(requests, 1)
    }

    func testFailedResponseIsRetriedAfterRelaunch() async throws {
        let name = "AcquisitionRetryTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let reporter = AcquisitionReporter(defaults: defaults, appID: { self.appID }) { _ in 503 }
        reporter.record(.redditForums)
        await reporter.flush()
        var sources: [String] = []
        let relaunched = AcquisitionReporter(defaults: defaults, appID: { self.appID }) { request in
            let events = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [[String: Any]])
            let payload = try XCTUnwrap(events.first?["payload"] as? [String: String])
            sources.append(try XCTUnwrap(payload[AcquisitionReporter.sourceParameter]))
            return 200
        }
        await relaunched.flush()
        await relaunched.flush()
        XCTAssertEqual(sources, ["reddit_forums"])
    }

    func testOfflineAndMissingConfigurationKeepTheSharedAnswer() async throws {
        let name = "AcquisitionOfflineTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var requests = 0
        let unconfigured = AcquisitionReporter(defaults: defaults, appID: { nil }) { _ in
            XCTFail("No request without an app ID")
            return 200
        }
        unconfigured.record(.youtube)
        await unconfigured.flush()
        let offline = AcquisitionReporter(defaults: defaults, appID: { self.appID }) { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }
        await offline.flush()
        let online = AcquisitionReporter(defaults: defaults, appID: { self.appID }) { _ in
            requests += 1
            return 200
        }
        await online.flush()
        await online.flush()
        XCTAssertEqual(requests, 2)
    }
}
