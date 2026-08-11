import SwiftUI

/// Money and units, built like the translator next door: what goes in on the
/// left, what comes out on the right, and the two units over the gap between
/// them.
///
/// It used to be one long row — a field, two pickers, a swap button, a spinner —
/// with the answer underneath and a table of rates under that. Nothing lined up
/// with anything, and the tab that answers one question was the busiest in the
/// panel. Same shape as Translate now, and the rate table is gone: the picker
/// knows every code the service quotes, and the six most used sit at the top of
/// it by themselves.
struct ConvertView: View {
    @ObservedObject var store: ConvertStore
    @ObservedObject var state: PanelState

    @FocusState private var typing: Bool

    var body: some View {
        // Ten between the rows rather than twelve, and the boxes six shorter:
        // the list of past sums underneath needs the points more than the air
        // between two chips does.
        VStack(spacing: 10) {
            kinds
            units

            HStack(alignment: .top, spacing: 14) {
                box {
                    TextField("", text: $store.amount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .focused($typing)
                        // Return is what says "I meant that one" — the moment
                        // the sum is worth keeping, and the only one.
                        .onSubmit { withAnimation(Theme.drop) { store.record() } }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }

                box {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(store.result.isEmpty ? "—" : store.result)
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(store.result.isEmpty ? Theme.inkDim : Theme.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            past

            trouble

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 6)
        .onAppear {
            store.activate()
            state.wantsKeyboard = true
            typing = true
            // The amount is never empty — there is always a 1 in it — so taking
            // focus would otherwise open the tab with the figure selected.
            FieldCaret.toEnd()
        }
        .onDisappear {
            state.wantsKeyboard = false
            state.isEditing = false
        }
    }

    private func box<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(Theme.fillInput)
            )
    }

    /// The kinds, in the middle. A row pinned to the left edge of a tab whose
    /// content is centred is the thing that reads as crooked — the complaint was
    /// about the mass row, and it was true of all seven.
    private var kinds: some View {
        HStack(spacing: 3) {
            Spacer(minLength: 0)
            ForEach(ConvertStore.Mode.allCases) { mode in
                Chip(title: mode.title, isSelected: store.mode == mode, padding: 9) {
                    store.mode = mode
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var units: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            unitPicker(selection: $store.from)
            GlyphButton(symbol: "arrow.left.arrow.right", size: 11, diameter: 26) { store.swap() }
                .labelled("Swap them round")
            unitPicker(selection: $store.to)
            Spacer(minLength: 0)
        }
    }

    /// What has already been worked out, newest first.
    ///
    /// The same space used to hold the amount repeated in every other unit of
    /// its kind — five figures nobody had asked for, under the one that had been.
    /// A conversion that was actually made is worth more than four that were not:
    /// it is the rate looked up this morning, the weight from the recipe, and it
    /// is one press away from being the sum on screen again.
    @ViewBuilder
    private var past: some View {
        if store.history.isEmpty {
            // A line rather than an illustration: this strip is empty only until
            // the first sum, and a large grey glyph in it would be a permanent
            // announcement of a temporary state.
            Text("Press ↩ and the sum stays here")
                .font(Theme.captionText)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } else {
            // All of them, at the size of the boxes above, and the list simply
            // runs off the bottom.
            //
            // It was four short rows in small type, which is a footnote to the
            // answer rather than a list of answers. These are the same sums
            // written the same way as the one on screen, so the eye moves down
            // the column without changing gear; three fit, the rest are a scroll
            // away, and the bar down the left says how many that is.
            GaugedScroll(fade: 12) {
                VStack(spacing: 2) {
                    ForEach(store.history) { entry in
                        PastRow(entry: entry) { store.restore(entry) }
                    }
                }
            }
            // Measured, like the boxes above: the tab hands its content a width
            // and leaves the height to whatever is in it.
            .frame(height: 90)
            .padding(.top, 2)
        }
    }

    /// Whatever went wrong, and nothing at all when nothing did. Emptying the
    /// list is up in the corner with the other things this tab can be told to
    /// do — see `ContentView.trailingAction`.
    private var trouble: some View {
        HStack(spacing: 7) {
            if store.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
            }
            if !store.failure.isEmpty {
                Text(store.failure)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.alert)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 14)
    }

    /// A menu rather than a row of chips: a hundred and sixty currencies do not
    /// fit a row, and a picker is the same gesture for seven lengths anyway.
    /// The units of the current kind come first, everything else the rate table
    /// knows sits under a rule.
    private func unitPicker(selection: Binding<String>) -> some View {
        var rows: [PickerRow] = store.units.map { .item(title: $0, value: $0) }
        if !store.otherUnits.isEmpty {
            rows.append(.separator)
            rows += store.otherUnits.map { .item(title: $0, value: $0) }
        }
        return PickerPlate(title: selection.wrappedValue.isEmpty ? "—" : selection.wrappedValue,
                           rows: rows) { selection.wrappedValue = $0 }
    }
}

/// One conversion that was made, written the way it was asked.
///
/// The whole row is the button. Pressing it does not merely quote the answer
/// back — it puts the amount and both units into the boxes above, so a rate
/// looked up an hour ago is a starting point rather than a souvenir.
private struct PastRow: View {
    let entry: ConvertStore.Entry
    let onPick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 6) {
                figure(entry.amount, unit: entry.from, colour: Theme.textSecondary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkDim)
                    .accessibilityHidden(true)

                figure(entry.result, unit: entry.to,
                       colour: hovering ? Theme.tint : Theme.textPrimary)

                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(hovering ? Theme.fillHover : Theme.surface.opacity(0.55))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
        .accessibilityLabel("\(entry.amount) \(entry.from) is \(entry.result) \(entry.to). Use it again")
        .dropIn()
    }

    private func figure(_ value: String, unit: String, colour: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colour)
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        // A long figure gives way rather than pushing its own unit off the row.
        .minimumScaleFactor(0.7)
    }
}

/// One line of a `PickerPlate`: something to choose, or a rule between groups.
enum PickerRow {
    case item(title: String, value: String)
    case separator
}

/// A plate that opens a list, and opens it from anywhere on the plate.
///
/// Two goes at this before. A plain `Menu` given a styled label draws that label
/// only while the window is inactive: the moment the panel took the keyboard,
/// AppKit's own pull-down painted bare text over it, so the plate vanished
/// exactly when somebody was using the tab. Hiding a `Menu` behind a clear
/// rectangle fixed the look and broke the press — `Color.clear` gives the menu
/// nothing to size itself by, and the hit area collapsed to a sliver in the
/// middle. Twenty presses on the unit plates in a row landed on nothing.
///
/// So the plate is an ordinary button, drawn by us and hit-tested edge to edge,
/// and the list is a real `NSMenu` opened underneath it. AppKit never gets to
/// touch how the plate looks, and the whole plate is the target.
struct PickerPlate: View {
    let title: String
    var isBold = true
    let rows: [PickerRow]
    let onPick: (String) -> Void

