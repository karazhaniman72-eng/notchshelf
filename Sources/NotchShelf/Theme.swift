import AppKit
import SwiftUI

/// One place for every colour, corner and text size in the panel.
///
/// Near-monochrome: the panel reads as a piece of the screen's own bezel, and
/// the bezel is black. Text stays white at four strengths — that is what makes a
/// dense panel legible without stripes of blue holding it together.
///
/// Colour is the exception, and there is essentially one of it: an accent,
/// spent on whatever the tab exists to show — the answer, the reading, the live
/// value — with a quieter second for the rare pair of equals that would
/// otherwise be confused. Both come from `Palette`, which is where the owner of
/// the Mac gets to choose them and where the choice is checked for contrast.
/// Red joins them only when something is wrong. A hue per tab was a rainbow, and
/// a rainbow makes every tab look like a different app.
///
/// The one licensed exception is the weather, where colour describes the thing
/// itself rather than the app: the sun is yellow because the sun is yellow.
enum Theme {

    // MARK: - Colour

    /// The panel body. Pure black by default: the notch is a physical hole in
    /// the glass, and any tint at all draws a visible seam where the panel meets
    /// it. Near-white when the white background is chosen, where that seam is
    /// the price knowingly paid for a light panel.
    static var body: Color { Skin.shared.isLight ? Color(white: 0.96) : .black }

    /// Everything readable is mixed from this, and it is whatever the body is
    /// not.
    static var ink: Color { Skin.shared.isLight ? .black : .white }

    /// The ink at one step of the scale, in the strength this skin needs.
    ///
    /// The two skins do **not** share the numbers, and the note that used to
    /// stand here claiming they did — "black on white at 0.62 is as far from the
    /// paper as white on black at 0.62 is" — is simply false. Alpha composites
    /// in gamma space and contrast is measured in linear light, so the two
    /// directions are not mirror images: white at 0.46 on black clears 4.6 : 1,
    /// and black at 0.46 on the near-white body manages 3.4 : 1. The quiet step
    /// of the type scale — captions, units, axis labels, every empty state —
    /// was below the readable floor on the light panel, which is most of why it
    /// looked washed out rather than quiet.
    ///
    /// So the *ratios* are the shared thing and the opacities are derived. Each
    /// light value below is the alpha that lands black on the 0.96 body at the
    /// same contrast the dark value lands white on black:
    ///
    /// | step      | dark | ratio    | light |
    /// |-----------|------|----------|-------|
    /// | primary   | 0.95 | 18.8 : 1 | 0.985 |
    /// | secondary | 0.62 |  7.9 : 1 | 0.689 |
    /// | tertiary  | 0.46 |  4.6 : 1 | 0.545 |
    /// | dim       | 0.35 |  3.0 : 1 | 0.421 |
    private static func inked(_ dark: Double, _ light: Double) -> Color {
        ink.opacity(Skin.shared.isLight ? light : dark)
    }

    /// The one thing that is active — a selected tab, the value being read.
    static var accent: Color { ink }

    /// Wrong, and only wrong: a dead line, a battery about to go, a failure.
    ///
    /// Taken down in luminance on a light panel: #EF534F manages 3.4 : 1 on
    /// white, and the one colour in the app that must never be missed cannot be
    /// the one that fades into the paper.
    static var alert: Color {
        Skin.shared.isLight
            ? Skin.onLight(Palette.alertHex)
            : Color(red: 0.937, green: 0.325, blue: 0.314)             // #EF534F
    }

    // MARK: - The one colour

    /// The blue. Every live reading in the panel is written in it — the answer,
    /// the speed of the line, the track playing — and nothing else is coloured
    /// at all.
    ///
    /// Blue by default and blue in every screenshot, but no longer a constant:
    /// it is whatever the owner of the Mac chose, and `Palette` is where that
    /// choice lives and where it is checked. Computed rather than copied into a
    /// `let` at launch so that a change lands without a restart — the cost is a
    /// dictionary read per access, against a value that is already re-evaluated
    /// on every layout pass.
    ///
    /// Views do not observe this. `Palette.shared` is the `ObservableObject`;
    /// something above the panel has to hold it for a change to redraw what is
    /// already on screen.
    static var tint: Color {
        Skin.shared.isLight ? Skin.onLight(Palette.shared.tintHex) : Palette.shared.tint
    }

