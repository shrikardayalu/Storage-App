import StorageCore
import SwiftUI

/// Home, laid out like the best iPhone utilities: one summary at the top, one
/// clear next step, then everything else in short grouped lists.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    /// Re-reads the plan when onboarding finishes over Home.
    @AppStorage(OnboardingAnswers.completedKey) private var onboardingDone = false
    @State private var showingPaywall = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                    .writesIn()
                StorageSummaryCard()
                    .drawsIn(section: 0)
                StorageHealthCard()
                    .drawsIn(section: 1)
                upNext
                    .drawsIn(section: 2)
                if let scan = model.albumScan, scan.total.count > 0 {
                    PhotoToolsSection(onPaywall: { showingPaywall = true })
                        .drawsIn(section: 3)
                }
                MoreSection()
                    .drawsIn(section: 4)
                SafetyFootnote()
                    .drawsIn(section: 5, outlined: false)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(PaperBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $model.isShowingResults) { ResultsView() }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallFlow(context: PaywallContext(proBytes: model.proSaving))
                .environment(purchases)
                .tint(Theme.accent)
        }
        // Duplicates are checked again after a relaunch, so their row and the
        // plan show a real number even when the tool itself needs Pro.
        .task(id: model.albumScan?.total.count) {
            if model.albumScan != nil, model.junkReport == nil { await model.findJunk() }
        }
    }

    /// The onboarding picks, as a checklist. Needs a scan for its numbers.
    private var showsPlan: Bool {
        onboardingDone && model.albumScan != nil && !OnboardingAnswers.load().picks.isEmpty
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            IllustrationView(.phoneSparkle, size: 40)
            Text("SimpleShrink")
                .font(.display(30))
                .boiling()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            TestModeBadge()
        }
        .padding(.top, 12)
    }

    /// The next step: scan, follow the plan (biggest free fix first, then the
    /// Pro picks that open the paywall), or the best tool for this album.
    /// Space still in Recently Deleted is a reminder under it, never instead
    /// of it: iOS can take a long time to count that space, and hiding the
    /// plan until it does stalled the free-then-Pro funnel.
    @ViewBuilder
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.albumScan == nil {
                ScanCard()
            } else if showsPlan {
                PlanCard(picks: OnboardingAnswers.load().picks)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let best = PhotoToolsSection.best(model) {
                BestNextCard(method: best, onPaywall: { showingPaywall = true })
            }
            if let waiting = model.spaceWaiting {
                SpaceWaitingCard(bytes: waiting)
            }
        }
    }
}

/// The phone's real free space, how full it is, and what the app has freed so far.
private struct StorageSummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.deviceStorage {
                VStack(alignment: .leading, spacing: 10) {
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
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(snapshot))
            } else if model.storageReadFailed {
                Text("Couldn't read this iPhone's storage.")
                    .font(.subheadline)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            }

            if model.freed.total > 0 {
                Divider()
                Button {
                    model.isShowingResults = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Theme.accent)
                        Text("You've freed \(ByteFormatter.string(model.freed.total, precision: .twoDecimals))")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text("Results")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sticker(padding: 18)
    }

    private func accessibilityText(_ snapshot: StorageSnapshot) -> String {
        "iPhone storage, \(ByteFormatter.accessibilityString(snapshot.availableBytes, precision: .twoDecimals)) free, "
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
        .card(padding: 16)
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IllustrationView(.reset, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for your restart")
                        .font(.headline)
                    Text("Open SimpleShrink again afterwards to see what came back.")
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
        .card(padding: 16)
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

// MARK: - Up next

/// A small label over the one card that says what to do next.
private struct UpNextLabel: View {
    var text = "Up next"

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Before the first scan: the one button that gets everything going.
private struct ScanCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UpNextLabel()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IllustrationView(.photo, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find what's taking space")
                            .font(.headline)
                        Text("Scans the \u{201C}\(TestMode.albumName)\u{201D} album. Scanning only reads it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let error = model.scanError {
                    ScanErrorView(error: error)
                }
                Button {
                    Task { await model.scanTestAlbum() }
                } label: {
                    if model.isScanning { ProgressView() } else { Text("Scan Test Album") }
                }
                .buttonStyle(.sticker)
                .disabled(model.isScanning)
            }
            .sticker(fill: Theme.mintSoft, padding: 16)
        }
    }
}

/// Space from the latest cleanup still sitting in Recently Deleted. Until
/// it's emptied the cleanup isn't finished, so it comes before anything else.
private struct SpaceWaitingCard: View {
    let bytes: Int64
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UpNextLabel(text: "Finish your cleanup")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IllustrationView(.trash, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ByteFormatter.string(bytes, precision: .twoDecimals)) waiting in Recently Deleted")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Empty it in Photos to get the space back. It takes about ten seconds.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Show Me How") { model.reopenGuide() }
                    .buttonStyle(.sticker)
            }
            .sticker(fill: Theme.mintSoft, padding: 16)
        }
    }
}

