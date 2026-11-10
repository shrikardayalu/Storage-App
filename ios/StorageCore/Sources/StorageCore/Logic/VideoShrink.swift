import Foundation

/// The two ways Step 6 re-encodes a video. Both write HEVC.
public enum VideoQuality: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Same resolution, re-encoded with HEVC at a bitrate that looks the same.
    case sameQuality
    /// One resolution step down (4K to 1080p, 1080p to 720p) and a lighter
    /// encode, so it's always clearly smaller than `sameQuality`.
    case smaller

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sameQuality: "Same quality"
        case .smaller: "Smaller file"
        }
    }

    /// What the option does to a video of this size, in plain words.
    public func detail(width: Int, height: Int) -> String {
        let source = VideoShrink.resolutionName(longSide: max(width, height), shortSide: min(width, height))
        switch self {
        case .sameQuality:
            return "Stays \(source). Looks the same, a more efficient file"
        case .smaller:
            let out = VideoShrink.outputSize(width: width, height: height, quality: self)
            let name = VideoShrink.resolutionName(longSide: max(out.width, out.height), shortSide: min(out.width, out.height))
            return name == source
                ? "Stays \(source), lighter encode. Fine on a phone screen"
                : "\(source) to \(name). Looks great on a phone, much smaller"
        }
    }

    /// The longest side the result can have for a source this size; nil keeps it.
    public func maxLongSide(forSourceLongSide longSide: Int) -> Int? {
        switch self {
        case .sameQuality: nil
        case .smaller:
            if longSide > 1920 { 1920 } else if longSide > 1280 { 1280 } else { nil }
        }
    }

    /// HEVC bits per pixel per frame. 0.07 is visually close to an iPhone
    /// camera's own HEVC; the smaller option trades a little detail for size.
    var bitsPerPixelFrame: Double {
        switch self {
        case .sameQuality: 0.07
        case .smaller: 0.045
        }
    }
}

/// The part of a video to keep, in seconds from its start.
public struct VideoTrim: Hashable, Sendable {
    /// A trimmed video is never shorter than this.
    public static let minimumLength: TimeInterval = 1

    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    /// The whole video.
    public static func full(_ duration: TimeInterval) -> VideoTrim {
        VideoTrim(start: 0, end: max(duration, 0))
    }

    public var length: TimeInterval { end - start }

    /// True when nothing is cut, allowing for a frame or so of slack.
    public func isFull(of duration: TimeInterval) -> Bool {
        start < 0.05 && end > duration - 0.05
    }

    /// The same trim kept inside the video and at least `minimumLength` long.
    /// A handle pushed past the other one moves it along rather than crossing it.
    public func clamped(to duration: TimeInterval) -> VideoTrim {
        guard duration > Self.minimumLength else { return .full(duration) }
        let end = min(max(end, Self.minimumLength), duration)
        let start = min(max(start, 0), end - Self.minimumLength)
        return VideoTrim(start: start, end: end)
    }
}

/// What the person chose for one video.
public struct VideoEdit: Hashable, Sendable {
    public let quality: VideoQuality
    public let trim: VideoTrim

    public init(quality: VideoQuality, trim: VideoTrim) {
        self.quality = quality
        self.trim = trim
    }
}

/// Which videos Step 6 can shrink, and roughly how much it saves before the
/// real export measures it.
public enum VideoShrink {
    /// Videos smaller than this aren't worth re-encoding.
    public static let minimumBytes: Int64 = 2_000_000
    /// A copy must be at least this much smaller than the original to replace it.
    public static let minimumSavingFraction = 0.05
    /// The scan doesn't read frame rates, so estimates assume the camera's default.
    static let assumedFrameRate = 30.0

    /// Why a video is left alone; nil when it can be shrunk.
    public static func unsupportedReason(for item: MediaItem) -> String? {
        guard item.category == .video else { return "Not a video." }
        if item.format == .proRes { return "ProRes is kept at full quality for editing." }
        if item.traits.contains(.slowMotion) { return "Slo-mo is left alone, so its slow part stays editable." }
        if item.traits.contains(.cinematic) { return "Cinematic videos are left alone, so their focus stays editable." }
        if (item.duration ?? 0) < VideoTrim.minimumLength { return "Too short to shrink." }
        if item.currentBytes < minimumBytes { return "Already small." }
        return nil
    }

