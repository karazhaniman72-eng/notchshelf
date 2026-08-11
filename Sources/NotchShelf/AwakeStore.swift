import IOKit.pwr_mgt
import Foundation

/// Keeps the Mac awake for as long as it is switched on.
///
/// A power assertion rather than shelling out to `caffeinate`: the assertion
/// dies with the app, so a crash can never leave a Mac that refuses to sleep
/// with nothing on screen explaining why.
final class AwakeStore: ObservableObject {

    @Published private(set) var isOn = false
    @Published private(set) var since: Date?

    private var assertion: IOPMAssertionID = 0

    func toggle() {
        isOn ? stop() : start()
    }

    func start() {
        guard !isOn else { return }
        var identifier: IOPMAssertionID = 0
        let reason = "NotchShelf: keep awake" as CFString
        // Idle sleep only. The lid still puts the machine to sleep, which is the
        // behaviour anyone shutting a laptop expects.
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason,
                                                 &identifier)
        guard result == kIOReturnSuccess else {
            Log.write("awake failed code=\(result)")
            return
        }
        assertion = identifier
        isOn = true
        since = Date()
        Log.write("awake on")
    }

    func stop() {
        guard isOn else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isOn = false
        since = nil
        Log.write("awake off")
    }

    /// How long it has been held, for the caption under the switch.
    var label: String {
        guard isOn, let since else { return "" }
        let seconds = Int(Date().timeIntervalSince(since))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "awake \(hours)h \(minutes)m" : "awake \(minutes)m"
    }

    deinit {
        if isOn { IOPMAssertionRelease(assertion) }
    }
}
