import StorageCore
import SwiftUI
import UIKit

/// Free: the photos most likely worth deleting (extra copies, blurry and
/// black shots, receipts, documents, old screenshots), one at a time.
/// Swipe left to delete, right to keep, with undo. Nothing is deleted while
/// swiping: the left swipes are collected and removed together at the end,
/// so iOS asks once, and they wait in Recently Deleted for 30 days.
///
/// Pro's Photo Cleanup does the same photos in one tap; this is the by-hand version.
struct SwipeCleanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var queue: [SwipeCandidate] = []
    @State private var position = 0
    /// What each swipe decided, newest last, for undo.
    @State private var decisions: [Decision] = []
    @State private var drag: CGSize = .zero
    @State private var loaded = false
    @State private var confirming = false
    @State private var error: PhotoChangeError?

    private var current: SwipeCandidate? { queue.indices.contains(position) ? queue[position] : nil }
    private var toDelete: [SwipeCandidate] { decisions.filter { $0.delete }.map { $0.candidate } }
    private var kept: [MediaItem.ID] { decisions.filter { !$0.delete }.map(\.candidate.id) }
    private var deleteBytes: Int64 { toDelete.reduce(0) { $0 + $1.item.currentBytes } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !loaded || model.isAnalyzing {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView(value: model.analysisProgress)
                        .tint(Theme.accent)
                    Text("Finding photos you probably don't need, on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .card(padding: 16)
                .padding(.horizontal, 20)
                Spacer()
            } else if let current {
                Spacer(minLength: 8)
                card(current)
                    .id(current.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                Spacer(minLength: 8)
                controls
            } else {
                Spacer()
                EmptyStateView(
                    illustration: .shieldCheck,
                    title: queue.isEmpty ? "Nothing to swipe" : "All caught up",
                    message: queue.isEmpty
                        ? "No likely deletes in \u{201C}\(TestMode.albumName)\u{201D} right now."
                        : (toDelete.isEmpty ? "You kept everything. Nothing will be deleted." : "Delete what you swiped left on below, or undo any of it first.")
                )
                .padding(.horizontal, 20)
                if !decisions.isEmpty {
                    Button("Undo last") { undo() }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 12)
                }
                Spacer()
            }
            if let error {
                Text(error.localizedDescription)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.tomato)
                    .padding(.horizontal, 20)
            }
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !toDelete.isEmpty { deleteBar }
        }
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Deleting what you swiped away…") }
        }
        .confirmationDialog(
            "Delete \(countText) from \u{201C}\(TestMode.albumName)\u{201D}?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete \(countText)", role: .destructive) { Task { await deleteMarked() } }
        } message: {
            Text("\(ByteFormatter.string(deleteBytes, precision: .twoDecimals)). They go to Recently Deleted, where you can recover them for 30 days.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: decisions.count)
        .task { await load() }
        // Photos kept on a swipe stay kept: they aren't offered again next time.
        .onDisappear { model.markSwipeKept(kept) }
        .onChange(of: model.junkReport) { _, _ in
            // After a delete the album is scanned again: start over on what's left.
            if !model.isChanging, decisions.isEmpty { Task { await load() } }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("left to delete, right to keep")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
            Text("Swipe to clean")
                .font(.display(32))
                .boiling()
                .accessibilityAddTraits(.isHeader)
            if loaded, !queue.isEmpty {
                Text("\(min(position + 1, queue.count)) of \(queue.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// How far a card has to travel (or be flicked) to count as a swipe.
    private static let swipeDistance: CGFloat = 60

    private func card(_ candidate: SwipeCandidate) -> some View {
        let lean = drag.width / Self.swipeDistance
        return VStack(alignment: .leading, spacing: 10) {
            SwipePhoto(id: candidate.item.id)
                .frame(maxWidth: .infinity)
                .aspectRatio(candidate.item.pixelHeight > 0 ? CGFloat(candidate.item.pixelWidth) / CGFloat(candidate.item.pixelHeight) : 1, contentMode: .fit)
                .frame(maxHeight: 380)
                .overlay(alignment: .topLeading) {
                    RubberStamp(top: "swipe", main: "keep", color: Theme.accent, angle: -12)
                        .opacity(Double(max(0, lean)))
                        .padding(14)
                }
                .overlay(alignment: .topTrailing) {
                    RubberStamp(top: "swipe", main: "delete", color: Theme.tomato, angle: 12)
                        .opacity(Double(max(0, -lean)))
                        .padding(14)
                }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.reason)
                        .font(.headline)
                    Text(candidate.item.creationDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(ByteFormatter.string(candidate.item.currentBytes, precision: .twoDecimals))
                    .font(.metric(.headline))
                    .monospacedDigit()
            }
        }
        .sticker(padding: 12)
        .padding(.horizontal, 20)
        .offset(x: drag.width, y: drag.height * 0.2)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width) / 22))
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    // A short drag or a quick flick is enough; the predicted end
                    // counts the flick's speed, not just how far the finger went.
                    let reach = abs(value.predictedEndTranslation.width) > abs(value.translation.width)
                        ? value.predictedEndTranslation.width : value.translation.width
                    if reach < -Self.swipeDistance {
                        decide(delete: true)
                    } else if reach > Self.swipeDistance {
                        decide(delete: false)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Use the Delete and Keep buttons below.")
        .accessibilityAction(named: "Delete") { decide(delete: true) }
        .accessibilityAction(named: "Keep") { decide(delete: false) }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            CircleAction(symbol: "trash", label: "Delete", tint: Theme.tomato) { decide(delete: true) }
            CircleAction(symbol: "arrow.uturn.backward", label: "Undo", tint: Theme.ink, small: true) { undo() }
                .disabled(decisions.isEmpty)
                .opacity(decisions.isEmpty ? 0.35 : 1)
            CircleAction(symbol: "heart", label: "Keep", tint: Theme.accent) { decide(delete: false) }
        }
        .padding(.bottom, 14)
    }

    private var deleteBar: some View {
        VStack(spacing: 6) {
            Button("Delete \(countText) · \(ByteFormatter.string(deleteBytes, precision: .twoDecimals))") { confirming = true }
                .buttonStyle(.stickerDestructive)
                .disabled(model.isChanging)
            Text("Nothing is deleted until you tap this. Undo any swipe first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private var countText: String {
        toDelete.count == 1 ? "1 Photo" : "\(toDelete.count) Photos"
    }

    // MARK: Actions

    private func load() async {
        await model.findJunk()
        let candidates = model.swipeCandidates ?? []
        // Leave out anything the album check won't let the app touch, such as a photo in another album.
        var blocked: Set<MediaItem.ID> = []
        if !candidates.isEmpty, case .success(let check) = await model.albumCheck(Set(candidates.map(\.id))) {
            blocked = check.outsideTestAlbum.union(check.inOtherAlbums)
        }
        queue = candidates.filter { !blocked.contains($0.id) }
        position = 0
        decisions = []
        drag = .zero
        loaded = true
    }

    private func decide(delete: Bool) {
        guard let current else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            drag = .zero
            decisions.append(Decision(candidate: current, delete: delete))
            position += 1
        }
    }

    private func undo() {
        guard !decisions.isEmpty else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            decisions.removeLast()
            position = max(0, position - 1)
            drag = .zero
        }
    }

    private func deleteMarked() async {
        let remove = Set(toDelete.map(\.id))
        let keepers = Set(toDelete.compactMap(\.keeper))
        guard !remove.isEmpty else { return }
        model.markSwipeKept(kept)
        if let failure = await model.removeJunk(remove, keeping: keepers) {
            error = failure
        } else {
            error = nil
            await load()
        }
    }
}

/// One swipe: which photo, and whether it goes.
private struct Decision: Equatable {
    let candidate: SwipeCandidate
    let delete: Bool
}

/// A big copy of one photo for the swipe card.
private struct SwipePhoto: View {
    let id: MediaItem.ID
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.well
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.ink.opacity(0.8), lineWidth: 1.25))
        .task(id: id) {
            image = PhotoThumbnailLoader.cached(id)
            image = await PhotoThumbnailLoader.image(for: id, side: 700) ?? image
        }
        .accessibilityHidden(true)
    }
}

/// A round button under the swipe card.
private struct CircleAction: View {
    let symbol: String
    let label: String
    let tint: Color
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(small ? .body.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: small ? 48 : 66, height: small ? 48 : 66)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.ink.opacity(0.85), lineWidth: 1.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    NavigationStack { SwipeCleanView() }
        .environment(AppModel.preview())
}
