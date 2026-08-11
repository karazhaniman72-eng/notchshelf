import AppKit
import SwiftUI
import Combine

/// Borderless panels refuse key status by default, and without it the text
/// fields for links and notes cannot be typed into.
///
/// Only while there is something to type into, though, and that is the whole
/// point of the switch. A panel that may always become key is a panel that will
/// eventually become key when nobody asked: anything that activates this app —
/// the eyedropper closing, an open dialog dismissed, the menu in the tray —
/// hands the keyboard to the front window, and the front window is always this
/// one, because it is always on screen at level 27. From then on every keystroke
/// goes into a panel with no field in it and the machine looks broken.
///
/// `canBecomeKey` is asked by AppKit every time it looks for somewhere to put
/// the keyboard, so refusing here is refusing at the only moment that matters,
/// whatever route the activation came by.
final class KeyablePanel: NSPanel {
    /// Set from the one place that decides the panel is being typed into.
    var wantsKeyboard = false
    override var canBecomeKey: Bool { wantsKeyboard }
}

/// The window is transparent and larger than the notch, so clicks pass through
/// everywhere except the active area: the notch when collapsed, the whole panel
/// when open.
final class ContainerView: NSView {
    /// The notch is the panel's handle, open or shut, and the click on it is
    /// always the container's own — never the transparent SwiftUI layer's.
    var notchRect: CGRect = .zero
    /// The body of the open panel, where clicks belong to the interface.
    var activeRect: CGRect = .zero
    /// The tools hanging under the panel. They sit in the transparent strip
    /// below the black slab, so they need a hole of their own: everything else
    /// down there is desktop and has to stay clickable.
    var dialRect: CGRect = .zero
    /// The gear in the lane to the right of the slab. Same reasoning as the
    /// dial: that lane is transparent air sitting over somebody's menu bar, and
    /// only the disc itself may take a click out of it.
    var gearRect: CGRect = .zero
    /// Whether the panel is open at all.
    ///
    /// Every rectangle above belongs to something that is only on screen while
    /// it is, and they are all emptied on the way down — but a rectangle that
    /// is left behind by a step that did not run swallows clicks on a panel
    /// nobody can see, and there is no way to tell from the outside that it is
    /// happening. One flag, checked first, so a stale rectangle can do nothing.
    var isOpen = false
    var onClick: (() -> Void)?
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if notchRect.contains(local) { return self }
        guard isOpen,
              activeRect.contains(local) || dialRect.contains(local) || gearRect.contains(local) else {
            return nil
        }
        // A click landing between two controls has to stop at the panel, not
        // fall through to whatever window is underneath it.
        return super.hitTest(point) ?? self
    }

    /// Only the notch switches the panel. Clicks that miss a control inside the
    /// panel are swallowed here and do nothing — closing on them meant a
    /// slightly misjudged press on a tab folded the whole thing away.
    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard notchRect.contains(local) else { return }
        onClick?()
    }

    // Dragging a file onto the notch opens the panel at once, without the
    // hover delay: the hand is already busy holding the file.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExit?() }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

final class PanelController {
    private let model: AppModel
    private let panel: KeyablePanel
    private let container: ContainerView
    private let hosting: NSHostingView<ContentView>
    private var geometry: NotchGeometry

    /// The size of the open panel, and it is the same for every tab.
    ///
    /// Narrower than it was by 120pt: a 720pt slab is a letterbox, and a
    /// letterbox forces every tab to lay its content out sideways in one thin
    /// band. The same content in a shorter, taller box has room to breathe, and
    /// the panel stops reaching across the status icons on both sides.
    /// The window, which is the panel plus the strip of tools hanging under it.
    static let panelHeight: CGFloat = PanelState.bodyHeight + PanelState.dialHeight
    /// The black slab.
    static let expandedWidth: CGFloat = 600
    /// The window, which is the slab plus a transparent lane on either side for
    /// the gear to hang in. Both sides, because the window is centred on the
    /// notch and widening one of them would slide the panel off the cut-out.
    static let windowWidth: CGFloat = expandedWidth + PanelState.sideLane * 2

    /// Long enough that a cursor crossing the notch on its way somewhere else
    /// does not open the panel, short enough that aiming at it feels instant.
    ///
    /// A quarter of a second was not long enough. A hand travelling to the menu
    /// bar rests on the notch for longer than that on the way past.
    private let hoverDelay: TimeInterval = 0.45

