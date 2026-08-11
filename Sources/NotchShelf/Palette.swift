import Foundation
import SwiftUI

/// The two colours the owner of the Mac is allowed to move, and the rules that
/// stop a choice from taking the panel apart.
///
/// `Theme` holds the colours that mean something fixed — black is the bezel,
/// red is a failure, the sun is yellow because the sun is yellow. None of those
/// are a preference, and none of them are here. What is here is the pair that
/// is pure taste:
///
/// * **tint** — the one colour of the panel: the live reading, the answer, the
///   tab that is open. Change it and the panel changes character without any
///   piece of it changing meaning.
/// * **second** — the colour for the case the tint cannot cover on its own:
///   two things of the *same rank* that must not be confused. A second curve
///   against the first, the row picked out of a list while another row is
///   hovered, the "before" against the "after" of a conversion. Without it the
///   only way to separate two equals is to make one of them dimmer, which is a
///   lie — dim means finished or off everywhere else in the panel. `second` is
///   deliberately quieter than `tint` in every ready-made choice below: the
///   pair reads as first and second, not as two apps arguing.
///
/// Everything a person can pick has to survive being **text on black**, because
/// that is what it usually is here — a number, a name, a unit — not a filled
/// chip with white on top. That is the whole reason the choice is a list rather
/// than a colour well: a navy or a chocolate is a perfectly nice colour and an
/// unreadable one at 13 points on black, and nobody discovers that until they
/// have already saved it.
final class Palette: ObservableObject {

    // MARK: - What a choice is

    /// One named entry in the settings list. `name` is English and goes on
    /// screen; `hex` is what is written to disk and what identifies the row.
    struct Choice: Identifiable, Hashable {
        let name: String
        let hex: String

        var id: String { hex }
        var color: Color { Palette.color(hex) }
        /// The colour as the panel will actually draw it, which on a light panel
        /// is not the one in the list: `Skin` walks every accent down until it
        /// can be read on white. A swatch showing the raw hex would promise a
        /// sky blue and deliver a slate one — and the ring marking the chosen
        /// swatch, drawn in the same raw colour, all but vanished on paper.
        var shown: Color { Skin.shared.isLight ? Skin.onLight(hex) : Palette.color(hex) }
        /// Contrast against the panel body, for anyone who wants to show it.
        var contrast: Double { Palette.contrastOnBlack(hex) }
    }

    // MARK: - The rules a colour has to pass

    /// The same 4.5 : 1 that holds `Theme.textTertiary` at 0.46 opacity. A tint
    /// is read as small text far more often than it is read as a shape, so it
    /// is held to the text bar rather than the 3 : 1 graphics one.
    static let readableFloor: Double = 4.5

    /// `Theme.alert`, written again here rather than pulled out of the `Color`.
    ///
    /// SwiftUI will not hand back the components of a `Color` without going
    /// through `NSColor` and a colour-space conversion that can fail, and this
    /// value is needed for a comparison that must never silently stop working.
    /// If `Theme.alert` ever moves, move this string with it — it is the only
    /// place the two are tied together.
    static let alertHex = "#EF534F"

    /// How wide the wedge of hue around the alert red is closed off.
    ///
    /// Red in this panel means *broken* — a dead line, a battery about to go.
    /// The moment the open tab is also red, red stops being an alarm and starts
    /// being decoration, and the one colour in the app that was worth looking
    /// at is spent. Thirty degrees either side of the alert hue takes out the
    /// reds, the salmons and the hot pinks on one side and the burnt oranges on
    /// the other, while leaving amber (about 37°, where `Theme.sun` lives) and
    /// the violets alone.
    static let reservedArc: Double = 30

    /// Below this saturation a hue is not a hue any more — a warm grey sits at
    /// "red" on the wheel and reads as grey on screen. Judging those by angle
    /// would ban every neutral in the list for no gain.
    static let reservedSaturation: Double = 0.22

    /// Why a colour was turned down. The settings screen can show `reason`
    /// as it is; the strings are English because everything on screen is.
    enum Refusal: Equatable {
        /// Not six hex digits.
        case malformed
        /// Legible as a shape, perhaps, but not as the small text it will be.
        case unreadable(Double)
        /// Too close to the colour that means something is wrong.
        case reserved

        var reason: String {
            switch self {
            case .malformed:
                return "Not a colour — use six hex digits, like #59C7FA."
            case .unreadable(let ratio):
                return String(format: "Too dark to read on black (%.1f : 1, needs 4.5 : 1).", ratio)
            case .reserved:
                return "Red is reserved for failures — pick a colour further from it."
            }
        }
    }

    // MARK: - Ready-made choices

