import Foundation
@testable import StorageCore

/// Fixed "now" for test items, so dates never depend on the clock.
let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)

/// Builds a hand-written item so tests can assert exact numbers.
func makeItem(
    id: String,
    category: MediaCategory = .photo,
    format: MediaFormat? = nil,
    bytes: Int64 = 3_000_000,
    daysAgo: Double = 0
) -> MediaItem {
    let resolvedFormat = format ?? {
        switch category {
        case .photo: .heic
        case .video: .hevc
        case .screenshot: .png
        }
    }()
    return MediaItem(
        id: id,
        category: category,
        format: resolvedFormat,
        filename: "\(id).\(resolvedFormat.fileExtension)",
        creationDate: referenceDate.addingTimeInterval(-daysAgo * 86_400),
        pixelWidth: 4032,
        pixelHeight: 3024,
        duration: category == .video ? 30 : nil,
        originalBytes: bytes,
        thumbnailSeed: 1
    )
}

/// A small mixed library with known sizes.
func sampleItems() -> [MediaItem] {
    [
        makeItem(id: "p1", category: .photo, bytes: 4_000_000, daysAgo: 1),
        makeItem(id: "p2", category: .photo, bytes: 2_000_000, daysAgo: 5),
        makeItem(id: "raw", category: .photo, format: .proRAW, bytes: 50_000_000, daysAgo: 10),
        makeItem(id: "v1", category: .video, bytes: 600_000_000, daysAgo: 2),
        makeItem(id: "v2", category: .video, bytes: 40_000_000, daysAgo: 30),
        makeItem(id: "s1", category: .screenshot, bytes: 1_000_000, daysAgo: 3),
        makeItem(id: "s2", category: .screenshot, bytes: 100_000, daysAgo: 4),
    ]
}

/// A stand-in for the test album with at least one item in every scan group.
func sampleScanItems() -> [MediaItem] {
    func photo(_ id: String, bytes: Int64, format: MediaFormat = .heic, traits: MediaTraits = [], burst: String? = nil) -> MediaItem {
        MediaItem(
            id: id, category: .photo, format: format, filename: "\(id).\(format.fileExtension)",
            creationDate: referenceDate, pixelWidth: 4032, pixelHeight: 3024,
            duration: nil, originalBytes: bytes, thumbnailSeed: 1, traits: traits, burstID: burst
        )
    }
    func video(_ id: String, bytes: Int64, width: Int = 1920, height: Int = 1080, format: MediaFormat = .hevc, traits: MediaTraits = []) -> MediaItem {
        MediaItem(
            id: id, category: .video, format: format, filename: "\(id).MOV",
            creationDate: referenceDate, pixelWidth: width, pixelHeight: height,
            duration: 10, originalBytes: bytes, thumbnailSeed: 1, traits: traits
        )
    }
    return [
        photo("still", bytes: 2_000),
        photo("raw", bytes: 50_000, format: .proRAW),
        photo("live", bytes: 4_000, traits: .livePhoto),
        photo("b1a", bytes: 1_000, burst: "B1"),
        photo("b1b", bytes: 1_100, burst: "B1"),
        photo("b2a", bytes: 900, burst: "B2"),
        makeItem(id: "shot", category: .screenshot, bytes: 300),
        video("hd", bytes: 10_000),
        video("4k", bytes: 90_000, width: 2160, height: 3840),
        video("slomo", bytes: 20_000, traits: .slowMotion),
        video("prores", bytes: 400_000, format: .proRes),
    ]
}
