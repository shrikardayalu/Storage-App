import Foundation

/// A small, fast, deterministic random number generator (SplitMix64).
/// `SystemRandomNumberGenerator` can't be seeded, and demo libraries must be
/// identical on every reset and on every platform.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds the simulated media libraries used in Demo Mode.
///
/// Sizes, dimensions, and durations follow the rough shape of a real iPhone
/// library: mostly 2–5 MB HEIC photos, a few large ProRAW shots, short videos
/// with a long tail of multi-gigabyte 4K clips, and many small screenshots.
public enum MockMediaFactory {
    /// Dates are spread backwards from this fixed point so output never depends on the clock.
    public static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000) // Sept 2026

    public static func makeLibrary(for scenario: DemoScenario) -> [MediaItem] {
        var rng = SeededGenerator(seed: scenario.seed)
        var items: [MediaItem] = []
        items.reserveCapacity(scenario.totalCount)

        // Spread items across ~4 years, newest first, interleaving categories the way a camera roll does.
        var plan: [MediaCategory] = []
        for category in MediaCategory.allCases {
            plan += Array(repeating: category, count: scenario.counts[category] ?? 0)
        }
        plan.shuffle(using: &rng)

        let span: TimeInterval = 4 * 365 * 24 * 3600
        var counters: [MediaCategory: Int] = [:]
        for (index, category) in plan.enumerated() {
            // Recent months are denser, like a real library.
            let position = Double(index) / Double(max(plan.count, 1))
            let age = span * pow(position, 1.6) + Double.random(in: 0..<3600, using: &rng)
            let date = referenceDate.addingTimeInterval(-age)
            counters[category, default: 0] += 1
            items.append(makeItem(
                category: category,
                id: "\(scenario.rawValue)-\(index)",
                number: counters[category]!,
                date: date,
                rng: &rng
            ))
        }
        return items
    }

    static func makeItem(
        category: MediaCategory,
        id: String,
        number: Int,
        date: Date,
        rng: inout SeededGenerator
    ) -> MediaItem {
        let seed = UInt32.random(in: .min ... .max, using: &rng)
        switch category {
        case .photo:
            return makePhoto(id: id, number: number, date: date, seed: seed, rng: &rng)
        case .video:
            return makeVideo(id: id, number: number, date: date, seed: seed, rng: &rng)
        case .screenshot:
            return makeScreenshot(id: id, number: number, date: date, seed: seed, rng: &rng)
        }
    }

    private static func makePhoto(id: String, number: Int, date: Date, seed: UInt32, rng: inout SeededGenerator) -> MediaItem {
        let roll = Double.random(in: 0..<1, using: &rng)
        let format: MediaFormat = roll < 0.04 ? .proRAW : roll < 0.22 ? .jpeg : .heic
        let (width, height): (Int, Int) = switch Int.random(in: 0..<10, using: &rng) {
        case 0..<5: (4032, 3024)
        case 5..<7: (3024, 4032)
        case 7..<9: (5712, 4284)
        default: (4032, 2268)
        }
        let megapixels = Double(width * height) / 1_000_000
        let bytesPerMegapixel: Double = switch format {
        case .proRAW: Double.random(in: 2_400_000...3_200_000, using: &rng)
        case .jpeg: Double.random(in: 380_000...720_000, using: &rng)
        default: Double.random(in: 180_000...420_000, using: &rng)
        }
        let bytes = Int64(megapixels * bytesPerMegapixel)
        return MediaItem(
            id: id,
            category: .photo,
            format: format,
            filename: "IMG_\(String(format: "%04d", 1000 + number % 9000)).\(format.fileExtension)",
            creationDate: date,
            pixelWidth: width,
            pixelHeight: height,
            duration: nil,
            originalBytes: bytes,
            thumbnailSeed: seed
        )
    }

    private static func makeVideo(id: String, number: Int, date: Date, seed: UInt32, rng: inout SeededGenerator) -> MediaItem {
        // Most clips are short; a long tail runs for many minutes.
        let lengthRoll = Double.random(in: 0..<1, using: &rng)
        let duration: TimeInterval = switch lengthRoll {
        case ..<0.55: Double.random(in: 3...30, using: &rng)
        case ..<0.85: Double.random(in: 30...120, using: &rng)
        case ..<0.97: Double.random(in: 120...600, using: &rng)
        default: Double.random(in: 600...1800, using: &rng)
        }
        let qualityRoll = Double.random(in: 0..<1, using: &rng)
        let (width, height, megabitsPerSecond, format): (Int, Int, Double, MediaFormat) = switch qualityRoll {
        case ..<0.02: (3840, 2160, 700, .proRes)
        case ..<0.22: (3840, 2160, 45, .hevc)
        case ..<0.80: (1920, 1080, 16, .hevc)
        default: (1920, 1080, 24, .h264)
        }
        // ProRes is enormous per second, so people only shoot short clips with it.
        let length = format == .proRes ? min(duration, 90) : duration
        let portrait = Bool.random(using: &rng)
        let bytes = Int64(length * megabitsPerSecond * 1_000_000 / 8 * Double.random(in: 0.85...1.1, using: &rng))
        return MediaItem(
            id: id,
            category: .video,
            format: format,
            filename: "IMG_\(String(format: "%04d", 5000 + number % 5000)).MOV",
            creationDate: date,
            pixelWidth: portrait ? height : width,
            pixelHeight: portrait ? width : height,
            duration: length.rounded(),
            originalBytes: bytes,
            thumbnailSeed: seed
        )
    }

    private static func makeScreenshot(id: String, number: Int, date: Date, seed: UInt32, rng: inout SeededGenerator) -> MediaItem {
        let (width, height): (Int, Int) = Int.random(in: 0..<3, using: &rng) == 0 ? (1179, 2556) : (1290, 2796)
        let bytes = Int64(Double.random(in: 150_000...4_200_000, using: &rng))
        return MediaItem(
            id: id,
            category: .screenshot,
            format: .png,
            filename: "Screenshot \(number).PNG",
            creationDate: date,
            pixelWidth: width,
            pixelHeight: height,
            duration: nil,
            originalBytes: bytes,
            thumbnailSeed: seed
        )
    }
}
