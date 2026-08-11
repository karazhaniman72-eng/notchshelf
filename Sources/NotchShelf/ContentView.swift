import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    /// Observed by name, not reached through `model`. AppModel publishes
    /// nothing itself, so a view watching only it never hears that the panel
    /// opened — it stayed blank while the log cheerfully said "opened".
    @ObservedObject var state: PanelState
    /// The two stores whose contents decide whether a button in the tab strip
    /// exists at all.
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var convert: ConvertStore
    @ObservedObject var translate: TranslateStore
    /// Which tabs are in the strip at all, and what the panel is made of.
    @ObservedObject var settings: SettingsStore
    /// Not passed in: there is one palette and every view reads it through
    /// `Theme`. It is observed here so that changing the colour repaints a panel
    /// that is already open — `Theme` is an enum of static properties and
    /// SwiftUI cannot watch it, so without this the new colour would only turn
    /// up the next time the panel was opened.
    @ObservedObject private var palette = Palette.shared
    /// Observed for the same reason as the palette: the white background is the
    /// light skin, every colour in `Theme` is mixed from it, and `Theme` is not
    /// something SwiftUI can watch.
    @ObservedObject private var skin = Skin.shared
    let panelHeight: CGFloat

    /// Which way the next tab arrives from: right when moving right along the
    /// row, left when moving back.
    @State private var direction: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            slab
            // Outside the black, hanging under its bottom left corner. The whole
            // of the panel above belongs to the open tab.
            modeDial
        }
        // The black slab is narrower than the window: a transparent lane runs
        // down either side of it, and the gear hangs in the right-hand one.
        .frame(width: PanelController.expandedWidth)
        .overlay(alignment: .topTrailing) { gear }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The settings, outside the panel at the top right — the mirror of the
    /// tools hanging outside it at the bottom left.
    ///
    /// Out there rather than in the strip because it is not a tab: the strip is
    /// what the panel is *for*, and a page about the panel itself sitting in it
    /// would take a place from a subject and be the first thing anybody
    /// switched off. Out there rather than in the top right corner of the black,
    /// because that corner already belongs to what the open tab can be told to
    /// do — "Clear" and the reload arrow live there, and a gear among them would
    /// read as one more thing that empties something.
    private var gear: some View {
        ModeDial(symbol: "gearshape",
                 title: "Settings",
                 isActive: state.showsSettings) {
            withAnimation(Theme.swap) {
                state.showsSettings.toggle()
                if state.showsSettings { state.settingsMode = .tabs }
            }
        }
        .offset(x: PanelState.gearSize + 8, y: PanelState.gearTop)
        // It belongs to the open panel and arrives with it, like the tools.
        .opacity(state.isExpanded ? 1 : 0)
        .allowsHitTesting(state.isExpanded)
        .animation(Theme.unfold, value: state.isExpanded)
    }

    /// The panel itself: the black body and everything written on it.
    private var slab: some View {
        ZStack(alignment: .topTrailing) {
            // One body, full width from the top pixel of the screen down. It
            // covers the menu bar across its own width, which is what makes it
            // read as one slab growing out of the bezel; the notch is simply
            // inside it, black on black while the panel is black.
            //
            // Frosted if that is what was asked for, and frosted all the way up:
            // the top strip is no more opaque than the rest. See
            // `PanelBackground` for what that costs and why it is paid.
            PanelBackdropSlab(settings: settings)
                .frame(maxWidth: .infinity)
                // The slab is a different kind of view in each of the five
                // choices — a filled shape for two of them, a hosted material
                // for three — so switching between them is a cut, not a change,
                // and SwiftUI has nothing to interpolate. Cross-fading the whole
                // thing is what makes picking a background feel like turning a
                // dial rather than throwing a switch.
                .id(settings.backdrop)
                .transition(.opacity)
                .animation(Theme.settle, value: settings.backdrop)

            VStack(spacing: 0) {
                // The notch strip stays empty: notch is black, panel is black,
                // the boundary between them must not read.
                Color.clear.frame(height: state.notchSize.height)

                tabStrip
                content
                    // Top, not centre: a tab with one short row in it used to
                    // leave the row floating in the middle of a tall black
                    // rectangle.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.bottom, Theme.contentBottom)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: fullHeight, alignment: .top)
            // Fades a shade faster than the slab moves, so nothing is caught
            // half-drawn on the closing edge — but not so much faster that the
            // last third of the unroll is an empty black box. Easing in on the
            // way out rather than out: leaving should start gently and finish,
            // which is the opposite shape from arriving.
            .opacity(state.isExpanded ? 1 : 0)
            .animation(state.isExpanded ? .easeOut(duration: 0.3) : .easeIn(duration: 0.16),
                       value: state.isExpanded)

        }
        .onChange(of: state.tab) { old, new in
            direction = (PanelTab.allCases.firstIndex(of: new) ?? 0)
                >= (PanelTab.allCases.firstIndex(of: old) ?? 0) ? 1 : -1
        }
        // The panel is not shown and hidden, it is unrolled: the slab grows to
        // its full height and the contents are revealed by the growing edge, the
        // way a blind comes down. Content is laid out at full height throughout
        // and simply clipped, so nothing reflows while the movement runs —
        // reflowing mid-animation is what made the old version look like a
        // window appearing rather than a shelf sliding out of the bezel.
        .frame(height: state.isExpanded ? fullHeight : 0, alignment: .top)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Theme.unfold, value: state.isExpanded)
    }

    /// The black part of the window: everything except the tool strip under it.
    private var bodyHeight: CGFloat {
        min(PanelState.bodyHeight, panelHeight - PanelState.dialHeight)
    }

    private var fullHeight: CGFloat { state.notchSize.height + bodyHeight }

    // MARK: - Tabs

    private var tabStrip: some View {
        HStack(spacing: 0) {
            // Only the tabs that are switched on. The row is the one place the
            // choice shows, and a tab switched off leaves no gap behind it.
            ForEach(settings.tabs) { tab in
                TabChip(tab: tab, isActive: state.tab == tab && !state.showsSettings) {
                    // Picking a tab is also how the settings page is left: the
                    // gear opened something over the panel, and going back to
                    // work is going back to a subject.
                    guard state.tab != tab || state.showsSettings else { return }
                    withAnimation(Theme.swap) {
                        state.resetModes()
                        state.showsSettings = false
                        state.tab = tab
                    }
                }
            }

            Spacer(minLength: 8)

            // The name of the open tab, in the row it belongs to.
            //
            // It was laid over the strip before, on the theory that a word set
            // into the row would push the icons about as it changed length. It
            // does not: the icons are held against the left edge and the spacer
            // above takes the slack. What the overlay did instead was collide
            // with whatever sat in the corner — "Convert" straight through the
            // "Clear" beside it — because a fixed inset cannot know how wide
            // this tab's actions happen to be.
            Text(state.showsSettings ? "Settings" : state.tab.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
                .padding(.trailing, 4)
                .allowsHitTesting(false)
                // Keyed on the tab, so the word is replaced rather than edited:
                // the new name lands the way the tab it names does.
                .id(state.tab)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.86).combined(with: .opacity).animation(Theme.drop),
                    removal: .opacity.animation(.easeOut(duration: 0.14))
                ))

            trailingAction
        }
        .animation(Theme.swap, value: state.tab)
        // The same gutter as everything under it, so the lit tab's underline
        // starts on the same vertical line as the content it belongs to.
        .padding(.horizontal, Theme.gutter)
        // Tight to the notch above it: the row is the first thing under the
        // cut-out and every point of slack over it reads as a gap in the black.
        .padding(.top, 1)
        .padding(.bottom, 4)
    }

    /// What the tab as a whole can be told to do — read the folder again, forget
    /// what it is holding. Not the tools inside it: those are the dial under the
    /// notch, one row down.
    ///
    /// A thing that changes data says what it changes to, in a word: "Clear"
    /// rather than a bin. A bin is a picture of somewhere rubbish goes, and it
    /// was doing the work of a verb on four different tabs.
    ///
    /// Nothing here holds an empty seat any more. Four of these used to be
    /// `.reserved`, which keeps a control's place in the row while it has
    /// nothing to do — right for a row of buttons, wrong for the last thing in
    /// a line, because an invisible button on the end pushes the tab's name
    /// away from the edge and leaves a gap that reads as a mistake. Where there
    /// is nothing to press, the name runs to the corner.
    ///
    /// A refresh button now means one thing everywhere: this reading was taken
    /// at some moment and the world may have moved since. The folder, the
    /// calendar, the forecast and the speed of the line are all of those. Rates
    /// are not — they are fetched when the tab opens and republished once a day
    /// at the source, so the button was offering to ask again for the same
    /// table.
    @ViewBuilder
    private var trailingAction: some View {
        if state.showsSettings {
            // Nothing here. Every switch on that page takes effect where it is
            // pressed, so there is no change to apply and nothing to undo.
            EmptyView()
        } else {
            tabAction
        }
    }

    @ViewBuilder
    private var tabAction: some View {
        switch state.tab {
        case .shelf:
            // Always there, full strength, whether the shelf is full or already
            // empty. It used to fade out once there was nothing to throw away,
            // which is a control that vanishes the moment you look for it.
            HoverButton(title: "Clear") { shelf.clear() }
                .labelled("Take everything off the shelf")
        case .clipboard:
            // Passwords are kept, never cleared: the one thing on this tab that
            // cannot be got back if it goes.
            if state.clipboardMode == .history {
                HoverButton(title: "Clear") { clipboard.clear() }
                    .labelled("Forget everything copied")
            }
        case .downloads:
            GlyphButton(symbol: "arrow.clockwise", size: 12) { model.downloads.reload() }
                .labelled("Read the folder again")
        case .plans:
            GlyphButton(symbol: "arrow.clockwise", size: 12) {
                model.calendar.reload()
                model.plans.reload()
            }
            .labelled("Read the calendar and the plan file again")
        case .calc:
            HoverButton(title: "Clear") { model.math.clear() }
                .labelled("Wipe the sum and everything counted")
        case .convert:
            if !convert.history.isEmpty {
                HoverButton(title: "Clear") { convert.clearHistory() }
                    .labelled("Forget every conversion listed")
            }
        case .translate:
            if !translate.input.isEmpty {
                HoverButton(title: "Clear") { translate.clear() }
                    .labelled("Empty both boxes")
            }
        case .music:
            EmptyView()
        case .weather:
            GlyphButton(symbol: "arrow.clockwise", size: 12) { model.weather.reload() }
                .labelled("Ask for the forecast again")
        case .system:
            if state.systemMode == .line {
                GlyphButton(symbol: "arrow.clockwise", size: 12) { model.network.refresh() }
                    .labelled("Measure the line again")
            }
        }
    }

    /// The tools of the open tab, as a row of small circles directly under the
    /// notch — the one place on this panel the eye already goes.
    ///
    /// They used to be square switches in the top right corner, next to the
    /// actions, which put "open the eyedropper" and "empty the shelf" in the same
    /// row wearing the same clothes. A tool is not an action: it changes what the
    /// tab is showing, so it sits over the thing it changes and stays out of the
    /// corner where things get pressed by accident.
    ///
    /// The row keeps its height on tabs that have no tools. A strip that appears
    /// and disappears would move the whole tab up and down under the cursor every
    /// time one is picked.
    private var modeDial: some View {
        HStack(spacing: 8) {
            // Left, under the corner of the panel, not centred under the notch:
            // centred they sat over whatever the panel was covering, and the eye
            // has to find them in the same place on every tab.
            ForEach(dials) { dial in
                ModeDial(symbol: dial.symbol,
                         title: dial.title,
                         isActive: dial.isActive,
                         action: dial.pick)
                    // A tab with five tools giving way to one with two used to
                    // be three discs blinking out of existence. They land and
                    // leave the way everything else on this panel does.
                    .dropIn()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: PanelState.dialHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.swap, value: state.tab)
        .animation(Theme.swap, value: state.showsSettings)
        // They belong to the panel: they arrive with it and go with it.
        .opacity(state.isExpanded ? 1 : 0)
        .offset(y: state.isExpanded ? 0 : -PanelState.dialHeight)
        .animation(Theme.unfold, value: state.isExpanded)
    }

    /// The discs hanging under the panel: whatever the thing on screen can be
    /// switched between.
    ///
    /// One list built by hand rather than a `switch` full of `ForEach`es, and
    /// the reason is the identity. All of those rows lived in the same `HStack`,
    /// so their ids shared one namespace — and `ShelfMode.colour` and
    /// `SettingsMode.colour` are both "colour". Two different discs answering to
    /// one name in one container is the bug that ate half the days of the month
    /// out of the calendar; here it would have had the eyedropper and the
    /// palette trading places on the way in. The family goes in the id.
    private var dials: [DialItem] {
        if state.showsSettings {
            // The settings page has tools of its own, and they hang in the same
            // place as every other tab's: what is being changed is one choice at
            // a time, and the page above belongs to it.
            return SettingsMode.allCases.map { mode in
                DialItem(family: "settings", mode: mode, isActive: state.settingsMode == mode) {
                    state.settingsMode = mode
                }
            }
        }
        switch state.tab {
        case .shelf:
            return ShelfMode.allCases.map { mode in
                DialItem(family: "shelf", mode: mode, isActive: state.shelfMode == mode) {
                    state.shelfMode = mode
                }
            }
        case .clipboard:
            return ClipboardMode.allCases.map { mode in
                DialItem(family: "clipboard", mode: mode, isActive: state.clipboardMode == mode) {
                    state.clipboardMode = mode
                }
            }
        case .calc:
            return CalcMode.allCases.map { mode in
                DialItem(family: "calc", mode: mode, isActive: state.calcMode == mode) {
                    state.calcMode = mode
                }
            }
        case .system:
            return SystemMode.allCases.map { mode in
                DialItem(family: "system", mode: mode, isActive: state.systemMode == mode) {
                    state.systemMode = mode
                }
            }
        default:
            return []
        }
    }

    // MARK: - Bodies

    @ViewBuilder
    private var content: some View {
        ZStack {
            if state.showsSettings {
                SettingsView(settings: settings,
                             palette: palette,
                             state: state)
            } else {
                tabContent
            }
        }
        // One tab gives way to the next with a shove in the direction travelled.
        // A full-width slide was tried and thrown out: two tabs crossing a 300
        // point window read as the panel itself moving. Thirty-four points is
        // enough to say which way the row went, and the fade carries the rest —
        // the panel stays put, only what is written on it travels.
        .transition(.asymmetric(
            insertion: .offset(x: direction * Theme.slide).combined(with: .opacity),
            removal: .offset(x: -direction * Theme.slide).combined(with: .opacity)
        ))
        .animation(Theme.swap, value: state.tab)
        .onAppear {
            Log.write("drew tab=\(state.showsSettings ? "settings" : state.tab.rawValue) notch=\(Int(state.notchSize.height)) body=\(Int(bodyHeight)) window=\(Int(panelHeight))")
        }
        .id("\(state.showsSettings ? "settings-\(state.settingsMode.rawValue)" : state.tab.rawValue)-\(state.shelfMode.rawValue)-\(state.clipboardMode.rawValue)-\(state.calcMode.rawValue)-\(state.systemMode.rawValue)")
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch state.tab {
            case .shelf:
                switch state.shelfMode {
                case .shelf:
                    ShelfView(store: model.shelf, pins: model.pins, state: state)
                case .record:
                    RecordView(store: model.recorder)
                case .convert, .cutout:
                    ImageToolView(store: model.images,
                                  shelf: model.shelf,
                                  state: state,
                                  mode: state.shelfMode)
                case .colour:
                    ColorView(store: model.colors)
                }
            case .clipboard:
                if state.clipboardMode == .history {
                    ClipboardView(store: model.clipboard, pins: model.pins)
                } else {
                    PasswordView(store: model.passwords, state: state)
                }
            case .downloads:
                DownloadsView(store: model.downloads, pins: model.pins)
            case .plans:
                PlansView(calendar: model.calendar,
                          plans: model.plans,
                          timer: model.timer,
                          awake: model.awake,
                          state: state,
                          settings: settings)
            case .calc:
                switch state.calcMode {
                case .math:
                    MathView(store: model.math, state: state)
                case .plot:
                    PlotView(store: model.math, state: state)
                case .theorem:
                    TheoremView(store: model.theorem, settings: settings)
                }
            case .convert:
                ConvertView(store: model.convert, state: state)
            case .translate:
                TranslateView(store: model.translate, state: state)
            case .music:
                MusicView(spotify: model.spotify)
            case .weather:
                WeatherView(store: model.weather)
            case .system:
                switch state.systemMode {
                case .machine:
                    SystemView(store: model.system)
                case .line:
                    NetworkView(store: model.network)
                case .vpn:
                    VPNView(store: model.vpn)
                case .privacy:
                    PrivacyView(store: model.privacy)
                }
            }
        }
    }
}

