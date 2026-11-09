import StorageCore
import SwiftUI

/// Step 3's review: every picked item on a receipt, a fresh safety check
/// stamped on top, and a confirm before anything is deleted. Items can be taken
/// off the receipt; only what's left on it when Delete is tapped is approved.
struct CleanupReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// What's on the receipt. Starts as the Library selection.
    @State private var approved: [MediaItem] = []
    @State private var check: SafetyCheck?
    @State private var checkError: PhotoChangeError?
    @State private var changeError: PhotoChangeError?
    @State private var isChecking = false
    @State private var confirming = false
    @State private var progress: CGFloat = 0

    private var approvedIDs: Set<MediaItem.ID> { Set(approved.map(\.id)) }
    private var totalBytes: Int64 { approved.reduce(0) { $0 + $1.currentBytes } }
    private var isSafe: Bool { check?.isSafe == true && check?.approved == approvedIDs }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    receipt
                    safetyList
                    if let error = changeError ?? checkError {
                        Text(error.localizedDescription)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.tomato)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .background(PaperBackground())
            .safeAreaInset(edge: .bottom) { deleteBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isChanging)
                }
            }
            .overlay {
                if model.isChanging { WorkingOverlay(message: "Deleting from the test album…") }
            }
            .confirmationDialog(
                "Delete \(countText) from \u{201C}\(TestMode.albumName)\u{201D}?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Delete \(countText)", role: .destructive) {
                    Task { await deleteApproved() }
                }
            } message: {
                Text("\(ByteFormatter.string(totalBytes, precision: .twoDecimals)). They go to Recently Deleted, where you can still get them back for 30 days. Nothing else is touched.")
            }
        }
        .interactiveDismissDisabled(model.isChanging)
        .drawing($progress, duration: 2.2)
        .task {
            approved = model.selectedItems
            await runCheck()
        }
    }

    private var countText: String {
        approved.count == 1 ? "1 Item" : "\(approved.count) Items"
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("look before it goes")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
                .handwritten(progress, start: 0, length: 0.18)
            Text("Review what you picked")
                .font(.display(32))
                .boiling()
                .tracking(-1)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
    }

    // MARK: Receipt

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cleanup receipt")
                    .font(.display(21))
                    .tracking(-0.5)
                Spacer()
                Text("test album")
                    .font(.hand(16))
                    .foregroundStyle(.secondary)
            }
            Text("\(TestMode.albumName.uppercased()) · TODAY")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            DashedRule().padding(.vertical, 12)

            if approved.isEmpty {
                Text("Nothing left on the receipt. Cancel and pick again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
            ForEach(approved) { item in
                ReceiptRow(item: item, flag: flag(for: item)) {
                    withAnimation(.snappy) { approved.removeAll { $0.id == item.id } }
                    Task { await runCheck() }
                }
            }

            DashedRule().padding(.vertical, 12)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TO DELETE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                    SizeText(bytes: totalBytes, style: .largeTitle, unitStyle: .title3, precision: .twoDecimals)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ITEMS")
                        .font(.caption2.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                    Text("\(approved.count)")
                        .font(.metric(.largeTitle))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .onReceipt()
        .overlay(alignment: .bottomTrailing) { stamp.offset(x: 6, y: 18) }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var stamp: some View {
        if isChecking {
            RubberStamp(top: "safety check", main: "checking…", color: .secondary, angle: -6)
                .opacity(0.8)
        } else if isSafe {
            RubberStamp(top: "only from", main: TestMode.albumName, color: Theme.accent)
                .transition(.scale(scale: 1.8).combined(with: .opacity))
        } else if check != nil || checkError != nil {
            RubberStamp(top: "safety check", main: "stopped", color: Theme.tomato, angle: 7)
                .transition(.scale(scale: 1.8).combined(with: .opacity))
        }
    }

    private func flag(for item: MediaItem) -> String? {
        guard let check else { return nil }
        if check.outsideTestAlbum.contains(item.id) { return "not in the test album any more" }
        if check.inOtherAlbums.contains(item.id) { return "also in another album, tap × to take it off" }
        return nil
    }

    // MARK: Safety list

    private var safetyList: some View {
        let inAlbum = check.map { $0.outsideTestAlbum.isEmpty } ?? false
        let noOther = check.map { $0.inOtherAlbums.isEmpty } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            Text("Before anything is deleted")
                .font(.headline)
            SafetyLine(done: inAlbum && !isChecking, text: "Every item is in \u{201C}\(TestMode.albumName)\u{201D}, checked just now", progress: progress, start: 0.35)
            SafetyLine(done: noOther && !isChecking, text: "None of them are in any other album", progress: progress, start: 0.5)
            SafetyLine(done: true, text: "iOS asks you to confirm once more", progress: progress, start: 0.65)
            SafetyLine(done: true, text: "They wait 30 days in Recently Deleted, so you can undo", progress: progress, start: 0.8)
        }
        .padding(.top, 18)
    }

    // MARK: Delete

    private var deleteBar: some View {
        VStack(spacing: 6) {
            Button {
                confirming = true
            } label: {
                Label("Delete \(countText)", systemImage: "trash")
            }
            .buttonStyle(.stickerDestructive)
            .disabled(!isSafe || model.isChanging)
            Text(isSafe ? "Only the items on this receipt." : "Delete unlocks when the safety check passes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func runCheck() async {
        changeError = nil
        guard !approved.isEmpty else {
            check = nil
            return
        }
        isChecking = true
        let ids = approvedIDs
        let result = await model.safetyCheck(ids)
        // A newer check (after removing a row) wins.
        guard ids == approvedIDs else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            isChecking = false
            switch result {
            case .success(let value):
                check = value
                checkError = nil
            case .failure(let error):
                // Keep a refused check so each row it names says why and can be taken off.
                if case .unsafe(let refused) = error { check = refused } else { check = nil }
                checkError = error
            }
        }
    }

    private func deleteApproved() async {
        // Exactly what's on the receipt now, and only if this exact set passed the check.
        let ids = approvedIDs
        guard isSafe, check?.approved == ids else { return }
        if let error = await model.delete(approved: ids) {
            changeError = error
            if case .unsafe = error { await runCheck() }
        }
    }
}

/// One line on the receipt, with a × to take it off.
private struct ReceiptRow: View {
    let item: MediaItem
    let flag: String?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(id: item.id, side: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let flag {
                    Text(flag)
                        .font(.hand(14))
                        .foregroundStyle(Theme.tomato)
                } else {
                    Text("\(ScanGroup.kind(of: item).title) · \(item.creationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            Text(ByteFormatter.string(item.currentBytes, precision: .twoDecimals))
                .font(.subheadline.weight(.bold).monospacedDigit())
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(Theme.well, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take \(item.filename) off the receipt")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(flag == nil ? Color.clear : Theme.tomato.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, -8)
        .accessibilityElement(children: .combine)
    }
}

/// A line with a hand-drawn tick that inks in when its check passes.
struct SafetyLine: View {
    let done: Bool
    let text: String
    let progress: CGFloat
    let start: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            InkCheck(isOn: done && progress >= start, size: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(done ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .opacity(progress >= start - 0.1 ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: progress >= start - 0.1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Passed" : "Not yet")
    }
}

/// A small square thumbnail. After a delete it shows the cached copy, since
/// the item is no longer in Photos.
struct ItemThumbnail: View {
    let id: MediaItem.ID
    var side: CGFloat = 52
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.well
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous).strokeBorder(Theme.ink.opacity(0.8), lineWidth: 1.25))
        .task(id: id) {
            image = PhotoThumbnailLoader.cached(id)
            if image == nil { image = await PhotoThumbnailLoader.image(for: id, side: side) }
        }
        .accessibilityHidden(true)
    }
}
