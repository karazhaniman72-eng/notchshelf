import AppKit
import Combine
import SwiftUI

/// The frosted alternative to the black slab. Frosted all the way to the top
/// edge of the screen, with nothing painted over the band the notch sits in.
///
/// There was an opaque cap across that top band for most of this file's life,
/// and it was defended by two arguments. Both are true, and neither survives
/// contact with what the setting is for:
///
///  1. **The notch outline.** The cut-out is a hole in the glass with no pixels
///     behind it, so it is absolutely black whatever the panel does. Against a
///     translucent slab it stops being swallowed and reads as an oblong
///     silhouette in the middle of the top edge.
///  2. **The menu bar underneath.** This window sits at statusBar+2 and covers
///     the bar across its own width. `.behindWindow` blending samples whatever
///     is behind the *window*, and the menu bar is behind the window, so the top
///     band shows a blurred row of menu titles and status icons.
///
/// The cap solved both by painting the band opaque black — and an opaque black
/// bar across the head of a see-through panel is not a solution, it is the
/// thing itself failing. It was tried twice: melted into the slab with a
/// sixteen-point gradient (a bruise) and then as one crisp edge (a black
/// rectangle stuck on top). The owner of this Mac looked at the second one and
/// said, correctly, that he had asked for a transparent panel and been handed a
/// black rectangle.
///
/// So: no cap. "Clear" means clear, including over the menu bar, and the two
/// costs above are the honest price of the row rather than problems to be
/// papered over. Anybody who does not want to pay them has three flat choices
/// in the same list — Solid and White are opaque, Veil is 88 % opaque — and
/// those do not come through this file at all.

// MARK: - Strength

/// How much of the desktop is allowed through, in three steps.
///
/// The number that actually varies is `dim`: the opacity of the black scrim laid
/// over the blurred desktop. The blur alone cannot be trusted for contrast — it
/// preserves the average brightness of what it samples, so a blurred white
/// Finder window is still white, and white text on it disappears. The scrim is
/// what guarantees a floor no matter what is underneath.
///
/// Three steps rather than a slider, and the steps are picked by arithmetic
/// rather than by eye. Worst case is a pure-white desktop; the material is
/// assumed to pass it through unchanged, which is pessimistic (a dark HUD
/// material tints it down) but is the only assumption that holds on every
/// wallpaper and in every macOS version. Composite in gamma space, the way
/// Core Animation blends: text of opacity a over background g renders at
/// `a + (1 - a) * g`, and `g = 1 - dim`.
///
/// Against a white desktop, the three text steps in `Theme` come out at:
///
/// | dim  | primary .95 | secondary .62 | tertiary .46 |
/// |------|-------------|---------------|--------------|
/// | 0.88 | 15.0 : 1    | 7.1 : 1       | 4.5 : 1      |
/// | 0.72 |  8.5 : 1    | 4.7 : 1       | 3.4 : 1      |
/// | 0.56 |  4.6 : 1    | 3.0 : 1       | 2.3 : 1      |
///
/// So the 4.5 : 1 that WCAG and Apple both ask of small text survives down to
/// dim 0.873 for tertiary text, 0.705 for secondary, and 0.553 for primary.
/// That is the honest cost of this feature: a panel that is visibly see-through
/// cannot also keep the quiet step of the type scale readable over a light
/// desktop. `.slight` is the only step where the palette as written still holds,
/// which is why it is the default and the only one the settings offer as "Veil".
enum PanelBackdropStrength: String, CaseIterable, Identifiable, Sendable {
    /// Almost black. Frost as a hint of one — the wallpaper's colour comes
    /// through, its shapes do not.
    case slight
    /// The middle. Breath on a window: shapes behind become smudges of tone.
    case medium
    /// Genuinely see-through: the window underneath is a window, not a tone.
    /// Only primary text clears 4.5 : 1 here, so nothing in the panel below a
    /// heading is guaranteed readable over a light desktop — which is what the
    /// settings row for it says, in those words.
    case strong

    var id: String { rawValue }

    /// Opacity of the scrim over the blurred desktop — black on a dark panel,
    /// white on a light one.
    var dim: Double {
        switch self {
        case .slight: return 0.88
        case .medium: return 0.72
        // 0.56, not the 0.42 that was here. The table above is the arithmetic
        // for this list and it has always said 0.56; the code had drifted to a
        // number nobody re-checked, and at 0.42 the panel is not "see-through
        // with small text suffering", it is a panel with nothing readable on it
        // at all — the headline falls to 2.9 : 1 over a white desktop, under
        // even the 3 : 1 that shapes are held to. The row promises one step of
        // the type scale survives; 0.56 is the darkest this may be while that
        // stays true.
        case .strong: return 0.56
        }
    }

