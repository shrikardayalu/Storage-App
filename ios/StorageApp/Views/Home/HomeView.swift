import StorageCore
import SwiftUI

/// Dashboard: the phone's real storage, and what takes up space in the test album.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                DeviceStorageCard()
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

/// What the app can do to the test album so far. The shrink tools need Pro;
/// without it their cards open the paywall instead.
private struct CleanupSection: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @State private var showingPaywall = false

    var body: some View {
        let live = model.convertibleLivePhotos
        let liveSaving = model.livePhotoSaving
        let bursts = model.bursts
        let burstSaving = model.burstSaving
        let videos = model.shrinkableVideos
        let videoSaving = model.videoSaving
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Clean up")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("only in the test album")
                    .font(.hand(16))
                    .foregroundStyle(Theme.accent)
            }
            if !live.isEmpty {
                proLink {
                    LivePhotoStillsView()
                } label: {
                    ActionCard(
                        illustration: .photo,
                        title: "Live Photos \u{2192} stills",
                        subtitle: "\(live.count) Live \(live.count == 1 ? "Photo" : "Photos"), same photos without the video",
                        figure: "\u{2212}" + ByteFormatter.string(liveSaving, precision: .twoDecimals),
                        isPro: purchases.requiresPro
                    )
                }
            }
            if !videos.isEmpty {
                proLink {
                    VideosView()
                } label: {
                    ActionCard(
                        illustration: .compress,
                        title: "Shrink videos",
                        subtitle: "\(videos.count) \(videos.count == 1 ? "video" : "videos"), compress or trim, same memories",
                        figure: "\u{2212}" + ByteFormatter.string(videoSaving, precision: .twoDecimals),
                        isPro: purchases.requiresPro
                    )
                }
            }
            NavigationLink {
                JunkReviewView()
            } label: {
                ActionCard(
                    illustration: .beaker,
                    title: "Duplicates and junk",
                    subtitle: junkSubtitle,
                    figure: model.junkReport.flatMap { $0.isEmpty ? nil : "\u{2212}" + ByteFormatter.string($0.suggestedBytes, precision: .twoDecimals) }
                )
            }
            .buttonStyle(.plain)
            if !bursts.isEmpty {
                proLink {
                    BurstPicksView()
                } label: {
                    ActionCard(
                        illustration: .stackSmall,
                        title: "Best shot of each burst",
                        subtitle: "\(bursts.count) \(bursts.count == 1 ? "burst" : "bursts"), keep one shot, remove the rest",
                        figure: "\u{2212}" + ByteFormatter.string(burstSaving, precision: .twoDecimals),
                        isPro: purchases.requiresPro
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
}

extension CleanupSection {
    /// Opens `destination` for Pro, or the paywall for everyone else.
    @ViewBuilder
    fileprivate func proLink<Destination: View>(@ViewBuilder destination: @escaping () -> Destination, label: () -> ActionCard) -> some View {
        if purchases.requiresPro {
            Button { showingPaywall = true } label: { label() }
                .buttonStyle(.plain)
        } else {
            NavigationLink(destination: destination, label: label)
                .buttonStyle(.plain)
        }
    }

    fileprivate var junkSubtitle: String {
        guard let report = model.junkReport else { return "Copies, blurry and black shots, receipts, old screenshots" }
        if report.isEmpty { return "Nothing found. Look again after adding photos" }
        return "\(report.suggestedCount) \(report.suggestedCount == 1 ? "photo" : "photos") to review, best copies kept"
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
                    if isPro {
                        Text("PRO")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.mint, in: Capsule())
                            .foregroundStyle(Color(hex: 0x1A1A17))
                    }
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
}
