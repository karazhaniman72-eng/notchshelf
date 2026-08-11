import SwiftUI

struct MusicView: View {
    @ObservedObject var spotify: SpotifyStore

    var body: some View {
        Group {
            switch spotify.state {
            case .notRunning:
                MessageView(
                    icon: "music.note",
                    title: "Spotify is not running",
                    subtitle: "Open Spotify and the player shows up here",
                    action: ("Open Spotify", { open() })
                )
            case .notPermitted:
                MessageView(
                    icon: "lock",
                    title: "No permission to control Spotify",
                    subtitle: "System Settings → Privacy & Security → Automation"
                )
            case .playing(let track), .paused(let track):
                player(track)
            }
        }
        .animation(Theme.settle, value: spotify.state)
    }

    /// The cover, and the song. Nothing else.
    ///
    /// The right hand column has now held two different lists nobody wanted: the
    /// five tracks played before this one, then the speaker the sound was coming
    /// out of. Both were true and neither was worth a third of the tab — so the
    /// cover took the room instead, which is the one thing on this tab that is
    /// better bigger.
    private func player(_ track: SpotifyStore.Track) -> some View {
        HStack(alignment: .top, spacing: 22) {
            artwork

            VStack(alignment: .leading, spacing: 0) {
                // Two lines, because song titles are long and the space under
                // this one was empty anyway. "Nothing Can Come Between Us" came
                // out as "Nothing Can Come Between…" over sixty points of black.
                Text(track.name)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(track.artist)
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.tint)
                    .lineLimit(1)
                    .padding(.top, 3)

                if !track.album.isEmpty {
                    Text(track.album)
                        .font(Theme.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }

                // Everything above holds to the top of the cover, everything
                // below to its bottom edge — the column is as tall as the
                // artwork, so the controls line up with the corner of it
                // instead of stopping halfway down an empty tab.
                Spacer(minLength: 12)

                progress(track)

                HStack(spacing: 0) {
                    Text(Self.clock(spotify.position))
                    Spacer(minLength: 0)
                    Text(Self.clock(track.duration))
                }
                .font(Theme.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)

                HStack(spacing: 2) {
                    GlyphButton(symbol: "backward.fill", size: 16, diameter: 38) { spotify.previous() }
                        .labelled("Previous track")
                    GlyphButton(
                        symbol: spotify.state.isPlaying ? "pause.fill" : "play.fill",
                        size: 20,
                        diameter: 48
                    ) { spotify.playPause() }
                        .labelled(spotify.state.isPlaying ? "Pause" : "Play")
                    GlyphButton(symbol: "forward.fill", size: 16, diameter: 38) { spotify.next() }
                        .labelled("Next track")

                    VolumeControl(value: spotify.volume) { spotify.setVolume($0) }
                        .padding(.leading, 12)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Exactly as tall as the cover beside it. It was 214 against an
            // artwork of 238, so the transport stopped 24 points short of the
            // corner it was meant to line up with.
            .frame(height: 238)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .fill(Theme.surface)
            if let image = spotify.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .accessibilityHidden(true)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.inkDim)
            }
        }
        // As tall as the tab has room for. The cover is the only thing here
        // worth looking at rather than reading, and it used to be a stamp in the
        // corner of a mostly empty panel.
        .frame(width: 238, height: 238)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .animation(Theme.settle, value: spotify.artwork)
    }

    /// The track bar doubles as the scrubber: the one place showing where you
    /// are is the one place worth clicking to move.
    private func progress(_ track: SpotifyStore.Track) -> some View {
        let fraction = track.duration > 0 ? min(max(spotify.position / track.duration, 0), 1) : 0
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surface)
                    .frame(height: 6)
                Capsule()
                    .fill(Theme.tint)
                    .frame(width: proxy.size.width * fraction, height: 6)
                Circle()
                    .fill(Theme.tint)
                    .frame(width: 11, height: 11)
                    .offset(x: proxy.size.width * fraction - 5.5)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { drag in
                    guard proxy.size.width > 0 else { return }
                    spotify.seek(to: drag.location.x / proxy.size.width)
                }
            )
        }
        .frame(height: 14)
        .animation(.linear(duration: 0.25), value: fraction)
    }

    private func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Spotify's volume, not the system's. Dragging is the whole control: a 0…100
/// number needs no arrows and no read-out.
private struct VolumeControl: View {
    let value: Int
    let onChange: (Int) -> Void

    private var symbol: String {
        if value == 0 { return "speaker.slash.fill" }
        return value < 45 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 15)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surface)
                        .frame(height: 4)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: proxy.size.width * Double(value) / 100, height: 4)
                }
                // A four point tall target is a target nobody hits; the whole
                // row takes the drag.
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        guard proxy.size.width > 0 else { return }
                        onChange(Int((drag.location.x / proxy.size.width * 100).rounded()))
                    }
                )
            }
            .frame(width: 70, height: 16)
        }
    }
}
