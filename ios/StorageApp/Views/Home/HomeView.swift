import StorageCore
import SwiftUI

/// Dashboard: the phone's real storage, and what takes up space in the test album.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(OnboardingAnswers.planDismissedKey) private var planDismissed = false
    /// Re-reads the plan when onboarding finishes over Home.
    @AppStorage(OnboardingAnswers.completedKey) private var onboardingDone = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if showsPlan {
                    PlanCard(picks: OnboardingAnswers.load().picks) {
                        withAnimation(.easeInOut) { planDismissed = true }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                DeviceStorageCard()
                StorageHealthCard()
                if model.freed.total > 0 {
                    ResultsCard(bytes: model.freed.total)
                }
                TestAlbumCard()
                if let waiting = model.spaceWaiting {
                    SpaceWaitingCard(bytes: waiting)
                }
                if let scan = model.albumScan, scan.total.count > 0 {
                    CleanupSection()
                    groupSection(scan)
                }
                FilesSection()
                OtherAppsSection()
                SafetyNote()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(PaperBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $model.isShowingResults) { ResultsView() }
        // Duplicates are checked again after a relaunch, so their card and the
        // plan show a real number even when the tool itself needs Pro.
        .task(id: model.albumScan?.total.count) {
            if model.albumScan != nil, model.junkReport == nil { await model.findJunk() }
        }
    }

    /// The onboarding picks, until they're closed. Needs a scan for its numbers.
    private var showsPlan: Bool {
        onboardingDone && !planDismissed && model.albumScan != nil && !OnboardingAnswers.load().picks.isEmpty
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            IllustrationView(.phoneSparkle, size: 48)
            Text("Storage App")
                .font(.display(34))
                .boiling()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            TestModeBadge()
        }
        .padding(.top, 12)
    }

    private func groupSection(_ scan: LibraryScan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where the space is")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(ScanGroup.allCases.filter { scan[$0].count > 0 }) { group in
                CategoryCard(
                    illustration: Illustration.forGroup(group),
                    title: group.title,
                    subtitle: group.detail,
                    total: scan[group]
                ) { model.showLibrary(group: group) }
            }
        }
    }
}

/// The phone's real used and free space, with two decimals like Settings.
private struct DeviceStorageCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iPhone storage")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if let snapshot = model.deviceStorage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SizeText(bytes: snapshot.availableBytes, style: .largeTitle, unitStyle: .title2, precision: .twoDecimals)
                    Text("free")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                UsageBar(fraction: snapshot.usedFraction)
                HStack {
                    Text("\(ByteFormatter.string(snapshot.usedBytes, precision: .twoDecimals)) of \(ByteFormatter.string(snapshot.advertisedCapacityBytes)) used")
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.updatedText(since: snapshot.date, now: context.date))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if model.storageReadFailed {
                Text("Couldn't read this iPhone's storage.")
                    .font(.subheadline)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            }

            Text("Settings may show slightly different numbers.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .sticker(padding: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let snapshot = model.deviceStorage else {
            return model.storageReadFailed ? "iPhone storage unavailable" : "iPhone storage, loading"
        }
        return "iPhone storage, \(ByteFormatter.accessibilityString(snapshot.availableBytes, precision: .twoDecimals)) free, "
            + "\(ByteFormatter.accessibilityString(snapshot.usedBytes, precision: .twoDecimals)) of "
            + "\(ByteFormatter.accessibilityString(snapshot.advertisedCapacityBytes)) used. "
            + Self.updatedText(since: snapshot.date, now: Date())
    }

    /// "Updated just now", "Updated 5 min ago", "Updated 2 hr ago", or a date.
    static func updatedText(since date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "Updated just now"
        case ..<60: return "Updated \(minutes) min ago"
        case ..<(24 * 60): return "Updated \(minutes / 60) hr ago"
        default: return "Updated \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

/// Build Plan step 9: warns when space is low or shrinking fast, suggests a
/// restart, and shows what the restart gave back on the next open.
private struct StorageHealthCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let result = model.restartCoach.result {
            resultCard(result)
        } else if model.restartCoach.pending != nil {
            waitingCard
        } else if let warning = model.storageWarning {
            warningCard(warning)
        }
    }

    private func warningCard(_ warning: StorageWarning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IllustrationView(.reset, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(warning))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("a restart sometimes gives some back")
                        .font(.hand(16))
                        .foregroundStyle(Theme.tomato)
                }
            }
            Button("Show Me How") { model.isShowingRestartGuide = true }
                .buttonStyle(.soft)
        }
        .sticker(padding: 16)
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IllustrationView(.reset, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for your restart")
                        .font(.headline)
                    Text("Open Storage App again afterwards to see what came back.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Show Steps") { model.isShowingRestartGuide = true }
                    .buttonStyle(.soft)
                Button("Not Now") { model.cancelRestart() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.leading, 8)
            }
        }
        .card(padding: 16)
    }

    private func resultCard(_ result: RestartResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IllustrationView(result.gaveSpaceBack ? .piggy : .reset, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                if result.gaveSpaceBack {
                    Text("You got back \(ByteFormatter.string(result.gainedBytes, precision: .twoDecimals)) from a restart")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("It's counted in your results.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The restart didn't free much this time")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("That's normal when iOS has little to tidy up. The cleanups below are where the space is.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button { model.dismissRestartResult() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Dismiss")
        }
        .sticker(fill: Theme.mintSoft, padding: 16)
    }

    private func title(_ warning: StorageWarning) -> String {
        switch warning {
        case .low(let available):
            "Only \(ByteFormatter.string(available, precision: .twoDecimals)) free"
        case .shrinking(let lost, let days):
            "Free space dropped \(ByteFormatter.string(lost, precision: .twoDecimals)) in \(days) days"
        }
    }
}