    /// The dimmest white the type scale may use at this strength and still clear
    /// 4.5 : 1 over a white desktop. `Theme.textTertiary` is 0.46,
    /// `Theme.textSecondary` 0.62, `Theme.textPrimary` 0.95 — so this says, in
    /// one number, how much of the palette survives the choice.
    var readableTextFloor: Double {
        switch self {
        case .slight: return 0.46
        case .medium: return 0.62
        case .strong: return 0.95
        }
    }
}

// MARK: - The background

/// The panel body, frosted: blurred desktop and a scrim over it for contrast,
/// cut to `shape`. Two layers, no third one hiding the top.
///
/// Drop-in replacement for `NotchBody().fill(Theme.body)` — same size, same
/// silhouette, same place in the stack.
struct PanelBackdrop: View {
    /// The silhouette. Passed in rather than constructed here so the mask and the
    /// visible edge can never drift apart: whatever `ContentView` draws the panel
    /// as, this is cut from the same value.
    var shape: NotchBody = NotchBody()
    var strength: PanelBackdropStrength = .slight
    /// Which system material does the blurring. See `PanelBlurLayer` for why
    /// `.hudWindow` is the default.
    var material: NSVisualEffectView.Material = .hudWindow

    /// Cached rather than read during layout, and refreshed from the workspace
    /// notification below. Note this is *not* left to `NSVisualEffectView`,
    /// which honours the setting by going opaque grey — grey is a window colour,
    /// and this panel has to be bezel-coloured or the fillets stop working.
    @State private var reduceTransparency =
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    var body: some View {
        content
            // The setting can move while the app is running, and this app runs
            // for weeks at a time. Cheap to watch: the notification fires when
            // somebody changes an accessibility switch, which is approximately
            // never.
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
                let now = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                guard now != reduceTransparency else { return }
                reduceTransparency = now
                Log.write("reduce transparency=\(now)")
            }
    }

    @ViewBuilder
    private var content: some View {
        if reduceTransparency {
            // Asked for less transparency, given none: the panel it was before.
            shape.fill(Theme.body)
        } else {
            ZStack(alignment: .top) {
                PanelBlurLayer(material: material, shape: shape, isLight: Skin.shared.isLight)

                // The scrim. Over the material rather than under it, which is
                // the same result and a far easier thing to reason about: the
                // final background is exactly `(1 - dim)` of whatever the blur
                // produced, which is the arithmetic the table above is built on.
                Rectangle()
                    .fill(Theme.body)
                    .opacity(strength.dim)
            }
            // Belt and braces. The blur carries its own mask because a
            // behind-window material is composited outside this clip (see
            // `MaskedVisualEffectView`); everything else in the stack is
            // ordinary SwiftUI content and is cut here.
            .clipShape(shape)
        }
    }
}

// MARK: - Settings glue

/// `PanelBackdrop` wired to the setting, so `ContentView` needs one line and
/// `PanelController` needs no change at all.
///
/// It owns the observation itself: `ContentView` watches `AppModel` by name for
/// each store it actually reads, and `AppModel` publishes nothing of its own, so
/// a background chosen in settings would otherwise not arrive until something
/// else redrew the panel.
struct PanelBackdropSlab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        switch settings.backdrop {
        case .solid:
            // Not merely `strength` at its darkest: no blur at all. A material
            // that is 99 % covered still costs a backdrop layer and still
            // re-samples the desktop behind the window on every frame anything
            // moves under it, for a difference nobody can see.
            NotchBody().fill(Theme.body)
        case .veil:
            PanelBackdrop(strength: .slight)
        case .glass:
            PanelBackdrop(strength: .medium)
        case .clear:
            PanelBackdrop(strength: .strong)
        case .white:
            // Paper, and nothing behind it. This was a frosted white for a day
            // and the frost is what made it look cheap: eighty-eight per cent of
            // a near-white scrim over a blurred desktop is not white, it is
            // whatever the wallpaper is, diluted — grey over a dark picture,
            // faintly green over a green one, and different on every space. A
            // panel that is meant to read as a sheet of paper hung off the bezel
            // has to be the same sheet every time it opens.
            //
            // Same treatment as `.solid`, and for the same reason: the two ends
            // of the range are colours, the three in the middle are materials.
            NotchBody().fill(Theme.body)
        }
    }
}

// MARK: - The material

