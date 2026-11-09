import StorageCore
import SwiftUI
import UniformTypeIdentifiers

/// Step 8: big files, duplicate files and old downloads in one folder the
/// person picks in Files. The app sees only that folder. Nothing is ticked
/// except the extra copies of duplicates, and deleting is for good, so the
/// confirmation says so plainly.
struct FilesCleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    /// Large and old files ticked for deletion.
    @State private var ticked: Set<FileItem.ID> = []
    /// Duplicate group → the copy to keep.
    @State private var keepers: [FileDuplicateGroup.ID: FileItem.ID] = [:]
    /// Duplicate groups the person chose to leave alone.
    @State private var skipped: Set<FileDuplicateGroup.ID> = []
    @State private var error: FileChangeError?
    @State private var confirming = false

    private var report: FileReport? { model.fileReport }

    private func keeper(of group: FileDuplicateGroup) -> FileItem.ID {
        keepers[group.id] ?? group.suggestedKeeper
    }

    private var activeGroups: [FileDuplicateGroup] {
        (report?.duplicates ?? []).filter { !skipped.contains($0.id) }
    }

    /// Exactly what is deleted when the person confirms, as the review showed it.
    private var approved: [FileItem] {
        guard let report else { return [] }
        let extras = activeGroups.flatMap { group in group.files.filter { $0.id != keeper(of: group) } }
        return extras + (report.large + report.old).filter { ticked.contains($0.id) }
    }

    private var keeperFiles: [FileItem] {
        activeGroups.compactMap { group in group.files.first { $0.id == keeper(of: group) } }
    }

    private var approvedBytes: Int64 { approved.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let receipt = model.lastFileDeletion {
                    DeletedCard(receipt: receipt, reclaim: model.fileReclaim)
                }
                content
                if let message = (error ?? model.folderError)?.localizedDescription {
                    Text(message)
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
            if model.isChanging { WorkingOverlay(message: "Deleting files…") }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                error = nil
                Task { await model.pick(folder: url) }
            case .failure(let failure):
                error = .verificationFailed(failure.localizedDescription)
            }
        }
        .confirmationDialog(
            "Delete \(countText) for good?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete \(countText)", role: .destructive) {
                Task { await deleteApproved() }
            }
        } message: {
            Text("\(ByteFormatter.string(approvedBytes, precision: .twoDecimals)) from \u{201C}\(model.folderScan?.folderName ?? "this folder")\u{201D}. Files deleted here don't go to Recently Deleted and can't be recovered. Nothing outside this folder is touched.")
        }
        .onChange(of: model.fileReport) { _, newReport in
            prune(to: newReport)
        }
    }

    private var countText: String {
        approved.count == 1 ? "1 File" : "\(approved.count) Files"
    }

    /// Drops choices for files that are gone, keeping the rest.
    private func prune(to report: FileReport?) {
        guard let report else {
            ticked = []
            keepers = [:]
            skipped = []
            return
        }
        ticked = ticked.intersection((report.large + report.old).map(\.id))
        let groups = Set(report.duplicates.map(\.id))
        keepers = keepers.filter { groups.contains($0.key) }
        skipped = skipped.intersection(groups)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("only the folder you pick")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
            Text("Clean up files")
                .font(.display(32))
                .boiling()
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
            if let scan = model.folderScan {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scan.folderName)
                            .font(.headline)
                        Text("\(scan.files.count == 1 ? "1 file" : "\(scan.files.count) files") · \(ByteFormatter.string(scan.totalBytes, precision: .twoDecimals))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Button("Change") { picking = true }
                        .font(.footnote.weight(.semibold))
                        .disabled(model.isChanging)
                }
                .card(padding: 14)
                .padding(.top, 6)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.pickedFolder == nil {
            VStack(alignment: .leading, spacing: 14) {
                IllustrationView(.stackLarge, size: 72)
                Text("Pick a folder in Files, such as \u{201C}\(TestMode.albumName)\u{201D} in On My iPhone. SimpleShrink looks for big files, duplicate copies and old downloads in it, and can't see anything else.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Pick a Folder") { picking = true }
                    .buttonStyle(.sticker)
            }
            .card(padding: 18)
        } else if model.isScanningFolder && report == nil {
            ProgressView("Reading the folder…")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if let report, report.isEmpty {
            EmptyStateView(
                illustration: .shieldCheck,
                title: "Nothing to clean",
                message: "No large files, duplicate copies or old downloads in this folder."
            )
        } else if let report {
            if !report.duplicates.isEmpty {
                sectionTitle("Duplicate copies", detail: "tap the copy to keep")
                ForEach(report.duplicates) { group in
                    DuplicateFilesCard(
                        group: group,
                        keeper: keeper(of: group),
                        isOn: !skipped.contains(group.id),
                        pick: { keepers[group.id] = $0 },
                        toggle: {
                            if skipped.contains(group.id) { skipped.remove(group.id) } else { skipped.insert(group.id) }
                        }
                    )
                }
            }
            if !report.large.isEmpty {
                fileSection("Large files", detail: "10 MB or more", files: report.large)
            }
            if !report.old.isEmpty {
                fileSection("Old downloads", detail: "untouched for 6 months", files: report.old)
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

    private func fileSection(_ title: String, detail: String, files: [FileItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title, detail: detail)
            VStack(spacing: 0) {
                ForEach(files) { file in
                    FileRow(file: file, isOn: ticked.contains(file.id)) {
                        if ticked.contains(file.id) { ticked.remove(file.id) } else { ticked.insert(file.id) }
                    }
                    if file.id != files.last?.id { Divider().padding(.leading, 44) }
                }
            }
            .card(padding: 12)
        }
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Text(approved.isEmpty ? "Tick files to delete" : "Delete \(countText)")
            }
            .buttonStyle(.sticker)
            .disabled(approved.isEmpty || model.isChanging || model.isScanningFolder)
            Text("Deleted for good. Kept copies stay.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    // MARK: Actions

    private func deleteApproved() async {
        let files = approved
        guard !files.isEmpty else { return }
        error = await model.deleteFiles(files, keeping: keeperFiles)
    }
}

/// One file with a tick.
private struct FileRow: View {
    let file: FileItem
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                InkCheck(isOn: isOn, size: 24)
                FileInfo(file: file)
                Spacer(minLength: 6)
                Text(ByteFormatter.string(file.bytes, precision: .twoDecimals))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(file.name), \(ByteFormatter.accessibilityString(file.bytes, precision: .twoDecimals))")
        .accessibilityValue(isOn ? "Will be deleted" : "Kept")
        .accessibilityAddTraits(.isButton)
    }
}

/// Name, where it is, and when it was last used.
private struct FileInfo: View {
    let file: FileItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(file.kind))
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text([file.subfolder, "used \(file.lastUsed.formatted(date: .abbreviated, time: .omitted))"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    static func symbol(_ kind: FileKind) -> String {
        switch kind {
        case .video: "film"
        case .archive: "doc.zipper"
        case .document: "doc.text"
        case .image: "photo"
        case .audio: "waveform"
        case .other: "doc"
        }
    }
}

/// Identical files: the kept copy marked, the others to delete.
private struct DuplicateFilesCard: View {
    let group: FileDuplicateGroup
    let keeper: FileItem.ID
    let isOn: Bool
    let pick: (FileItem.ID) -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    HStack(spacing: 10) {
                        InkCheck(isOn: isOn, size: 24)
                        Text("\(group.files.count) identical copies")
                            .font(.subheadline.weight(.semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(group.files.count) identical copies of \(group.files[0].name)")
                .accessibilityValue(isOn ? "Will be cleaned" : "Skipped")
                .accessibilityAddTraits(.isButton)
                Spacer(minLength: 6)
                if isOn {
                    Text("\u{2212}\(ByteFormatter.string(group.savedBytes(keeping: keeper), precision: .twoDecimals))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
            ForEach(group.files) { file in
                let isKeeper = file.id == keeper
                Button {
                    pick(file.id)
                } label: {
                    HStack(spacing: 10) {
                        FileInfo(file: file)
                            .opacity(isOn && !isKeeper ? 0.55 : 1)
                        Spacer(minLength: 6)
                        Text(isOn ? (isKeeper ? "keep" : "delete") : " ")
                            .font(.hand(15))
                            .foregroundStyle(isKeeper ? Theme.accent : Theme.tomato)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isOn)
                .accessibilityLabel(file.id)
                .accessibilityValue(isOn ? (isKeeper ? "Keep" : "Delete") : "Skipped")
                .accessibilityHint("Keeps this copy and deletes the others")
            }
        }
        .card(padding: 14)
    }
}

/// What the latest deletion did, checked afterwards.
private struct DeletedCard: View {
    let receipt: FileDeletionReceipt
    let reclaim: ReclaimMeasurement?

    var body: some View {
        HStack(spacing: 14) {
            IllustrationView(.shieldCheck, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text("Deleted \(receipt.deleted.count == 1 ? "1 file" : "\(receipt.deleted.count) files") · \(ByteFormatter.string(receipt.deletedBytes, precision: .twoDecimals))")
                    .font(.headline)
                Text("checked: \(receipt.folderCountBefore) \u{2192} \(receipt.folderCountAfter) files, all gone")
                    .font(.hand(15))
                    .foregroundStyle(Theme.accent)
                if let reclaim {
                    Text("Free space went up \(ByteFormatter.string(reclaim.reclaimedBytes, precision: .twoDecimals)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .sticker(fill: Theme.mintSoft, padding: 16)
        .accessibilityElement(children: .combine)
    }
}