    @State private var hovering = false
    @State private var anchor: NSView?

    var body: some View {
        Button(action: present) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: isBold ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(hovering ? Theme.fillHover : Theme.fillInput)
            )
            // Edge to edge, including the padding: the plate is the button.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchor { anchor = $0 })
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }

    private func present() {
        guard let anchor else { return }
        let menu = NSMenu()
        let sink = MenuSink.shared
        sink.onPick = onPick
        for row in rows {
            switch row {
            case .separator:
                menu.addItem(.separator())
            case let .item(title, value):
                let entry = NSMenuItem(title: title,
                                       action: #selector(MenuSink.pick(_:)),
                                       keyEquivalent: "")
                entry.target = sink
                entry.representedObject = value
                entry.state = value == self.title || title == self.title ? .on : .off
                menu.addItem(entry)
            }
        }
        // Hung from the bottom-left of the plate, the way a pop-up button does
        // it. The anchor is not flipped, so its own origin is that corner.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: anchor)
    }
}

/// Carries the choice back out of AppKit, which needs an object with a selector
/// rather than a closure.
private final class MenuSink: NSObject {
    static let shared = MenuSink()
    var onPick: ((String) -> Void)?

    @objc func pick(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        onPick?(value)
    }
}

/// A zero-size AppKit view living behind the plate, only so the menu has
/// something to hang from.
private struct MenuAnchor: NSViewRepresentable {
    let ready: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { ready(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Type on the left, read on the right. Google while there is a line out, the
/// local model when there is not — the tab says which one answered.
struct TranslateView: View {
    @ObservedObject var store: TranslateStore
    @ObservedObject var state: PanelState

    @FocusState private var typing: Bool
    /// Says "Copied" for a second after the answer has been taken.
    @State private var copied = false
    @State private var flag: DispatchWorkItem?
    @State private var hoveringAnswer = false

    /// Where the text starts inside either box. A `TextEditor` puts its own five
    /// points of padding around the line, and a `Text` puts none — which is why
    /// the two sides used to sit at different heights and the placeholder sat at
    /// a third. Everything on this tab is laid out from these two numbers.
    ///
    /// The text itself is sixteen point, up from fourteen: this is the one tab
    /// in the panel whose content is prose, and prose set at the size of a
    /// caption is a caption.
    private static let inset = CGSize(width: 14, height: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            languages

            HStack(alignment: .top, spacing: 14) {
                written
                read
            }
            // Measured, not stretched: the container hands the tab its width but
            // not its height, so `maxHeight` had nothing to fill. 300 of body,
            // less the language row, the spacing above and the panel's own air
            // at the bottom.
            //
            // Eighteen points taller than it was, and the whole of that came
            // from the row that used to sit underneath — a copy button and a
            // badge reading "Google" under every translation. What little that
            // row still has to say is said inside the box instead.
            .frame(height: 194)
        }
        // The column has to fill the tab before anything inside it can: without
        // this the stack is only as tall as its contents and the boxes have
        // nothing to grow into.
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 2)
        .onAppear {
            store.activate()
            state.wantsKeyboard = true
            typing = true
        }
        .onDisappear {
            state.wantsKeyboard = false
            state.isEditing = false
        }
    }

    /// The side that is typed into. The editor is inset by nine and adds five of
    /// its own, so the placeholder is drawn at fourteen to land on exactly the
    /// same pixel as the first letter typed.
    private var written: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Theme.fillInput)

