import AVFoundation
import CoreVideo
import StorageCore
import XCTest
@testable import StorageApp

/// The real exporter, run on a small generated clip.
final class VideoExporterTests: XCTestCase {
    /// Many Android videos open with an empty edit before the first frame.
    /// Reading from the gap once put a black frame first in the copy, which
    /// Photos showed as the thumbnail.
    func testAVideoThatStartsWithAGapDoesNotGetABlackFirstFrame() async throws {
        let clip = try await Self.makeGrayClip(seconds: 2)
        defer { try? FileManager.default.removeItem(at: clip) }

        let source = AVURLAsset(url: clip)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceTrack = try await source.loadTracks(withMediaType: .video).first else {
            return XCTFail("No video track")
        }
        let sourceDuration = try await source.load(.duration)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: sourceDuration), of: sourceTrack, at: .zero)
        // A 30 ms gap at the start, like a Galaxy phone's recording.
        composition.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 3, timescale: 100)))

        let duration = try await composition.load(.duration).seconds
        let copy: (url: URL, bytes: Int64, duration: TimeInterval)
        do {
            copy = try await VideoExporter.export(composition, edit: VideoEdit(quality: .sameQuality, trim: .full(duration)))
        } catch PhotoChangeError.exportFailed(let reason) where reason.contains("HEVC") {
            throw XCTSkip("This machine can't encode HEVC: \(reason)")
        }
        defer { VideoExporter.remove(copy.url) }

        let luma = try await Self.firstFrameBrightness(of: AVURLAsset(url: copy.url))
        XCTAssertGreaterThan(luma, 90, "The copy's first frame should be the gray picture, not black")
        XCTAssertEqual(copy.duration, 2, accuracy: 0.1)
    }

    // MARK: Helpers

    /// Writes a clip of mid-gray frames at 30 fps.
    private static func makeGrayClip(seconds: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let (width, height) = (320, 240)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { throw PhotoChangeError.exportFailed("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 128, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        return url
    }

    /// Average brightness, 0 to 255, of the first frame a reader hands out.
    private static func firstFrameBrightness(of asset: AVAsset) async throws -> Double {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        reader.startReading()
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer(), let image = CMSampleBufferGetImageBuffer(sample) else { return 0 }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
        let (width, height, row) = (CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image), CVPixelBufferGetBytesPerRow(image))
        var total = 0
        for y in 0..<height {
            for x in 0..<width {
                let pixel = base + y * row + x * 4
                total += Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
            }
        }
        return Double(total) / Double(width * height * 3)
    }
}