/// A single used-of-capacity bar.
private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.mint)
                .frame(width: max(6, proxy.size.width * CGFloat(fraction)))
        }
        .frame(height: 18)
        .padding(3)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Test Mode: scans the "Storage App Test" album (read-only) and opens the Library.
private struct TestAlbumCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test album")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if let scan = model.albumScan {
                Button {
                    model.showLibrary(group: nil)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            SizeText(bytes: scan.total.bytes, style: .title, unitStyle: .headline, precision: .twoDecimals)
                            Text("\(scan.total.count.formatted()) items · \(ScanSource.title(for: model.photoAccess))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Test album, \(scan.total.count) items, \(ByteFormatter.accessibilityString(scan.total.bytes, precision: .twoDecimals))")
                .accessibilityHint("Shows every item in the Library, biggest first.")
                .accessibilityAddTraits(.isButton)
            } else {
                Text("See what takes up space in the \u{201C}\(TestMode.albumName)\u{201D} album. Scanning only reads it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = model.scanError {
                ScanErrorView(error: error)
            }

            Button {
                Task { await model.scanTestAlbum() }
            } label: {
                if model.isScanning {
                    ProgressView()
                } else {
                    Text(model.albumScan == nil ? "Scan Test Album" : "Scan Again")
                }
            }
            .buttonStyle(.soft)
            .disabled(model.isScanning)
        }
        .card(padding: 18)
    }
}

/// Space from the latest cleanup still sitting in Recently Deleted.
private struct SpaceWaitingCard: View {
    let bytes: Int64
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.reopenGuide()
        } label: {
            HStack(spacing: 14) {
                IllustrationView(.trash, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ByteFormatter.string(bytes, precision: .twoDecimals)) waiting in Recently Deleted")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("show me how to get it back")
                        .font(.hand(16))
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .sticker(fill: Theme.mintSoft, padding: 16)
        }
        .buttonStyle(.plain)
    }
}

/// Opens a cleanup method: its tool, its guide, or the paywall when it needs Pro.
private struct MethodLink<Label: View>: View {
    let method: CleanupMethod
    let onPaywall: () -> Void
    @ViewBuilder var label: Label
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases

    var body: some View {
        if method.isPro && purchases.requiresPro {
            Button(action: onPaywall) { label }
                .buttonStyle(.plain)
        } else if let guide = method.guide {
            Button { model.open(guide) } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink { destination } label: { label }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch method {
        case .shrinkVideos: VideosView()
        case .photoCleanup: PhotoCleanupView()
        case .duplicates: JunkReviewView()
        case .livePhotos: LivePhotoStillsView()
        case .screenshots: ScreenshotResaveView()
        case .swipe: SwipeCleanView()
        case .bursts: BurstPicksView()
        case .chatAttachments: EmptyView()
        }
    }
}

/// What they picked in onboarding, as a checklist that opens each tool, in
/// `PlanOrder`: the free fix that frees the most leads ("start here"), Pro
/// picks follow and open the paywall when tapped. Done ones sink to the bottom.
private struct PlanCard: View {
    let picks: [CleanupMethod]
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @State private var showingPaywall = false

