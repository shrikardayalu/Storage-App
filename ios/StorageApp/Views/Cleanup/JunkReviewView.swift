import StorageCore
import SwiftUI

/// Step 7: duplicates, near-duplicates, blurry and black shots, receipts,
/// documents and old screenshots in the test album. Everything is a
/// suggestion: the person reviews each one, and only what's still ticked when
/// they confirm goes to Recently Deleted. The best copy of each duplicate stays.
struct JunkReviewView: View {
    @Environment(AppModel.self) private var model
    /// Single-photo findings that are ticked for removal.
    @State private var ticked: Set<MediaItem.ID> = []
    /// Duplicate group → the copy to keep.
    @State private var keepers: [DuplicateGroup.ID: MediaItem.ID] = [:]
    /// Duplicate groups the person chose to leave alone.
    @State private var skipped: Set<DuplicateGroup.ID> = []
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var loadedReport: JunkReport?

    private var report: JunkReport? { model.junkReport }
    /// Photos the safety check refused, such as ones also in another album.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.outsideTestAlbum.union(check.inOtherAlbums)
    }

    private func keeper(of group: DuplicateGroup) -> MediaItem.ID {
        keepers[group.id] ?? group.suggestedKeeper
    }

    private func isBlocked(_ group: DuplicateGroup) -> Bool {
        group.items.contains { $0.id != keeper(of: group) && blocked.contains($0.id) }
    }

    private var activeGroups: [DuplicateGroup] {
        (report?.duplicates ?? []).filter { !skipped.contains($0.id) && !isBlocked($0) }
    }

    /// Exactly what goes when the person confirms.
    private var removeIDs: Set<MediaItem.ID> {
        var ids = ticked.subtracting(blocked)
        for group in activeGroups {
            ids.formUnion(group.items.map(\.id).filter { $0 != keeper(of: group) })
        }
        return ids
    }

    private var keeperIDs: Set<MediaItem.ID> { Set(activeGroups.map(keeper(of:))) }

    private var removeBytes: Int64 {
        (model.albumScan?.items ?? []).filter { removeIDs.contains($0.id) }.reduce(0) { $0 + $1.currentBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
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
        .safeAreaInset(edge: .bottom) {
            if report?.isEmpty == false { actionBar }
        }
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Removing what you picked…") }
        }
        .confirmationDialog(
            "Remove \(countText) from \u{201C}\(TestMode.albumName)\u{201D}?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Remove \(countText)", role: .destructive) {
                Task { await remove() }
            }
        } message: {
            Text("\(ByteFormatter.string(removeBytes, precision: .twoDecimals)). The best copy of each duplicate stays. The rest go to Recently Deleted, where you can recover them for 30 days.")
        }
        .task {
            await model.findJunk()
            reset()
            await runCheck()
        }
        .onChange(of: model.junkReport) { _, _ in
            reset()
            Task { await runCheck() }
        }
    }

    private var countText: String {
        removeIDs.count == 1 ? "1 Photo" : "\(removeIDs.count) Photos"
    }

    /// Starts every suggestion fresh for a new report, keeping the person's choices where they still apply.
    private func reset() {
        guard let report, report != loadedReport else { return }
        let firstLoad = loadedReport == nil
        let known = Set(loadedReport?.findings.map(\.id) ?? [])
        loadedReport = report
        let ids = Set(report.findings.map(\.id))
        ticked = ticked.intersection(ids).union(
            report.findings.filter { $0.reason.startsSelected && (firstLoad || !known.contains($0.id)) }.map(\.id)
        )
        let groups = Set(report.duplicates.map(\.id))
        keepers = keepers.filter { groups.contains($0.key) }
        skipped = skipped.intersection(groups)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("found, never removed without you")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
            Text("Duplicates and junk")
                .font(.display(32))
                .boiling()
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
            if report != nil, !model.isAnalyzing {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Saves about")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SizeText(bytes: removeBytes, style: .title, unitStyle: .headline, precision: .twoDecimals)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.isAnalyzing || report == nil {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: model.analysisProgress)
                    .tint(Theme.accent)
                Text("Looking at each photo, on this iPhone. Nothing leaves it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card(padding: 16)
        } else if let report, report.isEmpty {
            EmptyStateView(
                illustration: .shieldCheck,
                title: "Nothing to clean",
                message: "No duplicates, blurry or black shots, receipts, documents or old screenshots in \u{201C}\(TestMode.albumName)\u{201D}."
            )
        } else if let report {
            Text("Untick anything you want to keep. Receipts and documents start unticked, in case you still need them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !report.duplicates.isEmpty {
                sectionTitle(JunkReason.duplicate.title, detail: "tap the copy to keep")
                ForEach(report.duplicates) { group in
                    DuplicateCard(
                        group: group,
                        keeper: keeper(of: group),
                        isOn: !skipped.contains(group.id),
                        blockedReason: isBlocked(group) ? "a copy is also in another album, so this is left alone" : nil,
                        pick: { keepers[group.id] = $0 },
                        toggle: {
                            if skipped.contains(group.id) { skipped.remove(group.id) } else { skipped.insert(group.id) }
                        }
                    )
                }
            }
            ForEach(JunkReason.allCases.filter { $0 != .duplicate }) { reason in
                let findings = report.findings(for: reason)
                if !findings.isEmpty {
                    findingSection(reason, findings)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.hand(16))
                .foregroundStyle(Theme.accent)
        }
        .padding(.top, 6)
    }

    private func findingSection(_ reason: JunkReason, _ findings: [JunkFinding]) -> some View {
        let ids = Set(findings.map(\.id))
        let allTicked = ids.subtracting(blocked).isSubset(of: ticked)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(reason.title, detail: Self.detail(reason))
                Spacer(minLength: 6)
                Button(allTicked ? "Untick all" : "Tick all") {
                    if allTicked { ticked.subtract(ids) } else { ticked.formUnion(ids.subtracting(blocked)) }
                }
                .font(.footnote.weight(.semibold))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 12) {
                ForEach(findings) { finding in
                    FindingTile(
                        item: finding.item,
                        isOn: ticked.contains(finding.id) && !blocked.contains(finding.id),
                        isBlocked: blocked.contains(finding.id)
                    ) {
                        if ticked.contains(finding.id) { ticked.remove(finding.id) } else { ticked.insert(finding.id) }
                    }
                }
            }
            .card(padding: 12)
        }
    }

    private static func detail(_ reason: JunkReason) -> String {
        switch reason {
        case .duplicate: "tap the copy to keep"
        case .dark: "taken by accident"
        case .blurry: "out of focus or shaken"
        case .receipt: "keep any you still need"
        case .document: "pages and notes"
        case .oldScreenshot: "over a month old"
        }
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(removeIDs.isEmpty ? "Tick photos to remove" : "Remove \(countText)")
            }
            .buttonStyle(.sticker)
            .disabled(removeIDs.isEmpty || check == nil || model.isChanging || model.isAnalyzing)
            Text(check == nil ? (error == nil ? "Checking the test album…" : "Fix the problem above to continue.") : "Best copies stay. The rest go to Recently Deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    // MARK: Actions

    /// Checks every suggested photo once, so ones that can't be touched are shown as such.
    private func runCheck() async {
        guard let report else { return }
        let all = Set(report.findings.map(\.id)).union(report.duplicates.flatMap(\.items).map(\.id))
        guard !all.isEmpty else { return }
        switch await model.albumCheck(all) {
        case .success(let value):
            check = value
            error = nil
        case .failure(let failure):
            check = nil
            error = failure
        }
    }

    private func remove() async {
        let remove = removeIDs
        guard !remove.isEmpty else { return }
        if let failure = await model.removeJunk(remove, keeping: keeperIDs) {
            error = failure
            await runCheck()
        }
    }
}

