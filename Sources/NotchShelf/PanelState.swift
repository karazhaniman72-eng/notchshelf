import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    /// Ten tabs, not twenty-one: each one is a subject, and the two or three
    /// tools that belong to that subject live inside it on a small switch. A
    /// row of twenty icons is a menu bar, which is the thing this replaces.
    ///
    /// The network had a tab of its own until it did not: what the line is doing
    /// is a reading about this machine, in the same family as its memory and its
    /// battery, and a tab per reading is how a panel turns back into a menu bar.
    case shelf, clipboard, downloads, plans, calc, convert, translate, music, weather, system

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .shelf: return "photo.on.rectangle.angled"
        case .clipboard: return "doc.on.clipboard"
        case .downloads: return "arrow.down.circle"
        case .plans: return "calendar"
        case .calc: return "function"
        case .convert: return "arrow.left.arrow.right"
        case .translate: return "character.bubble"
        case .music: return "music.note"
        case .weather: return "cloud.sun.fill"
        case .system: return "speedometer"
        }
    }

    /// One colour for every tab, because eleven colours was a rainbow. The strip
    /// marks which tab is open by which one is lit, not by what shade it is.
    var tint: Color { Theme.tint }

    var title: String {
        switch self {
        case .shelf: return "Shelf"
        case .clipboard: return "Clipboard"
        case .downloads: return "Downloads"
        case .plans: return "Plans"
        case .calc: return "Calc"
        case .convert: return "Convert"
        case .translate: return "Translate"
        case .music: return "Music"
        case .weather: return "Weather"
        case .system: return "System"
        }
    }
}

/// What every one of the little enums below has in common: a name to store, a
/// glyph to draw and a word to say out loud.
///
/// They are separate types on purpose — nothing should be able to hand the
/// shelf a system mode — but the row of discs under the panel draws all of them
/// the same way, and without this it had to be written out five times.
protocol PanelMode: RawRepresentable where RawValue == String {
    var symbol: String { get }
    var title: String { get }
}

/// The tools living inside Shelf. The shelf itself is one of them, and the
/// others take its place while they are open.
///
/// Pinning used to be a fourth tool with a board of its own. It is not a tool:
/// every picture on the shelf already carries a pin button, and a pin on the
/// screen is taken down from the pin itself — so the board was a page for
/// managing something nobody needed to manage.
enum ShelfMode: String, CaseIterable, Identifiable, PanelMode {
    case shelf, record, convert, cutout, colour

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .shelf: return "photo.on.rectangle.angled"
        case .record: return "record.circle"
        case .convert: return "arrow.triangle.2.circlepath"
        case .cutout: return "person.and.background.dotted"
        case .colour: return "eyedropper"
        }
    }

    var title: String {
        switch self {
        case .shelf: return "Shelf"
        case .record: return "Record"
        case .convert: return "Format"
        case .cutout: return "Cut out"
        case .colour: return "Colour"
        }
    }
}

/// The three things about the panel itself that can be changed, and they are
/// tools of the settings page in exactly the way the eyedropper is a tool of the
/// shelf — so they hang under the panel as the same row of discs, and the page
/// above them belongs entirely to whichever one is open.
enum SettingsMode: String, CaseIterable, Identifiable, PanelMode {
    case tabs, colour, backdrop, folders

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tabs: return "square.grid.2x2"
        case .colour: return "paintpalette"
        case .backdrop: return "circle.lefthalf.filled"
        case .folders: return "folder"
        }
    }

    var title: String {
        switch self {
        case .tabs: return "Tabs"
        case .colour: return "Colour"
        case .backdrop: return "Background"
        case .folders: return "Folders"
        }
    }
}

/// Clipboard holds what has been copied — and the generator that produces the
/// one kind of text nobody types by hand.
enum ClipboardMode: String, CaseIterable, Identifiable, PanelMode {
    case history, passwords

    var id: String { rawValue }
    var symbol: String { self == .history ? "doc.on.clipboard" : "key" }
    var title: String { self == .history ? "History" : "Passwords" }
}

/// Counting, drawing, and looking a theorem up. The plot used to appear inside
/// the calculator the moment a formula had an x in it, which meant the answer
/// and the history vanished under a picture nobody asked for.
enum CalcMode: String, CaseIterable, Identifiable, PanelMode {
    case math, plot, theorem

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .math: return "function"
        case .plot: return "chart.xyaxis.line"
        case .theorem: return "text.book.closed"
        }
    }

    var title: String {
        switch self {
        case .math: return "Calc"
        case .plot: return "Graph"
        case .theorem: return "Theorem"
        }
    }
}