    var body: some View {
        let rows = ordered
        let next = rows.first { !isDone($0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your plan")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(next == nil && rows.allSatisfy(isDone) ? "all done, nice" : "from your picks")
                    .font(.hand(16))
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide plan")
            }
            ForEach(rows) { method in
                MethodLink(method: method, onPaywall: { showingPaywall = true }) {
                    PlanRow(method: method, bytes: model.saving(for: method), isDone: isDone(method),
                            isLocked: isLocked(method), isNext: method == next)
                }
                .disabled(isDone(method))
            }
        }
        .sticker(padding: 16)
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallFlow(context: PaywallContext(proBytes: model.proSaving))
                .environment(purchases)
                .tint(Theme.accent)
        }
    }

    private func isLocked(_ method: CleanupMethod) -> Bool {
        method.isPro && purchases.requiresPro
    }

    /// Measured, with nothing left to free. Guides can't be measured, so they stay open.
    private func isDone(_ method: CleanupMethod) -> Bool {
        model.saving(for: method) == 0
    }

    /// `PlanOrder`, with anything already done moved to the end.
    private var ordered: [CleanupMethod] {
        let planned = model.planOrder(picks)
        return planned.filter { !isDone($0) } + planned.filter(isDone)
    }
}

private struct PlanRow: View {
    let method: CleanupMethod
    let bytes: Int64?
    let isDone: Bool
    let isLocked: Bool
    let isNext: Bool

    var body: some View {
        HStack(spacing: 12) {
            InkCheck(isOn: isDone, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(method.title)
                        .font(.headline)
                        .strikethrough(isDone, color: .secondary)
                    if isLocked { ProTag() }
                }
                Text(status)
                    .font(isNext ? Font.hand(16) : .caption)
                    .foregroundStyle(isNext ? Theme.accent : Color.secondary)
            }
            Spacer(minLength: 8)
            if let bytes, bytes > 0 {
                Text("\u{2212}" + ByteFormatter.string(bytes, precision: .twoDecimals))
                    .font(.metric(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(isLocked ? Theme.ink : Theme.accent)
            }
            if !isDone {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isNext ? Theme.mintSoft : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        if isDone { return "done" }
        if isNext { return "start here" }
        return method.pitch
    }
}

/// What the app can do to the test album. Pro methods (see
/// `CleanupMethod.isPro`) open the paywall instead until Pro is unlocked.
private struct CleanupSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @State private var showingPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Clean up")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("only in the test album")
                    .font(.hand(16))
                    .foregroundStyle(Theme.accent)
            }
            ForEach(methods) { method in
                MethodLink(method: method, onPaywall: { showingPaywall = true }) {
                    ActionCard(
                        illustration: method.illustration,
                        title: method.title,
                        subtitle: subtitle(for: method),
                        figure: figure(for: method),
                        isPro: method.isPro && purchases.requiresPro
                    )
                }
            }
            Button {
                model.isSelecting = true
                model.showLibrary(group: nil)
            } label: {
                ActionCard(
                    illustration: .trash,
                    title: "Pick what to delete",
                    subtitle: "Review it on a receipt before anything goes",
                    figure: nil
                )
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallFlow(context: PaywallContext(proBytes: model.proSaving))
                .environment(purchases)
                .tint(Theme.accent)
        }
    }

    /// The album tools with something to work on. The photo-checking ones
    /// always show, so they can run their first check.
    private var methods: [CleanupMethod] {
        [CleanupMethod.photoCleanup, .swipe, .shrinkVideos, .livePhotos, .screenshots, .duplicates, .bursts].filter { method in
            switch method {
            case .livePhotos: !model.convertibleLivePhotos.isEmpty
            case .screenshots: !model.resavableScreenshots.isEmpty
            case .shrinkVideos: !model.shrinkableVideos.isEmpty
            case .bursts: !model.bursts.isEmpty
            case .photoCleanup, .swipe, .duplicates: true
            case .chatAttachments: false
            }
        }
    }