    /// The tint's second, for the one case the tint cannot handle alone: two
    /// things of equal rank that must not be read as one. The second curve
    /// against the first, the selected row while another is hovered, the target
    /// unit against the source.
    ///
    /// Not a second accent to sprinkle about. If something can be told apart by
    /// position, by weight or by simply being the only coloured thing on the
    /// tab, it is already told apart, and colouring it again spends the panel's
    /// one signal on nothing. See `Palette` for why the choices are quieter
    /// than the tints.
    static var second: Color {
        Skin.shared.isLight ? Skin.onLight(Palette.shared.secondHex) : Palette.shared.second
    }

    /// The sun, and nothing but the sun. Weather is the one tab where the
    /// colour describes the world rather than the interface.
    /// Darkened on a light panel for the same reason as the alert: a #FDBF5C sun
    /// on near-white paper is 1.6 : 1, which is a sun nobody can see.
    static var sun: Color {
        Skin.shared.isLight ? Skin.onLight("#FDBF5C")
                            : Color(red: 0.99, green: 0.75, blue: 0.36)  // #FDBF5C
    }

    // MARK: - Over a picture

    /// Ink for something written on top of an image rather than on the panel.
    ///
    /// White in both skins, and that is not an oversight. The name on a
    /// thumbnail, the cross on a pin, the zoom beside it — none of them are on
    /// the panel's paper, they are on somebody's screenshot, and a screenshot
    /// is whatever colour it happens to be. They are legible because of the
    /// scrim under them, not because of the skin, so they must not follow it:
    /// black ink on a black scrim is how the light panel lost its file names.
    static let onMedia = Color.white
    /// The scrim those sit on. Dark in both skins, for the same reason.
    static func mediaScrim(_ opacity: Double = 0.72) -> Color {
        Color.black.opacity(opacity)
    }

    /// The curves on the graph, in the order they are drawn.
    ///
    /// The third licensed exception, after the sun and the moon, and it is the
    /// same argument: the colour describes the thing rather than the interface.
    /// Three curves drawn in one blue and two greys are three curves nobody can
    /// tell apart — sin, cos and tan on one picture came out as a scribble, and
    /// no amount of labelling round the edge fixes a line you cannot follow with
    /// your eye. Each curve owns a hue, the legend under the plot spells out
    /// which, and the hues are far enough apart to survive being crossed.
    ///
    /// Fixed, and not derived from `tint`. What matters on a plot is the
    /// distance between the five, not their agreement with the rest of the app:
    /// swinging the first one to follow a chosen tint would sooner or later
    /// slide it into the third, and two curves nobody can tell apart is the
    /// exact failure this list exists to prevent.
    /// Kept as hex rather than as components so the light panel can have them:
    /// five colours picked to be far apart on black are five pale washes on
    /// white — the blue draws a 1.9 : 1 line, which is a curve you cannot
    /// follow. `Skin.onLight` walks each one down until it reads, keeping the
    /// hue, so the picture stays five distinguishable lines in either skin.
    static let curveHexes = ["#59C7FA",      // the blue, as before
                             "#FCBF5C",      // amber
                             "#73DE99",      // green
                             "#CC99FA",      // violet
                             "#F58C9E"]      // rose

    static var curves: [Color] { curveHexes.map(shade) }

    static func curve(_ index: Int) -> Color {
        shade(curveHexes[((index % curveHexes.count) + curveHexes.count) % curveHexes.count])
    }

    /// A fixed colour, as this skin can show it. Cached inside `Skin`, so this
    /// is a dictionary read on the light side and a hex parse on the dark one.
    private static func shade(_ hex: String) -> Color {
        Skin.shared.isLight ? Skin.onLight(hex) : Palette.color(hex)
    }

