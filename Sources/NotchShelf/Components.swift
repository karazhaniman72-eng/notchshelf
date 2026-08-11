import SwiftUI

/// The look of the one text field in the app. A modifier rather than a wrapper
/// view: `.focused` only binds when it sits directly on the `TextField`, so the
/// field has to stay where its form can reach it.
private struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.rowText)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(Theme.fillInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func inputField() -> some View { modifier(InputFieldStyle()) }
}

/// Borderless button that lights up under the cursor.
struct HoverButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.metaText)
                .foregroundStyle(hovering ? Theme.accent : Theme.textTertiary)
                // Bare text is only clickable on the letters themselves, with
                // misses in the gaps between them.
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }
}

extension View {
    /// Keeps a control's place in the row when it has nothing to do.
    ///
    /// Showing and hiding a button inside an `HStack` moves every other button
    /// in it. On a row that is pointed at rather than read — the tools in the
    /// top right corner, the actions on a list row — that means the thing under
    /// the cursor slides out from under the cursor. Reserved, it fades instead
    /// and nothing moves.
    func reserved(_ isAvailable: Bool) -> some View {
        opacity(isAvailable ? 1 : 0)
            // It lands rather than fades up: the place was always held, so the
            // only thing left to say is that something has just arrived in it.
            // Scale is drawn and not laid out, so the seat stays exactly as
            // wide as it was and the row still does not move.
            .landing(isAvailable ? 1 : 0.66)
            .allowsHitTesting(isAvailable)
            .animation(isAvailable ? Theme.drop : Theme.pop, value: isAvailable)
    }
}

/// A button that says what it does. Used where a glyph on its own would be a
/// guess — the two or three actions a tab is really for.
struct ActionButton: View {
    let symbol: String
    let title: String
    /// The one action the tab exists for wears the colour; anything beside it
    /// stays grey, or they compete.
    var isPrimary = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Theme.rowText)
            }
            .foregroundStyle(isPrimary ? Theme.tint : (hovering ? Theme.textPrimary : Theme.textSecondary))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(hovering ? Theme.fillHover : Theme.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }
}

/// A setting that is on or off, and looks it. A capsule that only changes shade
/// reads as a button somebody pressed by accident; the tick says which it is.
struct ToggleChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .accessibilityHidden(true)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(Theme.metaText)
            }
            .foregroundStyle(isOn ? Theme.textPrimary : (hovering ? Theme.textSecondary : Theme.textTertiary))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(hovering ? Theme.fillHover : Theme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }
}

/// Small round glyph button used for row actions and player controls.
struct GlyphButton: View {
    let symbol: String
    var size: CGFloat = 13
    var diameter: CGFloat = 30
    /// The ink to draw in, for the buttons that do not sit on the panel.
    ///
    /// Left nil, the glyph follows the skin, which is right everywhere except on
    /// top of a picture: a cross over somebody's screenshot is readable because
    /// of the dark scrim under it, and on a light panel the skin would turn that
    /// cross black and hide it in its own scrim. Those pass `Theme.onMedia`.
    var ink: Color?
    let action: () -> Void

    @State private var hovering = false

    private var glyph: Color {
        guard let ink else { return hovering ? Theme.accent : Theme.textSecondary }
        return hovering ? ink : ink.opacity(0.8)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(glyph)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? (ink?.opacity(0.16) ?? Theme.fillHover) : .clear))
                // Square target under a round button: the corners of the glyph
                // are a miss otherwise, and a miss is indistinguishable from a
                // dead button.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .landing(hovering ? 1.08 : 1)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }
}

/// Centred placeholder for empty and blocked states.
struct MessageView: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .accessibilityHidden(true)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.inkDim)
            Text(title)
                .font(Theme.rowText)
                .foregroundStyle(Theme.textSecondary)
            Text(subtitle)
                .font(Theme.captionText)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            if let action {
                HoverButton(title: action.title, action: action.run)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Row background that lifts under the cursor. Used by every list.
struct RowBackground: ViewModifier {
    let hovering: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.rowPaddingH)
            .padding(.vertical, Theme.rowPaddingV)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(hovering ? Theme.fillHover : .clear)
            )
            .animation(Theme.touch, value: hovering)
    }
}