/// The body of the panel: one black slab hanging off the top edge of the screen.
///
/// It is full width at the very top pixel of the display and stays that way
/// across the menu bar, so the notch is swallowed by it and the bar underneath
/// is covered rather than left showing. Only the fillets take a bite out of the
/// sides, and they are scooped — the arc bulges into the corner — so the black
/// looks poured out of the bezel instead of pasted onto it.
///
/// Two earlier versions both left a seam. The first began at the bottom of the
/// menu bar, so a band of menu bar ran across the top of the panel. The second
/// climbed to the top edge as a column only as wide as the notch, which meant
/// the same band survived either side of it — the strip of blue and the app's
/// own menu titles visible left and right of the notch.
struct NotchBody: Shape {
    /// The scoop where the body meets the top edge of the screen.
    var fillet: CGFloat = Theme.filletRadius
    var bottom: CGFloat = Theme.bottomRadius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // The slab is drawn at every height between nothing and full while it
        // unrolls, and a corner radius taller than the shape itself turns the
        // path inside out.
        let fillet = min(self.fillet, rect.height / 2)
        let bottom = min(self.bottom, rect.height / 2)
        let left = rect.minX + fillet
        let right = rect.maxX - fillet

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.minX, y: rect.minY + fillet),
                    radius: fillet,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(0),
                    clockwise: false)

        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addArc(center: CGPoint(x: left + bottom, y: rect.maxY - bottom),
                    radius: bottom,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true)
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addArc(center: CGPoint(x: right - bottom, y: rect.maxY - bottom),
                    radius: bottom,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: true)

        path.addLine(to: CGPoint(x: right, y: rect.minY + fillet))
        path.addArc(center: CGPoint(x: rect.maxX, y: rect.minY + fillet),
                    radius: fillet,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// A tab is an icon until it is picked, and only then spells its name out.
/// Eleven labels in a row would be a menu bar; eleven icons are a set of tools.
private struct TabChip: View {
    let tab: PanelTab
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var pending: DispatchWorkItem?

    /// The glyph's own box, the swelling it is allowed, and the slot that holds
    /// both — see the note beside `slot`.
    private static let glyph: CGFloat = 19
    private static let grown: CGFloat = 1.22
    /// The room the biggest swelling needs, rounded up.
    ///
    /// Scale is drawn and not laid out, which is exactly what keeps the row
    /// from shuffling — and it also means the extra height goes somewhere
    /// nobody asked it to. Half of `glyph × (grown − 1)` hangs below the box,
    /// straight into the three points that separate the glyph from its rule.
    /// Symbols that fill their box top to bottom then land on the line:
    /// measured on screen, the clipboard sat one pixel off its own underline
    /// and the converter three, where a calendar sat eight. A gap that depends
    /// on which symbol was drawn is not a gap, it is a coincidence — so the
    /// slot reserves the grown height for every tab, lit or not, and the three
    /// points are three points on all ten.
    private static let slot: CGFloat = (glyph * grown).rounded(.up)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .accessibilityHidden(true)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? tab.tint : (hovering ? Theme.textSecondary : Theme.textTertiary))
                    .frame(height: Self.glyph)
                    // Growing rather than reflowing: the picked tab swells where
                    // it stands. Scale is drawn, not laid out, so the row keeps
                    // its spacing and nothing beside it moves.
                    .scaleEffect(isActive ? Self.grown : (hovering ? 1.1 : 1))
                    .frame(height: Self.slot)

                // A hairline instead of a capsule: the selected tab is marked,
                // not upholstered. It carries the tab's own colour, which is the
                // same colour the reading inside is written in.
                Rectangle()
                    .fill(isActive ? tab.tint : .clear)
                    .frame(height: 1.5)
                    // The rule draws itself from the middle out instead of
                    // fading up under the icon.
                    .scaleEffect(x: isActive ? 1 : 0.2, anchor: .center)
            }
            // Every tab is the same width, lit or not. Spelling the active
            // one's name out shoved its neighbours sideways, so the whole row
            // shifted under the cursor on every switch.
            .frame(width: 36, height: Self.slot + 3 + 1.5)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.drop, value: isActive)
        // Pointing at a tab is the whole gesture. The short delay keeps a
        // cursor crossing the row from leafing through every tab it passes.
        .onHover { inside in
            hovering = inside
            pending?.cancel()
            guard inside, !isActive else { return }
            let task = DispatchWorkItem(block: action)
            pending = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: task)
        }
        .animation(Theme.touch, value: hovering)
        .labelled(tab.title)
    }
}

