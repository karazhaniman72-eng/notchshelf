import AppKit
import SwiftUI

/// How much of the desktop shows through the panel.
///
/// The black slab is the panel's whole reason for reading as part of the
/// machine rather than a window floating on it, so translucency here is a
/// setting and never the default: the notch is a physical hole in the glass and
/// stays black whatever is chosen, which means the more of the desktop that
/// comes through the slab, the more visible the seam around that hole becomes.
///
/// Three steps rather than a slider. A slider invites the middle of the range,
/// and the middle of this range is where text stops being readable over a busy
/// wallpaper — these three are all measured against white underneath.
enum Backdrop: String, CaseIterable, Identifiable {
    case solid, veil, glass, clear, white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .veil: return "Veil"
        case .glass: return "Glass"
        case .clear: return "Clear"
        case .white: return "White"
        }
    }

    /// What the person is choosing between, in the fewest words that say it —
    /// and, for the two that cost something, what it costs.
    var detail: String {
        switch self {
        case .solid: return "Black, like the bezel"
        case .veil: return "Frosted, barely"
        case .glass: return "Frosted, like breath on a window"
        case .clear: return "See the window underneath · small text suffers"
        case .white: return "Light panel, dark writing"
        }
    }

    /// The panel writes in black on white here, which is every colour in it
    /// changing at once rather than only the background.
    var isLight: Bool { self == .white }
}

/// Everything about the panel that the owner of the Mac gets to decide.
///
/// Deliberately small. The panel is opinionated on purpose — sizes, spacing and
/// what each tab is for are decisions, not preferences — and the two things
/// here are the two that genuinely differ between people: which subjects they
/// care about, and how the thing should look against their desktop.
final class SettingsStore: ObservableObject {

