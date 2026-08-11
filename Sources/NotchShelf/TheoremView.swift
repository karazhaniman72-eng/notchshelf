import SwiftUI

struct TheoremView: View {
    @ObservedObject var store: TheoremStore
    /// For the empty state only — the same problem and the same button as
    /// `PlansView`: with nowhere to read from, the fix belongs where the
    /// emptiness is rather than behind the gear.
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Group {
            if !store.hasFolder {
                MessageView(icon: "folder.badge.questionmark",
                            title: "No folder of textbooks yet",
                            subtitle: "Pick one, and the newest book in it becomes a statement a day",
                            action: (title: "Choose a folder",
                                     run: { settings.chooseFolder(.textbooks) }))
            } else if store.isReading {
                MessageView(icon: "book.pages",
                            title: "Reading the textbook",
                            subtitle: "Cutting it into statements, once")
            } else if let item = store.current {
                statement(item)
            } else if store.items.isEmpty, !store.source.isEmpty {
                MessageView(icon: "questionmark.text.page",
                            title: "No statements in that file",
                            subtitle: "Lines starting with Теорема, Лемма, Определение are what it looks for",
                            action: (title: "Open the folder", run: store.revealFolder))
            } else {
                MessageView(icon: "text.book.closed",
                            title: "No textbook in that folder",
                            subtitle: "Drop a PDF, txt or md into it",
                            action: (title: "Open the folder", run: store.revealFolder))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.index)
    }

    private func statement(_ item: TheoremStore.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.kind.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.fillActive))

                Text(item.title)
                    .font(Theme.titleText)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            ScrollView(.vertical, showsIndicators: false) {
                // A theorem is read, not glanced at, and this is the longest
                // stretch of prose in the panel: it gives way by a point as it
                // gets longer rather than being set small for the worst case.
                Text(item.body)
                    .font(.system(size: Theme.shrink(15.5, count: item.body.count / 90, comfortable: 3, floor: 12.5)))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 4) {
                Text("\(store.position)  ·  \(store.source)")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                HoverButton(title: "Copy") { store.copyCurrent() }
                GlyphButton(symbol: "chevron.left", size: 11, diameter: 26) { store.advance(by: -1) }
                    .labelled("The one before")
                GlyphButton(symbol: "chevron.right", size: 11, diameter: 26) { store.advance(by: 1) }
                    .labelled("The next one")
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 2)
    }
}
