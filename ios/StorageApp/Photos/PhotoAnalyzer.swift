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
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in assets.append(asset) }

        var results: [MediaItem.ID: PhotoSignals] = [:]
        for (index, asset) in assets.enumerated() {
            if Task.isCancelled { break }
            if let image = await Self.smallCopy(of: asset),
               let signals = await Task.detached(priority: .userInitiated, operation: { Self.measure(image) }).value {
                results[asset.localIdentifier] = signals
            }
            progress(Double(index + 1) / Double(assets.count))
        }
        return results
    }

    /// A copy no bigger than `side` on its long edge, as Photos shows it (edits included).
    private static func smallCopy(of asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        // Only a small copy is fetched if the photo is in iCloud.
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: side, height: side)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func measure(_ image: UIImage) -> PhotoSignals? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(of: image))

        let printRequest = VNGenerateImageFeaturePrintRequest()
        printRequest.imageCropAndScaleOption = .scaleFill
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        do {
            try handler.perform([printRequest, textRequest])
        } catch {
            return nil
        }

        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let coverage = (textRequest.results ?? []).reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
        guard let gray = grayPixels(cgImage) else { return nil }
        let stats = ImageStats.measure(gray: gray.pixels, width: gray.width, height: gray.height)
        return PhotoSignals(
            featurePrint: printRequest.results?.first.map(floats) ?? [],
            sharpness: stats.sharpness,
            brightness: stats.brightness,
            darkFraction: stats.darkFraction,
            textLines: lines,
            textCoverage: min(coverage, 1)
        )
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
