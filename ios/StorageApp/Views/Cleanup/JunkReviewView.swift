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
/// Which part of the report is on screen. Everything is the old full list;
/// the other two skip the long scroll to the bottom.
private enum JunkSection: String, CaseIterable, Identifiable {
    case everything, duplicates, junk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .duplicates: "Duplicates"
        case .junk: "Junk"
        }
    }
}

struct JunkReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: PickScope = .all
    @State private var section: JunkSection = .everything
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
    /// The report on screen. Newer ones from a pass still running wait behind
    /// "Show more", so the list doesn't move while the person is picking.
    @State private var shown: JunkReport?
    /// Photos in the latest report that aren't on screen yet.
    @State private var waiting = 0
    /// Set when what's on screen is out of date for sure, as after a removal.
    @State private var adoptNext = false

    private var report: JunkReport? { shown }

    /// Whether the person has picked anything that a new report would have to carry over.
    private var hasChoices: Bool {
        !ticked.isEmpty || !keepers.isEmpty || !pickedGroups.isEmpty
    }
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

    private var showsDuplicates: Bool { section != .junk }
    private var showsJunk: Bool { section != .duplicates }

    private var activeGroups: [DuplicateGroup] {
        guard showsDuplicates else { return [] }
        return (report?.duplicates ?? []).filter { isIncluded($0) && !isBlocked($0) }
    }

    /// The single photos that go: every suggestion in All (receipts and
    /// documents left alone), the ticked ones in Select. Scoped to the
    /// section on screen, so Remove only acts on what's in front of you.
    private var singles: Set<MediaItem.ID> {
        guard showsJunk else { return [] }
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
            // The section switch stays pinned so junk isn't a long scroll away.
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                header
                if model.isAnalyzing || report == nil {
                    PhotoAnalysisLoader(caption: "Looking at each photo, on this iPhone. Nothing leaves it. The first look takes a while; after that it's quick.")
                }
                if let report, !report.isEmpty {
                    Section {
                        findings(report)
                    } header: {
                        sectionSwitch(report)
                    }
                } else if let report, report.isEmpty, !model.isAnalyzing {
                    EmptyStateView(
                        illustration: .shieldCheck,
                        title: "Nothing to clean",
                        message: "No duplicates, blurry or black shots, receipts, documents or old screenshots in your library."
                    )
                }
                if waiting > 0, let latest = model.junkReport {
                    Button {
                        show(latest)
                    } label: {
                        Label(waiting == 1 ? "Show 1 more found" : "Show \(waiting) more found", systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .accessibilityHint("Adds the newly found photos to the list. Your picks stay.")
                }
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
            offer(model.junkReport)
            await model.findJunk()
            offer(model.junkReport, finished: true)
        }
        .onChange(of: model.junkReport) { _, latest in
            offer(latest, finished: !model.isAnalyzing)
        }
        .onChange(of: model.isAnalyzing) { _, analyzing in
            guard !analyzing else { return }
            offer(model.junkReport, finished: true)
        }
    }

    /// Puts `latest` on screen when that won't move anything the person is
    /// looking at: nothing shown yet, nothing found so far, a finished pass they
    /// haven't started picking in, or after a removal. Otherwise it waits behind "Show more".
    private func offer(_ latest: JunkReport?, finished: Bool = false) {
        guard let latest, latest != shown else {
            waiting = 0
            if finished, check == nil, error == nil, shown != nil { Task { await runCheck() } }
            return
        }
        if shown == nil || shown?.isEmpty == true || adoptNext || (finished && !hasChoices) {
            show(latest)
        } else {
            let onScreen = Self.ids(in: shown)
            waiting = Self.ids(in: latest).subtracting(onScreen).count
            if waiting == 0, finished { show(latest) }
        }
    }

    private func show(_ latest: JunkReport) {
        shown = latest
        waiting = 0
        adoptNext = false
        reset()
        // The library check waits until the pass is done, so it isn't repeated for every handful of photos.
        guard !model.isAnalyzing else { return }
        Task { await runCheck() }
    }

    private static func ids(in report: JunkReport?) -> Set<MediaItem.ID> {
        guard let report else { return [] }
        return Set(report.findings.map(\.id)).union(report.duplicates.flatMap(\.items).map(\.id))
    }

    private var countText: String {
        removeIDs.count == 1 ? "1 Photo" : "\(removeIDs.count) Photos"
    }

    /// Keeps the person's choices where they still apply to a new report.
    private func reset() {
        guard let report else { return }
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
            if report != nil {
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

    private func sectionSwitch(_ report: JunkReport) -> some View {
        let duplicateCount = report.duplicates.count
        let junkCount = report.findings.count
        return Picker("Section", selection: $section) {
            Text(duplicateCount + junkCount > 0
                 ? "Everything · \(duplicateCount + junkCount)"
                 : "Everything").tag(JunkSection.everything)
            Text(duplicateCount > 0 ? "Duplicates · \(duplicateCount)" : "Duplicates").tag(JunkSection.duplicates)
            Text(junkCount > 0 ? "Junk · \(junkCount)" : "Junk").tag(JunkSection.junk)
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Theme.background)
        .accessibilityLabel("Which findings to show")
    }

    @ViewBuilder
    private func findings(_ report: JunkReport) -> some View {
        Text(sectionHint)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if showsDuplicates {
            if report.duplicates.isEmpty {
                Text("No duplicates in this library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
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
        }
        if showsJunk {
            let junkReasons = JunkReason.allCases.filter { $0 != .duplicate }
            let anyJunk = junkReasons.contains { !report.findings(for: $0).isEmpty }
            if !anyJunk {
                Text("No junk photos in this library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(junkReasons) { reason in
                    let findings = report.findings(for: reason)
                    if !findings.isEmpty {
                        findingSection(reason, findings)
                    }
                }
            }
        }
    }

    private var sectionHint: String {
        switch (section, scope) {
        case (.everything, .all):
            "Everything suggested is included, and the best copy of each duplicate stays. Receipts and documents are left alone, in case you still need them. Switch to Select at the top to choose yourself. Press and hold a photo for a closer look."
        case (.duplicates, .all):
            "Every duplicate group is included, and the best copy stays. Switch to Select at the top to choose groups yourself. Press and hold a photo for a closer look."
        case (.junk, .all):
            "Blurry, black and old shots are included. Receipts and documents are left alone, in case you still need them. Switch to Select at the top to choose yourself. Press and hold a photo for a closer look."
        case (_, .select):
            "Tick what to remove, and tap the copy to keep in each duplicate. Press and hold a photo for a closer look."
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
                Text(removeIDs.isEmpty
                     ? (scope == .all ? "Nothing to Remove" : "Tick Photos to Remove")
                     : "Remove \(countText)")
            }
            .buttonStyle(.sticker)
            .disabled(removeIDs.isEmpty || check == nil || model.isChanging || model.isAnalyzing)
            Text(model.isAnalyzing
                 ? "Still looking. You can remove what's here once it's finished."
                 : (check == nil
                    ? (error == nil ? "Checking your library…" : "Fix the problem above to continue.")
                    : (section == .everything
                       ? "Best copies stay. The rest go to Recently Deleted."
                       : "Only what's in \(section.title.lowercased()) right now. Your other ticks stay for when you switch back.")))
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
        // The library is scanned again after a removal; what's on screen is out of date either way.
        adoptNext = true
        if let failure = await model.removeJunk(remove, keeping: keeperIDs) {
            if let latest = model.junkReport, latest != shown {
                show(latest)
            } else {
                adoptNext = false
                await runCheck()
            }
            // After the check: a successful re-check used to clear this message.
            error = failure
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
