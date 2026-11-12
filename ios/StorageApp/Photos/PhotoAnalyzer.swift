import CoreGraphics
import Foundation
import Photos
import StorageCore
import UIKit
import Vision

/// Measures scanned photos for the junk finder (Build Plan step 7). Read-only:
/// it asks Photos for a small copy of each photo and runs Vision and a pixel
/// pass on it, all on the phone. Nothing is changed and nothing leaves the device.
struct PhotoKitAnalyzer: PhotoAnalysisService {
    /// The long side of the copy every photo is measured at, so thresholds mean the same thing for each.
    static let side = 512

    func analyze(_ items: [MediaItem], progress: @escaping @Sendable (Double) -> Void) async -> [MediaItem.ID: PhotoSignals] {
        // Burst shots are left to Step 5.
        let ids = items.filter { $0.category != .video && $0.burstID == nil }.map(\.id)
        guard !ids.isEmpty else {
            progress(1)
            return [:]
        }
        let assets = PhotoLibrary.assets(withIDs: Set(ids))
        guard !assets.isEmpty else {
            progress(1)
            return [:]
        }

        // A few photos at a time: a whole library is a lot of photos, and
        // Vision still leaves the phone responsive at this pace.
        var results: [MediaItem.ID: PhotoSignals] = [:]
        await withTaskGroup(of: (String, PhotoSignals?).self) { group in
            var next = 0
            var done = 0
            while next < min(Self.atOnce, assets.count) {
                let asset = assets[next]
                group.addTask { (asset.localIdentifier, await Self.signals(for: asset)) }
                next += 1
            }
            for await (id, signals) in group {
                if let signals { results[id] = signals }
                done += 1
                progress(Double(done) / Double(assets.count))
                if next < assets.count, !Task.isCancelled {
                    let asset = assets[next]
                    group.addTask { (asset.localIdentifier, await Self.signals(for: asset)) }
                    next += 1
                }
            }
        }
        return results
    }

    /// How many photos are measured at the same time: enough that the next copy
    /// is on its way while Vision works, with cores left for the screen.
    private static let atOnce = max(3, min(6, ProcessInfo.processInfo.activeProcessorCount - 2))

    /// One PhotoKit image request that resumes exactly once. `requestImage` can
    /// call back twice (a stand-in, then the real copy); a second resume crashes the scan.
    private final class OneShotImage: @unchecked Sendable {
        private let lock = NSLock()
        private var requestID: PHImageRequestID = PHInvalidImageRequestID
        private var continuation: CheckedContinuation<UIImage?, Never>?
        private var finished = false
        private var cancelled = false

        func fetch(_ asset: PHAsset, target: CGSize, options: PHImageRequestOptions) async -> UIImage? {
            await withCheckedContinuation { continuation in
                self.lock.lock()
                self.continuation = continuation
                self.lock.unlock()

                // PhotoKit can deliver the copy on the thread that asked, and only
                // if that thread runs a run loop. The main thread does; a task doesn't.
                Task { @MainActor [self] in
                    let id = PHImageManager.default().requestImage(
                        for: asset, targetSize: target, contentMode: .aspectFit, options: options
                    ) { image, info in
                        let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                        let failed = info?[PHImageErrorKey] != nil
                        let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        if cancelled || failed {
                            self.finish(nil)
                            return
                        }
                        // Wait for the final copy when Photos hands over a stand-in first.
                        if degraded { return }
                        self.finish(image)
                    }
                    if self.remember(id) { PHImageManager.default().cancelImageRequest(id) }
                }
            }
        }

        /// Stores the Photos request id. Returns true when the request should be cancelled
        /// because the copy already arrived, or this pass already gave up on it.
        private func remember(_ id: PHImageRequestID) -> Bool {
            lock.lock()
            requestID = id
            let stop = finished || cancelled
            lock.unlock()
            return stop
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let id = requestID
            lock.unlock()
            if id != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(id)
            }
            finish(nil)
        }

