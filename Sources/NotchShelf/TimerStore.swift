import AppKit
import UserNotifications

/// The focus timer. It belongs to `AppModel` and keeps its own clock, because
/// the panel is shut for all but a few seconds of a block — a timer that stops
/// when nobody is looking at it is not a timer.
final class TimerStore: ObservableObject {

    enum Phase: String {
        case idle, focus, rest

        var title: String {
            switch self {
            case .idle: return "Ready"
            case .focus: return "Focus"
            case .rest: return "Break"
            }
        }
    }

    /// Minutes. Half an hour, an hour, an afternoon.
    static let presets = [30, 60, 180]
    /// Every focus block is followed by the same short break.
    private let restLength: TimeInterval = 5 * 60

    static func label(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60)"
    }

    /// The same length with the spaces squeezed out, for a chip that has to
    /// share a 194pt column with a ring and three buttons.
    static func shortLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h\(minutes % 60)"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var preset = 25
    @Published private(set) var sessionsToday = 0
    @Published private(set) var focusToday: TimeInterval = 0

    /// The length of the phase on screen, so the ring knows how much of it has
    /// gone.
    private var phaseLength: TimeInterval = 25 * 60
    /// A tick is a repaint, not the clock. The clock is this date: `Timer` does
    /// not fire while the machine sleeps, and counting ticks loses the whole nap.
    private var deadline: Date?
    /// One ticker for the app, alive only while something is counting.
    private var ticker: Timer?
    private var askedForNotifications = false

    private let defaults = UserDefaults.standard

    private enum Key {
        static let preset = "timer.preset"
        static let sessions = "timer.sessionsToday"
        static let focus = "timer.focusToday"
        static let day = "timer.day"
    }

    init() {
        // Any length that was typed in, not only the three on the chips: a
        // custom block used to be forgotten at every launch and quietly
        // replaced by half an hour.
        let saved = defaults.integer(forKey: Key.preset)
        preset = (1...600).contains(saved) ? saved : Self.presets[0]
        phaseLength = TimeInterval(preset * 60)
        remaining = phaseLength
        loadCounters()
    }

    // MARK: - Reading

    var progress: Double {
        guard phaseLength > 0 else { return 0 }
        return min(max(1 - remaining / phaseLength, 0), 1)
    }

    var clock: String { Self.clock(remaining) }

    static func clock(_ seconds: TimeInterval) -> String {
        // Rounded up: a fresh 30 minute block must read 30:00, not 29:59.
        let total = Int(seconds.rounded(.up))
        guard total >= 3600 else { return String(format: "%02d:%02d", total / 60, total % 60) }
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    var summary: String {
        guard sessionsToday > 0 else { return "No sessions yet today" }
        let word = sessionsToday == 1 ? "session" : "sessions"
        return "\(sessionsToday) \(word) today · \(focusLabel)"
    }

    private var focusLabel: String {
        let minutes = Int(focusToday) / 60
        guard minutes >= 60 else { return "\(minutes) m" }
        return "\(minutes / 60) h \(minutes % 60) m"
    }

    // MARK: - Controls

    /// Called when the tab is opened. The timer itself needs nothing to wake up;
    /// this only catches a day that turned over while it was idle.
    func refresh() { rollOverIfNewDay() }

    /// Any length, not only the three on the chips: the presets are shortcuts,
    /// not the whole vocabulary. Ten hours is the ceiling because past that it
    /// is a calendar entry, not a timer.
    func select(_ minutes: Int) {
        let minutes = min(max(minutes, 1), 600)
        preset = minutes
        defaults.set(minutes, forKey: Key.preset)
        // Picking a length is picking the next block, so it starts over. Silent
        // truncation of a run in progress would be worse than an obvious stop.
        enter(.idle)
    }

    func toggle() { isRunning ? pause() : start() }

    /// Back to the top of the phase on screen, keeping it running if it was.
    func reset() {
        guard phase != .idle else { return }
        remaining = phaseLength
        deadline = isRunning ? Date().addingTimeInterval(phaseLength) : nil
        Log.write("timer reset phase=\(phase.rawValue)")
    }

    // MARK: - Running

    private func start() {
        rollOverIfNewDay()
        requestNotificationsOnce()
        if phase == .idle {
            enter(.focus)
            return
        }
        deadline = Date().addingTimeInterval(remaining)
        isRunning = true
        startTicking()
        Log.write("timer resume phase=\(phase.rawValue) remaining=\(Int(remaining))")
    }

    private func pause() {
        remaining = deadline.map { max(0, $0.timeIntervalSinceNow) } ?? remaining
        deadline = nil
        isRunning = false
        stopTicking()
        Log.write("timer pause remaining=\(Int(remaining))")
    }

    private func enter(_ next: Phase) {
        phase = next
        switch next {
        case .idle:
            phaseLength = TimeInterval(preset * 60)
            remaining = phaseLength
            deadline = nil
            isRunning = false
            stopTicking()
        case .focus, .rest:
            phaseLength = next == .focus ? TimeInterval(preset * 60) : restLength
            remaining = phaseLength
            deadline = Date().addingTimeInterval(phaseLength)
            isRunning = true
            startTicking()
        }
        Log.write("timer phase=\(next.rawValue) length=\(Int(phaseLength))")
    }

    private func tick() {
        rollOverIfNewDay()
        guard isRunning, let deadline else { return }
        let left = deadline.timeIntervalSinceNow
        guard left <= 0 else {
            remaining = left
            return
        }
        remaining = 0
        finish()
    }

    private func finish() {
        // The sound is ours rather than the notification's, so a block still
        // announces itself when notifications are refused.
        NSSound(named: "Glass")?.play()
        if phase == .focus {
            sessionsToday += 1
            focusToday += phaseLength
            saveCounters()
            notify(title: "Focus block done", body: "Take five.")
            enter(.rest)
        } else {
            notify(title: "Break over", body: "\(Self.label(preset)) of focus waiting.")
            enter(.idle)
        }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common mode: the default one stalls while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Today's tally

    private func loadCounters() {
        guard let day = defaults.object(forKey: Key.day) as? Date,
              Calendar.current.isDateInToday(day) else {
            resetCounters()
            return
        }
        sessionsToday = defaults.integer(forKey: Key.sessions)
        focusToday = defaults.double(forKey: Key.focus)
    }

    /// Local midnight, not twenty-four hours after launch: "today" has to mean
    /// the day the user means.
    private func rollOverIfNewDay() {
        let day = defaults.object(forKey: Key.day) as? Date
        guard day == nil || !Calendar.current.isDateInToday(day!) else { return }
        resetCounters()
    }

    private func resetCounters() {
        sessionsToday = 0
        focusToday = 0
        saveCounters()
    }

    private func saveCounters() {
        defaults.set(sessionsToday, forKey: Key.sessions)
        defaults.set(focusToday, forKey: Key.focus)
        defaults.set(Date(), forKey: Key.day)
    }

    // MARK: - Notifications

    /// Asked for on the first start, never at launch: a timer nobody starts
    /// should not raise a prompt.
    private func requestNotificationsOnce() {
        guard !askedForNotifications, Bundle.main.bundleIdentifier != nil else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Log.write("notifications granted=\(granted) error=\(error?.localizedDescription ?? "none")")
        }
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.write("notification error=\(error.localizedDescription)") }
        }
    }
}
