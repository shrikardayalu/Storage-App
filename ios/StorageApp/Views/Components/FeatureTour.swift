import SwiftUI

struct TourStep {
    let target: String
    let title: String
    let message: String
}

enum FeatureTour: String, CaseIterable {
    case home, videos, photoCleanup, duplicates, livePhotos, screenshots, swipe, bursts, files, library

    var storageKey: String { "tour.v1.\(rawValue)" }

    var steps: [TourStep] {
        switch self {
        case .home:
            return [
                TourStep(target: "storage", title: "Your space at a glance", message: "See how much space is free on your iPhone. Your cleanup results appear here too."),
                TourStep(target: "next", title: "Start here", message: "Scan your library or follow your suggested plan. Open a method for a quick guide before you begin."),
                TourStep(target: "more", title: "Find your way around", message: "More ways to clean are here. Library lets you browse and pick items yourself; Settings has your preferences. Tap the question mark to replay a tour.")
            ]
        case .swipe:
            return [
                TourStep(target: "header", title: "One photo at a time", message: "We suggest photos you may not need. Photos stored in iCloud can take a moment to download."),
                TourStep(target: "items", title: "Left to delete, right to keep", message: "Swipe the photo or use the buttons below. Left adds it to your delete pile; right keeps it."),
                TourStep(target: "controls", title: "You have the final say", message: "Undo takes back a swipe. Nothing is deleted until you tap Delete Photos and confirm. If a photo cannot load, skip it without keeping or deleting it.")
            ]
        case .photoCleanup:
            return [
                TourStep(target: "header", title: "A cleanup plan for you", message: "Review the suggested Live Photos, extra copies and junk. Favorites, edited photos, people, pets, scenery, receipts and documents are left alone."),
                TourStep(target: "items", title: "Check what's included", message: "The summary shows exactly what will change. You can leave old screenshots out with their switch. Use the individual methods to pick photos yourself."),
                confirmation("Clean up when you're ready", "Tap Clean up and confirm. Replaced or removed originals go to Recently Deleted. Follow the guide afterwards to free the space.")
            ]
        case .videos:
            return [scope("videos"),
                TourStep(target: "quality", title: "Smart picks the quality", message: "Smart chooses a quality for each video. Choose another preset to set it yourself, or tap a video to trim it and adjust its quality. Press and hold to play."),
                confirmation("Shrink after you review", "Check the estimated saving, then tap Shrink and confirm. Smaller copies are made first; originals go to Recently Deleted. Keep the app open while it works.")]
        case .duplicates:
            return [scope("photos", suggested: true),
                TourStep(target: "items", title: "Keep the copy you like", message: "Browse Everything, Duplicates and Junk. The best duplicate stays; tap another shot to change the keeper. Press and hold to look closely. In Select, tick the groups or photos to remove."),
                confirmation("Review, then remove", "The bottom button shows what you chose. Nothing changes until you confirm. Removed photos go to Recently Deleted for 30 days.")]
        case .livePhotos:
            return [scope("Live Photos", suggested: true),
                TourStep(target: "items", title: "Keep the photo, lose the motion", message: "All uses the photos suggested for stills. Select lets you pick from every Live Photo. Press and hold to play one before deciding."),
                confirmation("Make stills when you're ready", "The still keeps its date, location, favorite and albums. Only the original Live version goes to Recently Deleted after you confirm.")]
        case .screenshots:
            return [scope("screenshots"),
                TourStep(target: "items", title: "Same screenshot, smaller file", message: "Review the screenshots and estimated saving. In Select, tap the ones to re-save. Press and hold for a closer look."),
                confirmation("Re-save after you review", "Smaller copies are made first. After you confirm, the original PNGs go to Recently Deleted. Follow the guide to finish freeing the space.")]
        case .bursts:
            return [scope("bursts"),
                TourStep(target: "items", title: "Pick your favorite shot", message: "Tap the shot you want to keep in each burst. Press and hold to browse it full size. In Select, tick only the bursts you want to clean."),
                confirmation("Keep the best, clear the rest", "Check the bottom button and confirm. Your keeper stays; the other shots go to Recently Deleted for 30 days.")]
        case .files:
            return [
                TourStep(target: "header", title: "Choose one folder", message: "Pick a folder in Files. SimpleShrink can only review the folder you allow."),
                TourStep(target: "items", title: "Review the files", message: "Look through large files, duplicates and old downloads. Extra duplicate copies start selected; check every file you want to delete."),
                confirmation("File deletion is permanent", "Review the selection carefully before confirming. Files deleted here cannot be recovered through Photos' Recently Deleted.")]
        case .library:
            return [
                TourStep(target: "items", title: "Browse your library", message: "Items are listed biggest first. Tap a group to filter; tap a photo or video to preview it."),
                TourStep(target: "select", title: "Pick what to delete", message: "Tap Select, then choose items. You can change your mind before reviewing the receipt."),
                confirmation("Review your receipt", "The selection bar opens a receipt. Check it before confirming any deletion. Removed photos wait in Recently Deleted for 30 days.")]
        }
    }