    /// Nine tints, every one of them clearing 4.5 : 1 on black and none of them
    /// inside the reserved wedge. Spread round the wheel on purpose: a list of
    /// nine blues is a list of one blue with a rounding error.
    ///
    /// Contrast against black, for the record:
    /// Sky 11.0, Cyan 12.7, Aqua 11.7, Mint 12.6, Basil 11.5, Amber 12.5,
    /// Periwinkle 9.2, Lilac 9.2, Orchid 9.2.
    static let tintChoices: [Choice] = [
        Choice(name: "Sky",        hex: "#59C7FA"),   // the original, and the default
        Choice(name: "Cyan",       hex: "#66D9E8"),
        Choice(name: "Aqua",       hex: "#4FD6C1"),
        Choice(name: "Mint",       hex: "#73DE99"),
        Choice(name: "Basil",      hex: "#8FD07A"),
        Choice(name: "Amber",      hex: "#F2C14E"),
        Choice(name: "Periwinkle", hex: "#8FA8FF"),
        Choice(name: "Lilac",      hex: "#B79CFF"),
        Choice(name: "Orchid",     hex: "#E08FE0")
    ]

    /// Nine seconds, chosen to lose an argument with any tint above.
    ///
    /// Every one of them is desaturated next to the tints — that is the point,
    /// not an accident of picking. Two equally loud colours side by side is the
    /// rainbow the panel was built to avoid; a loud one and a quiet one reads
    /// immediately as "this one, and also that one".
    ///
    /// Contrast against black: Steel 10.0, Ice 14.3, Harbor 10.6, Seafoam 14.2,
    /// Sage 11.8, Moss 11.6, Straw 12.8, Lavender 11.3, Plum 9.2.
    static let secondChoices: [Choice] = [
        Choice(name: "Steel",    hex: "#9FB6CC"),     // the default
        Choice(name: "Ice",      hex: "#BFD8F0"),
        Choice(name: "Harbor",   hex: "#7FC4C0"),
        Choice(name: "Seafoam",  hex: "#9BE3C8"),
        Choice(name: "Sage",     hex: "#B3C9A4"),
        Choice(name: "Moss",     hex: "#A9CC7A"),
        Choice(name: "Straw",    hex: "#DCC98A"),
        Choice(name: "Lavender", hex: "#C0B8E8"),
        Choice(name: "Plum",     hex: "#C79BE0")
    ]

    static let defaultTintHex = "#59C7FA"
    static let defaultSecondHex = "#9FB6CC"

    // MARK: - Storage

    /// Hex strings rather than archived colour data. A preference somebody may
    /// one day have to read, diff or fix by hand should be legible in
    /// `defaults read`, and an sRGB triple survives a colour-space change in a
    /// way an archived `NSColor` does not.
    private static let tintKey = "theme.tint"
    private static let secondKey = "theme.second"

    static let shared = Palette()

    @Published private(set) var tintHex: String
    @Published private(set) var secondHex: String

    private init() {
        let defaults = UserDefaults.standard
        tintHex = Palette.stored(defaults.string(forKey: Palette.tintKey),
                                 fallback: Palette.defaultTintHex)
        secondHex = Palette.stored(defaults.string(forKey: Palette.secondKey),
                                   fallback: Palette.defaultSecondHex)
    }

    /// What `Theme.tint` and `Theme.second` resolve to.
    var tint: Color { Palette.color(tintHex) }
    var second: Color { Palette.color(secondHex) }

    var tintChoice: Choice? { Palette.tintChoices.first { $0.hex == tintHex } }
    var secondChoice: Choice? { Palette.secondChoices.first { $0.hex == secondHex } }

    // MARK: - Changing it

    /// Returns `nil` when the colour was taken, or the reason it was not.
    ///
    /// The check lives here rather than in the settings screen so that a colour
    /// arriving from anywhere — a list row, a typed hex, a preference restored
    /// from another Mac — goes through the same gate. A refused colour changes
    /// nothing: the old one stays, and the caller has a sentence to show.
    @discardableResult
    func setTint(_ hex: String) -> Refusal? {
        guard let normal = Palette.normalised(hex) else { return .malformed }
        if let refusal = Palette.refusal(for: normal) { return refusal }
        guard normal != tintHex else { return nil }
        tintHex = normal
        UserDefaults.standard.set(normal, forKey: Palette.tintKey)
        Log.write("tint \(normal)")
        return nil
    }

    @discardableResult
    func setSecond(_ hex: String) -> Refusal? {
        guard let normal = Palette.normalised(hex) else { return .malformed }
        if let refusal = Palette.refusal(for: normal) { return refusal }
        guard normal != secondHex else { return nil }
        secondHex = normal
        UserDefaults.standard.set(normal, forKey: Palette.secondKey)
        Log.write("second \(normal)")
        return nil
    }

