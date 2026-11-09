import Foundation
import SwiftUI
import UIKit

/// Things only the person can clear: other apps' data and Settings pages iOS
/// keeps the app out of. Each guide walks through the steps, then measures
/// free space against the reading taken when it opened (Build Plan step 10).
///
/// Steps follow iOS 17 to 26 and WhatsApp 25, and still need checking on a
/// phone (Build Plan step 10). When an update moves a button, change it here;
/// `GuidesAndResultsTests` checks every guide still has steps and drawings.
enum OtherAppGuide: String, CaseIterable, Identifiable {
    case whatsapp, messages, offloadApps, safari, downloads

    var id: String { rawValue }

    /// iOS 18 moved each app's settings under Settings → Apps.
    static var appsInSettings: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0))
    }

    /// "Settings → Apps → Safari", or "Settings → Safari" on iOS 17.
    static func settingsPath(for app: String) -> String {
        appsInSettings ? "Settings \u{2192} Apps \u{2192} \(app)" : "Settings \u{2192} \(app)"
    }

    static let iPhoneStoragePath = "Settings \u{2192} General \u{2192} iPhone Storage"

    /// Where the guide's Open button goes.
    enum Destination {
        case whatsapp
        /// SimpleShrink's own page in Settings: apps can't open any other page.
        case settings

        var label: String {
            switch self {
            case .whatsapp: "Open WhatsApp"
            case .settings: "Open Settings"
            }
        }

        var url: URL? {
            switch self {
            case .whatsapp: URL(string: "whatsapp://")
            case .settings: URL(string: UIApplication.openSettingsURLString)
            }
        }

        /// Said under the button, so landing on the wrong page isn't a surprise.
        var hint: String? {
            switch self {
            case .whatsapp: nil
            case .settings: "Settings opens on SimpleShrink's own page. Tap Back at the top left to reach the rest of Settings."
            }
        }
    }

    struct Step {
        let title: String
        let note: String
        let scene: [SceneMark]
        /// Something that can't be undone, shown in red.
        var warning: String? = nil
        /// Shows the guide's Open button on this step.
        var opens = false
    }

    var title: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .messages: "Messages"
        case .offloadApps: "Offload unused apps"
        case .safari: "Safari"
        case .downloads: "Downloaded shows and music"
        }
    }

    /// The line on Home.
    var subtitle: String {
        switch self {
        case .whatsapp: "Big videos and photos people sent you"
        case .messages: "Large attachments, and keeping 1 year"
        case .offloadApps: "Apps you don't use, data kept"
        case .safari: "History and website data"
        case .downloads: "TV, Music and streaming downloads"
        }
    }

    var illustration: Illustration {
        switch self {
        case .whatsapp: .phoneSparkle
        case .messages: .screenshot
        case .offloadApps: .stackLarge
        case .safari: .umbrella
        case .downloads: .video
        }
    }

    var destination: Destination {
        self == .whatsapp ? .whatsapp : .settings
    }

    /// The first page: what this frees, and why SimpleShrink can't do it itself.
    var intro: String {
        switch self {
        case .whatsapp:
            "WhatsApp keeps every video, photo and voice note from your chats, and big group chats add up fast. iOS keeps other apps' files locked away, so SimpleShrink can't clear them, but WhatsApp shows you exactly what's big."
        case .messages:
            "Videos and photos in your texts stay on your iPhone for as long as the messages do. Only you can clear them, from Settings."
        case .offloadApps:
            "Offloading removes an app but keeps its documents and data. Its icon stays, and tapping it downloads the app again, right where you left off. iOS hides other apps from SimpleShrink, so this is done in Settings."
        case .safari:
            "Safari keeps websites' saved files so pages load faster. Clearing them frees space, but signs you out of websites."
        case .downloads:
            "Shows, films, songs and podcasts you downloaded to watch or listen offline can take gigabytes. You can stream them again any time."
        }
    }

    var steps: [Step] {
        switch self {
        case .whatsapp: Self.whatsappSteps
        case .messages: Self.messagesSteps
        case .offloadApps: Self.offloadSteps
        case .safari: Self.safariSteps
        case .downloads: Self.downloadSteps
        }
    }

    /// On the measure page when nothing came back yet.
    var notBackHint: String {
        switch self {
        case .whatsapp: "WhatsApp deletes right away. If the number hasn't moved, the items may still be selected but not deleted: open Manage Storage again and check the chat's size went down."
        case .messages: "If you deleted whole conversations, they wait in Messages' Recently Deleted for up to 30 days. Empty it there, then measure again."
        case .offloadApps: "iOS can take a minute to finish offloading. Look for a small cloud next to the app's name on your Home Screen, then measure again."
        case .safari: "Website data is often small. If the number hasn't moved much, Safari wasn't using much space."
        case .downloads: "Some apps take a moment to remove downloads. Check the app's size in iPhone Storage went down, then measure again."
        }
    }

    // MARK: Steps

    private static let whatsappGreen = Color(hex: 0x25D366)

    private static var whatsappSteps: [Step] {
        [
            Step(
                title: "Open WhatsApp",
                note: "Then tap Settings at the bottom right.",
                scene: OtherAppScenes.homeScreen(app: "WhatsApp", color: whatsappGreen, note: "then tap Settings", seed: 700),
                opens: true
            ),
            Step(
                title: "Tap Storage and Data",
                note: "Then Manage Storage at the top. WhatsApp adds up every chat, which can take a few seconds.",
                scene: OtherAppScenes.list("Settings", rows: [
                    .init("Account"), .init("Privacy"), .init("Chats"), .init("Notifications"), .init("Storage and Data"),
                ], target: 4, note: "then Manage Storage", seed: 720)
            ),
            Step(
                title: "Start with the biggest",
                note: "\u{201C}Larger than 5 MB\u{201D} is at the top, and your chats are below, biggest first. Tap one to see what's in it.",
                scene: OtherAppScenes.list("Manage Storage", rows: [
                    .init("Larger than 5 MB", .text("1.4 GB")),
                    .init("Forwarded many\ntimes", .text("310 MB")),
                    .init("Family", .text("2.2 GB")),
                    .init("Football group", .text("960 MB")),
                    .init("Sam", .text("140 MB")),
                ], target: 0, note: "biggest first", seed: 740)
            ),
            Step(
                title: "Select, pick, Delete",
                note: "Tap Select, pick the videos and photos you don't need (or Select All), then tap Delete. Media is sorted newest first; tap the sort button to see the largest first.",
                scene: OtherAppScenes.list("Larger than 5 MB", rows: [
                    .init("Video, 3:12", .check), .init("Video, 0:48", .check), .init("Photo", .none),
                    .init("Video, 1:05", .check), .init("Delete Items", .none, color: Theme.tomato),
                ], target: 4, note: "gone right away", seed: 760),
                warning: "WhatsApp deletes these straight away. There's no Recently Deleted to get them back."
            ),
            Step(
                title: "Stop it filling up again",
                note: "In Settings \u{2192} Storage and Data, set Media Auto-Download to Wi-Fi or No for videos. And in Settings \u{2192} Chats, turning off Save to Photos stops a second copy of everything landing in your Photos library.",
                scene: OtherAppScenes.list("Chats", rows: [
                    .init("Chat Backup"), .init("Save to Photos", .toggle(on: false)), .init("Keep chats\narchived", .toggle(on: true)),
                ], target: 1, note: "one copy is enough", seed: 780)
            ),
        ]
    }

    private static var messagesSteps: [Step] {
        [
            Step(
                title: "Open iPhone Storage",
                note: "Go to \(iPhoneStoragePath) and wait for the list to fill in. Then tap Messages.",
                scene: OtherAppScenes.list("iPhone Storage", rows: [
                    .init("Photos", .text("38 GB")), .init("Messages", .text("6.2 GB")), .init("WhatsApp", .text("4.1 GB")), .init("Music", .text("2.0 GB")),
                ], target: 1, note: "tap Messages", seed: 800),
                opens: true
            ),
            Step(
                title: "Review Large Attachments",
                note: "It lists every video, photo and file in your texts, biggest first. Tap Edit to pick several.",
                scene: OtherAppScenes.list("Messages", rows: [
                    .init("Review Large\nAttachments"), .init("Top Conversations"), .init("Photos", .text("2.4 GB")), .init("Videos", .text("3.1 GB")),
                ], target: 0, note: "biggest first", seed: 820)
            ),
            Step(
                title: "Swipe left, Delete",
                note: "Swipe left on anything you don't need, or tap Edit, pick several, and tap the trash. The message stays in the chat; only the attachment goes.",
                scene: OtherAppScenes.list("Large Attachments", rows: [
                    .init("IMG_2041.MOV", .swipeDelete), .init("IMG_1877.MOV", .text("188 MB")), .init("Holiday.zip", .text("96 MB")),
                ], target: 0, note: "one swipe each", seed: 840)
            ),
            Step(
                title: "Keep Messages: 1 Year",
                note: "Go to \(settingsPath(for: "Messages")) \u{2192} Keep Messages and pick 1 Year. iOS then deletes texts and attachments older than a year, now and from then on.",
                scene: OtherAppScenes.list("Keep Messages", rows: [
                    .init("30 Days", .none), .init("1 Year", .check), .init("Forever", .none),
                ], target: 1, note: "older texts are erased", noteColor: Theme.tomato, seed: 860),
                warning: "iOS asks to delete older messages. That erases every text and attachment over a year old, for good. With Messages in iCloud on, they're erased on your other devices too."
            ),
            Step(
                title: "Empty Messages' Recently Deleted",
                note: "Whole conversations you delete wait here for up to 30 days. In Messages, tap Edit or Filters at the top left, then Recently Deleted, then Delete All.",
                scene: OtherAppScenes.list("Messages", rows: [
                    .init("All Messages"), .init("Known Senders"), .init("Unknown Senders"), .init("Recently Deleted"),
                ], target: 3, note: "only if you deleted chats", seed: 880)
            ),
        ]
    }

    private static var offloadSteps: [Step] {
        [
            Step(
                title: "Open iPhone Storage",
                note: "Go to \(iPhoneStoragePath) and wait for the list to fill in.",
                scene: OtherAppScenes.list("iPhone Storage", rows: [
                    .init("Offload Unused\nApps", .text("Enable", Theme.accent)), .init("Game", .text("3.4 GB")), .init("Video Editor", .text("1.9 GB")), .init("Airline", .text("620 MB")),
                ], target: 0, note: "save 4.2 GB", seed: 900),
                opens: true
            ),
            Step(
                title: "Enable Offload Unused Apps",
                note: "If it's suggested, tap Enable. From then on, iOS offloads apps you haven't used in a while when space runs low. It's also in \(settingsPath(for: "App Store")).",
                scene: OtherAppScenes.list("App Store", rows: [
                    .init("Automatic\nDownloads"), .init("App Updates", .toggle(on: true)), .init("Offload Unused\nApps", .toggle(on: true)),
                ], target: 2, note: "your data stays", seed: 920)
            ),
            Step(
                title: "Or offload one app",
                note: "Tap a big app you rarely use in the iPhone Storage list, then Offload App, and confirm. Its documents and data stay; it downloads again when you tap its icon.",
                scene: OtherAppScenes.list("Game", rows: [
                    .init("App Size", .text("3.1 GB")), .init("Documents & Data", .text("300 MB")), .init("Offload App", .none, color: Theme.accent), .init("Delete App", .none, color: Theme.tomato),
                ], target: 2, note: "not Delete App", seed: 940)
            ),
        ]
    }

    private static var safariSteps: [Step] {
        [
            Step(
                title: "Open Safari's settings",
                note: "Go to \(settingsPath(for: "Safari")).",
                scene: OtherAppScenes.list(appsInSettings ? "Apps" : "Settings", rows: [
                    .init("Messages"), .init("Music"), .init("Photos"), .init("Safari"),
                ], target: 3, note: "tap Safari", seed: 1000),
                opens: true
            ),
            Step(
                title: "Clear History and Website Data",
                note: "It's near the bottom. Pick All History and tap Clear History. Your bookmarks and Reading List stay.",
                scene: OtherAppScenes.list("Safari", rows: [
                    .init("Search Engine"), .init("Passwords"), .init("Clear History and\nWebsite Data", .none, color: Theme.accent), .init("Advanced"),
                ], target: 2, note: "signs you out of sites", noteColor: Theme.tomato, seed: 1020),
                warning: "This signs you out of websites. If Safari syncs with iCloud, your history is cleared on your other devices too."
            ),
            Step(
                title: "Or keep your history",
                note: "Tap Advanced \u{2192} Website Data instead. It lists each site's data, biggest first: swipe left to delete one, or tap Remove All Website Data.",
                scene: OtherAppScenes.list("Website Data", rows: [
                    .init("news-site.com", .swipeDelete), .init("video-site.com", .text("84 MB")), .init("maps-site.com", .text("31 MB")), .init("Remove All", .none, color: Theme.tomato),
                ], target: 3, note: "history stays", seed: 1040)
            ),
        ]
    }

    private static var downloadSteps: [Step] {
        [
            Step(
                title: "See which apps have downloads",
                note: "Go to \(iPhoneStoragePath). TV, Music, Podcasts and streaming apps near the top usually have downloads in them.",
                scene: OtherAppScenes.list("iPhone Storage", rows: [
                    .init("TV", .text("4.2 GB")), .init("Streaming app", .text("3.1 GB")), .init("Music", .text("2.8 GB")), .init("Podcasts", .text("900 MB")),
                ], target: 0, note: "look for downloads", seed: 1100),
                opens: true
            ),
            Step(
                title: "TV and Music: swipe to delete",
                note: "Tap TV or Music in that list. Under the app's size, downloaded shows, albums and songs are listed. Swipe left on one and tap Delete, or tap Edit to remove several.",
                scene: OtherAppScenes.list("TV", rows: [
                    .init("A Show, Season 1", .swipeDelete), .init("A Film", .text("2.1 GB")), .init("Another Show", .text("880 MB")),
                ], target: 0, note: "stream it again any time", seed: 1120)
            ),
            Step(
                title: "Let Music tidy itself",
                note: "In \(settingsPath(for: "Music")), turn on Optimize Storage. When space runs low, iOS removes songs you haven't played in a while.",
                scene: OtherAppScenes.list("Music", rows: [
                    .init("Downloads"), .init("Optimize Storage", .toggle(on: true)), .init("Automatic\nDownloads", .toggle(on: false)),
                ], target: 1, note: "only songs you don't play", seed: 1140)
            ),
            Step(
                title: "Streaming apps keep their own",
                note: "Apps like Netflix, Spotify and Prime Video keep downloads inside the app. Open the app's Downloads page and delete there, or look for a \u{201C}remove all downloads\u{201D} option in its settings.",
                scene: OtherAppScenes.list("Downloads", rows: [
                    .init("Episode 4", .swipeDelete), .init("Episode 5", .text("410 MB")), .init("A Film", .text("1.6 GB")),
                ], target: 0, note: "inside each app", seed: 1160)
            ),
        ]
    }
}