    private func scope(_ items: String, suggested: Bool = false) -> TourStep {
        TourStep(target: "scope", title: "All or Select?", message: "All includes \(suggested ? "the suggested" : "every eligible") \(items). Select starts empty so you choose which ones. This switch controls what the bottom button acts on.")
    }

    private func confirmation(_ title: String, _ message: String) -> TourStep {
        TourStep(target: "action", title: title, message: message)
    }
}

private struct TourAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tourTarget(_ name: String) -> some View {
        id("tour.\(name)").anchorPreference(key: TourAnchors.self, value: .bounds) { [name: $0] }
    }

    func featureTour(_ tour: FeatureTour, enabled: Bool = true) -> some View {
        modifier(FeatureTourModifier(tour: tour, enabled: enabled))
    }
}

private struct FeatureTourModifier: ViewModifier {
    let tour: FeatureTour
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage private var seen: Bool
    @State private var step: Int?
    @AccessibilityFocusState private var focused: Bool

    init(tour: FeatureTour, enabled: Bool) {
        self.tour = tour
        self.enabled = enabled
        _seen = AppStorage(wrappedValue: false, tour.storageKey)
    }

    func body(content: Content) -> some View {
        ScrollViewReader { scroll in
            content
                .accessibilityHidden(step != nil)
                .overlayPreferenceValue(TourAnchors.self) { anchors in
                    GeometryReader { geometry in
                        if let step {
                            let instruction = tour.steps[step]
                            let bounds = anchors[instruction.target].map { geometry[$0] }
                            let visible = bounds.flatMap { rect -> CGRect? in
                                let clipped = rect.intersection(CGRect(origin: .zero, size: geometry.size))
                                guard !clipped.isNull, clipped.height >= 20 else { return nil }
                                return CGRect(x: clipped.minX, y: clipped.minY, width: clipped.width, height: min(clipped.height, 180))
                            }
                            ZStack {
                                Path { path in
                                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                                    if let visible { path.addRoundedRect(in: visible.insetBy(dx: -4, dy: -4), cornerSize: CGSize(width: 16, height: 16)) }
                                }
                                .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))
                                .contentShape(Rectangle())
                                .onTapGesture {} // Spotlight taps must never trigger a cleanup.
                                if let visible {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Theme.accent, lineWidth: 3)
                                        .frame(width: visible.width + 8, height: visible.height + 8)
                                        .position(x: visible.midX, y: visible.midY)
                                        .allowsHitTesting(false)
                                }
                                VStack {
                                    if (visible?.midY ?? 0) < geometry.size.height / 2 { Spacer(minLength: 16) }
                                    tooltip(instruction, index: step, height: min(340, geometry.size.height * 0.58))
                                    if (visible?.midY ?? 0) >= geometry.size.height / 2 { Spacer(minLength: 16) }
                                }
                                .padding(16)
                            }
                        }
                    }
                }
                .toolbar {
                    if tour != .home {
                        ToolbarItem(placement: .topBarTrailing) { help }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if tour == .home, step == nil { help.padding(.trailing, 20).padding(.top, 12) }
                }
                .task(id: enabled) {
                    guard enabled, !seen, ScreenshotRoute.current == nil else { return }
                    do { try await Task.sleep(for: .milliseconds(tour == .home ? 1600 : 500)) } catch { return }
                    guard !Task.isCancelled else { return }
                    step = 0
                }
                .onChange(of: enabled) { _, active in if !active { step = nil } }
                .onChange(of: step) { _, index in
                    guard let index else { return }
                    if reduceMotion { scroll.scrollTo("tour.\(tour.steps[index].target)", anchor: .center) }
                    else { withAnimation(.easeInOut(duration: 0.25)) { scroll.scrollTo("tour.\(tour.steps[index].target)", anchor: .center) } }
                    focused = true
                }
        }
    }

    private var help: some View {
        Button { step = 0 } label: {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Show this screen's tour")
        .disabled(!enabled)
    }

    private func tooltip(_ instruction: TourStep, index: Int, height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(index + 1) of \(tour.steps.count)").font(.caption).foregroundStyle(.secondary)
                Text(instruction.title).font(.headline).accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
                Text(instruction.message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Skip tour") { finish() }.frame(minHeight: 44)
                    Spacer()
                    if index > 0 { Button("Back") { step = index - 1 }.frame(minHeight: 44) }
                    Button(index == tour.steps.count - 1 ? "Got it" : "Next") {
                        if index == tour.steps.count - 1 { finish() } else { step = index + 1 }
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(18)
        }
        .frame(height: height)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.accent, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { finish() }
    }

    private func finish() { seen = true; step = nil }
}
