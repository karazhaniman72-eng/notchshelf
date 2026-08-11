import AppKit
import Combine

/// Recording the screen, and putting what comes out on the shelf.
///
/// The shelf already catches everything Shift-Cmd-5 writes to the screenshot
/// folder, video included — so the tab could be said to record already. It could
/// not: reaching for the system toolbar, choosing video, choosing a region and
/// then hunting the stop button in the menu bar is four decisions for a thing
/// the panel is sitting right there to do in one press.
///
/// The recording is made by `screencapture`, the same program the system toolbar
/// drives, and it is stopped the way that program expects to be stopped — an
/// interrupt, which makes it close the movie properly. Killing it outright
/// leaves an unplayable file.
///
/// Where the file goes is the other half of this. It does **not** go to the
/// screenshot folder: that folder is watched, and everything in it is fair game
/// for the shelf to push into the Trash once nine things have piled up. A
/// recording is minutes of somebody's time and must not be thrown away by a
/// counter. It lands inside the app's own folder, which means the shelf holds
/// the only visible copy of it — the card is where you go to find it, drag it
/// out of, or reveal it in the Finder.
final class RecordStore: ObservableObject {

    /// Nil when nothing is being recorded. Everything the view needs to know
    /// about a run in progress is in here, so there is no way to be half in one
    /// state and half in another.
    enum Stage: Equatable {
        case idle
        /// Our own process, recording the whole screen. We started it and we can
        /// stop it.
        case recording(since: Date)
        /// The system's own selector is on screen: the person is dragging out a
        /// region, and the stop button is the one in the menu bar. We are only
        /// waiting for the file.
        case delegated
    }

    @Published private(set) var stage: Stage = .idle
    /// Ticks once a second while recording, so the view can show the length.
    @Published private(set) var elapsed: TimeInterval = 0
    /// What went wrong, in a sentence, in the tab. The usual cause by far is
    /// permission, which is why the view offers the settings pane beside it.
    @Published private(set) var failure: String?

    /// Sound from the default input, mixed into the movie. Off unless asked
    /// for: a screen recording that quietly carries the room is not what
    /// anybody meant by "record the screen".
    @Published var capturesAudio: Bool {
        didSet { UserDefaults.standard.set(capturesAudio, forKey: Self.audioKey) }
    }
    /// The pointer, drawn into the picture. On by default — a recording of a
    /// screen being used with no pointer in it is a recording of things moving
    /// by themselves.
    @Published var showsCursor: Bool {
        didSet { UserDefaults.standard.set(showsCursor, forKey: Self.cursorKey) }
    }
    /// A ring around every click. Off by default; it belongs to recordings made
    /// to show somebody how something is done.
    @Published var showsClicks: Bool {
        didSet { UserDefaults.standard.set(showsClicks, forKey: Self.clicksKey) }
    }

    private static let audioKey = "record.audio"
    private static let cursorKey = "record.cursor"
    private static let clicksKey = "record.clicks"

    private unowned let shelf: ShelfStore
    private var process: Process?
    private var target: URL?
    private var ticker: Timer?
    /// When the process was launched, so a run that dies immediately can be told
    /// apart from one that was stopped. An instant death is what a refused
    /// permission looks like from out here — `screencapture` says nothing.
    private var startedAt: Date?

    init(shelf: ShelfStore) {
        self.shelf = shelf
        let defaults = UserDefaults.standard
        capturesAudio = defaults.bool(forKey: Self.audioKey)
        showsCursor = (defaults.object(forKey: Self.cursorKey) as? Bool) ?? true
        showsClicks = defaults.bool(forKey: Self.clicksKey)
    }

    var isBusy: Bool { stage != .idle }

    // MARK: - Starting

    /// The whole screen, straight away. No selector, no toolbar: the press is
    /// the decision.
    func startFullScreen() {
        guard stage == .idle else { return }
        launch(extraArguments: ["-v"], stage: .recording(since: Date()))
    }