    /// Closing waits as well now, and that is the whole fix for the flapping.
    ///
    /// Opening waited and closing did not, and the asymmetry is what made the
    /// panel toggle itself: the cursor going up shut it on the way past, left
    /// the zone a tick later, came back and opened it again. Six switches in
    /// four seconds in the log, and 42 % of all closes over a day were undone
    /// inside two seconds. Shorter than the open delay because the panel is
    /// already in the way by then and the wish to be rid of it is not idle.
    private let closeDelay: TimeInterval = 0.3

    /// How long hover stays deaf after a close. Whatever the cursor is doing up
    /// there, it is not asking for the thing that has just been dismissed.
    private let reopenBlock: TimeInterval = 0.7

    private var hoverSince: Date?
    private var closeSince: Date?
    private var closedAt: Date?
    /// Set false after a collapse so the panel does not spring open again while
    /// the cursor is still resting on the notch.
    private var armed = true
    /// Set once the cursor has walked off the notch after an open, which is
    /// what arms the notch as the close gesture too.
    private var leftNotch = false
    private var wasHovering = false
    private var watcher: Timer?
    private var ticks = 0
    private var snapshotTrigger: SnapshotTrigger?
    private var snapshotQueue: [String] = []
    private var snapshotBusy = false
    /// Whether a snapshot request is what opened the panel, and so whether it
    /// owes the screen a close when the queue runs out.
    private var snapshotOpenedPanel = false
    /// The pending return of the window to the size of the notch.
    private var shrink: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private var state: PanelState { model.panel }

    init?(model: AppModel) {
        guard let geometry = NotchGeometry.current() else { return nil }
        self.model = model
        self.geometry = geometry

        // Shut, and the window is the notch: see `collapsedSize`.
        let frame = geometry.windowFrame(expandedSize: CGSize(width: geometry.notchRect.width, height: 0))
        panel = KeyablePanel(contentRect: frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.isFloatingPanel = true
        // Strictly after isFloatingPanel: it resets the level to .floating (3).
        // The menu bar sits at 24 and has to stay under us or a seam shows; the
        // status items and their popovers sit at 25, and every menu the system
        // drops down is at 101. Sitting between the two — just above 26, which
        // is where another app that keeps a strip across the top of the screen
        // sits — is what leaves both the panel and the menu bar usable.
        panel.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: Skin.shared.isLight ? .aqua : .darkAqua)

        container = ContainerView(frame: CGRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]

        model.panel.notchSize = geometry.notchRect.size
        hosting = NSHostingView(rootView: ContentView(model: model, state: model.panel, shelf: model.shelf, clipboard: model.clipboard, convert: model.convert, translate: model.translate, settings: model.settings, panelHeight: Self.panelHeight))
        // Laid out at the size of the *open* panel for the whole life of the
        // app, whatever the window is doing — see `placeHosting`.
        hosting.autoresizingMask = []
        container.addSubview(hosting)

        panel.contentView = container
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        placeHosting()

        wireContainer()
        listenForSnapshotRequests()
        startWatchingCursor()
        // The one store that keeps working with the panel shut, on purpose: a
        // history of the line is only worth anything if it was recorded while
        // nobody was watching it.
        model.network.watch()
        applyActiveRect()
        Log.write("panel window=\(NSStringFromRect(frame)) notch=\(NSStringFromRect(geometry.notchRect)) trigger=\(NSStringFromRect(geometry.triggerRect))")
        logWindowLevels()
        observe()
    }

