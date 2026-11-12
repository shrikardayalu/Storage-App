import AVFoundation
import Photos

/// Loads a scanned video for playing inside the app. Read-only.
enum VideoPreviewLoader {
    /// The video as Photos plays it, edits included. Downloads it from iCloud if needed.
    static func playerItem(for localIdentifier: String) async -> AVPlayerItem? {
        guard let asset = PhotoLibrary.asset(localIdentifier) else { return nil }
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}
