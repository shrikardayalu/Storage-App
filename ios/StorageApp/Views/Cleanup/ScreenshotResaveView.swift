import StorageCore
import SwiftUI

/// Re-save screenshots: iPhone saves screenshots as PNG, built for perfect
/// copies rather than small files. Each one is replaced by a high-quality
/// HEIC copy of the same image, with the same date, favorite and album; the
/// PNG goes to Recently Deleted. Screenshots that wouldn't get much smaller
/// are left alone.
///
/// It opens on All, where one tap re-saves every one. Select, in the top
/// bar, starts with nothing ticked so the person chooses. Pressing and
/// holding a screenshot shows it big.
struct ScreenshotResaveView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: PickScope = .all
    /// The screenshots ticked in Select. All ignores it.
    @State private var chosen: Set<MediaItem.ID> = []
    @State private var preview: MediaPreview?
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var progress: CGFloat = 0

    private var screenshots: [MediaItem] { model.resavableScreenshots }
    /// Items the safety check refused, such as ones that are gone since the scan.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.missing
    }
    private var approved: Set<MediaItem.ID> {
        (scope == .all ? Set(screenshots.map(\.id)) : chosen).subtracting(blocked)
    }
    private var savedBytes: Int64 {
        let approved = approved
        return screenshots.reduce(0) { approved.contains($1.id) ? $0 + ScreenshotResave.estimatedSaving(for: $1) : $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                IllustrationView(.screenshot, size: 120)
                    .frame(maxWidth: .infinity)
                    .sticker(radius: 26, padding: 16)
                    .rotationEffect(.degrees(-0.6))
                keeps
                list
                if let error {
                    Text(error.localizedDescription)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.tomato)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .scopePicker($scope, label: "Which screenshots to re-save", isShown: !screenshots.isEmpty, isDisabled: model.isChanging)
        .safeAreaInset(edge: .bottom) { actionBar }
        .drawing($progress, duration: 3)
        .mediaPreview($preview)
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Re-saving screenshots…") }
        }
        .confirmationDialog(
            "Re-save \(countText)?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(buttonTitle) {
                Task { await resave() }
            }
        } message: {
            Text("Each screenshot is saved again as a smaller copy that stays in your library, with its date, favorite and albums. The old PNG versions go to Recently Deleted. You can recover them there for 30 days. Screenshots that are already small are left alone.")
        }
        .task(id: screenshots.map(\.id)) {
            chosen.formIntersection(screenshots.map(\.id))
            await runCheck()
        }
    }

    private var countText: String {
        approved.count == 1 ? "1 screenshot" : "\(approved.count) screenshots"
    }

    private var buttonTitle: String {
        approved.count == 1 ? "Re-save 1 Screenshot" : "Re-save \(approved.count) Screenshots"
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("same screenshots, smaller files")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.2)
            Text("Re-save screenshots")
                .font(.display(32))
                .boiling()
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Saves about")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                SizeText(bytes: savedBytes, style: .title, unitStyle: .headline, precision: .twoDecimals)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 2)
            Text("iPhone saves screenshots as PNG, a format made for perfect copies, not small files. Saved again as HEIC, they look the same on your phone and take far less room.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var keeps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every copy keeps")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                SafetyLine(done: true, text: "Its size on screen", progress: progress, start: 0.55)
                SafetyLine(done: true, text: "Its date", progress: progress, start: 0.62)
                SafetyLine(done: true, text: "Favorite", progress: progress, start: 0.69)
                SafetyLine(done: true, text: "Its albums", progress: progress, start: 0.76)
            }
            Text("The figure is an estimate. SimpleShrink makes each copy first and only swaps the ones that come out clearly smaller, then checks each copy afterwards and shows you the result.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var list: some View {
        // Worked out once, not once per row: a library can hold thousands of these.
        let approved = approved
        let lastID = screenshots.last?.id
        if screenshots.isEmpty {
            EmptyStateView(
                illustration: .screenshot,
                title: "No PNG screenshots here",
                message: "Every screenshot in your library is already saved in a smaller format."
            )
        } else {
            // Lazy: a library can hold thousands of these.
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(screenshots.count) PNG \(screenshots.count == 1 ? "screenshot" : "screenshots")")
                        .font(.headline)
                    Spacer()
                    if scope == .select {
                        Text("\(approved.count) picked")
                            .font(.hand(16))
                            .foregroundStyle(Theme.accent)
                        if !chosen.isEmpty {
                            Button("Clear") { chosen = [] }
                                .font(.subheadline.weight(.semibold))
                                .padding(.leading, 6)
                        }
                    }
                }
                .padding(.bottom, 4)
                Text(scope == .all
                     ? "Every screenshot is included. Switch to Select at the top to choose which ones. Press and hold one for a closer look."
                     : "Tick the screenshots to re-save. Press and hold one for a closer look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                ForEach(screenshots) { item in
                    let blockedReason = blockedReason(item)
                    ScreenshotRow(item: item, showsCheck: scope == .select, isOn: approved.contains(item.id), blockedReason: blockedReason)
                        .tapAndHold(isEnabled: blockedReason == nil) {
                            if scope == .select {
                                if chosen.contains(item.id) { chosen.remove(item.id) } else { chosen.insert(item.id) }
                            } else {
                                preview = MediaPreview(item)
                            }
                        } hold: {
                            preview = MediaPreview(item)
                        }
                    if item.id != lastID { Divider() }
                }
            }
            .card(padding: 14)
        }
    }

    private func blockedReason(_ item: MediaItem) -> String? {
        guard let check else { return nil }
        if check.missing.contains(item.id) { return "not in your library any more" }
        return nil
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(approved.isEmpty ? "Pick Screenshots" : buttonTitle)
            }
            .buttonStyle(.sticker)
            .disabled(approved.isEmpty || check == nil || model.isChanging)
            Text(check == nil ? (error == nil ? "Checking your library…" : "Fix the problem above to continue.") : "Copies stay in your library. Old PNGs go to Recently Deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    // MARK: Actions

    /// Checks every screenshot once, so ones that can't be touched are shown as such.
    private func runCheck() async {
        let all = Set(screenshots.map(\.id))
        guard !all.isEmpty else { return }
        switch await model.albumCheck(all) {
        case .success(let value):
            check = value
            error = nil
        case .failure(let failure):
            // A failed check leaves nothing approved, not the last check's result.
            check = nil
            error = failure
        }
    }

    private func resave() async {
        let ids = approved
        guard !ids.isEmpty else { return }
        if let failure = await model.resaveScreenshots(approved: ids) {
            error = failure
            await runCheck()
        }
    }
}

private struct ScreenshotRow: View {
    let item: MediaItem
    let showsCheck: Bool
    let isOn: Bool
    let blockedReason: String?

    private var saving: Int64 { ScreenshotResave.estimatedSaving(for: item) }

    var body: some View {
        Group {
            HStack(spacing: 12) {
                if showsCheck {
                    InkCheck(isOn: isOn, size: 24)
                        .opacity(blockedReason == nil ? 1 : 0.3)
                }
                ItemThumbnail(id: item.id, side: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let blockedReason {
                        Text(blockedReason)
                            .font(.hand(14))
                            .foregroundStyle(Theme.tomato)
                    } else {
                        Text("\(ByteFormatter.string(item.currentBytes, precision: .twoDecimals)) as PNG")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("−\(ByteFormatter.string(saving, precision: .twoDecimals))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Text("about")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .opacity(blockedReason == nil ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.filename), saves about \(ByteFormatter.accessibilityString(saving, precision: .twoDecimals))")
        .accessibilityValue(blockedReason ?? (showsCheck ? (isOn ? "Picked" : "Not picked") : "Included"))
    }
}
