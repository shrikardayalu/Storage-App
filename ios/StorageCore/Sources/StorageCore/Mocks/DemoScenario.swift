import Foundation

/// The predefined simulated libraries a tester can switch between in Settings.
public enum DemoScenario: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case typical
    case large
    case empty

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .typical: "Typical Library"
        case .large: "Large Library"
        case .empty: "Empty Library"
        }
    }

    public var summary: String {
        switch self {
        case .typical: "About 3,700 items: photos, a few hundred videos, and screenshots."
        case .large: "About 20,000 items, for testing scrolling, sorting, and filtering at scale."
        case .empty: "No media at all, for checking empty states."
        }
    }

    /// How many items of each category the scenario generates.
    public var counts: [MediaCategory: Int] {
        switch self {
        case .typical: [.photo: 2_900, .video: 340, .screenshot: 460]
        case .large: [.photo: 15_600, .video: 1_900, .screenshot: 2_500]
        case .empty: [:]
        }
    }

    public var totalCount: Int { counts.values.reduce(0, +) }

    /// Fixed seed so a scenario produces the identical library on every reset.
    var seed: UInt64 {
        switch self {
        case .typical: 0x5EED_0001
        case .large: 0x5EED_0002
        case .empty: 0x5EED_0003
        }
    }
}