    /// Opening used to hang on NSTrackingArea. Rebuilding that area on every
    /// open and close means AppKit never re-sends mouseEntered while the cursor
    /// is already inside it, so the panel opened only every other time.
    /// Reading the cursor position directly has no such state to get wrong.
    private func startWatchingCursor() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    private func checkCursor() {
        let cursor = NSEvent.mouseLocation
        let inTrigger = geometry.triggerRect.contains(cursor)
        if wasHovering != inTrigger {
            wasHovering = inTrigger
            Log.write("hover=\(inTrigger) x=\(Int(cursor.x)) y=\(Int(cursor.y))")
        }
        ticks += 1
        if ticks % 600 == 0 { Log.write("watcher alive ticks=\(ticks)") }
        if ticks % 2 == 0 { readSnapshotRequestFile() }

        if state.isExpanded {
            hoverSince = nil

            // Whether the panel is being pointed at, which is what decides
            // whether it may hold the keyboard. The window is wider than the
            // black slab and the strip under it is mostly transparent, so this
            // is measured against the frame the panel actually draws in.
            let pointed = pointedRect.contains(cursor)
            if state.isPointedAt != pointed { state.isPointedAt = pointed }

            // The notch is a switch, and nothing else closes the panel. Walking
            // the cursor away used to shut it, which meant the panel could not
            // be left open while working in the window under it — reading a
            // theorem, watching a timer. Point at the notch again to close.
            //
            // Measured against the notch itself rather than the hover zone: the
            // hover zone hangs ten points below the notch, straight over the
            // first row of tabs, and reaching for a tab there shut the panel.
            //
            // The cursor has to leave the notch first, or the panel would shut
            // in the same instant it opened, with the pointer still resting
            // there from the gesture that opened it.
            guard geometry.closeRect.contains(cursor) else {
                leftNotch = true
                closeSince = nil
                return
            }
            guard leftNotch, state.canCollapse else { return }
            guard let since = closeSince else {
                closeSince = Date()
                return
            }
            if Date().timeIntervalSince(since) >= closeDelay { collapse() }
            return
        }

        // Wait for the cursor to leave before hover may open the panel again.
        guard armed else {
            hoverSince = nil
            if !inTrigger { armed = true }
            return
        }
        guard inTrigger else {
            hoverSince = nil
            return
        }
        if let closedAt, Date().timeIntervalSince(closedAt) < reopenBlock {
            hoverSince = nil
            return
        }
        guard let since = hoverSince else {
            hoverSince = Date()
            return
        }
        if Date().timeIntervalSince(since) >= hoverDelay {
            open("hover")
        }
    }

    private func open(_ reason: String) {
        hoverSince = nil
        closeSince = nil
        guard !state.isExpanded else { return }
        state.isExpanded = true
        leftNotch = false
        Log.write("opened by \(reason)")
    }

    private func wireContainer() {
        // The notch works as a switch: a click opens without waiting out the
        // hover delay, and closes without having to walk the cursor off the
        // panel. Held open by a pin or a drag, it stays open.
        container.onClick = { [weak self] in
            guard let self else { return }
            self.armed = false
            if self.state.isExpanded {
                self.collapse()
            } else {
                self.open("click")
            }
        }
        container.onDragEnter = { [weak self] in
            guard let self else { return }
            self.hoverSince = nil
            self.state.isDropTarget = true
            self.state.tab = .shelf
            self.state.isExpanded = true
        }
        container.onDragExit = { [weak self] in
            guard let self else { return }
            self.state.isDropTarget = false
            self.collapse()
        }
        container.onDrop = { [weak self] urls in
            guard let self else { return }
            self.state.isDropTarget = false
            self.model.shelf.add(urls)
        }
    }

