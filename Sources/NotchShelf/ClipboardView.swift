import SwiftUI

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var pins: PinStore

    @State private var copiedID: UUID?

    var body: some View {
        Group {
            if store.entries.isEmpty {
                MessageView(
                    icon: "doc.on.clipboard",
                    title: "Clipboard is empty",
                    subtitle: "Copy something and it lands here.\nNothing is written to disk"
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(store.entries) { entry in
                            ClipboardRow(
                                entry: entry,
                                count: store.entries.count,
                                copied: copiedID == entry.id,
                                onCopy: { copy(entry) },
                                onDelete: { store.remove(entry) },
                                onPin: { pins.pin(text: entry.text) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .fadingBottom()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: store.entries)
    }

    private func copy(_ entry: ClipboardStore.Entry) {
        store.copy(entry)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardStore.Entry
    /// How many rows there are in total. Type on this panel is set large on
    /// purpose, and a long list is exactly where large stops fitting: the row
    /// gives way rather than the list being cut off.
    let count: Int
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.text)
                .font(Theme.scaled(15, count: count, comfortable: 6))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(copied ? "Copied" : entry.timeLabel)
                .font(Theme.metaText)
                .foregroundStyle(copied ? Theme.accent : Theme.textTertiary)

            // Reserved rather than revealed: appearing on hover shoved the
            // time column left by the width of two buttons, so every row
            // twitched as the cursor swept down the list.
            GlyphButton(symbol: "pin", size: 11, diameter: 24, action: onPin)
                .labelled("Pin this entry")
                .reserved(hovering)
            // A word, not a bin: the same word the whole tab is cleared with,
            // doing the same thing to one row.
            HoverButton(title: "Clear", action: onDelete)
                .reserved(hovering)
        }
        .rowBackground(hovering: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
    }
}
