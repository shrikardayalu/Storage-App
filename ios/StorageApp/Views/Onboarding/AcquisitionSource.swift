import Foundation

/// Stable reporting values; changing a label must not split historical totals.
enum AcquisitionSource: String, CaseIterable, Identifiable {
    case tiktok
    case instagram
    case facebook
    case redditForums = "reddit_forums"
    case website = "simpleshrink_website"
    case search = "search_engine"
    case appStore = "app_store"
    case youtube
    case wordOfMouth = "word_of_mouth"
    case article = "article_newsletter"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .redditForums: "Reddit or an online forum"
        case .website: "simpleshrink.com"
        case .search: "Google or another search engine"
        case .appStore: "App Store"
        case .youtube: "YouTube"
        case .wordOfMouth: "A friend or family member"
        case .article: "An article or newsletter"
        case .other: "Somewhere else"
        }
    }

    var detail: String? {
        switch self {
        case .website: "Our website, blog or storage guides"
        default: nil
        }
    }
}
