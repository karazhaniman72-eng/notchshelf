import AppKit
import SwiftUI

/// Whether the panel is written in white on black or in black on white.
///
/// It exists because one of the backgrounds is white, and a white background is
/// not a background change — it is every colour in the panel at once. Text that
/// was white has to become black, the fills that lifted a row out of the black
/// have to darken it instead, and the accent has to survive a light surface: the
/// sky blue that reads at 11 : 1 on black manages 1.9 : 1 on white, which is a
/// colour nobody can read a number in.
///
/// A switch rather than a whole second theme. `Theme` asks this one object which
/// way round it is and mixes everything from `ink` as it always did, so the
/// light panel cannot drift away from the dark one — there is one set of
/// opacities and one set of rules, held up to a different piece of paper.
final class Skin: ObservableObject {
    static let shared = Skin()

    /// Set from `SettingsStore`, which owns the background choice. Nothing else
    /// writes it, so the light panel and the white background can never be out
    /// of step with each other.
    @Published var isLight = false {
        didSet {
            guard isLight != oldValue else { return }
            Log.write("skin=\(isLight ? "light" : "dark")")
        }
    }

    private init() {}

    // MARK: - Accents on a light panel

    /// The same accent, dark enough to be read on white.
    ///
    /// `Palette` guarantees every colour it offers clears 4.5 : 1 against black,
    /// which is the right guarantee for a black panel and exactly the wrong one
    /// for a white one — the two run in opposite directions, and the brightest,
    /// most legible accents on black are the worst on white. Rather than keeping
    /// a second palette that would have to be chosen from twice, the hue is
    /// kept and the colour walked down in luminance until it clears the same bar
    /// against white. Sky stays recognisably sky; it just stops glowing.
    ///
    /// Cached because this is read during layout, dozens of times per frame, and
    /// the answer only changes when somebody picks a new colour.
    static func onLight(_ hex: String) -> Color {
        if let hit = cache[hex] { return hit }
        let colour = darkenedForWhite(hex)
        cache[hex] = colour
        return colour
    }

    private static var cache: [String: Color] = [:]

    /// How much more colour a shade needs on paper than it did on black.
    ///
    /// Scaling all three channels equally — which is what this did — keeps the
    /// hue *and* the saturation exactly: HSV saturation is `(max − min) / max`,
    /// and a common factor cancels out of it. That sounds like the right answer
    /// and it looks like a wrong one, because a colour at two thirds brightness
    /// and two thirds saturation is a colour with the life gone out of it: the
    /// sky blue came back as slate, the amber as olive. Every design system that
    /// carries one hue across a light and a dark surface does the same thing
    /// instead — as the shade goes down, the chroma goes up.
    ///
    /// A third more, which is enough to keep sky reading as sky at half the
    /// brightness and not so much that a pastel turns into a poster.
    private static let chromaBoost = 1.35

    private static func darkenedForWhite(_ hex: String) -> Color {
        guard let rgb = Palette.components(hex) else { return .black }
        let (hue, saturation, value) = hsv(rgb)
        let wanted = min(1, saturation * chromaBoost)

        // Sixty steps of 2 % reaches near-black, so the loop always ends on an
        // answer. Walking the brightness rather than solving for it: the floor
        // is a contrast ratio, and contrast is not linear in any of these.
        var level = value
        for _ in 0..<60 {
            let candidate = rgbFrom(hue: hue, saturation: wanted, value: level)
            if contrastOnWhite(candidate) >= Palette.readableFloor {
                return Color(red: candidate.r, green: candidate.g, blue: candidate.b)
            }
            level *= 0.98
        }
        return .black
    }

    private static func hsv(_ rgb: (r: Double, g: Double, b: Double))
        -> (hue: Double, saturation: Double, value: Double) {
        let high = max(rgb.r, rgb.g, rgb.b)
        let low = min(rgb.r, rgb.g, rgb.b)
        let spread = high - low
        guard spread > 0, high > 0 else { return (0, 0, high) }

        let hue: Double
        if high == rgb.r {
            hue = 60 * (((rgb.g - rgb.b) / spread).truncatingRemainder(dividingBy: 6))
        } else if high == rgb.g {
            hue = 60 * (((rgb.b - rgb.r) / spread) + 2)
        } else {
            hue = 60 * (((rgb.r - rgb.g) / spread) + 4)
        }
        return ((hue < 0 ? hue + 360 : hue), spread / high, high)
    }

    private static func rgbFrom(hue: Double, saturation: Double, value: Double)
        -> (r: Double, g: Double, b: Double) {
        let sector = (hue.truncatingRemainder(dividingBy: 360)) / 60
        let index = Int(sector.rounded(.down))
        let fraction = sector - Double(index)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))
        switch index % 6 {
        case 0: return (value, t, p)
        case 1: return (q, value, p)
        case 2: return (p, value, t)
        case 3: return (p, q, value)
        case 4: return (t, p, value)
        default: return (value, p, q)
        }
    }

    /// WCAG contrast against pure white, the mirror of `Palette.contrastOnBlack`.
    private static func contrastOnWhite(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        1.05 / (Palette.luminance(rgb) + 0.05)
    }
}
