import AppKit
import CoreAudio
import CoreMediaIO
import CoreLocation

/// Who is listening and who is watching, right now.
///
/// macOS shows a dot in the menu bar and nothing else; this says which app it
/// is. The microphone can be traced to a process through CoreAudio. The camera
/// cannot — CoreMediaIO reports that a device is running somewhere without
/// saying where — so the camera line is honest about that rather than guessing.
final class PrivacyStore: ObservableObject {

    struct User: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
    }

    @Published private(set) var listeners: [User] = []
    @Published private(set) var cameraInUse = false
    @Published private(set) var microphoneInUse = false
    @Published private(set) var locationEnabled = false
    @Published private(set) var checkedAt: Date?

    private var timer: Timer?

    func startPolling() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        listeners = Self.listeningApps()
        microphoneInUse = !listeners.isEmpty || Self.anyInputRunning()
        cameraInUse = Self.cameraRunning()
        locationEnabled = CLLocationManager.locationServicesEnabled()
        checkedAt = Date()
    }

    func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Microphone, by process

    /// CoreAudio keeps an object per process that has touched audio, and each
    /// one says whether it is recording at this moment.
    private static func listeningApps() -> [User] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &objects) == noErr else {
            return []
        }

        var found: [User] = []
        for object in objects {
            guard running(object) else { continue }
            let pid = processID(object)
            guard pid > 0 else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? "PID \(pid)"
            // The app itself is never the answer worth showing.
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            found.append(User(id: "\(pid)", name: name, icon: app?.icon))
        }
        return found
    }

    private static func running(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private static func processID(_ object: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr else {
            return -1
        }
        return pid
    }

    /// Fallback for the light itself: is any input device recording at all,
    /// whoever is doing it.
    private static func anyInputRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr, device != 0 else {
            return false
        }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var valueSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &valueSize, &value) == noErr else {
            return false
        }
        return value != 0
    }

    // MARK: - Camera

    /// CoreMediaIO mirrors CoreAudio's shape: every camera is an object, and one
    /// of its properties is whether anything at all has it open.
    private static func cameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                            &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }

        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                        &address, 0, nil, size, &used, &devices) == noErr else {
            return false
        }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var value: UInt32 = 0
            var valueSize: UInt32 = 0
            var valueUsed: UInt32 = 0
            guard CMIOObjectGetPropertyDataSize(device, &runningAddress, 0, nil, &valueSize) == noErr,
                  CMIOObjectGetPropertyData(device, &runningAddress, 0, nil,
                                            valueSize, &valueUsed, &value) == noErr else { continue }
            if value != 0 { return true }
        }
        return false
    }
}
