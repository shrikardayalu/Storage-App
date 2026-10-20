import Foundation
@testable import StorageCore

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
        creationDate: MockMediaFactory.referenceDate.addingTimeInterval(-daysAgo * 86_400),
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