        private func finish(_ image: UIImage?) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: image)
        }
    }

    private static func signals(for asset: PHAsset) async -> PhotoSignals? {
        guard let image = await smallCopy(of: asset) else { return nil }
        return await Task.detached(priority: .utility) { measure(image) }.value
    }

    /// How long one photo may take to come back before it's skipped for this pass.
    /// A photo that never arrives (usually one still downloading from iCloud) used
    /// to hold the progress bar in place for the rest of the library.
    private static let copyTimeout = Duration.seconds(8)

    /// A copy no bigger than `side` on its long edge, as Photos shows it (edits included).
    /// Asked for on the main thread: PhotoKit delivers some results on the calling
    /// thread's run loop, and a Swift task has none, so the request would never finish.
    private static func smallCopy(of asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        // The nearest copy Photos already has; the pixel pass scales it to `side` anyway.
        options.resizeMode = .fast
        options.version = .current
        // Only a small copy is fetched if the photo is in iCloud.
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        let request = OneShotImage()
        let size = CGSize(width: side, height: side)
        return await withTaskGroup(of: UIImage?.self) { group in
            group.addTask { await request.fetch(asset, target: size, options: options) }
            group.addTask {
                do { try await Task.sleep(for: copyTimeout) } catch { return nil }
                request.cancel()
                return nil
            }
            let image = await group.next() ?? nil
            group.cancelAll()
            if image == nil { request.cancel() }
            return image
        }
    }

    private static func measure(_ image: UIImage) -> PhotoSignals? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(of: image))

        let printRequest = VNGenerateImageFeaturePrintRequest()
        printRequest.imageCropAndScaleOption = .scaleFill
        // What's in the picture and how it came out, so memories aren't
        // mistaken for junk. Run together when the phone can; fall back one
        // by one if a request the phone doesn't support spoils the batch.
        let sceneRequest = VNClassifyImageRequest()
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        do {
            try handler.perform([printRequest, sceneRequest, faceRequest])
        } catch {
            do {
                try handler.perform([printRequest])
            } catch {
                return nil
            }
            try? handler.perform([sceneRequest])
            try? handler.perform([faceRequest])
        }
        let looks = aesthetics(handler)
        let labels = (sceneRequest.results ?? [])
            .filter { $0.confidence >= 0.15 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(12)
            .reduce(into: [String: Double]()) { $0[$1.identifier] = Double($1.confidence) }
        let faces = faceRequest.results ?? []

        guard let gray = grayPixels(cgImage) else { return nil }
        let stats = ImageStats.measure(gray: gray.pixels, width: gray.width, height: gray.height)
        var signals = PhotoSignals(
            featurePrint: printRequest.results?.first.map(floats) ?? [],
            sharpness: stats.sharpness,
            brightness: stats.brightness,
            darkFraction: stats.darkFraction,
            peakSharpness: stats.peakSharpness,
            faceCount: faces.count,
            faceArea: faces.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0,
            faceQuality: faces.compactMap(\.faceCaptureQuality).min().map(Double.init),
            labels: labels,
            aesthetics: looks?.score,
            isUtility: looks?.isUtility ?? false
        )
        // Text only matters for documents and receipts, and a photo of people,
        // a pet or scenery is never one, so reading it is skipped there.
        guard PhotoWorth.keepReason(for: signals) == nil else { return signals }
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        guard (try? handler.perform([textRequest])) != nil, let text = textRequest.results else { return signals }
        signals.textLines = text.compactMap { $0.topCandidates(1).first?.string }
        signals.textCoverage = min(text.reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }, 1)
        return signals
    }

    /// Vision's rating of how good the photo looks, on iOS 18 and later.
    private static func aesthetics(_ handler: VNImageRequestHandler) -> (score: Double, isUtility: Bool)? {
        guard #available(iOS 18.0, *) else { return nil }
        let request = VNCalculateImageAestheticsScoresRequest()
        guard (try? handler.perform([request])) != nil, let result = request.results?.first else { return nil }
        return (Double(result.overallScore), result.isUtility)
    }

    /// The print as unit-length floats, so distances mean the same thing whatever Vision revision made it.
    private static func floats(_ observation: VNFeaturePrintObservation) -> [Float] {
        guard observation.elementType == .float else { return [] }
        let values = observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(observation.elementCount)) }
        let length = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? values.map { $0 / length } : []
    }

    /// One gray byte per pixel, at most `side` on the long edge.
    private static func grayPixels(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let scale = min(1, Double(side) / Double(max(image.width, image.height)))
        let width = max(3, Int(Double(image.width) * scale))
        let height = max(3, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: width * height), count: width * height))
        return (pixels, width, height)
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