    /// The moon, on the same licence as the sun: night is blue, and deep blue
    /// rather than pale — a night sky, not a daytime one. Nothing else in the
    /// panel is this colour, so it cannot be confused with `tint`, which is the
    /// blue that means "this is the live reading".
    static var moon: Color { shade("#4A70EB") }

    // MARK: - Text, three steps and a floor

    /// Names, titles, the number you came to read.
    static var textPrimary: Color { inked(0.95, 0.985) }  // 18.8 : 1
    /// Times, hosts, units — present, not competing.
    static var textSecondary: Color { inked(0.62, 0.689) } //  7.9 : 1
    /// The quiet step: footnotes, captions, units, axis labels, idle icons.
    ///
    /// This is the bottom of the scale, and it is where it is for a reason.
    /// White on black clears the 4.5 : 1 that both Apple and WCAG ask of small
    /// text only from 0.455 up; below that the words are on the panel without
    /// being readable on it. There used to be a fourth step under this one at
    /// 0.24 — 1.9 : 1 — and the uptime, the disk, the battery health and the
    /// case charge were all written in it.
    static var textTertiary: Color { inked(0.46, 0.545) } //  4.6 : 1

    /// Not a text colour. This is the shade of something that is off, done or
    /// not there yet: the dot beside a disconnected device, the rule through a
    /// finished plan, the zero on a calculator nobody has typed into.
    ///
    /// It stays under the text floor on purpose — dimness is the message here,
    /// and WCAG exempts inactive controls for exactly this reason. It clears
    /// 3 : 1, which is the bar for graphics, so the shapes still read.
    static var inkDim: Color { inked(0.35, 0.421) }       //  3.0 : 1

    // MARK: - Fills, four steps

    /// The plate under a card or a grouped reading. Barely there on purpose:
    /// it separates, it does not decorate.
    static var surface: Color { ink.opacity(0.06) }
    /// A row or chip under the cursor.
    static var fillHover: Color { ink.opacity(0.10) }
    /// The selected thing.
    static var fillActive: Color { ink.opacity(0.16) }
    /// Text field backgrounds.
    static var fillInput: Color { ink.opacity(0.07) }
    /// Borders and dividers.
    static var hairline: Color { ink.opacity(0.10) }

    // MARK: - Corners, three steps

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16

    /// Where the panel meets the top of the screen: a fillet, so the black runs
    /// out of the bezel instead of butting against it in a step.
    static let filletRadius: CGFloat = 14
    /// The bottom two corners of the panel.
    static let bottomRadius: CGFloat = 30

    // MARK: - Type, four steps

    /// The one big number on a tab.
    static let titleText = Font.system(size: 20, weight: .semibold)
    /// Every list row.
    static let rowText = Font.system(size: 15, weight: .medium)
    /// Times, numbers, hosts — figures line up in rounded.
    static let metaText = Font.system(size: 13.5, design: .rounded)
    /// Footnotes.
    static let captionText = Font.system(size: 12.5)

    /// Type that gives way when there is a lot of it.
    ///
    /// The panel is read at arm's length off the top of the screen, so the
    /// default is deliberately large — and a list of twenty rows at that size
    /// would run off the bottom. Rather than picking a size small enough for the
    /// worst case and living with it on every tab, the size is chosen from how
    /// much there is: full size while the tab is half empty, stepping down as it
    /// fills, never past `floor` where it would stop being legible.
    static func scaled(_ base: CGFloat, count: Int, comfortable: Int,
                       floor: CGFloat = 11) -> Font {
        .system(size: shrink(base, count: count, comfortable: comfortable, floor: floor),
                weight: .medium)
    }

    static func shrink(_ base: CGFloat, count: Int, comfortable: Int,
                       floor: CGFloat = 11) -> CGFloat {
        guard count > comfortable else { return base }
        // One point per extra item, which lands a twenty-row list a couple of
        // steps down rather than instantly at the floor.
        return max(floor, base - CGFloat(count - comfortable))
    }

    // MARK: - Spacing

