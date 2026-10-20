import StorageCore
import SwiftUI

/// Browse, filter, sort, and select demo media.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var detailItem: MediaItem?

    var body: some View {
        @Bindable var model = model
        content
            .background(Theme.background)
            .navigationTitle("Library")
            .safeAreaInset(edge: .top, spacing: 0) {
                FilterBar(filter: $model.libraryFilter)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !model.selection.isEmpty {
                    SelectionBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: model.selection.isEmpty)
            .toolbar { toolbarContent }
            .sheet(item: $detailItem) { item in
                MediaDetailView(itemID: item.id)
            }
    }

    @ViewBuilder
    private var content: some View {
        let items = model.visibleItems
        if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            EmptyStateView(
                illustration: .emptyBox,
                title: "No media in this library",
                message: "The Empty Library scenario has no items. Switch scenarios in Settings to browse sample media.",
                actionTitle: "Open Settings",
                action: { model.selectedTab = .settings }
            )
            .frame(maxHeight: .infinity)
        } else if items.isEmpty {
            EmptyStateView(
                illustration: .shieldCheck,
                title: "Nothing in \(model.libraryFilter.title)",
                message: "There are no items in this category right now.",
                actionTitle: "Show All",
                action: { model.libraryFilter = .all }
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LibraryHeader(count: items.count, bytes: model.visibleBytes)
                switch model.libraryLayout {
                case .grid:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 3)], spacing: 3) {
                        ForEach(items) { item in
                            MediaGridCell(item: item, isSelected: model.isSelected(item), isSelecting: model.isSelecting)
                                .onTapGesture { tap(item) }
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                case .list:
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            MediaListRow(item: item, isSelected: model.isSelected(item), isSelecting: model.isSelecting)
                                .onTapGesture { tap(item) }
                                .contextMenu { contextMenu(for: item) }
                            Divider().padding(.leading, 84)
                        }
                    }
                    .background(Theme.surface)
                }
            }
        }
    }

    private func tap(_ item: MediaItem) {
        if model.isSelecting {
            model.toggleSelection(item)
        } else {
            detailItem = item
        }
    }

    @ViewBuilder
    private func contextMenu(for item: MediaItem) -> some View {
        Button {
            model.toggleSelection(item)
        } label: {
            if model.isSelected(item) {
                Label("Deselect", systemImage: "minus.circle")
            } else {
                Label("Select", systemImage: "checkmark.circle")
            }
        }
        Button {
            detailItem = item
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.isSelecting {
                Button(model.areAllVisibleSelected ? "Deselect All" : "Select All") {
                    if model.areAllVisibleSelected {
                        model.deselectAllVisible()
                    } else {
                        model.selectAllVisible()
                    }
                }
                .disabled(model.visibleItems.isEmpty)
            } else {
                Menu {
                    Picker("Sort", selection: Bindable(model).librarySort) {
                        ForEach(MediaSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    Picker("Layout", selection: Bindable(model).libraryLayout) {
                        ForEach(LibraryLayout.allCases) { layout in
                            Label(layout.title, systemImage: layout.systemImage).tag(layout)
                        }
                    }
                } label: {
                    Label("Sort and View", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(model.isSelecting ? "Done" : "Select") {
                model.isSelecting.toggle()
            }
            .fontWeight(.semibold)
            .disabled(model.items.isEmpty)
        }
    }
}

/// Item count and size for the current filter, plus the active sort.
private struct LibraryHeader: View {
    @Environment(AppModel.self) private var model
    let count: Int
    let bytes: Int64

    var body: some View {
        HStack {
            Text("\(count.formatted()) items · \(ByteFormatter.string(bytes))")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(model.librarySort.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontally scrolling category chips.
private struct FilterBar: View {
    @Binding var filter: MediaFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MediaFilter.allCases) { option in
                    let isOn = option == filter
                    Button {
                        filter = option
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isOn ? Color(hex: 0x1A1A17) : .primary)
                            .background(isOn ? Theme.mint : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(isOn ? Color(hex: 0x1A1A17) : Theme.hairline, lineWidth: isOn ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Theme.background)
    }
}

/// Bottom bar showing what's selected, with the route into cleanup review.
private struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.selection.count.formatted()) selected")
                    .font(.headline)
                Text(ByteFormatter.string(model.selectedBytes))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Clear", action: model.clearSelection)
                .font(.subheadline.weight(.semibold))
                .tint(Theme.accent)
            Button("Review") {
                model.isReviewPresented = true
            }
            .buttonStyle(StickerButtonStyle())
            .frame(width: 120)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .environment(AppModel.preview(.typical))
}
