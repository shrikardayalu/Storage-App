import Foundation

/// Measures photos for the junk finder (Build Plan step 7). Read-only: it looks
/// at a small copy of each photo and never changes anything.
public protocol PhotoAnalysisService: Sendable {
    /// Signals for each item it could read. Items it couldn't read are left out.
    /// `progress` gets the share done so far, 0 to 1.
    func analyze(_ items: [MediaItem], progress: @escaping @Sendable (Double) -> Void) async -> [MediaItem.ID: PhotoSignals]
}

/// Returns fixed signals, for tests and previews.
public struct MockPhotoAnalysis: PhotoAnalysisService {
    public var signals: [MediaItem.ID: PhotoSignals]

    public init(signals: [MediaItem.ID: PhotoSignals] = [:]) {
        self.signals = signals
    }

    public func analyze(_ items: [MediaItem], progress: @escaping @Sendable (Double) -> Void) async -> [MediaItem.ID: PhotoSignals] {
        progress(1)
        let ids = Set(items.map(\.id))
        return signals.filter { ids.contains($0.key) }
    }
}
