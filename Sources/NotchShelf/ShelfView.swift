import SwiftUI

/// The shelf, cut to fit whatever is on it. Newest top left, reading order from
/// there — so the arrangement itself says how many shots have been taken.
///
/// Eight fixed slots was the earlier shape, and a single screenshot sat in one
/// of them as a stamp in the corner of an empty page. The shelf divides the
/// space it has instead: one shot fills it, two split it down the middle, three
/// go one over two, four go two over two, and so on to eight. Nothing is ever a
/// placeholder, and the biggest picture is always the one taken last.
struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var pins: PinStore
    @ObservedObject var state: PanelState

    /// The whole of the content area: 548 across the panel's gutters, and what
    /// the 300pt body leaves under the tab strip.
    /// Shorter since the tools moved to the dial under the notch: the row of
    /// circles takes its height out of every tab, and a board measured for the
    /// old height puts the bottom row of cards through the panel's edge.
    private static let board = CGSize(width: 548, height: 232)
    private static let gap: CGFloat = 8

    var body: some View {
        Group {
            if state.isDropTarget {
                MessageView(
                    icon: "arrow.down.circle",
                    title: "Drop to keep it here",
                    subtitle: "Files stay on the shelf until you remove them"
                )
            } else if store.accessDenied {
                MessageView(
                    icon: "exclamationmark.triangle",
                    title: "No access to the screenshots folder",
                    subtitle: "System Settings → Privacy & Security → Files and Folders"
                )
            } else if store.items.isEmpty {
                MessageView(
                    icon: "camera.viewfinder",
                    title: "Nothing on the shelf",
                    subtitle: "Press ⌘⇧4, or drag a file onto the notch"
                )
            } else {
                board
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.items.count)
    }

    private var board: some View {
        let rows = Self.split(store.items.count)
        let height = rows.count > 1 ? (Self.board.height - Self.gap) / 2 : Self.board.height

        return VStack(spacing: Self.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let width = (Self.board.width - Self.gap * CGFloat(row.count - 1)) / CGFloat(row.count)
                HStack(spacing: Self.gap) {
                    ForEach(row, id: \.self) { index in
                        card(at: index, size: CGSize(width: width, height: height))
                            // A shot lands on the shelf. Everything already on
                            // it slides over to make room, which is the board
                            // resizing; the new card is the only thing that
                            // should look like it arrived.
                            .dropIn()
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Which cards go on which row. One row up to two shots, two rows after
    /// that, with the smaller half on top — three reads as one over two, and the
    /// newest shot is the wide one.
    private static func split(_ count: Int) -> [[Int]] {
        guard count > 2 else { return [Array(0..<count)] }
        let top = count / 2
        return [Array(0..<top), Array(top..<count)]
    }

    private func card(at index: Int, size: CGSize) -> some View {
        let item = store.items[index]
        return CardView(
            item: item,
            size: size,
            // A card with room for it wears its name and time all the time; the
            // small ones only under the cursor, or the shelf becomes a list of
            // file names with pictures behind them.
            showsName: size.width >= 240,
            onRemove: { store.remove(item) },
            onReveal: { store.reveal(item) },
            onPin: { pins.pin(url: item.url) }
        )
    }
}

struct CardView: View {
    let item: ShelfItem
    var size: CGSize
    /// The big card carries the file's name and time under it at all times;
    /// the small ones only when the cursor is on them.
    var showsName: Bool = false
    let onRemove: () -> Void
    let onReveal: () -> Void
    let onPin: () -> Void

    @State private var hovering = false

    private var width: CGFloat { size.width }
    private var height: CGFloat { size.height }
    private var radius: CGFloat { size.width > 200 ? Theme.radiusLarge : Theme.radiusMedium }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail

            if hovering {
                HStack(spacing: 3) {
                    GlyphButton(symbol: "pin", size: 9, diameter: 19, ink: Theme.onMedia, action: onPin)
                        .labelled("Pin this")
                        .background(Circle().fill(Theme.mediaScrim(0.6)))
                    GlyphButton(symbol: "xmark", size: 9, diameter: 19, ink: Theme.onMedia, action: onRemove)
                        .labelled("Take off the shelf")
                        .background(Circle().fill(Theme.mediaScrim(0.6)))
                }
                .padding(4)
                .dropIn()
            }

            // The file's name, shown on the card itself. It used to be a system
            // tooltip, and a tooltip rides on the view rather than on the card:
            // when the shelf reordered, the fifth card cheerfully announced the
            // third one's file.
            if showsName || hovering {
                VStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text(item.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(item.timeLabel)
                            .monospacedDigit()
                            .foregroundStyle(Theme.onMedia.opacity(0.7))
                    }
                    .font(.system(size: width >= 240 ? 12.5 : 10.5))
                    // The name is written on the picture, not on the panel, so
                    // it keeps its own ink whatever the skin — see `Theme.onMedia`.
                    .foregroundStyle(Theme.onMedia)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.mediaScrim())
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .accessibilityAddTraits(.isButton)
        .labelled("Open \(item.url.lastPathComponent)")
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Reveal in Finder", action: onReveal)
            Button("Pin to screen", action: onPin)
            Divider()
            Button("Remove from Shelf", action: onRemove)
        }
    }

    private var thumbnail: some View {
        Group {
            if let image = item.thumbnail, !item.isIcon {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // A dropped document has no picture of its own: show its file
                // type icon on a plate instead of stretching it.
                ZStack {
                    Theme.surface
                    if let image = item.thumbnail {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: min(width, height) * 0.45)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(hovering ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1)
        )
    }
}