    private func observe() {
        // Everything macOS draws inside this window rather than the panel
        // drawing it: the grey of a placeholder, the caret, the selection
        // behind a word, the pop-up a `Menu` opens. All of it is picked from
        // the window's appearance, which knows nothing about the skin — so a
        // white panel wrote "A password you already have" in white on its own
        // paper, and a Mac set to light mode did the mirror of that inside the
        // black one. The window is told which way round the panel is instead.
        Skin.shared.$isLight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] light in
                self?.panel.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
            }
            .store(in: &cancellables)

        state.$isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                guard let self else { return }
                self.fitToContent()
                self.applyActiveRect()
                if expanded {
                    // Whatever opened it — hover, a click, a drag, a pin — the
                    // cursor has to leave the notch before pointing at it means
                    // close. Set only in `open` before, so a panel opened any
                    // other way shut again in the same breath if the cursor
                    // happened to be resting on the notch.
                    self.leftNotch = false
                    self.activateTab(self.state.tab)
                } else {
                    self.suspendAll()
                    self.state.isEditing = false
                    self.state.wantsKeyboard = false
                    self.state.isPointedAt = false
                    // Settings do not survive a close. The panel is opened to
                    // look at something, and finding yesterday's settings page
                    // instead of the shelf is finding the wrong thing.
                    self.state.showsSettings = false
                }
            }
            .store(in: &cancellables)

        state.$tab
            .receive(on: RunLoop.main)
            .sink { [weak self] tab in
                self?.activateTab(tab)
                self?.fitToContent()
                // Each tab hangs a different number of discs under the panel, so
                // the hole cut for them in the transparent strip changes with it.
                self?.applyActiveRect()
            }
            .store(in: &cancellables)

        // The settings page hangs three discs of its own under the panel, and
        // the tab it covers may hang four or five — so the hole cut for them in
        // the transparent strip has to be recut when the gear is pressed.
        state.$showsSettings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyActiveRect() }
            .store(in: &cancellables)

        // The System tab is four readings behind one icon, and each of them
        // costs something different to take — a ping, a subprocess, a poll of
        // the microphone. Only the one on screen is woken.
        state.$systemMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self, self.state.isExpanded, self.state.tab == .system else { return }
                self.activateSystem(mode)
            }
            .store(in: &cancellables)

        // A tool opened inside a tab can need more room than the tab does.
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.fitToContent() }
            .store(in: &cancellables)

        // Text fields only accept keystrokes while the app is active.
        // Without removeDuplicates every tab switch writes the same value again
        // and deactivates the app for nothing.
        //
        // And only while the cursor is on the panel. A tab that wants the
        // keyboard used to take it for as long as it was open, so an open shelf
        // swallowed everything typed at the window underneath it.
        state.$isEditing
            .combineLatest(state.$wantsKeyboard, state.$isPointedAt)
            .map { ($0 || $1) && $2 }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] editing in
                guard let self else { return }
                editing ? self.takeKeyboard() : self.returnKeyboard()
            }
            .store(in: &cancellables)

        // Plugging in a display, changing resolution or waking from sleep moves
        // the notch. Without this the panel stays at the old coordinates.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
    }

    // MARK: - The keyboard

    /// The app that was in front when this panel took the keyboard.
    ///
    /// Borrowed, not taken: this is an accessory app, it has no windows of its
    /// own to fall back to, and the thing it interrupted is always somebody's
    /// real work. Remembering who it was is the only way to give the keyboard
    /// back to the same place it came from.
    private var interrupted: NSRunningApplication?

    private func takeKeyboard() {
        if !NSApp.isActive {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                interrupted = front
            }
        }
        panel.wantsKeyboard = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hands the keyboard back to whoever had it, and stops answering for it.
    ///
    /// `NSApp.deactivate()` on its own is what was here, and it is what made the
    /// keyboard go dead: it says "this app is no longer active" and names no
    /// successor. A normal app has other windows behind it and macOS picks one;
    /// an agent app with a single floating panel has nothing behind it, so on a
    /// bad roll of the dice no application ends up active at all — every
    /// keystroke lands nowhere until something is clicked. Naming the app that
    /// was interrupted removes the dice from it.
    ///
    /// `wantsKeyboard` goes false first, so that if anything activates this app
    /// again by another route the panel is no longer eligible to hold the
    /// keyboard.
    private func returnKeyboard() {
        panel.wantsKeyboard = false
        if let interrupted, !interrupted.isTerminated {
            interrupted.activate()
        } else {
            NSApp.deactivate()
        }
        interrupted = nil
    }

    /// Each tab wakes up only when it is actually on screen: no calendar
    /// permission prompt and no chatter with Spotify until they are opened.
    private func activateTab(_ tab: PanelTab) {
        guard state.isExpanded else { return }
        suspendAll(except: tab)
        switch tab {
        case .music:
            model.spotify.startPolling()
        case .plans:
            model.calendar.activate()
            model.plans.reload()
            model.timer.refresh()
        case .system:
            activateSystem(state.systemMode)
        case .weather:
            model.weather.activate()
        case .downloads:
            model.downloads.reload()
        case .calc:
            model.math.activate()
            model.theorem.activate()
        case .convert:
            model.convert.activate()
        case .translate:
            model.translate.activate()
        default:
            break
        }
    }

    /// One reading at a time inside the System tab.
    private func activateSystem(_ mode: SystemMode) {
        model.system.stopPolling()
        model.privacy.stopPolling()
        model.network.deactivate()
        model.vpn.deactivate()

        switch mode {
        case .machine: model.system.startPolling()
        case .line: model.network.activate()
        case .vpn: model.vpn.activate()
        case .privacy: model.privacy.startPolling()
        }
    }

    /// Nothing polls anything unless its own tab is the one on screen. The
    /// timer is the exception and is not here: a block has to keep counting
    /// with the panel shut, which is the whole point of it.
    private func suspendAll(except tab: PanelTab? = nil) {
        if tab != .music { model.spotify.stopPolling() }
        if tab != .system {
            model.system.stopPolling()
            model.privacy.stopPolling()
            model.network.deactivate()
            model.vpn.deactivate()
        }
    }

    /// The window while the panel is shut: the notch, and not one point more.
    ///
    /// It used to keep its full size the whole time — six hundred points across
    /// and three hundred and change down, transparent, hanging over the top of
    /// the screen with nothing drawn in it. Everything under that rectangle
    /// depended on `hitTest` handing the click on, which it does, right up until
    /// one of the rectangles it consults is left over from the last time the
    /// panel was open. Then a third of the screen quietly stops answering the
    /// mouse and there is nothing on it to explain why.
    ///
    /// A window that is the size of the notch cannot take a click that was not
    /// aimed at the notch, whatever the code inside it believes. Hovering is
    /// unaffected: the cursor is read from the screen, not from this window.
    private var collapsedSize: CGSize { CGSize(width: geometry.notchRect.width, height: 0) }

    private var expandedSize: CGSize { CGSize(width: Self.windowWidth, height: state.desiredHeight) }

    /// Resizes the window to whatever is on screen. Nothing but the height
    /// changes while the panel is open: the notch, and therefore the panel's
    /// centre, stays put.
    private func fitToContent() {
        if state.isExpanded {
            shrink?.cancel()
            shrink = nil
            apply(size: expandedSize)
            return
        }
        // The slab is still rolling up inside the window. Taking the window away
        // now would cut the closing animation off half done, so the shrink waits
        // for it — and is cancelled if the panel opens again in the meantime.
        let wanted = geometry.windowFrame(expandedSize: collapsedSize)
        guard panel.frame != wanted, shrink == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.shrink = nil
            guard !self.state.isExpanded else { return }
            self.apply(size: self.collapsedSize)
        }
        shrink = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    private func apply(size: CGSize) {
        let frame = geometry.windowFrame(expandedSize: size)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        container.frame = CGRect(origin: .zero, size: frame.size)
        placeHosting()
        applyActiveRect()
    }

    /// The interface is always laid out at the size of the open panel, and the
    /// window is a hole the right shape held over it.
    ///
    /// The obvious thing — let the view resize with the window — is what broke
    /// the way the panel opens. SwiftUI lays out for the size it is given, so a
    /// window the size of the notch meant the whole panel was re-laid out from
    /// a hundred and seventy points wide at the very moment it was supposed to
    /// be unrolling, and the unroll had nothing to unroll. Pinned to the open
    /// size, nothing about the layout changes when the window does: the slab
    /// grows exactly as it always did, and the window growing under it is not
    /// something SwiftUI ever hears about.
    private func placeHosting() {
        let open = geometry.windowFrame(expandedSize: expandedSize)
        hosting.frame = CGRect(x: open.minX - panel.frame.minX,
                               y: open.minY - panel.frame.minY,
                               width: open.width,
                               height: open.height)
    }

    private func relayout() {
        guard let updated = NotchGeometry.current() else { return }
        geometry = updated
        state.notchSize = updated.notchRect.size
        shrink?.cancel()
        shrink = nil
        let frame = updated.windowFrame(expandedSize: state.isExpanded ? expandedSize : collapsedSize)
        panel.setFrame(frame, display: true)
        container.frame = CGRect(origin: .zero, size: frame.size)
        placeHosting()
        applyActiveRect()
        Log.write("relayout window=\(NSStringFromRect(frame)) notch=\(NSStringFromRect(updated.notchRect))")
    }

    /// The notch stays clickable either way. Collapsed, the panel takes no
    /// clicks at all, so the desktop and the whole menu bar underneath stay
    /// reachable.
    ///
    /// Open, every point of the window is the panel's, the menu bar strip along
    /// its top included. That strip is painted black now, and a black pixel that
    /// quietly forwards the click to a status icon nobody can see is worse than
    /// one that swallows it. The status icons under the panel are reached by
    /// shutting it — the notch is the switch.
    private func applyActiveRect() {
        let bounds = container.bounds
        let click = geometry.clickRect
        container.notchRect = CGRect(
            x: click.minX - panel.frame.minX,
            y: bounds.height - click.height,
            width: click.width,
            height: click.height
        )
        // The black slab is everything above the tool strip and inside the two
        // lanes; the strip and the lanes are transparent and belong to the
        // desktop except where a disc is drawn on them.
        let body = CGRect(x: PanelState.sideLane, y: PanelState.dialHeight,
                          width: bounds.width - PanelState.sideLane * 2,
                          height: max(bounds.height - PanelState.dialHeight, 0))
        container.isOpen = state.isExpanded
        container.activeRect = state.isExpanded ? body : .zero
        container.dialRect = state.isExpanded ? toolStripRect(in: bounds) : .zero
        container.gearRect = state.isExpanded ? gearButtonRect(in: bounds) : .zero
    }

    /// Where the gear is, so the rest of the lane stays the menu bar's.
    ///
    /// Kept in step with `ContentView.gear` — the disc is drawn against the
    /// right edge of the slab and pushed out by its own width plus the gap, and
    /// these are the same two numbers read from the other end. A couple of
    /// points of margin all round, because the thing being aimed at is 30
    /// points wide and sits over icons that must not be hit by mistake.
    private func gearButtonRect(in bounds: CGRect) -> CGRect {
        let size = PanelState.gearSize
        let gap: CGFloat = 8
        let left = PanelState.sideLane + Self.expandedWidth + gap
        let top = PanelState.gearTop
        return CGRect(x: left - 3,
                      y: bounds.height - top - size - 3,
                      width: size + 6,
                      height: size + 6)
    }

    /// The panel as the cursor meets it: the black slab, not the whole window.
    ///
    /// The window grew a transparent lane down each side when the gear moved
    /// out there, and those lanes hang directly over the status icons. Measured
    /// against the whole frame, a cursor on its way to the Wi-Fi menu would
    /// count as pointing at the panel — which is the bug that was fixed once
    /// already, when the menu bar strip was part of the hold zone.
    private var pointedRect: CGRect {
        panel.frame.insetBy(dx: PanelState.sideLane, dy: 0)
    }

    /// Where the discs actually are, so nothing but them catches a click down
    /// there. Kept in step with `ContentView.modeDial` — same gutter, same
    /// diameter, same spacing.
    private func toolStripRect(in bounds: CGRect) -> CGRect {
        let count = CGFloat(toolCount)
        guard count > 0 else { return .zero }
        let diameter: CGFloat = 30
        let spacing: CGFloat = 8
        let width = count * diameter + (count - 1) * spacing
        return CGRect(x: PanelState.sideLane + Theme.gutter - 4,
                      y: 0,
                      width: width + 8,
                      height: PanelState.dialHeight)
    }

    private var toolCount: Int {
        // The settings page has tools of its own and they hang in the same
        // place, so the hole under them is the same hole.
        if state.showsSettings { return SettingsMode.allCases.count }
        switch state.tab {
        case .shelf: return ShelfMode.allCases.count
        case .clipboard: return ClipboardMode.allCases.count
        case .calc: return CalcMode.allCases.count
        case .system: return SystemMode.allCases.count
        default: return 0
        }
    }

    /// One-shot diagnostics: who else sits on the top window levels.
    /// Shows whether the menu bar covers us.
    private func logWindowLevels() {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let top = infos.compactMap { info -> String? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 20 else { return nil }
            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            return "\(owner)=\(layer)"
        }
        Log.write("window levels ours=\(panel.level.rawValue) others=[\(top.joined(separator: ", "))]")
    }

    private func collapse() {
        hoverSince = nil
        closeSince = nil
        guard state.canCollapse, state.isExpanded else { return }
        state.isExpanded = false
        armed = false
        closedAt = Date()
        Log.write("closed")
    }

    /// A snapshot can be asked for from outside — `notify` with the tab name as
    /// the object. Opens the panel on that tab, lets it settle, and draws it.
    /// Used to check the real window rather than a hopeful copy of it.
    private func listenForSnapshotRequests() {
        snapshotTrigger = SnapshotTrigger { [weak self] raw in
            // Trimmed, and dropped when it says nothing, the same as the file
            // below: an empty request splits into no parts at all, and the tab
            // is read out of it by index.
            let wanted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty else { return }
            self?.snapshotQueue.append(wanted)
            self?.serveSnapshotQueue()
        }
    }

    /// The same request, written to a file instead of broadcast.
    ///
    /// Distributed notifications are the tidier mechanism and they cannot be
    /// trusted for this: a background app gets them in bursts, or not at all,
    /// and a run of eleven arrived as two. A file either exists or it does not.
    private func readSnapshotRequestFile() {
        let path = NSTemporaryDirectory() + "/notchshelf-request.txt"
        guard FileManager.default.fileExists(atPath: path),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(atPath: path)
        let wanted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return }
        snapshotQueue.append(wanted)
        serveSnapshotQueue()
    }

    /// One request at a time, each given time to draw before it is captured.
    ///
    /// Requests arrive in bursts however slowly they are sent, and the first
    /// version set the tab and captured 0.6s later. Three requests landing
    /// together produced three files of the last tab, all correctly named after
    /// the tabs they were not.
    private func serveSnapshotQueue() {
        guard !snapshotBusy, !snapshotQueue.isEmpty else { return }
        snapshotBusy = true
        let raw = snapshotQueue.removeFirst()

        // "calc/plot?x^2-4" — the tab, the tool inside it, and something to put
        // in its field. A snapshot of an empty graph proves the empty state and
        // nothing else, and the only other way to fill the field is to stand at
        // the machine and type.
        let request = raw.split(separator: "?", maxSplits: 1).map(String.init)
        let wantedTab = request[0]
        let typed = request.count > 1 ? request[1] : ""

        let parts = wantedTab.split(separator: "/").map(String.init)
        // "settings/colour" — the page behind the gear is asked for by name
        // like a tab, because from out here it is one: a request names what
        // should be on the panel when the picture is taken.
        state.showsSettings = parts.first == "settings"
        if state.showsSettings {
            state.settingsMode = parts.count > 1
                ? (SettingsMode(rawValue: parts[1]) ?? .tabs)
                : .tabs
        }
        if let tab = parts.first, let wanted = PanelTab(rawValue: tab) {
            state.resetModes()
            // A tab asked for on its own means the tab as it opens, not the
            // tool somebody left open inside it two requests ago.
            state.shelfMode = .shelf
            state.clipboardMode = .history
            state.calcMode = .math
            state.systemMode = .machine
            state.tab = wanted
        }
        if parts.count > 1 {
            let mode = parts[1]
            if let shelf = ShelfMode(rawValue: mode) { state.shelfMode = shelf }
            if let clip = ClipboardMode(rawValue: mode) { state.clipboardMode = clip }
            if let calc = CalcMode(rawValue: mode) { state.calcMode = calc }
            if let system = SystemMode(rawValue: mode) { state.systemMode = system }
            // The converter keeps its kind in the store rather than in the
            // panel's state, so it is set here and not with the others.
            if let kind = ConvertStore.Mode(rawValue: mode) { model.convert.mode = kind }
            if mode == "month" { state.showsMonth = true }
        }
        if !typed.isEmpty, state.showsSettings {
            // "settings/backdrop?white", "settings/colour?#66D9E8" — a picture of
            // a setting is only worth taking with the setting actually applied,
            // and the alternative is standing at the machine pressing it.
            if let style = Backdrop(rawValue: typed) { model.settings.backdrop = style }
            if typed.hasPrefix("#") { Palette.shared.setTint(typed) }
        } else if !typed.isEmpty {
            switch state.tab {
            case .calc:
                // "a;b" — everything before the last semicolon is kept on the
                // plot and the last one goes in the field, so a snapshot can
                // show two curves at once.
                let curves = typed.split(separator: ";").map(String.init)
                model.math.preload(curves: curves)
            case .translate: model.translate.input = typed
            case .convert: model.convert.amount = typed
            default: break
            }
        }
        // A picture is a look, not a visit. Whoever asked for one is not sitting
        // at the machine — that is the whole point of asking from outside — so
        // the panel has to be put back the way it was found. Left open, it hangs
        // over the top of the screen taking clicks from somebody who never
        // opened it and cannot see why they are disappearing.
        if !state.isExpanded { snapshotOpenedPanel = true }
        state.isExpanded = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            // Named after the tab and tool only: whatever was typed into the
            // field is data, not part of the file's name.
            let stem = raw.split(separator: "?", maxSplits: 1).map(String.init).first ?? ""
            let name = stem.isEmpty ? "live" : stem.replacingOccurrences(of: "/", with: "-")
            self.writeSnapshot(named: "notchshelf-" + name)
            self.snapshotBusy = false
            if self.snapshotQueue.isEmpty, self.snapshotOpenedPanel {
                self.snapshotOpenedPanel = false
                self.state.isExpanded = false
                self.armed = false
                self.closedAt = Date()
                Log.write("closed after snapshot")
            }
            self.serveSnapshotQueue()
        }
    }

    /// Draws the live panel into a PNG — the window that is actually on screen,
    /// at the size it actually has. The off-screen render used for layout checks
    /// agreed with itself and not with reality, which is how a panel that sat
    /// half under the menu bar passed every check.
    ///
    /// This is the app drawing its own view. Nothing on the screen is captured.
    func writeSnapshot(named name: String = "notchshelf-live") {
        guard let view = panel.contentView else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(name + ".png")
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        Log.write("live snapshot window=\(NSStringFromRect(panel.frame)) tab=\(state.tab.rawValue) file=\(url.path)")
    }

    /// Opens the panel without hovering and keeps it open.
    func togglePinned() {
        state.isPinned.toggle()
        state.isExpanded = state.isPinned
        Log.write("pinned=\(state.isPinned)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var controller: PanelController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    /// Held for the life of the app, and never released.
    private var awakeToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An agent app with no window in front is a candidate for App Nap, and
        // a napping app has its timers coalesced into near-stillness. The timer
        // here is the one that watches the cursor, so napping means the notch
        // stops answering to the mouse until something else wakes the app —
        // measured: after half a minute of no input the ten-a-second tick had
        // stopped firing altogether. Idle system sleep is still allowed; only
        // our own throttling is refused.
        awakeToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Watching the notch for the cursor"
        )

        // Asked once at launch and again whenever macOS says an accessibility
        // setting moved, so "Reduce motion" takes effect without a restart.
        Theme.refreshMotionPreference()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in Theme.refreshMotionPreference() }

        controller = PanelController(model: model)

        // Variable rather than square: the tray icon grows a countdown beside
        // it while a block runs.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Shelf")
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Keep Panel Open", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let copy = NSMenuItem(title: "Copy New Screenshot to Clipboard",
                              action: #selector(toggleCopy),
                              keyEquivalent: "")
        copy.target = self
        copy.state = model.shelf.copiesToClipboard ? .on : .off
        menu.addItem(copy)

        let shot = NSMenuItem(title: "Save Panel Snapshot", action: #selector(savePanelSnapshot), keyEquivalent: "")
        shot.target = self
        menu.addItem(shot)

        let folder = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        // The notch cannot show the countdown — it is a hole in the display,
        // nothing lights up there — so the tray carries it instead.
        model.timer.$isRunning
            .combineLatest(model.timer.$remaining)
            .map { running, remaining in running ? " " + TimerStore.clock(remaining) : "" }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak item] title in item?.button?.title = title }
            .store(in: &cancellables)
    }

    @objc private func togglePanel(_ sender: NSMenuItem) {
        controller?.togglePinned()
        sender.state = model.panel.isPinned ? .on : .off
    }

    @objc private func toggleCopy(_ sender: NSMenuItem) {
        model.shelf.copiesToClipboard.toggle()
        sender.state = model.shelf.copiesToClipboard ? .on : .off
    }

    @objc private func savePanelSnapshot() {
        controller?.writeSnapshot()
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(model.shelf.folder)
    }
}

/// Asks the panel to draw itself into a PNG, so a layout can be checked as it
/// really renders on screen rather than in an offscreen copy that agrees with
/// itself.
///
/// Registered by selector rather than by block on purpose: the block form of
/// `addObserver` registers with `.coalesce`, and a background app on that
/// setting has its notifications merged and dropped. Asking for eleven tabs in
/// a row delivered two, one of them carrying the wrong tab.
private final class SnapshotTrigger: NSObject {
    private let handler: (String) -> Void

    init(handler: @escaping (String) -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(fire(_:)),
            name: Notification.Name("NotchShelfSnapshot"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func fire(_ note: Notification) {
        handler(note.object as? String ?? "")
    }
}