/// Everything this machine can be asked about itself: what is charged, what the
/// line is doing, whether the traffic goes through a tunnel, and who is using
/// the microphone. Four readings about one computer, on one tab.
enum SystemMode: String, CaseIterable, Identifiable, PanelMode {
    case machine, line, vpn, privacy

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .machine: return "speedometer"
        case .line: return "wifi"
        case .vpn: return "lock.shield"
        case .privacy: return "eye.slash"
        }
    }

    var title: String {
        switch self {
        case .machine: return "Machine"
        case .line: return "Line"
        case .vpn: return "VPN"
        case .privacy: return "Watching"
        }
    }
}

/// Everything about how the panel behaves, kept apart from the data stores.
final class PanelState: ObservableObject {
    @Published var isExpanded = false
    /// Pinned from the menu: hovering away no longer collapses the panel.
    @Published var isPinned = false
    /// A drag is hovering the notch and waiting to be dropped.
    @Published var isDropTarget = false
    /// Typing needs a key window, and the panel must not fold away mid-word.
    @Published var isEditing = false
    /// A tab that can be typed into the moment it opens — the calculator. It
    /// takes the keyboard without pinning the panel open, which `isEditing`
    /// does: a field nobody has typed in yet is no reason to keep the panel on
    /// screen.
    @Published var wantsKeyboard = false
    /// Whether the cursor is over the panel at all.
    ///
    /// The keyboard follows this and nothing else. An open panel on a tab with a
    /// field in it used to hold the keyboard for as long as it was open, which
    /// meant that reaching past it to write somewhere else typed into the panel
    /// instead — the shelf had the focus, and the sentence went nowhere. Now the
    /// panel takes the keyboard while it is being pointed at and gives it back
    /// the moment the cursor is somewhere else, which is what a window that
    /// hangs over everything else has to do to be liveable with.
    @Published var isPointedAt = false
    /// Kept here so the layout follows the notch after a display change.
    @Published var notchSize: CGSize = .zero
    @Published var tab: PanelTab = .shelf

    // Which tool is open inside a tab.
    @Published var shelfMode: ShelfMode = .shelf
    @Published var clipboardMode: ClipboardMode = .history
    @Published var calcMode: CalcMode = .math
    @Published var systemMode: SystemMode = .machine
    /// The settings page, opened by the gear outside the top right corner.
    ///
    /// Not a tab. Tabs are what the panel is for; this is the panel itself, and
    /// putting it in the strip would mean the one page nobody looks at daily
    /// took a place from the ones they do — and it would be the first thing
    /// somebody turned off in it.
    @Published var showsSettings = false
    @Published var settingsMode: SettingsMode = .tabs
    /// The month grid unfolded out of the top left corner of Plans.
    @Published var showsMonth = false
    /// The day picked out of the month grid. Nil means today, which is what the
    /// tab shows when nobody has pressed a date.
    @Published var pickedDay: Date?

    /// One height for every tab, and the panel never changes size.
    ///
    /// It used to be measured per tab, which was correct arithmetic and wrong
    /// design: the panel jumped a different distance down the screen on every
    /// switch, so nothing on it ever stayed where the hand left it. A window
    /// that holds still is worth more than a window with no slack in it.
    static let bodyHeight: CGFloat = 300

    /// The strip below the panel where the tools of the open tab hang.
    ///
    /// Outside the black slab on purpose: the tools are not part of the tab, they
    /// are what switches it, and every point they took out of the body was a
    /// point the tab itself lost. The window is this much taller than the panel
    /// and the extra is transparent — clicks pass through it everywhere except
    /// the discs themselves.
    static let dialHeight: CGFloat = 36

    /// Transparent lane down either side of the black slab.
    ///
    /// The window is wider than the panel by this much on both sides, and the
    /// extra is empty air that clicks fall straight through. It exists for one
    /// thing: the gear has to hang outside the black the way the tools hang
    /// under it, and the slab has no room to give — every point spent on a
    /// button up there is a point taken from the tab.
    ///
    /// Both sides, not just the right, because the window is centred on the
    /// notch: widening one side would drag the panel off the cut-out.
    static let sideLane: CGFloat = 44

    /// The gear: same disc as a tool, in the right lane, level with the row of
    /// tabs so it reads as the end of that row rather than a thing stuck to the
    /// corner of the screen.
    static let gearSize: CGFloat = 30
    static let gearTop: CGFloat = 34

    var desiredHeight: CGFloat { Self.bodyHeight + Self.dialHeight }

    /// The panel may only fold away when nothing is holding it open.
    ///
    /// Typing is deliberately not on this list. It used to be, and text left in
    /// the calculator field pinned the panel open for good: the cursor was gone,
    /// so nothing could close it, and the notch click was blocked by the same
    /// check.
    var canCollapse: Bool { !isPinned && !isDropTarget }

    /// Called whenever the tab changes, so a tool left open inside one tab does
    /// not greet the next visit.
    func resetModes() {
        isEditing = false
        showsMonth = false
        pickedDay = nil
    }
}
