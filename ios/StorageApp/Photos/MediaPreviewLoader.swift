import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Loads one item big enough to look at closely, for the press-and-hold
/// preview. Read-only: nothing here changes Photos.
enum MediaPreviewLoader {
    /// The photo as Photos shows it (edits included), fitted inside `side` points.
    /// Fetches it from iCloud if it isn't on the phone.
    static func image(for localIdentifier: String, side: CGFloat) async -> UIImage? {
        guard let asset = PhotoLibrary.asset(localIdentifier) else { return nil }
        let options = PHImageRequestOptions()
        // One callback, with the full-quality picture.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.version = .current
        options.isNetworkAccessAllowed = true
        let scale = await UIScreen.main.scale
        let size = CGSize(width: side * scale, height: side * scale)
        return await withCheckedContinuation { continuation in
            let once = Once()
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                if once.first() { continuation.resume(returning: image) }
            }
        }
    }

    /// The Live Photo, ready to play.
    fileprivate static func livePhoto(for localIdentifier: String, side: CGFloat) async -> PHLivePhoto? {
        guard let asset = PhotoLibrary.asset(localIdentifier) else { return nil }
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        let scale = await UIScreen.main.scale
        let size = CGSize(width: side * scale, height: side * scale)
        return await withCheckedContinuation { continuation in
            let once = Once()
            PHImageManager.default().requestLivePhoto(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { livePhoto, _ in
                if once.first() { continuation.resume(returning: livePhoto) }
            }
        }
    }

    /// True the first time it's asked, so a request that calls back twice answers once.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false

        func first() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if used { return false }
            used = true
            return true
        }
    }
}

/// Plays a Live Photo: once when it appears, and again on the Play button
/// or a press on the photo, the way Photos does.
struct LivePhotoPlayer: View {
    let id: String
    /// Whether this is the page on screen; only that one plays.
    var isActive = true
    @State private var livePhoto: PHLivePhoto?
    @State private var couldNotLoad = false
    @State private var plays = 0

    var body: some View {
        ZStack {
            if let livePhoto {
                Surface(livePhoto: livePhoto, plays: plays)
                    .overlay(alignment: .topLeading) {
                        Button {
                            plays += 1
                        } label: {
                            Label("Play", systemImage: "livephoto")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .accessibilityLabel("Play Live Photo")
                    }
            } else if couldNotLoad {
                // The still is better than nothing.
                StillPreview(id: id)
            } else {
                SketchSpinner(size: 28)
            }
        }
        .task(id: id) {
            livePhoto = await MediaPreviewLoader.livePhoto(for: id, side: 520)
            couldNotLoad = livePhoto == nil
            // Give the view a moment to settle on screen, or the first play is dropped.
            try? await Task.sleep(for: .milliseconds(350))
            if isActive, !Task.isCancelled { plays += 1 }
        }
        .onChange(of: isActive) { _, active in
            if active, livePhoto != nil { plays += 1 }
        }
    }

    private struct Surface: UIViewRepresentable {
        let livePhoto: PHLivePhoto
        let plays: Int

        func makeUIView(context: Context) -> PHLivePhotoView {
            let view = PHLivePhotoView()
            view.contentMode = .scaleAspectFit
            view.livePhoto = livePhoto
            return view
        }

        func updateUIView(_ view: PHLivePhotoView, context: Context) {
            if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
            if context.coordinator.plays != plays {
                context.coordinator.plays = plays
                view.startPlayback(with: .full)
            }
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator {
            var plays = 0
        }
    }
}
