import Foundation

/// One photo, video, or screenshot from the library, mapped from a `PHAsset`
/// by the app's PhotoKit scanner. Tests build them by hand.
public struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let category: MediaCategory
    public let format: MediaFormat
    public let filename: String
    public let creationDate: Date
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Video length in seconds; `nil` for photos and screenshots.
    public let duration: TimeInterval?
    /// Size of the file as it was captured.
    public let originalBytes: Int64
    /// Size after any simulated compression. Equal to `originalBytes` until compressed.
    public var currentBytes: Int64
    /// The strongest simulated compression applied so far, if any.
    public var compressionLevel: CompressionLevel?
    /// Seed that picks the placeholder thumbnail artwork and tint.
    public let thumbnailSeed: UInt32
    /// Capture details that matter for grouping, such as Live Photo or slo-mo.
    public let traits: MediaTraits
    /// Shared by every shot in one burst; nil for everything else.
    public let burstID: String?
    /// A Live Photo's paired video, which turning it into a still removes. 0 otherwise.
    public let livePhotoVideoBytes: Int64

    public init(
        id: String,
        category: MediaCategory,
        format: MediaFormat,
        filename: String,
        creationDate: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval?,
        originalBytes: Int64,
        currentBytes: Int64? = nil,
        compressionLevel: CompressionLevel? = nil,
        thumbnailSeed: UInt32,
        traits: MediaTraits = [],
        burstID: String? = nil,
        livePhotoVideoBytes: Int64 = 0
    ) {
        self.id = id
        self.category = category
        self.format = format
        self.filename = filename
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.originalBytes = originalBytes
        self.currentBytes = currentBytes ?? originalBytes
        self.compressionLevel = compressionLevel
        self.thumbnailSeed = thumbnailSeed
        self.traits = traits
        self.burstID = burstID
        self.livePhotoVideoBytes = livePhotoVideoBytes
    }

    public var isCompressed: Bool { compressionLevel != nil }

    /// Bytes already saved on this item by simulated compression.
    public var savedBytes: Int64 { originalBytes - currentBytes }

    /// Whether the simulated compression model supports this item's format at all.
    public var isCompressionEligible: Bool {
        CompressionModel.unsupportedReason(for: self) == nil
    }

    /// A Live Photo that can become a still. Shots in a burst are left to the burst step.
    public var isConvertibleLivePhoto: Bool {
        category == .photo && traits.contains(.livePhoto) && burstID == nil
    }

    public var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000
    }
}

/// Capture details beyond category and format.
public struct MediaTraits: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// A photo with a short paired video.
    public static let livePhoto = MediaTraits(rawValue: 1 << 0)
    /// A high-frame-rate (slo-mo) video.
    public static let slowMotion = MediaTraits(rawValue: 1 << 1)
}
