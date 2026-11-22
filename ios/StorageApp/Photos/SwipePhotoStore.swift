import Observation
import Photos
import UIKit

/// A small moving window, so a swipe never starts a whole-library download.
/// PhotoKit may deliver a small image first and the iCloud copy later.
@MainActor @Observable
final class SwipePhotoStore {
    struct Preview {
        var image: UIImage?
        var progress: Double?
        var failed = false
    }

    enum Event {
        case progress(Double)
        case image(UIImage, final: Bool)
        case failed
    }
    typealias Request = @MainActor (String, @escaping (Event) -> Void) -> (() -> Void)?

    private(set) var previews: [String: Preview] = [:]
    @ObservationIgnored private let requestImage: Request
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var requests: [String: (token: UUID, cancel: () -> Void, timeout: Task<Void, Never>)] = [:]

    init(timeout: Duration = .seconds(30), requestImage: Request? = nil) {
        self.timeout = timeout
        if let requestImage { self.requestImage = requestImage }
        else { self.requestImage = Self.photoKitRequest }
    }

    func prepare(_ identifiers: [String]) {
        let wanted = Set(identifiers)
        for id in Array(previews.keys) where !wanted.contains(id) {
            cancel(id)
            previews.removeValue(forKey: id)
        }
        for id in identifiers where previews[id] == nil { load(id) }
    }

    func retry(_ id: String) {
        cancel(id)
        load(id)
    }

    func stop() {
        for id in Array(requests.keys) { cancel(id) }
        previews = [:]
    }

    private func load(_ id: String) {
        previews[id] = Preview(image: PhotoThumbnailLoader.cached(id))
        let token = UUID()
        guard let cancelRequest = requestImage(id, { [weak self] event in
            // Apply callbacks after registration, even if PhotoKit calls synchronously.
            Task { @MainActor in
                guard let self, self.requests[id]?.token == token else { return }
                switch event {
                case .progress(let progress): self.previews[id]?.progress = progress
                case .image(let image, let final):
                    self.previews[id]?.image = image
                    if final { self.finish(id) }
                case .failed: self.finish(id)
                }
            }
        }) else {
            previews[id]?.failed = previews[id]?.image == nil
            return
        }
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: self?.timeout ?? .seconds(30)) } catch { return }
            guard let self, self.requests[id]?.token == token else { return }
            self.finish(id)
        }
        requests[id] = (token, cancelRequest, timeout)
    }

    private func finish(_ id: String) {
        previews[id]?.failed = previews[id]?.image == nil
        previews[id]?.progress = nil
        cancel(id)
    }

    private func cancel(_ id: String) {
        guard let request = requests.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.cancel()
    }

    private static func photoKitRequest(_ id: String, receive: @escaping (Event) -> Void) -> (() -> Void)? {
        guard let asset = PhotoLibrary.asset(id) else { return nil }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress, error, _, _ in
            receive(error == nil ? .progress(progress) : .failed)
        }
        let request = manager.requestImage(for: asset,
            targetSize: CGSize(width: 1080, height: 1080), contentMode: .aspectFit, options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            if let image { receive(.image(image, final: !degraded)) }
            else if !degraded || info?[PHImageErrorKey] != nil || (info?[PHImageCancelledKey] as? Bool) == true {
                receive(.failed)
            }
        }
        return { manager.cancelImageRequest(request) }
    }
}