    /// The pixel size of the result.
    public static func outputSize(width: Int, height: Int, quality: VideoQuality) -> (width: Int, height: Int) {
        let longSide = max(width, height)
        guard let cap = quality.maxLongSide(forSourceLongSide: longSide), longSide > cap else { return (width, height) }
        let scale = Double(cap) / Double(longSide)
        return (Int((Double(width) * scale).rounded()), Int((Double(height) * scale).rounded()))
    }

    /// The bitrate, in bits per second, a copy is encoded at: enough for HEVC
    /// at this resolution and frame rate, and never more than the original's.
    public static func targetBitrate(
        width: Int, height: Int, frameRate: Double, sourceBitrate: Double, quality: VideoQuality = .sameQuality
    ) -> Double {
        let fps = min(max(frameRate, 24), 60)
        return min(Double(width * height) * fps * quality.bitsPerPixelFrame, sourceBitrate)
    }

    /// "4K", "1080p", "720p" or "480p", by the short side.
    public static func resolutionName(longSide: Int, shortSide: Int) -> String {
        switch shortSide {
        case 2000...: "4K"
        case 1000...: "1080p"
        case 700...: "720p"
        default: "\(shortSide)p"
        }
    }

    /// A rough size for the result: the kept part at the target bitrate. The
    /// real export measures it; this is only for showing a figure before it runs.
    public static func estimatedBytes(for item: MediaItem, edit: VideoEdit) -> Int64 {
        guard let duration = item.duration, duration > 0 else { return item.currentBytes }
        let trim = edit.trim.clamped(to: duration)
        let sourceBitrate = Double(item.currentBytes) * 8 / duration
        let out = outputSize(width: item.pixelWidth, height: item.pixelHeight, quality: edit.quality)
        let bitrate = targetBitrate(
            width: out.width, height: out.height, frameRate: assumedFrameRate, sourceBitrate: sourceBitrate, quality: edit.quality
        )
        return Int64((bitrate * trim.length / 8).rounded())
    }

    public static func estimatedSaving(for item: MediaItem, edit: VideoEdit) -> Int64 {
        max(0, item.currentBytes - estimatedBytes(for: item, edit: edit))
    }

    /// True when a copy of `newBytes` is worth swapping in for `originalBytes`.
    public static func isWorthReplacing(originalBytes: Int64, newBytes: Int64) -> Bool {
        newBytes > 0 && Double(newBytes) <= Double(originalBytes) * (1 - minimumSavingFraction)
    }
}

/// How "shrink all at once" picks a quality for each video.
public enum BatchVideoQuality: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Each video gets the quality `VideoShrink.smartPick` suggests.
    case smart
    case sameQuality
    case smaller

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smart: "Smart"
        case .sameQuality: "Same quality"
        case .smaller: "Smaller files"
        }
    }

    public var detail: String {
        switch self {
        case .smart: "Smaller files for screen recordings, saved clips and older 4K. Your camera videos keep their look."
        case .sameQuality: "Every video keeps its resolution and look, in a more efficient file."
        case .smaller: "Every video drops one size step. Still looks great on a phone, saves the most."
        }
    }
}

/// The quality chosen for one video in a batch, and why, in a few words.
public struct SmartPick: Hashable, Sendable {
    public let quality: VideoQuality
    public let reason: String
}

extension VideoShrink {
    /// Videos with a 4K picture older than this get the smaller option from Smart.
    static let older4KAge: TimeInterval = 365 * 24 * 3600

    /// Which quality a video needs. Screen recordings, clips saved from other
    /// apps and 4K videos over a year old rarely need full quality, so they get
    /// `.smaller`. Everything else, which is mostly recent camera video, keeps its look.
    public static func smartPick(for item: MediaItem, now: Date = Date()) -> SmartPick {
        let name = item.filename.uppercased()
        if name.hasPrefix("RPREPLAY") || name.contains("SCREEN RECORDING") {
            return SmartPick(quality: .smaller, reason: "screen recording")
        }
        if !(name.hasPrefix("IMG_") || name.hasPrefix("VID_")) {
            return SmartPick(quality: .smaller, reason: "saved from an app")
        }
        if min(item.pixelWidth, item.pixelHeight) >= 2000, now.timeIntervalSince(item.creationDate) > older4KAge {
            return SmartPick(quality: .smaller, reason: "older 4K, 1080p is plenty")
        }
        return SmartPick(quality: .sameQuality, reason: "camera video, keeps its look")
    }