    /// Distance from the panel edge to any content. Wide on purpose: content
    /// running up to the black edge is what made the panel read as a box
    /// somebody had stuffed full.
    static let gutter: CGFloat = 26
    /// Air under the last row, so nothing sits on the bottom rounding.
    static let contentBottom: CGFloat = 18
    static let rowPaddingH: CGFloat = 12
    static let rowPaddingV: CGFloat = 8

    // MARK: - Motion

    /// Whether the owner of the Mac has asked for less movement.
    ///
    /// Every animation below reads this, so honouring the setting is one switch
    /// rather than a modifier remembered on ninety views. Cached rather than
    /// asked each time: this is read during layout, and layout runs far more
    /// often than anybody changes an accessibility setting. `AppDelegate`
    /// refreshes it when macOS says the setting moved.
    private(set) static var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    static func refreshMotionPreference() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        Log.write("reduce motion=\(reduceMotion)")
    }

    /// What everything becomes when movement is refused: a cross-fade, which is
    /// what Apple asks for in its place — not nothing at all, or the panel would
    /// snap between states with no thread between them.
    private static let crossFade = Animation.easeOut(duration: 0.2)

    /// The panel unfolding. Slow enough to read as one movement, damped enough
    /// not to wobble: it is a slab of the bezel sliding down, not a bubble.
    static var unfold: Animation {
        reduceMotion ? crossFade : .smooth(duration: 0.46, extraBounce: 0.08)
    }
    /// Content settling into a tab that is already open.
    static var settle: Animation { reduceMotion ? crossFade : .smooth(duration: 0.34) }
    /// Anything answering the cursor. Short, because the hand is still moving —
    /// but a spring rather than a ramp, so it eases out of the movement instead
    /// of stopping dead at the end of it.
    static var touch: Animation {
        reduceMotion ? crossFade : .spring(response: 0.26, dampingFraction: 0.82)
    }
    /// One tab giving way to the next, and one tool inside a tab to the next.
    /// Slower than a hover and softer than the unfold: the panel stays put and
    /// only what is written on it changes.
    static var swap: Animation { reduceMotion ? crossFade : .smooth(duration: 0.28) }
    /// A figure that keeps changing while it is being watched — a clock, a
    /// reading, an answer counting itself up.
    static var value: Animation { reduceMotion ? crossFade : .smooth(duration: 0.22) }

    /// A thing arriving where there was nothing: a button that has just become
    /// possible, a card landing on the shelf, a reading that finally came back.
    ///
    /// Bouncier than anything else here on purpose. Fading a control in tells
    /// you it is there; landing tells you it just happened, and the eye catches
    /// the second one without being asked to look.
    static var drop: Animation {
        reduceMotion ? crossFade : .spring(response: 0.34, dampingFraction: 0.58)
    }
    /// The same thing going away. Faster and without the bounce — leaving is
    /// not an event, and a wobble on the way out reads as a mistake.
    static var pop: Animation {
        reduceMotion ? crossFade : .spring(response: 0.2, dampingFraction: 0.9)
    }
    /// How far a tab slides in from as it takes over. A whole panel's width
    /// reads as the panel itself moving; this is a nudge in the direction
    /// travelled, and the fade does the rest of the work.
    static var slide: CGFloat { reduceMotion ? 0 : 34 }
}

extension View {
    /// Arriving like a drop rather than a dissolve: down a little, small, and
    /// then settling with a bounce. Leaving is the same movement, quicker and
    /// straighter.
    ///
    /// With movement refused it is the dissolve after all — the point of the
    /// setting is that nothing travels or springs.
    func dropIn() -> some View {
        transition(
            Theme.reduceMotion
                ? AnyTransition.opacity.animation(Theme.settle)
                : .asymmetric(
                    insertion: .scale(scale: 0.72).combined(with: .opacity).combined(with: .offset(y: -6)).animation(Theme.drop),
                    removal: .scale(scale: 0.86).combined(with: .opacity).animation(Theme.pop)
                )
        )
    }

    /// The scale part of a landing, dropped when movement is refused.
    func landing(_ scale: CGFloat) -> some View {
        scaleEffect(Theme.reduceMotion ? 1 : scale)
    }
}
