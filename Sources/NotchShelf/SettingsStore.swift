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

    private static let hiddenKey = "settings.hiddenTabs"
    private static let backdropKey = "settings.backdrop"

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
}