    private func subtitle(for method: CleanupMethod) -> String {
        switch method {
        case .livePhotos:
            let count = model.convertibleLivePhotos.count
            return "\(count) Live \(count == 1 ? "Photo" : "Photos"), same photos without the video"
        case .screenshots:
            let count = model.resavableScreenshots.count
            return "\(count) \(count == 1 ? "screenshot" : "screenshots") saved as PNG, same look, far smaller"
        case .shrinkVideos:
            let count = model.shrinkableVideos.count
            return "\(count) \(count == 1 ? "video" : "videos"), compress or trim, same memories"
        case .bursts:
            let count = model.bursts.count
            return "\(count) \(count == 1 ? "burst" : "bursts"), keep one shot, remove the rest"
        case .duplicates:
            guard let report = model.junkReport else { return "Copies, blurry and black shots, receipts, old screenshots" }
            if report.isEmpty { return "Nothing found. Look again after adding photos" }
            return "\(report.suggestedCount) \(report.suggestedCount == 1 ? "photo" : "photos") to review, best copies kept"
        case .photoCleanup:
            guard let plan = model.photoCleanupPlan else { return method.pitch }
            if plan.isEmpty { return "Nothing to clean right now" }
            return "\(plan.stillCount + plan.remove.count) photos in one tap, best copies kept"
        case .swipe:
            guard let report = model.junkReport else { return method.pitch }
            let count = SwipeCandidate.all(from: report).count
            if count == 0 { return "Nothing to swipe right now" }
            return "\(count) likely \(count == 1 ? "delete" : "deletes"), one at a time"
        case .chatAttachments:
            return method.pitch
        }
    }

    private func figure(for method: CleanupMethod) -> String? {
        guard let bytes = model.saving(for: method), bytes > 0 else { return nil }
        return "\u{2212}" + ByteFormatter.string(bytes, precision: .twoDecimals)
    }
}

/// Files the person keeps outside Photos, in one folder they pick.
private struct FilesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Files")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("only a folder you pick")
                    .font(.hand(16))
                    .foregroundStyle(Theme.accent)
            }
            NavigationLink {
                FilesCleanupView()
            } label: {
                ActionCard(
                    illustration: .stackLarge,
                    title: "Clean up a folder",
                    subtitle: subtitle,
                    figure: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitle: String {
        guard let scan = model.folderScan else { return "Big files, duplicate copies and old downloads in Files" }
        return "\(scan.folderName): \(scan.files.count == 1 ? "1 file" : "\(scan.files.count) files"), \(ByteFormatter.string(scan.totalBytes, precision: .twoDecimals))"
    }
}

/// Everything freed so far, measured. Opens the results.
private struct ResultsCard: View {
    let bytes: Int64
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.isShowingResults = true
        } label: {
            HStack(spacing: 14) {
                IllustrationView(.piggy, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You've freed \(ByteFormatter.string(bytes, precision: .twoDecimals))")
                        .font(.headline)
                    Text("see what each step gave back")
                        .font(.hand(16))
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .sticker(fill: Theme.mintSoft, padding: 16)
        }
        .buttonStyle(.plain)
    }
}

/// Guides for space Storage App isn't allowed to clear itself.
private struct OtherAppsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Other apps")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("we'll show you how")
                    .font(.hand(16))
                    .foregroundStyle(Theme.accent)
            }
            ForEach(OtherAppGuide.allCases) { guide in
                Button {
                    model.open(guide)
                } label: {
                    ActionCard(illustration: guide.illustration, title: guide.title, subtitle: guide.subtitle, figure: nil)
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                ResultsView()
            } label: {
                ActionCard(illustration: .piggy, title: "Results", subtitle: "What every cleanup and guide gave back, measured", figure: nil)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ActionCard: View {
    let illustration: Illustration
    let title: String
    let subtitle: String
    let figure: String?
    /// Shows a PRO tag: tapping opens the paywall.
    var isPro = false

    var body: some View {
        HStack(spacing: 14) {
            IllustrationView(illustration, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if isPro { ProTag() }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let figure {
                Text(figure)
                    .font(.metric(.headline))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .sticker(padding: 14)
        .contentShape(Rectangle())
    }
}

private struct CategoryCard: View {
    let illustration: Illustration
    let title: String
    let subtitle: String
    let total: CategoryTotal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IllustrationView(illustration, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormatter.string(total.bytes, precision: .twoDecimals))
                        .font(.metric(.headline))
                        .monospacedDigit()
                    Text("\(total.count.formatted()) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .card(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(total.count) items, \(ByteFormatter.accessibilityString(total.bytes, precision: .twoDecimals))")
        .accessibilityHint("Shows these items in the library.")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppModel.preview())
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
}
