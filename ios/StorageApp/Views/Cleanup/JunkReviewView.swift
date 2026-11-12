import StorageCore
import SwiftUI

/// Step 7: duplicates, near-duplicates, blurry and black shots, receipts,
/// documents and old screenshots in the library. Everything is a
/// suggestion: the person reviews each one, and only what's still ticked when
/// they confirm goes to Recently Deleted. The best copy of each duplicate stays.
///
/// It opens on All, which covers every suggestion except receipts and
/// documents. Select, in the top bar, starts with nothing ticked so the
/// person chooses. Pressing and holding a photo shows it big.
struct JunkReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: PickScope = .all
    /// Single-photo findings ticked in Select. All ignores it.
    @State private var ticked: Set<MediaItem.ID> = []
    /// Duplicate group → the copy to keep, where it isn't the suggested one.
    @State private var keepers: [DuplicateGroup.ID: MediaItem.ID] = [:]
    /// Duplicate groups ticked in Select. All ignores it.
    @State private var pickedGroups: Set<DuplicateGroup.ID> = []
    @State private var preview: MediaPreview?
    @State private var check: SafetyCheck?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    @State private var loadedReport: JunkReport?

    private var report: JunkReport? { model.junkReport }
    /// Photos the safety check refused, such as ones that are gone since the scan.
    private var blocked: Set<MediaItem.ID> {
        guard let check else { return [] }
        return check.missing
    }

    private func keeper(of group: DuplicateGroup) -> MediaItem.ID {
        keepers[group.id] ?? group.suggestedKeeper
    }

    private func isBlocked(_ group: DuplicateGroup) -> Bool {
        group.items.contains { $0.id != keeper(of: group) && blocked.contains($0.id) }
    }

    private func isIncluded(_ group: DuplicateGroup) -> Bool {
        scope == .all || pickedGroups.contains(group.id)
    }

    private var activeGroups: [DuplicateGroup] {
        (report?.duplicates ?? []).filter { isIncluded($0) && !isBlocked($0) }
    }

    /// The single photos that go: every suggestion in All (receipts and
    /// documents left alone), the ticked ones in Select.
    private var singles: Set<MediaItem.ID> {
        let included = scope == .all
            ? Set((report?.findings ?? []).filter { $0.reason.startsSelected }.map(\.id))
            : ticked
        return included.subtracting(blocked)
    }

    /// Exactly what goes when the person confirms.
    private var removeIDs: Set<MediaItem.ID> {
        var ids = singles
        for group in activeGroups {
            ids.formUnion(group.items.map(\.id).filter { $0 != keeper(of: group) })
        }
        return ids
    }

    private var keeperIDs: Set<MediaItem.ID> { Set(activeGroups.map(keeper(of:))) }

    private var removeBytes: Int64 {
        // Added up from the report, not by walking the whole library on every redraw.
        guard let report else { return 0 }
        let singles = singles
        var bytes = report.findings.reduce(Int64(0)) { singles.contains($1.id) ? $0 + $1.item.currentBytes : $0 }
        var counted = singles
        for group in activeGroups {
            let keeper = keeper(of: group)
            for item in group.items where item.id != keeper && counted.insert(item.id).inserted {
                bytes += item.currentBytes
            }
        }
        return bytes
    }

    var body: some View {
        ScrollView {
            // Lazy: a library can hold hundreds of duplicate groups.
            LazyVStack(alignment: .leading, spacing: 20) {
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
        .scopePicker($scope, label: "Which photos to remove", isShown: report?.isEmpty == false, isDisabled: model.isChanging)
        .safeAreaInset(edge: .bottom) {
            if report?.isEmpty == false { actionBar }
        }
        .mediaPreview($preview)
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Removing what you picked…") }
        }
        .confirmationDialog(
            "Remove \(countText) from your library?",
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

    /// Keeps the person's choices where they still apply to a new report.
    private func reset() {
        guard let report, report != loadedReport else { return }
        loadedReport = report
        ticked.formIntersection(report.findings.map(\.id))
        let groups = Set(report.duplicates.map(\.id))
        keepers = keepers.filter { groups.contains($0.key) }
        pickedGroups.formIntersection(groups)
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
                message: "No duplicates, blurry or black shots, receipts, documents or old screenshots in your library."
            )
        } else if let report {
            Text(scope == .all
                 ? "Everything suggested is included, and the best copy of each duplicate stays. Receipts and documents are left alone, in case you still need them. Switch to Select at the top to choose yourself. Press and hold a photo for a closer look."
                 : "Tick what to remove, and tap the copy to keep in each duplicate. Press and hold a photo for a closer look.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !report.duplicates.isEmpty {
                sectionTitle(JunkReason.duplicate.title, detail: "tap the copy to keep")
                ForEach(report.duplicates) { group in
                    let keeper = keeper(of: group)
                    let pick: (MediaItem.ID) -> Void = { copy in
                        keepers[group.id] = copy
                        pickedGroups.insert(group.id)
                    }
                    DuplicateCard(
                        group: group,
                        keeper: keeper,
                        showsCheck: scope == .select,
                        isOn: isIncluded(group),
                        blockedReason: isBlocked(group) ? "a copy is no longer in your library, so this is left alone" : nil,
                        pick: pick,
                        toggle: {
                            if pickedGroups.contains(group.id) { pickedGroups.remove(group.id) } else { pickedGroups.insert(group.id) }
                        },
                        hold: { copy in
                            preview = MediaPreview(
                                items: group.items, start: copy,
                                title: group.isExact ? "\(group.items.count) copies" : "\(group.items.count) near-identical",
                                keeper: keeper, pick: pick
                            )
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
        let singles = singles
        // In All, receipts and documents are shown but not removed.
        let leftAlone = scope == .all && !reason.startsSelected
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(reason.title, detail: leftAlone ? "left alone, Select to pick" : Self.detail(reason))
                Spacer(minLength: 6)
                if scope == .select {
                    Button(allTicked ? "Untick all" : "Tick all") {
                        if allTicked { ticked.subtract(ids) } else { ticked.formUnion(ids.subtracting(blocked)) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 12) {
                ForEach(findings) { finding in
                    let isBlocked = blocked.contains(finding.id)
                    FindingTile(
                        item: finding.item,
                        showsCheck: scope == .select,
                        isOn: singles.contains(finding.id),
                        isBlocked: isBlocked
                    )
                    .tapAndHold(isEnabled: !isBlocked) {
                        if scope == .select {
                            if ticked.contains(finding.id) { ticked.remove(finding.id) } else { ticked.insert(finding.id) }
                        } else {
                            preview = MediaPreview(finding.item)
                        }
                    } hold: {
                        preview = MediaPreview(finding.item)
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
                Text(removeIDs.isEmpty ? (scope == .all ? "Nothing to Remove" : "Tick Photos to Remove") : "Remove \(countText)")
            }
            .buttonStyle(.sticker)
            .disabled(removeIDs.isEmpty || check == nil || model.isChanging || model.isAnalyzing)
            Text(check == nil ? (error == nil ? "Checking your library…" : "Fix the problem above to continue.") : "Best copies stay. The rest go to Recently Deleted.")
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
    /// Select shows a tick on each group; All includes every one.
    let showsCheck: Bool
    let isOn: Bool
    let blockedReason: String?
    let pick: (MediaItem.ID) -> Void
    let toggle: () -> Void
    /// A copy was pressed and held.
    let hold: (MediaItem.ID) -> Void

    private var active: Bool { isOn && blockedReason == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        if showsCheck {
                            InkCheck(isOn: active, size: 24)
                                .opacity(blockedReason == nil ? 1 : 0.3)
                        }
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
                // All includes every group, so there's nothing to tick.
                .allowsHitTesting(showsCheck)
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
        return VStack(spacing: 6) {
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
        .accessibilityElement(children: .ignore)
        .tapAndHold(isEnabled: blockedReason == nil) {
            pick(item.id)
        } hold: {
            hold(item.id)
        }
        .accessibilityLabel("\(item.filename), \(item.pixelWidth) by \(item.pixelHeight)")
        .accessibilityValue(active ? (isKeeper ? "Keep" : "Remove") : "Skipped")
        .accessibilityHint("Keeps this copy and removes the others")
    }
}

/// One flagged photo, with a tick in Select.
private struct FindingTile: View {
    let item: MediaItem
    let showsCheck: Bool
    let isOn: Bool
    let isBlocked: Bool

    var body: some View {
        VStack(spacing: 4) {
            ItemThumbnail(id: item.id, side: 78)
                .opacity(isOn ? 1 : 0.55)
                .overlay(alignment: .topTrailing) {
                    if showsCheck {
                        InkCheck(isOn: isOn, size: 22)
                            .padding(5)
                            .opacity(isBlocked ? 0.3 : 1)
                    }
                }
            Text(isBlocked ? "not in your library" : ByteFormatter.string(item.currentBytes))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isBlocked ? Theme.tomato : .secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.filename)
        .accessibilityValue(isBlocked ? "No longer in your library, left alone" : (isOn ? "Will be removed" : "Kept"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
