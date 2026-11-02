import AVFoundation
import Foundation
import StorageCore
import VideoToolbox

/// Writes a smaller (and optionally trimmed) HEVC copy of a video into the
/// app's own temporary folder. The only code in the app that re-encodes media
/// or removes files, and it only ever removes its own copies in that folder.
/// It never touches Photos: `TestAlbumChanges.swift` hands it the video and
/// decides what to do with the copy. `Tools/check-no-device-access.sh` enforces this.
///
/// It decodes every frame and encodes it again at `VideoShrink.targetBitrate`.
/// Apple's export presets can't be given a bitrate, and on iPhone videos
/// (already HEVC) they come out about as big as the original.
enum VideoExporter {
    /// The app's own folder for copies waiting to replace a video.
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SmallerVideos", isDirectory: true)

    /// Exports the kept part of `asset` at `quality` and returns the copy's location, size and length.
    static func export(_ asset: AVAsset, edit: VideoEdit) async throws -> (url: URL, bytes: Int64, duration: TimeInterval) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        do {
            try await transcode(asset, edit: edit, to: url)
        } catch let error as PhotoChangeError {
            remove(url)
            throw error
        } catch {
            remove(url)
            throw PhotoChangeError.exportFailed(error.localizedDescription)
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let newDuration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        return (url, bytes, newDuration)
    }

    private static func transcode(_ asset: AVAsset, edit: VideoEdit, to url: URL) async throws {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw PhotoChangeError.exportFailed("the video has no picture track.")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        let trim = edit.trim.clamped(to: duration)
        let (natural, transform, frameRate, sourceBitrate, formats) = try await video.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions
        )
        let color = ColorInfo(formats.first)

        // naturalSize is the encoded (unrotated) size; the transform rotates it on playback.
        let scaled = VideoShrink.outputSize(width: Int(abs(natural.width)), height: Int(abs(natural.height)), quality: edit.quality)
        let width = scaled.width / 2 * 2
        let height = scaled.height / 2 * 2
        let bitrate = VideoShrink.targetBitrate(
            width: width, height: height, frameRate: Double(frameRate), sourceBitrate: Double(sourceBitrate)
        )

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: trim.start, preferredTimescale: 600),
            end: CMTime(seconds: trim.end, preferredTimescale: 600)
        )
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: color.isHDR
                ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut) else { throw PhotoChangeError.exportFailed("the video's picture couldn't be read.") }
        reader.add(videoOut)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Camera details such as the make and model travel with the video.
        writer.metadata = (try? await asset.load(.metadata)) ?? []

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: Int(bitrate),
            AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
        ]
        if color.isHDR {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        }
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        if width != Int(abs(natural.width)) || height != Int(abs(natural.height)) {
            settings[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspectFill
        }
        if let properties = color.properties {
            settings[AVVideoColorPropertiesKey] = properties
        }
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoIn) else { throw PhotoChangeError.exportFailed("this phone can't encode HEVC at that size.") }
        writer.add(videoIn)

        // Sound is copied as is, not re-encoded. Tracks the .mov can't hold
        // (such as an extra spatial-audio track) are left out; the stereo track stays.
        var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(videoOut, videoIn)]
        for track in audio {
            let hint = try await track.load(.formatDescriptions).first
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(out), writer.canAdd(input) {
                reader.add(out)
                writer.add(input)
                pairs.append((out, input))
            }
        }
        if !audio.isEmpty, pairs.count == 1 {
            throw PhotoChangeError.exportFailed("the video's sound couldn't be copied.")
        }

        guard reader.startReading() else {
            throw PhotoChangeError.exportFailed(reader.error?.localizedDescription ?? "the video couldn't be read.")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw PhotoChangeError.exportFailed(writer.error?.localizedDescription ?? "the copy couldn't be written.")
        }
        // The copy's timeline starts where the trim starts.
        writer.startSession(atSourceTime: reader.timeRange.start)

        await withTaskGroup(of: Void.self) { group in
            for (index, pair) in pairs.enumerated() {
                group.addTask { await pump(pair.0, into: pair.1, label: "VideoExporter.\(index)") }
            }
        }

        if reader.status == .failed || writer.status == .failed {
            reader.cancelReading()
            writer.cancelWriting()
            throw PhotoChangeError.exportFailed((writer.error ?? reader.error)?.localizedDescription ?? "the export stopped.")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw PhotoChangeError.exportFailed(writer.error?.localizedDescription ?? "the copy couldn't be finished.")
        }
    }

    /// Moves samples from one reader output to one writer input until either runs out.
    private static func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, label: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: label)) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    /// The source's color details, so HDR stays HDR and colors don't shift.
    private struct ColorInfo {
        let properties: [String: String]?
        let isHDR: Bool

        init(_ format: CMFormatDescription?) {
            func value(_ key: CFString) -> String? {
                format.flatMap { CMFormatDescriptionGetExtension($0, extensionKey: key) as? String }
            }
            let primaries = value(kCMFormatDescriptionExtension_ColorPrimaries)
            let transfer = value(kCMFormatDescriptionExtension_TransferFunction)
            let matrix = value(kCMFormatDescriptionExtension_YCbCrMatrix)
            if let primaries, let transfer, let matrix {
                properties = [
                    AVVideoColorPrimariesKey: primaries,
                    AVVideoTransferFunctionKey: transfer,
                    AVVideoYCbCrMatrixKey: matrix,
                ]
            } else {
                properties = nil
            }
            isHDR = transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                || transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        }
    }

    /// Removes a copy, but only if it's one of ours.
    static func remove(_ url: URL) {
        guard url.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Clears copies left over from a run that ended before they were used.
    static func removeLeftovers() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        urls.forEach(remove)
    }
}
