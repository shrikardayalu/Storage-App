import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AcquisitionConfig {
    /// The organization's namespace, shown beside the app ID in TelemetryDeck.
    static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/namespace/com.simpleshrink/")!
    /// Public ID from the TelemetryDeck dashboard. Set in project.yml and
    /// xtool-Info.plist. An empty/invalid ID disables sending.
    static var appID: String? {
        Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
    }
}

/// Sends only an explicitly shared survey choice. No analytics SDK, automatic
/// events, installation ID, account ID, device metadata or photo-library data.
/// Every installation uses the SAME clientUser: use event counts in the dashboard.
@MainActor
final class AcquisitionReporter {
    static let shared = AcquisitionReporter()
    nonisolated static let eventName = "Onboarding.acquisitionSource"
    nonisolated static let sourceParameter = "Acquisition.source"

    private enum Keys {
        static let recorded = "acquisition.recorded"
        static let pending = "acquisition.pendingSource"
    }

    private let defaults: UserDefaults
    private let appID: () -> String?
    private let send: (URLRequest) async throws -> Int
    private var sending = false

    init(defaults: UserDefaults = .standard,
         appID: @escaping () -> String? = { AcquisitionConfig.appID },
         send: @escaping (URLRequest) async throws -> Int = { request in
             let configuration = URLSessionConfiguration.ephemeral
             configuration.httpCookieStorage = nil
             configuration.urlCredentialStorage = nil
             configuration.urlCache = nil
             let session = URLSession(configuration: configuration)
             defer { session.finishTasksAndInvalidate() }
             let (_, response) = try await session.data(for: request)
             return (response as? HTTPURLResponse)?.statusCode ?? 0
         }) {
        self.defaults = defaults
        self.appID = appID
        self.send = send
    }

    /// Freeze the first decision so replaying onboarding cannot inflate totals.
    /// A skip records no pending event and makes no network request.
    func record(_ source: AcquisitionSource?) {
        guard !defaults.bool(forKey: Keys.recorded) else { return }
        defaults.set(source?.rawValue, forKey: Keys.pending)
        defaults.set(true, forKey: Keys.recorded)
    }

    /// Retry a shared answer after a failed request or offline launch. Never
    /// delays onboarding. With no unique event ID, an ambiguous network failure
    /// can produce a duplicate: these are approximate response totals.
    func flush() async {
        guard !sending,
              let raw = defaults.string(forKey: Keys.pending),
              let source = AcquisitionSource(rawValue: raw),
              let request = Self.request(source: source, appID: appID()) else { return }
        sending = true
        defer { sending = false }
        do {
            let status = try await send(request)
            if (200..<300).contains(status) {
                defaults.removeObject(forKey: Keys.pending)
            }
        } catch {
            // Keep the one pending choice for the next foreground launch.
        }
    }

    static func request(source: AcquisitionSource, appID: String?) -> URLRequest? {
        guard let appID, UUID(uuidString: appID) != nil else { return nil }
        struct Event: Encodable {
            let appID: String
            let clientUser = "anonymous-acquisition-survey"
            let type = AcquisitionReporter.eventName
            let isTestMode: Bool
            let payload: [String: String]
        }
        #if DEBUG
        let testMode = true
        #else
        let testMode = false
        #endif
        let event = Event(appID: appID, isTestMode: testMode,
                          payload: [sourceParameter: source.rawValue])
        var request = URLRequest(url: AcquisitionConfig.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("SimpleShrinkSurvey/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONEncoder().encode([event])
        return request
    }
}
