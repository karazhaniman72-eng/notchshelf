import AppKit

/// Talks to the Spotify desktop app over AppleScript. No developer app, no
/// OAuth, no API keys: the desktop client is already signed in.
final class SpotifyStore: ObservableObject {
    enum State: Equatable {
        case notRunning
        case notPermitted
        case playing(Track)
        case paused(Track)

        var track: Track? {
            switch self {
            case .playing(let track), .paused(let track): return track
            default: return nil
            }
        }

        var isPlaying: Bool {
            if case .playing = self { return true }
            return false
        }
    }

    struct Track: Equatable {
        let name: String
        let artist: String
        let album: String
        let artworkURL: String
        /// Seconds.
        let position: Double
        let duration: Double

        var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(position / duration, 0), 1)
        }
    }

    @Published private(set) var state: State = .notRunning
    @Published private(set) var artwork: NSImage?
    /// Spotify's own volume, 0…100. Not the system volume: turning the panel's
    /// slider must not mute a video in another window.
    @Published private(set) var volume = 50
    /// Where the needle is right now. Spotify is asked every two seconds; in
    /// between, the clock runs on its own so the bar moves smoothly instead of
    /// jumping twice a second.
    @Published private(set) var position: Double = 0

    private let bundleIdentifier = "com.spotify.client"
    private let queue = DispatchQueue(label: "notchshelf.spotify")
    private var timer: Timer?
    private var needle: Timer?
    private var reported: Double = 0
    private var reportedAt = Date()
    private var artworkKey: String?
    /// A drag emits a value every few pixels, and every AppleScript round trip
    /// costs milliseconds — only the newest value is worth sending.
    private var pendingVolume: Int?
    private var volumeSentAt = Date.distantPast

    /// Polled only while the Music tab is open: no reason to talk to Spotify
    /// when nobody is looking.
    func startPolling() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let needle = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.advance()
        }
        RunLoop.main.add(needle, forMode: .common)
        self.needle = needle
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        needle?.invalidate()
        needle = nil
    }

    /// Between two answers from Spotify the needle is arithmetic: where it was,
    /// plus how long ago that was.
    private func advance() {
        guard state.isPlaying, let track = state.track else { return }
        position = min(reported + Date().timeIntervalSince(reportedAt), track.duration)
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func refresh() {
        guard isRunning else {
            apply(.notRunning)
            return
        }
        let script = """
        tell application id "\(bundleIdentifier)"
            set theState to player state as text
            set theName to name of current track
            set theArtist to artist of current track
            set theArt to artwork url of current track
            set thePosition to (player position) as integer
            set theDuration to (duration of current track) as integer
            set theVolume to (sound volume) as integer
            set theAlbum to album of current track
            return theState & "\t" & theName & "\t" & theArtist & "\t" & theArt & "\t" & thePosition & "\t" & theDuration & "\t" & theVolume & "\t" & theAlbum
        end tell
        """
        run(script) { [weak self] output, failed in
            guard let self else { return }
            if failed {
                self.apply(.notPermitted)
                return
            }
            guard let output else {
                self.apply(.notRunning)
                return
            }
            let parts = output.components(separatedBy: "\t")
            guard parts.count >= 6 else {
                self.apply(.notRunning)
                return
            }
            let track = Track(
                name: parts[1],
                artist: parts[2],
                // Appended after the volume rather than beside the artist, so an
                // older Spotify answering with six fields still parses.
                album: parts.count >= 8 ? parts[7] : "",
                artworkURL: parts[3],
                position: Self.number(parts[4]),
                // Spotify reports track length in milliseconds.
                duration: Self.number(parts[5]) / 1000
            )
            self.apply(parts[0] == "playing" ? .playing(track) : .paused(track))
            // A seek in Spotify's own window has to win over the needle here,
            // so every answer resets it rather than only the first.
            self.reported = track.position
            self.reportedAt = Date()
            self.position = track.position
            // Not while a drag is in flight: the reading is older than the
            // finger and the slider would jump backwards under it.
            if parts.count >= 7, self.pendingVolume == nil {
                self.volume = Int(Self.number(parts[6]))
            }
            self.loadArtwork(track.artworkURL)
        }
    }

    func next() { command("next track") }
    func previous() { command("previous track") }
    func playPause() { command("playpause") }

    /// Drop the needle somewhere else in the track. Moves locally first, for
    /// the same reason the volume slider does.
    func seek(to fraction: Double) {
        guard let track = state.track, track.duration > 0, isRunning else { return }
        let target = min(max(fraction, 0), 1) * track.duration
        reported = target
        reportedAt = Date()
        position = target
        run("tell application id \"\(bundleIdentifier)\" to set player position to \(Int(target))") { _, _ in }
    }

    /// The slider moves at once and the app catches up: a control that waits
    /// for a round trip before it moves feels broken.
    func setVolume(_ value: Int) {
        let clamped = min(max(value, 0), 100)
        guard clamped != volume else { return }
        volume = clamped
        pendingVolume = clamped

        let elapsed = Date().timeIntervalSince(volumeSentAt)
        guard elapsed >= 0.12 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 - elapsed) { [weak self] in
                self?.flushVolume()
            }
            return
        }
        flushVolume()
    }

    private func flushVolume() {
        guard let value = pendingVolume else { return }
        pendingVolume = nil
        volumeSentAt = Date()
        guard isRunning else { return }
        run("tell application id \"\(bundleIdentifier)\" to set sound volume to \(value)") { _, _ in }
    }

    private func command(_ verb: String) {
        guard isRunning else { return }
        run("tell application id \"\(bundleIdentifier)\" to \(verb)") { [weak self] _, _ in
            // Spotify needs a moment to settle on the new track.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.refresh() }
        }
    }

    private func run(_ source: String, completion: @escaping (String?, Bool) -> Void) {
        queue.async {
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let failed = (error?["NSAppleScriptErrorNumber"] as? Int).map { $0 == -1743 } ?? false
            if let error, !failed {
                Log.write("spotify script error=\(error["NSAppleScriptErrorBriefMessage"] ?? error)")
            }
            let output = descriptor?.stringValue
            DispatchQueue.main.async { completion(output, failed) }
        }
    }

    /// AppleScript formats numbers for the user's locale, so on a Russian Mac
    /// `player position` comes back as "83,4" — and `Double("83,4")` is nil.
    /// That is why the bar sat at 0:00 while the track played: the position
    /// parsed as nothing, and the duration, being a whole number of
    /// milliseconds, parsed fine.
    private static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func apply(_ newState: State) {
        DispatchQueue.main.async {
            guard self.state != newState else { return }
            self.state = newState
            if newState.track == nil {
                self.artwork = nil
                self.artworkKey = nil
            }
        }
    }

    private func loadArtwork(_ address: String) {
        guard artworkKey != address, let url = URL(string: address) else { return }
        artworkKey = address
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artwork = image }
        }.resume()
    }
}