    func reset() {
        setTint(Palette.defaultTintHex)
        setSecond(Palette.defaultSecondHex)
    }

    // MARK: - The gate

    /// Every reason a colour cannot be an accent, in the order that matters.
    ///
    /// Readability first: a colour that cannot be read is useless whatever hue
    /// it is, and telling somebody their maroon is "too close to red" when the
    /// real problem is that it is nearly black would send them looking for a
    /// darker maroon.
    static func refusal(for hex: String) -> Refusal? {
        guard let rgb = components(hex) else { return .malformed }
        let ratio = contrastOnBlack(rgb)
        if ratio < readableFloor { return .unreadable(ratio) }
        if isReserved(rgb) { return .reserved }
        return nil
    }

    static func isAllowed(_ hex: String) -> Bool { refusal(for: hex) == nil }

    /// WCAG relative luminance, and from it the contrast against pure black.
    ///
    /// Against black the general contrast formula collapses to
    /// `(L + 0.05) / 0.05`, because the darker of the two is always the panel
    /// and the panel's luminance is zero. Left as the full division rather than
    /// `20 * L + 1` so it still reads as the ratio it is.
    static func contrastOnBlack(_ hex: String) -> Double {
        guard let rgb = components(hex) else { return 0 }
        return contrastOnBlack(rgb)
    }

    static func contrastOnBlack(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        (luminance(rgb) + 0.05) / 0.05
    }

    static func luminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    /// Is this colour close enough to the alert red to blunt it?
    ///
    /// Compared by hue rather than by distance in RGB, because the thing being
    /// protected is the *reading* of the colour, not its coordinates. A pale
    /// salmon is nowhere near `#EF534F` in RGB and is still unmistakably red
    /// the moment it lands next to white text on a black panel.
    static func isReserved(_ hex: String) -> Bool {
        guard let rgb = components(hex) else { return false }
        return isReserved(rgb)
    }

    static func isReserved(_ rgb: (r: Double, g: Double, b: Double)) -> Bool {
        let (hue, saturation) = hueSaturation(rgb)
        guard saturation >= reservedSaturation else { return false }
        return hueDistance(hue, alertHue) <= reservedArc
    }

    /// The hue of `Theme.alert`, worked out once from `alertHex`.
    static let alertHue: Double = {
        guard let rgb = components(alertHex) else { return 0 }
        return hueSaturation(rgb).hue
    }()

    /// Degrees between two hues the short way round the wheel, so that 359° and
    /// 2° come out three degrees apart rather than three hundred and fifty.
    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    // MARK: - Hex in, colour out

    static func color(_ hex: String) -> Color {
        guard let rgb = components(hex) else { return Color.white }
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    /// `#RRGGBB`, upper case, or nothing. Accepts input with or without the
    /// hash and in either case so that a hex pasted from anywhere works, but
    /// only ever stores the one form — otherwise `#59c7fa` and `#59C7FA` are
    /// two different rows in a settings list that should have one.
    static func normalised(_ hex: String) -> String? {
        let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard digits.count == 6,
              digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + digits
    }

    static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let normal = normalised(hex),
              let value = UInt32(normal.dropFirst(), radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    // MARK: - Arithmetic

    /// sRGB companding, undone. Screen values are not proportional to light,
    /// and averaging them as if they were is what produces a "contrast check"
    /// that passes colours nobody can read.
    private static func linear(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    /// Plain HSV hue and saturation. Enough for "is this red", and it does not
    /// drag a colour-space framework into a decision made on six hex digits.
    private static func hueSaturation(_ rgb: (r: Double, g: Double, b: Double))
        -> (hue: Double, saturation: Double) {
        let high = max(rgb.r, rgb.g, rgb.b)
        let low = min(rgb.r, rgb.g, rgb.b)
        let spread = high - low
        guard spread > 0, high > 0 else { return (0, 0) }

        let hue: Double
        if high == rgb.r {
            hue = 60 * (((rgb.g - rgb.b) / spread).truncatingRemainder(dividingBy: 6))
        } else if high == rgb.g {
            hue = 60 * (((rgb.b - rgb.r) / spread) + 2)
        } else {
            hue = 60 * (((rgb.r - rgb.g) / spread) + 4)
        }
        return ((hue < 0 ? hue + 360 : hue), spread / high)
    }

    /// What was on disk, if it is still something this panel can show.
    ///
    /// A stored colour is checked again on the way in rather than trusted. The
    /// rules here are the ones that can tighten — a floor that moves, a wedge
    /// that widens — and a preference written under the old rules would
    /// otherwise keep an illegible tint alive forever.
    private static func stored(_ raw: String?, fallback: String) -> String {
        guard let raw, let normal = normalised(raw), isAllowed(normal) else { return fallback }
        return normal
    }
}