/// `NSVisualEffectView` as a SwiftUI view, masked to the panel's silhouette.
///
/// Material choice. What the person asked for is a frosted window — a strong
/// blur that carries tone but no shapes — over an arbitrary desktop, from a
/// floating panel that is usually not the active app:
///
///  * `.hudWindow` is the default and the right one. It is the material Apple
///    made for exactly this situation, a small dark surface floating over
///    somebody else's content, and in a dark appearance it is the darkest of
///    them, which is worth several points of contrast before the scrim does
///    anything at all.
///  * `.underWindowBackground` blurs harder still and is the one material
///    explicitly designed around `.behindWindow` blending, but it is lighter,
///    so more scrim is needed to get back to the same floor. Worth trying if
///    `.hudWindow` reads as too thin.
///  * `.fullScreenUI` is the third that blurs at this strength.
///  * `.menu`, `.popover`, `.sidebar` and the rest are deliberately not offered:
///    they are vibrancy surfaces, tuned thin and light so that text drawn *with*
///    vibrancy pops on them, and this panel draws plain white text on top.
private struct PanelBlurLayer: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let shape: NotchBody
    /// Which rendering of the material to ask for. Every material comes in a
    /// light and a dark one, and the choice is made by the view's appearance
    /// rather than by anything drawn on top of it — so a panel written in black
    /// has to ask for the light one or it ends up black on charcoal.
    let isLight: Bool

    func makeNSView(context: Context) -> MaskedVisualEffectView {
        let view = MaskedVisualEffectView()
        view.material = material
        // The whole point: sample what is behind the window, not what is behind
        // the view inside it. `.withinWindow` would blur the panel's own black,
        // which is nothing.
        view.blendingMode = .behindWindow
        // Not `.followsWindowActiveState`. This is an accessory app whose panel
        // is deliberately non-activating, so it is inactive nearly always, and
        // an inactive material stops blurring and goes flat grey — the panel
        // would frost only while it happened to be key.
        view.state = .active
        // Materials come in a light and a dark rendering, and which one is used
        // is decided by the view's appearance, not by the window's level or the
        // colours drawn on top. Everything written on this panel is white, so
        // the light rendering would be a white-on-white panel on a Mac set to
        // light mode.
        view.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
        view.shape = shape
        return view
    }

    func updateNSView(_ view: MaskedVisualEffectView, context: Context) {
        if view.material != material { view.material = material }
        let wanted = NSAppearance(named: isLight ? .aqua : .darkAqua)
        if view.appearance?.name != wanted?.name { view.appearance = wanted }
        view.shape = shape
    }
}

/// An `NSVisualEffectView` that keeps its own mask in step with its size.
///
/// The mask is not a nicety. SwiftUI's `clipShape` puts a mask on the layer it
/// wraps the hosted view in, and a `.behindWindow` material is not drawn into
/// that layer — the window server composites the backdrop behind the window and
/// the clip has nothing to bite on. The supported way to give one a shape is
/// `maskImage`, whose alpha channel the material is drawn through, and that is
/// what happens here.
///
/// The image is rebuilt from `NotchBody` itself rather than from a copy of its
/// geometry, so the fillets and the bottom rounding can be changed in one place
/// and the frost follows. It is rebuilt on every size change, which during the
/// unroll means once a frame: the panel is drawn at every height between nothing
/// and full, `NotchBody` clamps its radii to what fits, and a mask made once at
/// full height and stretched would put a 30-point rounding on a 10-point slab.
final class MaskedVisualEffectView: NSVisualEffectView {
    var shape = NotchBody() {
        didSet {
            guard shape.fillet != oldValue.fillet || shape.bottom != oldValue.bottom else { return }
            masked = nil
            needsLayout = true
        }
    }

    /// The size the current `maskImage` was drawn for. Nil means there isn't one.
    private var masked: CGSize?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Here as well as in `layout()`, and on purpose: SwiftUI positions a
        // represented view by setting its frame, and a mask applied one layout
        // pass later is one frame of blur spilling past the fillets.
        applyMask()
    }

    override func layout() {
        super.layout()
        applyMask()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyMask()
    }

    private func applyMask() {
        let size = bounds.size
        // Collapsed. A nil mask means the material is not cut at all, which is
        // correct for a view with no height — and cheaper than an empty image.
        guard size.width > 0.5, size.height > 0.5 else {
            if masked != nil {
                masked = nil
                maskImage = nil
            }
            return
        }
        guard masked != size else { return }
        masked = size

        // `NotchBody` builds its path with y running down, the way SwiftUI
        // works and the way an `NSImage` drawn `flipped: true` does — take the
        // flag off and the panel would be frosted with its fillets at the
        // bottom and its 30-point rounding cutting into the bezel.
        let path = shape.path(in: CGRect(origin: .zero, size: size)).cgPath
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        // Drawn at the exact size it is used at, so there is nothing to stretch
        // and no cap insets to get wrong.
        image.resizingMode = .stretch
        maskImage = image
    }
}