            TextEditor(text: $store.input)
                .font(.system(size: proseSize))
                .scrollContentBackground(.hidden)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Self.inset.width - 5)
                .padding(.vertical, Self.inset.height)
                .focused($typing)

            if store.input.isEmpty {
                Text(store.sourceSample)
                    .font(.system(size: proseSize))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Self.inset.width)
                    .padding(.vertical, Self.inset.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The side that is read. Pinned to the top left corner and never animated:
    /// a translation that slides into place as it arrives is a translation being
    /// read twice.
    ///
    /// The whole box is the copy button. There was a labelled button for it
    /// under the box, which is one more thing to aim at than the gesture needs:
    /// the answer is the only thing on that side, so pressing the answer can
    /// only mean one thing. The text still selects, so a single word can be
    /// taken out of a paragraph by dragging over it as before.
    private var read: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(hoveringAnswer && !store.output.isEmpty ? Theme.fillHover : Theme.surface)

            ScrollView(.vertical, showsIndicators: false) {
                Text(shown)
                    .font(.system(size: proseSize))
                    .foregroundStyle(store.output.isEmpty ? Theme.inkDim : Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, Self.inset.width)
            .padding(.vertical, Self.inset.height)

            // Inside the box rather than on a row of its own: this is empty
            // almost always, and an empty row is eighteen points of a
            // three-hundred point panel spent on nothing.
            VStack {
                Spacer(minLength: 0)
                engineLine
            }
            .padding(.horizontal, Self.inset.width)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: copyOutput)
        .onHover { hoveringAnswer = $0 }
        .accessibilityAddTraits(.isButton)
        .labelled(store.output.isEmpty ? "The translation appears here" : "Press to copy the translation")
        .animation(Theme.touch, value: hoveringAnswer)
        .animation(nil, value: store.output)
    }

    /// Nothing typed: the greeting on the left, really translated, on the right.
    private var shown: String {
        if !store.output.isEmpty { return store.output }
        return store.input.isEmpty ? store.sample : ""
    }

    /// The pair sits in the middle, over the gap between the two boxes, because
    /// that is where the arrow between them points.
    private var languages: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            LanguageMenu(selection: $store.source, includesAuto: true)

            GlyphButton(symbol: "arrow.left.arrow.right", size: 11, diameter: 26) { store.swap() }
                .labelled("Swap them round")

            LanguageMenu(selection: $store.target, includesAuto: false)

            Spacer(minLength: 0)
        }
    }

    /// Prose, set as prose — and smaller the more of it there is.
    ///
    /// Twenty for a word or a sentence, which is what this tab is used for most
    /// of the time, stepping down to thirteen for a paragraph so a long
    /// translation still fits the box instead of scrolling out of it. The two
    /// sides always agree: reading the answer at one size and the question at
    /// another makes them look like different documents.
    /// Two points up from twenty at the top, and it holds that size for longer:
    /// the boxes are forty points taller than they were, so a paragraph that
    /// used to have to shrink to fit now has somewhere to go.
    private var proseSize: CGFloat {
        let longest = max(store.input.count, store.output.count)
        return Theme.shrink(22, count: longest / 38, comfortable: 2, floor: 14)
    }

    /// Trouble, and only trouble.
    ///
    /// This line used to name the engine on every translation — a globe and the
    /// word "Google" under every answer, or the name of the local model — and
    /// carry a button reading "Copy the translation" at the end of it. Neither
    /// was worth a line of a three-hundred point panel: who translated it is not
    /// a decision anybody makes, and the answer itself is now the copy button.
    /// What is left is a warning, which is the one thing here that has to be
    /// read the moment it appears.
    private var engineLine: some View {
        HStack(spacing: 6) {
            if store.isWorking {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
            }
            if case let .failed(message) = store.engine {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.alert)
                    .lineLimit(1)
            } else if copied {
                Text("Copied")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 18)
    }

    /// Copies the answer and says so for a moment.
    private func copyOutput() {
        guard !store.output.isEmpty else { return }
        store.copyOutput()
        flag?.cancel()
        withAnimation(Theme.settle) { copied = true }
        let task = DispatchWorkItem { withAnimation(Theme.settle) { copied = false } }
        flag = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)
    }
}

/// One language out of every language there is.
///
/// The four that get used are at the top and the rest follow in alphabetical
/// order, so the common choice is a single press and the rare one is still
/// there — which is the whole difference between a picker and a row of chips.
private struct LanguageMenu: View {
    @Binding var selection: String
    let includesAuto: Bool

    var body: some View {
        var rows: [PickerRow] = []
        if includesAuto {
            rows.append(.item(title: "Detect", value: "auto"))
            rows.append(.separator)
        }
        rows += TranslateStore.favourites.map { .item(title: TranslateStore.name(of: $0), value: $0) }
        rows.append(.separator)
        rows += TranslateStore.languages.map { .item(title: $0.englishName, value: $0.code) }
        return PickerPlate(title: TranslateStore.name(of: selection),
                           isBold: false,
                           rows: rows) { selection = $0 }
    }
}