    /// A part of the screen, chosen the way macOS chooses one. The system
    /// selector is the only way to drag out a region, and re-drawing it inside
    /// the panel would be a worse copy of a thing everybody already knows.
    ///
    /// The trade is that the stop button is the system's, up in the menu bar:
    /// while this runs the panel can only wait for the file.
    func startRegion() {
        guard stage == .idle else { return }
        launch(extraArguments: ["-i", "-J", "video"], stage: .delegated)
    }

    private func launch(extraArguments: [String], stage newStage: Stage) {
        guard let folder = Self.folder() else {
            failure = "Nowhere to save the recording."
            return
        }
        let url = folder.appendingPathComponent(Self.filename())

        var arguments = extraArguments
        // Silent: the shutter belongs to a photograph, and this is not one.
        arguments.append("-x")
        if showsCursor { arguments.append("-C") }
        if showsClicks { arguments.append("-k") }
        if capturesAudio { arguments.append("-g") }
        arguments.append(url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            // Off the process's own queue: everything below touches published
            // state and the shelf.
            DispatchQueue.main.async { self?.finish(status: finished.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            failure = "Could not start the recorder."
            Log.write("record failed to launch error=\(error.localizedDescription)")
            return
        }

        self.process = process
        self.target = url
        self.startedAt = Date()
        self.failure = nil
        self.elapsed = 0
        self.stage = newStage
        if case .recording = newStage { startTicking() }
        Log.write("record started args=\(arguments.joined(separator: " "))")
    }

    // MARK: - Stopping

    /// An interrupt, not a kill. `screencapture` catches it, finishes writing
    /// the movie's index and exits; a `terminate` in the same place leaves a
    /// file QuickTime refuses to open.
    func stop() {
        guard let process, process.isRunning else { return }
        process.interrupt()
        Log.write("record stop requested")
        // If it has not gone in two seconds it is not going to, and a stuck
        // recorder holding the screen is worse than a lost tail of video.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let running = self?.process, running.isRunning else { return }
            running.terminate()
            Log.write("record force terminated")
        }
    }

    private func finish(status: Int32) {
        stopTicking()
        let url = target
        let ranFor = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        process = nil
        target = nil
        startedAt = nil
        stage = .idle
        elapsed = 0

        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            // No file at all. Either the region selector was dismissed, which is
            // an ordinary thing to do and deserves no message, or macOS refused
            // the recording — and that refusal is silent, so the only tell is
            // how fast the program gave up.
            if ranFor < 1.5 && status != 0 {
                failure = "macOS has not allowed this app to record the screen."
                Log.write("record denied status=\(status) ran=\(String(format: "%.2f", ranFor))")
            } else {
                Log.write("record cancelled status=\(status) ran=\(String(format: "%.2f", ranFor))")
            }
            return
        }

        shelf.add([url])
        Log.write("record saved file=\(url.lastPathComponent) ran=\(String(format: "%.1f", ranFor))")
    }

    /// Sends the person to the one settings pane that can grant this. Nothing in
    /// the app can grant it, and hunting for it under Privacy & Security is four
    /// screens away from where the refusal was seen.
    func openPermissionSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func clearFailure() { failure = nil }

    // MARK: - The clock

    private func startTicking() {
        stopTicking()
        let ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, case .recording(let since) = self.stage else { return }
            self.elapsed = Date().timeIntervalSince(since)
        }
        // The panel's own run loop mode changes while menus are up; common mode
        // keeps the count going through them.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    var elapsedLabel: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Where recordings live

    /// The app's own folder, not the screenshot folder and not the Desktop.
    ///
    /// Two reasons, and the first is the one that matters: the shelf trashes
    /// what falls off the end of it, but only files from the folder it watches —
    /// so a recording kept anywhere else is safe from its own shelf. The second
    /// is that a recording made from the panel was asked of the panel, and
    /// scattering movies across the Desktop is what the panel exists to stop.
    private static func folder() -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return nil }
        let folder = base
            .appendingPathComponent("NotchShelf", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.write("record folder failed error=\(error.localizedDescription)")
            return nil
        }
        return folder
    }

    /// Named the way macOS names its own captures, so a file dragged out of the
    /// panel looks like every other one on the machine.
    private static func filename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recording \(formatter.string(from: Date())).mov"
    }
}