/// The tool that frees the most for this album right now, free ones first.
private struct BestNextCard: View {
    let method: CleanupMethod
    let onPaywall: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UpNextLabel(text: "Best next step")
            MethodLink(method: method, onPaywall: onPaywall) {
                HStack(spacing: 14) {
                    IllustrationView(method.illustration, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(method.title).font(.headline)
                            if method.isPro && purchases.requiresPro { ProTag() }
                        }
                        Text(PhotoToolsSection.subtitle(for: method, model: model))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if let bytes = model.saving(for: method), bytes > 0 {
                        Text("\u{2212}" + ByteFormatter.string(bytes, precision: .twoDecimals))
                            .font(.metric(.headline))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .sticker(fill: Theme.mintSoft, padding: 16)
                .contentShape(Rectangle())
            }
        }
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
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @State private var showingPaywall = false

    var body: some View {
        let rows = ordered
        let next = rows.first { !isDone($0) }
        VStack(alignment: .leading, spacing: 10) {
            UpNextLabel()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your plan")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(next == nil && rows.allSatisfy(isDone) ? "all done, nice" : "from your picks")
                        .font(.hand(16))
                        .foregroundStyle(Theme.accent)
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
        }
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

// MARK: - Lists

/// Every photo and video tool as one grouped list, biggest saving first,
/// with the album itself at the top. Pro tools open the paywall until unlocked.
private struct PhotoToolsSection: View {
    let onPaywall: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "Photos & videos")
                Spacer(minLength: 8)
                Button {
                    Task { await model.scanTestAlbum() }
                } label: {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 32)
                .disabled(model.isScanning)
            }
            if let error = model.scanError {
                ScanErrorView(error: error)
            }
            GroupedList {
                if let scan = model.albumScan {
                    Button { model.showLibrary(group: nil) } label: {
                        ListRow(
                            illustration: .photo,
                            title: "Test album",
                            subtitle: "\(scan.total.count.formatted()) items · \(ScanSource.title(for: model.photoAccess))",
                            trailing: ByteFormatter.string(scan.total.bytes, precision: .twoDecimals),
                            trailingIsSaving: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows every item in the Library, biggest first.")
                }
                ForEach(methods) { method in
                    ListDivider()
                    MethodLink(method: method, onPaywall: onPaywall) {
                        ListRow(
                            illustration: method.illustration,
                            title: method.title,
                            subtitle: Self.subtitle(for: method, model: model),
                            trailing: figure(for: method),
                            isPro: method.isPro && purchases.requiresPro
                        )
                    }
                }
                ListDivider()
                Button {
                    model.isSelecting = true
                    model.showLibrary(group: nil)
                } label: {
                    ListRow(illustration: .trash, title: "Pick what to delete",
                            subtitle: "Review it on a receipt before anything goes", trailing: nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The album tools with something to work on, biggest saving first.
    private var methods: [CleanupMethod] {
        Self.available(model).sorted { (model.saving(for: $0) ?? -1) > (model.saving(for: $1) ?? -1) }
    }

    /// The photo-checking tools always show, so they can run their first check.
    static func available(_ model: AppModel) -> [CleanupMethod] {
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

    /// Home's suggestion when there's no plan: the first tool in plan order
    /// (free fixes first) with something to free.
    static func best(_ model: AppModel) -> CleanupMethod? {
        model.planOrder(available(model)).first { (model.saving(for: $0) ?? 0) > 0 }
    }

    static func subtitle(for method: CleanupMethod, model: AppModel) -> String {
        switch method {
        case .livePhotos:
            let count = model.convertibleLivePhotos.count
            return "\(count) Live \(count == 1 ? "Photo" : "Photos"), keep the still"
        case .screenshots:
            let count = model.resavableScreenshots.count
            return "\(count) \(count == 1 ? "screenshot" : "screenshots"), same look, far smaller"
        case .shrinkVideos:
            let count = model.shrinkableVideos.count
            return "\(count) \(count == 1 ? "video" : "videos"), compress or trim"
        case .bursts:
            let count = model.bursts.count
            return "\(count) \(count == 1 ? "burst" : "bursts"), keep the best shot"
        case .duplicates:
            guard let report = model.junkReport else { return "Copies, blurry shots, old screenshots" }
            if report.isEmpty { return "Nothing found right now" }
            return "\(report.suggestedCount) \(report.suggestedCount == 1 ? "photo" : "photos") to review, best copies kept"
        case .photoCleanup:
            guard let plan = model.photoCleanupPlan else { return method.pitch }
            if plan.isEmpty { return "Nothing to clean right now" }
            return "\(plan.stillCount + plan.remove.count) photos in one tap, best copies kept"
        case .swipe:
            guard let candidates = model.swipeCandidates else { return method.pitch }
            let count = candidates.count
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

/// Files and other apps: space the app can point to but can't clear from Photos.
private struct MoreSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Files & other apps")
            GroupedList {
                NavigationLink {
                    FilesCleanupView()
                } label: {
                    ListRow(illustration: .stackLarge, title: "Clean up a folder", subtitle: filesSubtitle, trailing: nil)
                }
                .buttonStyle(.plain)
                ForEach(OtherAppGuide.allCases) { guide in
                    ListDivider()
                    Button { model.open(guide) } label: {
                        ListRow(illustration: guide.illustration, title: guide.title, subtitle: guide.subtitle, trailing: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filesSubtitle: String {
        guard let scan = model.folderScan else { return "Big files, copies and old downloads" }
        return "\(scan.folderName): \(scan.files.count == 1 ? "1 file" : "\(scan.files.count) files"), \(ByteFormatter.string(scan.totalBytes, precision: .twoDecimals))"
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rows in one quiet card with hairlines between them, like a Settings list.
private struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .card(padding: 0)
    }
}

private struct ListDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, 64)
    }
}

/// One compact row: a small drawing, a title and a line, an optional figure.
private struct ListRow: View {
    let illustration: Illustration
    let title: String
    let subtitle: String
    let trailing: String?
    var trailingIsSaving = true
    var isPro = false

    var body: some View {
        HStack(spacing: 12) {
            IllustrationView(illustration, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if isPro { ProTag() }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.metric(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(trailingIsSaving ? Theme.accent : Color.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The safety promise, kept short at the bottom.
private struct SafetyFootnote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Test Mode: SimpleShrink sees only the \u{201C}\(TestMode.albumName)\u{201D} album, your free space and a folder you pick. Nothing changes without your OK.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppModel.preview())
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
}