/// One duplicate group: its copies side by side, with the keeper circled.
private struct DuplicateCard: View {
    let group: DuplicateGroup
    let keeper: MediaItem.ID
    let isOn: Bool
    let blockedReason: String?
    let pick: (MediaItem.ID) -> Void
    let toggle: () -> Void

    private var active: Bool { isOn && blockedReason == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        InkCheck(isOn: active, size: 24)
                            .opacity(blockedReason == nil ? 1 : 0.3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.isExact ? "\(group.items.count) copies" : "\(group.items.count) near-identical")
                                .font(.subheadline.weight(.semibold))
                            if let blockedReason {
                                Text(blockedReason)
                                    .font(.hand(14))
                                    .foregroundStyle(Theme.tomato)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let first = group.items.first {
                                Text(first.creationDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(blockedReason != nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(group.isExact ? "\(group.items.count) copies of a photo" : "\(group.items.count) near-identical photos")
                .accessibilityValue(blockedReason ?? (active ? "Will be cleaned" : "Skipped"))
                .accessibilityAddTraits(.isButton)
                Spacer(minLength: 6)
                if active {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\u{2212}\(ByteFormatter.string(group.savedBytes(keeping: keeper), precision: .twoDecimals))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("\(group.items.count - 1) to remove")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(group.items) { item in
                        copyButton(item)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .card(padding: 14)
    }

    private func copyButton(_ item: MediaItem) -> some View {
        let isKeeper = item.id == keeper
        return Button {
            pick(item.id)
        } label: {
            VStack(spacing: 6) {
                ItemThumbnail(id: item.id, side: 72)
                    .opacity(active && !isKeeper ? 0.45 : 1)
                    .overlay {
                        if active && isKeeper {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 3)
                                .padding(-5)
                        }
                    }
                Text(active ? (isKeeper ? "keep" : "remove") : ByteFormatter.string(item.currentBytes))
                    .font(.hand(14))
                    .foregroundStyle(active ? (isKeeper ? Theme.accent : Theme.tomato) : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(blockedReason != nil)
        .accessibilityLabel("\(item.filename), \(item.pixelWidth) by \(item.pixelHeight)")
        .accessibilityValue(active ? (isKeeper ? "Keep" : "Remove") : "Skipped")
        .accessibilityHint("Keeps this copy and removes the others")
    }
}

/// One flagged photo with a tick.
private struct FindingTile: View {
    let item: MediaItem
    let isOn: Bool
    let isBlocked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 4) {
                ItemThumbnail(id: item.id, side: 78)
                    .opacity(isOn ? 1 : 0.55)
                    .overlay(alignment: .topTrailing) {
                        InkCheck(isOn: isOn, size: 22)
                            .padding(5)
                            .opacity(isBlocked ? 0.3 : 1)
                    }
                Text(isBlocked ? "in another album" : ByteFormatter.string(item.currentBytes))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isBlocked ? Theme.tomato : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .accessibilityLabel(item.filename)
        .accessibilityValue(isBlocked ? "Also in another album, left alone" : (isOn ? "Will be removed" : "Kept"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