    /// Tabs switched off, by raw value. Stored as what is *off* rather than
    /// what is on, so a tab added in a future version arrives switched on
    /// instead of silently missing for everybody who ever opened this page.
    @Published private(set) var hidden: Set<String> {
        didSet { UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey) }
    }

    @Published var backdrop: Backdrop {
        didSet {
            UserDefaults.standard.set(backdrop.rawValue, forKey: Self.backdropKey)
            // The white background is also the light skin: `Theme` mixes every
            // colour in the panel from `Skin`, and this is the one place that
            // decides which way round it is.
            Skin.shared.isLight = backdrop.isLight
            Log.write("backdrop=\(backdrop.rawValue)")
        }
    }

    /// The two folders the panel reads somebody's own files out of.
    ///
    /// Nil until one is picked, and nil is a perfectly good state: the tabs that
    /// use them say so and offer the button. They used to be constants in
    /// `PlansStore` and `TheoremStore` pointing at one particular person's
    /// knowledge base, which worked exactly once — on that person's Mac — and
    /// silently showed nothing on anybody else's.
    ///
    /// A path rather than a security-scoped bookmark because this app is not
    /// sandboxed. What gates `~/Documents` here is TCC, which grants by
    /// application rather than by folder, so a bookmark would buy nothing that
    /// the plain path does not already have — as long as the app has a stable
    /// signature. See the note about the signing certificate in `build.sh`.
    @Published private(set) var plansFolder: URL? {
        didSet { Self.store(plansFolder, at: Self.plansKey) }
    }

    @Published private(set) var textbooksFolder: URL? {
        didSet { Self.store(textbooksFolder, at: Self.textbooksKey) }
    }

    private static let hiddenKey = "settings.hiddenTabs"
    private static let backdropKey = "settings.backdrop"
    private static let plansKey = "settings.plansFolder"
    private static let textbooksKey = "settings.textbooksFolder"

    init() {
        let defaults = UserDefaults.standard
        let saved = Set((defaults.array(forKey: Self.hiddenKey) as? [String]) ?? [])
        // A saved list that hides every tab would leave the strip empty and the
        // grid disagreeing with it — `tabs` would put one back to keep the panel
        // usable while `isOn` still said it was off. Only reachable from an old
        // build or a hand-edited preference, and cheaper to refuse here than to
        // reason about everywhere else.
        hidden = saved.count >= PanelTab.allCases.count ? [] : saved
        backdrop = Backdrop(rawValue: defaults.string(forKey: Self.backdropKey) ?? "") ?? .solid
        plansFolder = Self.folder(at: Self.plansKey)
        textbooksFolder = Self.folder(at: Self.textbooksKey)
        // `didSet` does not run for a value set in `init`, and the panel draws
        // its first frame from `Theme` before anything is ever changed — so the
        // skin has to be told here as well or a saved white background comes
        // back as white paper with white writing on it.
        Skin.shared.isLight = backdrop.isLight
    }

    /// The strip, in the order tabs are declared in. Order is not a setting:
    /// the row is read left to right dozens of times a day and a row that
    /// changes shape is a row that has to be read every time.
    var tabs: [PanelTab] {
        let shown = PanelTab.allCases.filter { !hidden.contains($0.rawValue) }
        // A panel with no tabs at all is a black rectangle with nothing in it,
        // and nothing in the interface would be left to undo that with.
        return shown.isEmpty ? [PanelTab.allCases[0]] : shown
    }

    func isOn(_ tab: PanelTab) -> Bool { !hidden.contains(tab.rawValue) }

    /// Turning the last one off is refused rather than prevented in the view:
    /// the switch stays where it is, so the row does not rearrange itself under
    /// a finger that pressed something that could not happen.
    func toggle(_ tab: PanelTab) {
        if hidden.contains(tab.rawValue) {
            hidden.remove(tab.rawValue)
        } else {
            guard tabs.count > 1 else {
                Log.write("refused to hide the last tab=\(tab.rawValue)")
                return
            }
            hidden.insert(tab.rawValue)
        }
        Log.write("tabs on=\(tabs.count) off=\(hidden.count)")
    }

    /// Which tab the panel should show, given one it was on. A tab switched off
    /// while it is open has to hand over to a neighbour, not leave the panel
    /// pointing at something that is no longer in the row.
    func resolve(_ tab: PanelTab) -> PanelTab {
        isOn(tab) ? tab : (tabs.first ?? PanelTab.allCases[0])
    }

    // MARK: - Folders

    enum Folder {
        case plans, textbooks

        var title: String {
            switch self {
            case .plans: return "Plans"
            case .textbooks: return "Textbooks"
            }
        }

        /// What the tab does with it, in one line, so the choice is not a guess.
        var detail: String {
            switch self {
            case .plans: return "today.md and goals.md are read from here"
            case .textbooks: return "One theorem a day out of the newest book"
            }
        }
    }

    func folder(_ which: Folder) -> URL? {
        switch which {
        case .plans: return plansFolder
        case .textbooks: return textbooksFolder
        }
    }

    /// Opens the picker and keeps whatever comes back.
    ///
    /// The app has to be brought to the front first: it is an accessory with no
    /// windows of its own, and an open panel from an inactive accessory can
    /// appear behind whatever is on screen with no way to reach it.
    func chooseFolder(_ which: Folder) {
        let dialog = NSOpenPanel()
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.allowsMultipleSelection = false
        dialog.canCreateDirectories = false
        dialog.prompt = "Use this folder"
        dialog.message = "Where should \(which.title) read from?"
        dialog.directoryURL = folder(which)

        NSApp.activate(ignoringOtherApps: true)
        dialog.begin { [weak self] response in
            guard response == .OK, let url = dialog.url else { return }
            self?.set(which, to: url)
        }
    }

    func forget(_ which: Folder) { set(which, to: nil) }

    private func set(_ which: Folder, to url: URL?) {
        switch which {
        case .plans: plansFolder = url
        case .textbooks: textbooksFolder = url
        }
        Log.write("folder \(which.title)=\(url?.path ?? "none")")
    }

    private static func store(_ url: URL?, at key: String) {
        let defaults = UserDefaults.standard
        if let url {
            defaults.set(url.path, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// What was saved, taken at its word.
    ///
    /// It checked `fileExists` first, on the reasoning that a path which has
    /// been moved is worth less than nothing. That check was wrong twice over.
    /// It is a disk call on the main thread during launch, into a folder macOS
    /// gates — the one thing this app has learned the hard way never to do,
    /// because a gated call to a background app does not fail, it waits. And
    /// `fileExists` answers **false** for a folder that is perfectly well there
    /// but not yet permitted, so the first launch after a rebuild threw the
    /// setting away and the tab announced that no folder had ever been chosen.
    ///
    /// Whether the folder can be read is the reading code's business, on its own
    /// queue, where the answer can be reported instead of guessed.
    private static func folder(at key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