/// One disc in the row under the panel, whichever family of tools it came from.
struct DialItem: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let isActive: Bool
    let pick: () -> Void

    /// `family` is what keeps two tools that happen to share a name apart — the
    /// eyedropper is `shelf.colour` and the palette is `settings.colour`, and
    /// they take turns in the same row.
    init<Mode: PanelMode>(family: String,
                          mode: Mode,
                          isActive: Bool,
                          pick: @escaping () -> Void) {
        self.id = family + "." + mode.rawValue
        self.symbol = mode.symbol
        self.title = mode.title
        self.isActive = isActive
        // Every one of these used to wrap itself; there is no tool anywhere in
        // the panel that should change what is on screen without the change
        // being drawn, so the wrapping belongs here rather than at each call.
        self.pick = { withAnimation(Theme.swap, pick) }
    }
}

/// One tool of the open tab: a black disc hanging under the notch.
///
/// Black inside, so it is a hole in the panel rather than a plate laid on it —
/// the same black as the body and the cut-out above it. What makes it a thing at
/// all is the ring around the outside and the glyph in the middle, and the glyph
/// is plain white: these are the tools of the tab, and a tool either is the open
/// one or is not.
///
/// The name is a tooltip and never a label beside the glyph. A word appearing on
/// hover grows the button, growing pushes its neighbours along, and the button
/// slides out from under the cursor that was pointing at it.
struct ModeDial: View {
    let symbol: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isActive || hovering ? Theme.ink : Theme.ink.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.body))
                .overlay(
                    Circle().strokeBorder(isActive ? Theme.tint : Theme.ink.opacity(hovering ? 0.4 : 0.22),
                                          lineWidth: isActive ? 1.4 : 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.09 : 1)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
        .animation(Theme.swap, value: isActive)
        .labelled(title)
    }
}