    /// The quality a batch setting gives one video.
    public static func pick(_ setting: BatchVideoQuality, for item: MediaItem, now: Date = Date()) -> SmartPick {
        switch setting {
        case .smart: smartPick(for: item, now: now)
        case .sameQuality: SmartPick(quality: .sameQuality, reason: "keeps its look")
        case .smaller: SmartPick(quality: .smaller, reason: "smaller file")
        }
    }
}

/// A smaller copy of one video, made in the app's own temporary folder. Nothing
/// in Photos has changed yet; the person sees the real sizes and decides.
public struct PreparedVideo: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let originalID: MediaItem.ID
    public let edit: VideoEdit
    /// The copy, inside the app's temporary folder.
    public let fileURL: URL
    public let originalBytes: Int64
    public let newBytes: Int64
    public let newDuration: TimeInterval
    /// Identifies the original as it was when copied, so a video edited since is refused.
    public let sourceVersion: String

    public init(
        id: UUID = UUID(),
        originalID: MediaItem.ID,
        edit: VideoEdit,
        fileURL: URL,
        originalBytes: Int64,
        newBytes: Int64,
        newDuration: TimeInterval,
        sourceVersion: String
    ) {
        self.id = id
        self.originalID = originalID
        self.edit = edit
        self.fileURL = fileURL
        self.originalBytes = originalBytes
        self.newBytes = newBytes
        self.newDuration = newDuration
        self.sourceVersion = sourceVersion
    }

    public var savedBytes: Int64 { originalBytes - newBytes }
}

/// The details of a video that replacing it with a smaller copy must keep.
public struct VideoDetails: Hashable, Sendable {
    public var creationDate: Date?
    public var latitude: Double?
    public var longitude: Double?
    public var isFavorite: Bool
    public var duration: TimeInterval
    public var bytes: Int64
    public var isVideo: Bool
    public var inTestAlbum: Bool

    public init(
        creationDate: Date?,
        latitude: Double?,
        longitude: Double?,
        isFavorite: Bool,
        duration: TimeInterval,
        bytes: Int64,
        isVideo: Bool,
        inTestAlbum: Bool
    ) {
        self.creationDate = creationDate
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.duration = duration
        self.bytes = bytes
        self.isVideo = isVideo
        self.inTestAlbum = inTestAlbum
    }
}

/// One video replaced by its smaller copy, with what was checked afterwards.
public struct VideoReplacement: Hashable, Sendable, Identifiable {
    public let originalID: MediaItem.ID
    public let newID: MediaItem.ID
    public let quality: VideoQuality
    public let wasTrimmed: Bool
    public let keptDate: Bool
    public let keptLocation: Bool
    public let keptFavorite: Bool
    public let keptAlbum: Bool
    /// A video, as long as the part the person kept.
    public let rightLength: Bool
    public let isSmaller: Bool
    /// The original went to Recently Deleted, so it's no longer in the album.
    public let originalGone: Bool
    public let originalBytes: Int64
    public let newBytes: Int64
    public let originalDuration: TimeInterval
    public let newDuration: TimeInterval

    public var id: MediaItem.ID { originalID }
    public var savedBytes: Int64 { originalBytes - newBytes }

    public var keptEverything: Bool {
        keptDate && keptLocation && keptFavorite && keptAlbum && rightLength && isSmaller && originalGone
    }

    public init(
        originalID: MediaItem.ID,
        newID: MediaItem.ID,
        edit: VideoEdit,
        original: VideoDetails,
        new: VideoDetails,
        originalGone: Bool
    ) {
        self.originalID = originalID
        self.newID = newID
        self.quality = edit.quality
        self.wasTrimmed = !edit.trim.isFull(of: original.duration)
        // Photos stores dates to the millisecond; allow for rounding.
        if let a = original.creationDate, let b = new.creationDate {
            keptDate = abs(a.timeIntervalSince(b)) < 1
        } else {
            keptDate = original.creationDate == nil && new.creationDate == nil
        }
        keptLocation = Self.same(original.latitude, new.latitude) && Self.same(original.longitude, new.longitude)
        keptFavorite = original.isFavorite == new.isFavorite
        keptAlbum = new.inTestAlbum
        // Encoders round to whole frames, so allow half a second either way.
        rightLength = new.isVideo && abs(new.duration - edit.trim.clamped(to: original.duration).length) < 0.5
        isSmaller = new.bytes > 0 && new.bytes < original.bytes
        self.originalGone = originalGone
        originalBytes = original.bytes
        newBytes = new.bytes
        originalDuration = original.duration
        newDuration = new.duration
    }

    private static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a - b) < 0.000_01
        default: false
        }
    }
}
