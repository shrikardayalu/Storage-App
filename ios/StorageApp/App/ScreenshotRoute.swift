import Foundation
import StorageCore

/// Lets CI open a specific screen at launch so it can take screenshots without
/// UI automation, e.g. `xcrun simctl launch <device> <bundle id> -screenshotScreen library`.
/// Launch arguments land in UserDefaults' argument domain; nothing is written to disk.
/// With no argument the app starts normally.
enum ScreenshotRoute: String {
    case home
    case library
    case settings
    /// The Recently Deleted guide after a sample delete. Sample numbers only; nothing is deleted.
    case guide

    static var current: ScreenshotRoute? {
        UserDefaults.standard.string(forKey: "screenshotScreen").flatMap(ScreenshotRoute.init(rawValue:))
    }

    @MainActor
    func apply(to model: AppModel) {
        switch self {
        case .home: model.selectedTab = .home
        case .library: model.showLibrary(group: nil)
        case .settings: model.selectedTab = .settings
        case .guide:
            let receipt = DeletionReceipt(deleted: ["sample-1", "sample-2", "sample-3"], albumCountBefore: 48, albumCountAfter: 45,
                                          deletedBytes: 1_240_000_000, onlyApprovedRemoved: true)
            model.guide = CleanupGuide(kind: .deleted(receipt), removedIDs: Array(receipt.deleted), expectedBytes: receipt.deletedBytes)
        }
    }
}
