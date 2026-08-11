import SwiftUI

/// The panel, about itself.
///
/// Three pages behind the gear, and they are the three decisions that genuinely
/// belong to the owner of the Mac rather than to whoever drew this: which
/// subjects are worth a place in the row, what colour the live readings are
/// written in, and how much of the desktop shows through the black.
///
/// Nothing here is applied, saved or confirmed. Every switch does its work the
/// moment it is pressed and the panel behind it changes while it is being
/// looked at, which is the only honest way to choose a colour — a swatch on a
/// settings page is not the thing, the panel is the thing.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var palette: Palette
    @ObservedObject var state: PanelState

    var body: some View {
        Group {
            switch state.settingsMode {
            case .tabs: tabs
            case .colour: colour
            case .backdrop: backdrop
            case .folders: folders
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: - Which tabs are in the row

    /// Two columns of five, in the order the strip has them, so the page is a
    /// picture of the row rather than a list that has to be matched up with it.
    private var tabs: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(settings.tabs.count) of \(PanelTab.allCases.count) in the row")
                .font(Theme.captionText)
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 2)

            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(PanelTab.allCases) { tab in
                    TabSwitch(tab: tab,
                              isOn: settings.isOn(tab),
                              // The last one standing cannot be switched off,
                              // and says so by refusing rather than by
                              // disappearing out of the grid.
                              isLocked: settings.isOn(tab) && settings.tabs.count == 1) {
                        withAnimation(Theme.swap) {
                            settings.toggle(tab)
                            state.tab = settings.resolve(state.tab)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Colour

    /// The two colours, each as its own row of dots, and the name of what is
    /// picked written beside the row in the colour itself — the only honest
    /// preview of a colour is the colour doing its job.
    private var colour: some View {
        VStack(alignment: .leading, spacing: 14) {
            swatchRow(title: "Live readings",
                      subtitle: palette.tintChoice?.name ?? palette.tintHex,
                      colour: Theme.tint,
                      choices: Palette.tintChoices,
                      selected: palette.tintHex) { palette.setTint($0) }

            swatchRow(title: "Second",
                      subtitle: palette.secondChoice?.name ?? palette.secondHex,
                      colour: Theme.second,
                      choices: Palette.secondChoices,
                      selected: palette.secondHex) { palette.setSecond($0) }

            HStack(spacing: 10) {
                // Red is missing from both rows on purpose, and the reason is
                // worth a line: it is the one colour in this panel that already
                // means something — a dead line, a battery about to go. An
                // accent in the same red would make every tab look broken.
                Text("Red is kept for what is wrong")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)

                Spacer(minLength: 0)

                if palette.tintHex != Palette.defaultTintHex
                    || palette.secondHex != Palette.defaultSecondHex {
                    HoverButton(title: "Back to the blue") { palette.reset() }
                        .labelled("Put both colours back the way they came")
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatchRow(title: String,
                           subtitle: String,
                           colour: Color,
                           choices: [Palette.Choice],
                           selected: String,
                           pick: @escaping (String) -> Palette.Refusal?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.textSecondary)
                Text(subtitle)
                    .font(Theme.metaText)
                    .foregroundStyle(colour)
            }

            HStack(spacing: 8) {
                ForEach(choices) { choice in
                    Swatch(choice: choice, isSelected: choice.hex == selected) {
                        withAnimation(Theme.swap) { _ = pick(choice.hex) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Background

    /// Three cards rather than a slider, and each one says what it costs: the
    /// more of the desktop that comes through, the more the notch — a real hole
    /// in the glass, always black — shows as a seam in the middle of it.
    private var backdrop: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Backdrop.allCases) { style in
                BackdropCard(style: style, isSelected: settings.backdrop == style) {
                    withAnimation(Theme.swap) { settings.backdrop = style }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Folders

    /// The two tabs that read somebody's own files, and where they read them
    /// from.
    ///
    /// This page exists because those two paths used to be constants in the
    /// source — one person's knowledge base, which is exactly right on one Mac
    /// and silently empty on every other. Nothing here has a default: a folder
    /// full of somebody's plans is not something an app should guess at.
    private var folders: some View {
        VStack(alignment: .leading, spacing: 7) {
            FolderRow(which: .plans,
                      url: settings.plansFolder,
                      choose: { settings.chooseFolder(.plans) },
                      forget: { withAnimation(Theme.swap) { settings.forget(.plans) } })
            FolderRow(which: .textbooks,
                      url: settings.textbooksFolder,
                      choose: { settings.chooseFolder(.textbooks) },
                      forget: { withAnimation(Theme.swap) { settings.forget(.textbooks) } })

            Text("Nothing outside these two folders is ever read")
                .font(Theme.captionText)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One folder: what it feeds, where it points, and the two things that can be
/// done to it.
private struct FolderRow: View {
    let which: SettingsStore.Folder
    let url: URL?
    let choose: () -> Void
    let forget: () -> Void

    @State private var hovering = false

    /// The path with the home folder written the way people write it. A full
    /// `/Users/somebody/...` is both longer and less recognisable than `~`.
    private var shown: String {
        guard let url else { return "Not set" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: url == nil ? "folder.badge.questionmark" : "folder.fill")
                .accessibilityHidden(true)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(url == nil ? Theme.inkDim : Theme.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(which.title)
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.textPrimary)
                Text(url == nil ? which.detail : shown)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            HoverButton(title: url == nil ? "Choose…" : "Change…", action: choose)
                .labelled("Pick the folder \(which.title) reads from")
            HoverButton(title: "Clear", action: forget)
                .labelled("Stop reading a folder for \(which.title)")
                .reserved(url != nil)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(hovering ? Theme.fillHover : Theme.surface)
        )
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }
}

// MARK: - Pieces

/// One tab, on or off. The icon is the same glyph the strip uses, so the switch
/// and the thing it switches are recognisably the same object.
private struct TabSwitch: View {
    let tab: PanelTab
    let isOn: Bool
    let isLocked: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .accessibilityHidden(true)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.tint : Theme.inkDim)
                    .frame(width: 18)

                Text(tab.title)
                    .font(Theme.metaText)
                    .foregroundStyle(isOn ? Theme.textPrimary : Theme.textTertiary)

                Spacer(minLength: 0)

                Image(systemName: isLocked ? "lock" : (isOn ? "checkmark" : ""))
                    .accessibilityHidden(true)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isLocked ? Theme.inkDim : Theme.tint)
                    .frame(width: 12)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(hovering ? Theme.fillHover : Theme.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
        .labelled(isLocked ? "\(tab.title): the last tab cannot be hidden"
                           : (isOn ? "Hide \(tab.title)" : "Show \(tab.title)"))
    }
}

/// A colour, as a dot of itself. Picked is a ring around it rather than a tick
/// on it: a tick lands in the middle of the one thing being looked at.
private struct Swatch: View {
    let choice: Palette.Choice
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(choice.shown)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .strokeBorder(Theme.ink.opacity(hovering && !isSelected ? 0.45 : 0), lineWidth: 1)
                )
                .padding(4)
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? choice.shown : .clear, lineWidth: 1.6)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
        .labelled(choice.name)
    }
}

/// One background to choose from, with the difference between them written out.
private struct BackdropCard: View {
    let style: Backdrop
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // A sample of the thing itself, not a glyph standing for it.
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(sampleFill)
                    .frame(width: 40, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(Theme.rowText)
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    Text(style.detail)
                        .font(Theme.captionText)
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.tint)
                    .reserved(isSelected)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(hovering ? Theme.fillHover : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .strokeBorder(isSelected ? Theme.tint : .clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
        .labelled(style.title)
    }
}

/// The little sample is the panel that row would give you, in miniature: black
/// where the panel is black, thinning as the desktop starts coming through, and
/// white where the panel is white.
///
/// It used to be mixed from `Theme.ink`, which is the colour the panel *writes*
/// in — so the whole ladder turned itself inside out the moment the white panel
/// was chosen and `ink` went black. The row saying "White · light panel, dark
/// writing" showed a black chip, and the one saying "Solid · black, like the
/// bezel" showed a nearly white one: the settings page argued with itself about
/// the setting it was on. These are fixed colours because the panel they stand
/// for is a fixed colour.
private extension BackdropCard {
    var sampleFill: Color {
        switch style {
        case .solid: return .black
        case .veil: return .black.opacity(PanelBackdropStrength.slight.dim)
        case .glass: return .black.opacity(PanelBackdropStrength.medium.dim)
        case .clear: return .black.opacity(PanelBackdropStrength.strong.dim)
        case .white: return Color(white: 0.96)
        }
    }
}
