import Foundation
import StorageCore

/// Lets CI open a specific screen at launch so it can take screenshots without
/// UI automation, e.g. `xcrun simctl launch <device> <bundle id> -screenshotScreen review`.
/// Launch arguments land in UserDefaults' argument domain; nothing is written to disk.
/// With no argument the app starts normally.
enum ScreenshotRoute: String {
    case home
    case library
    case libraryList = "library-list"
    case librarySelecting = "library-selecting"
    case review
    case settings

    static var current: ScreenshotRoute? {
        UserDefaults.standard.string(forKey: "screenshotScreen").flatMap(ScreenshotRoute.init(rawValue:))
    }

    @MainActor
    func apply(to model: AppModel) {
        switch self {
        case .home:
            model.selectedTab = .home
        case .library:
            model.showLibrary(filter: .all)
        case .libraryList:
            model.libraryLayout = .list
            model.showLibrary(filter: .videos)
        case .librarySelecting:
            model.showLibrary(filter: .screenshots, sort: .newestFirst)
            model.isSelecting = true
            for item in model.visibleItems.prefix(7) {
                model.toggleSelection(item)
            }
        case .review:
            model.reviewCleanup()
        case .settings:
            model.selectedTab = .settings
        }
    }
}