extension View {
    func rowBackground(hovering: Bool) -> some View {
        modifier(RowBackground(hovering: hovering))
    }
}

/// Circular meter, shared by the timer and the system gauges. It draws a
/// fraction and nothing else — whatever sits in the middle is handed in.
struct RingGauge<Label: View>: View {
    let progress: Double
    var diameter: CGFloat = 92
    var lineWidth: CGFloat = 7
    var tint: Color = Theme.accent
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surface, lineWidth: lineWidth)
                .padding(lineWidth / 2)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
            label()
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Flat meter for a fraction that has to be read at a glance rather than
/// admired: batteries in a row, memory under a heading.
struct LinearMeter: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .animation(Theme.settle, value: fraction)
    }
}

extension View {
    /// The name of a control, said once and used twice.
    ///
    /// Everything in this panel is a glyph: ten tabs, four discs under them, a
    /// row of round buttons on most tabs, and not a word on any of them. To the
    /// eye a tooltip is enough. To VoiceOver `.help` is only a hint — the name
    /// is a separate property, and without it every one of those buttons is
    /// announced as "button". This sets both from the same string, so a control
    /// cannot end up with a tooltip and no name.
    func labelled(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}

/// Small capsule that reads as one option out of a short set.
struct Chip: View {
    let title: String
    let isSelected: Bool
    /// Narrower where several chips have to share a column with something else.
    var padding: CGFloat = 11
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.metaText)
                .foregroundStyle(isSelected ? Theme.accent : (hovering ? Theme.textSecondary : Theme.textTertiary))
                .padding(.horizontal, padding)
                .frame(height: 26)
                .background(Capsule().fill(isSelected ? Theme.fillActive : (hovering ? Theme.fillHover : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }
}

/// A list with a bar down its left edge saying how much of it there is.
///
/// A panel three rows tall gives no clue whether it is holding three things or
/// thirty: the fade at the bottom says "there is more", never how much more. The
/// bar is the scale — its length is the fraction on screen and its position is
/// where in the list that fraction sits.
struct GaugedScroll<Content: View>: View {
    var fade: CGFloat = 20
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @State private var offset: CGFloat = 0

    private static var space: String { "gauged" }

    var body: some View {
        GeometryReader { outer in
            HStack(spacing: 8) {
                track(viewport: outer.size.height)

                ScrollView(.vertical, showsIndicators: false) {
                    content()
                        .background(
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: ScrollFrameKey.self,
                                    value: inner.frame(in: .named(Self.space))
                                )
                            }
                        )
                }
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(ScrollFrameKey.self) { frame in
                    contentHeight = frame.height
                    offset = -frame.minY
                }
                .fadingBottom(fade)
            }
        }
    }

    @ViewBuilder
    private func track(viewport: CGFloat) -> some View {
        // Nothing to say when it all fits: a full-length bar beside a short list
        // is a scrollbar that lies.
        if contentHeight > viewport + 1, viewport > 0 {
            let fraction = min(max(viewport / contentHeight, 0), 1)
            let thumb = max(viewport * fraction, 16)
            let travel = viewport - thumb
            let position = travel * min(max(offset / max(contentHeight - viewport, 1), 0), 1)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Theme.ink.opacity(0.07))
                    .frame(width: 3)
                Capsule()
                    .fill(Theme.ink.opacity(0.28))
                    .frame(width: 3, height: thumb)
                    .offset(y: position)
            }
            .frame(width: 3, height: viewport)
        } else {
            Color.clear.frame(width: 3)
        }
    }
}

private struct ScrollFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    /// Softens the bottom of a list that is longer than the panel.
    ///
    /// A scroll view cut by the panel's edge leaves half a row sitting on the
    /// rounding, which reads as content the box was too small to hold. Faded,
    /// the same cut reads as "there is more below".
    func fadingBottom(_ fade: CGFloat = 26) -> some View {
        mask(
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
            }
        )
    }
}
