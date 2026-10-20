import Foundation

/// One simulated photo, video, or screenshot.
///
/// In Phase 1 every `MediaItem` is generated in memory by `MockMediaFactory`.
/// A later PhotoKit-backed service will map `PHAsset`s onto this same type, so
/// the UI never needs to know where an item came from.
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
        thumbnailSeed: UInt32
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
    }

    public var isCompressed: Bool { compressionLevel != nil }

    /// Bytes already saved on this item by simulated compression.
    public var savedBytes: Int64 { originalBytes - currentBytes }

    /// Whether the simulated compression model supports this item's format at all.
    public var isCompressionEligible: Bool {
        CompressionModel.unsupportedReason(for: self) == nil
    }

    public var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000
    }
}
