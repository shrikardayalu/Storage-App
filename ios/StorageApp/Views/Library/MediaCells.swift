import StorageCore
import SwiftUI

/// Square grid cell: thumbnail with size, duration, and selection overlays.
struct MediaGridCell: View {
    let item: MediaItem
    let isSelected: Bool
    let isSelecting: Bool

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { MediaThumbnail(item: item) }
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    if let duration = item.duration {
                        Image(systemName: "play.fill").font(.system(size: 8))
                        Text(DurationFormatter.string(duration))
                    }
                    Spacer(minLength: 0)
                    Text(ByteFormatter.string(item.currentBytes))
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .topLeading) {
                if item.isCompressed {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(hex: 0x1A1A17))
                        .padding(4)
                        .background(Theme.mint, in: Circle())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting || isSelected {
                    SelectionMark(isSelected: isSelected).padding(6)
                }
            }
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(Theme.mint, lineWidth: 3)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilityDescription)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// List row: small thumbnail with filename, metadata, and size.
struct MediaListRow: View {
    let item: MediaItem
    let isSelected: Bool
    let isSelecting: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting || isSelected {
                SelectionMark(isSelected: isSelected)
            }
            MediaThumbnail(item: item)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormatter.string(item.currentBytes))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if item.isCompressed {
                    Text("Compressed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.mintSoft.opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var metadata: String {
        var parts = [item.creationDate.formatted(date: .abbreviated, time: .omitted), item.format.displayName]
        if let duration = item.duration {
            parts.append(DurationFormatter.string(duration))
        }
        return parts.joined(separator: " · ")
    }
}

/// Round checkmark used in both layouts.
struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Theme.mint : Color.black.opacity(0.18))
            Circle()
                .strokeBorder(isSelected ? Color(hex: 0x1A1A17) : .white, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x1A1A17))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
