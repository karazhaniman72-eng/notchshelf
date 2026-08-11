import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps

/// What is charged and what is full. Battery for the Mac and for whatever is
/// paired with it, then memory — with the processes actually holding it, since
/// a percentage on its own never answers the question it raises.
final class SystemStore: ObservableObject {

    /// One battery: the Mac's own, or a paired device's.
    struct DeviceCharge: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let percent: Int
        let caption: String
        var isCritical = false
        /// Paired but not connected: the figure is the last one macOS saw.
        var isOffline = false
    }

    struct Reading {
        var value = "—"
        var caption = ""
        var fraction: Double = 0
        var isCritical = false
    }

    struct ProcessUse: Identifiable {
        let id: String
        var name: String { id }
        let bytes: Double
    }

    /// One thing the machine knows about itself, with the word for it.
    ///
    /// These used to be a single string joined with middle dots — "Uptime 18 d
    /// 9 h · 283.24 GB free on disk · Health 100% · 25 cycles · 30 °C" — set in
    /// the smallest grey type in the app along the bottom edge. Five readings
    /// written as one sentence are five readings nobody looks up.
    struct Fact: Identifiable {
        var id: String { name }
        let name: String
        let value: String
    }

    @Published private(set) var devices: [DeviceCharge] = []
    @Published private(set) var memory = Reading()
    @Published private(set) var processes: [ProcessUse] = []
    @Published private(set) var facts: [Fact] = []

    private var timer: Timer?
    private var bluetoothCheckedAt: Date?
    private var pairedDevices: [DeviceCharge] = []
    private let queue = DispatchQueue(label: "notchshelf.system", qos: .utility)

    /// Polled only while the System tab is open. The syscalls are cheap, but not
    /// for a panel nobody is looking at.
    func startPolling() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
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
        memory = readMemory()
        facts = ([Fact(name: "Uptime", value: readUptime()),
                  Fact(name: "Disk free", value: readDisk())] + readBatteryHealth())
            .filter { !$0.value.isEmpty }
        devices = [readMacBattery()].compactMap { $0 } + pairedDevices
        readProcesses()
        readBluetooth()
    }

    // MARK: - Batteries

    private func readMacBattery() -> DeviceCharge? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let description = sources.lazy.compactMap({
                  IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
              }).first,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let capacity = description[kIOPSMaxCapacityKey] as? Int, capacity > 0
        else { return nil }

        let percent = Int((Double(current) / Double(capacity) * 100).rounded())
        let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        // Plugged in, a time estimate is either meaningless or a time to full,
        // which says nothing about how long the machine will last.
        let caption: String
        if charging {
            caption = "Charging"
        } else if onAC {
            caption = "Plugged in"
        } else {
            let minutes = description[kIOPSTimeToEmptyKey] as? Int ?? -1
            caption = minutes > 0 ? "\(Self.spell(minutes: minutes)) left" : "Calculating…"
        }

        return DeviceCharge(id: "mac",
                            name: "This Mac",
                            symbol: "laptopcomputer",
                            percent: percent,
                            caption: caption,
                            isCritical: !onAC && percent < 10)
    }

    /// Paired devices come from `system_profiler`: IORegistry only carries a
    /// battery while a device is actually connected, and headphones sitting in
    /// their case are exactly the ones worth knowing about. It costs a second,
    /// so it runs off the main thread and no more than twice a minute.
    private func readBluetooth() {
        if let checked = bluetoothCheckedAt, Date().timeIntervalSince(checked) < 30 { return }
        bluetoothCheckedAt = Date()
        queue.async { [weak self] in
            guard let self else { return }
            let found = self.scanBluetooth()
            DispatchQueue.main.async {
                self.pairedDevices = found
                self.devices = [self.readMacBattery()].compactMap { $0 } + found
            }
        }
    }

    private func scanBluetooth() -> [DeviceCharge] {
        guard let output = Self.shell("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var found: [DeviceCharge] = []
        for section in sections {
            for (key, value) in section where key.hasPrefix("device_") {
                guard let entries = value as? [[String: Any]] else { continue }
                let offline = key.contains("not_connected")
                for entry in entries {
                    for (name, raw) in entry {
                        guard let properties = raw as? [String: Any],
                              let device = Self.device(named: name, properties: properties, offline: offline)
                        else { continue }
                        found.append(device)
                    }
                }
            }
        }
        // Connected first, then the fullest: a device in use outranks one in a
        // drawer, whatever their charges are.
        return Array(found.sorted { ($0.isOffline ? 1 : 0, -$0.percent) < ($1.isOffline ? 1 : 0, -$1.percent) }.prefix(3))
    }

    private static func device(named name: String, properties: [String: Any], offline: Bool) -> DeviceCharge? {
        func percent(_ key: String) -> Int? {
            guard let text = properties[key] as? String else { return nil }
            return Int(text.replacingOccurrences(of: "%", with: ""))
        }

        let left = percent("device_batteryLevelLeft")
        let right = percent("device_batteryLevelRight")
        let single = percent("device_batteryLevelMain") ?? percent("device_batteryLevel")
        // Earbuds run out one at a time; the useful number is the one that dies
        // first.
        let charge = [left, right].compactMap { $0 }.min() ?? single
        guard let charge else { return nil }

        var notes: [String] = []
        if let box = percent("device_batteryLevelCase") { notes.append("case \(box)%") }
        if offline { notes.append("offline") }

        let kind = (properties["device_minorType"] as? String ?? "").lowercased()
        return DeviceCharge(id: (properties["device_address"] as? String) ?? name,
                            name: name,
                            symbol: symbol(for: kind),
                            percent: charge,
                            caption: notes.joined(separator: " · "),
                            isCritical: !offline && charge < 15,
                            isOffline: offline)
    }

    private static func symbol(for kind: String) -> String {
        if kind.contains("headphone") || kind.contains("headset") { return "airpods.pro" }
        if kind.contains("speaker") { return "hifispeaker.fill" }
        if kind.contains("trackpad") { return "trackpad" }
        if kind.contains("keyboard") { return "keyboard" }
        if kind.contains("mouse") { return "magicmouse" }
        if kind.contains("phone") { return "iphone" }
        return "dot.radiowaves.left.and.right"
    }

    // MARK: - Memory

    private func readMemory() -> Reading {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard let stats = vmStatistics(), total > 0 else {
            return Reading(value: "—", caption: "Unavailable", fraction: 0)
        }

        // Activity Monitor's "Memory Used": app memory (anonymous pages that are
        // not purgeable) plus wired plus compressed. Free pages are deliberately
        // not part of it — macOS keeps almost none.
        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page

        let fraction = min(max(used / total, 0), 1)
        let gigabyte = 1024.0 * 1024 * 1024
        return Reading(
            value: "\(Int((fraction * 100).rounded()))%",
            caption: String(format: "%.1f of %.0f GB", used / gigabyte, total / gigabyte),
            fraction: fraction,
            isCritical: fraction > 0.9
        )
    }

    private func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            Log.write("host_statistics64 failed code=\(result)")
            return nil
        }
        return stats
    }

    /// Who is actually holding the memory. `task_info` on someone else's process
    /// needs root, so this is resident size out of `ps`, summed per app: a
    /// browser is thirty processes and naming one of them explains nothing.
    private func readProcesses() {
        queue.async { [weak self] in
            guard let self, let output = Self.shell("/bin/ps", ["-Ao", "rss=,comm="]) else { return }
            var totals: [String: Double] = [:]
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let space = trimmed.firstIndex(of: " "),
                      let kilobytes = Double(trimmed[trimmed.startIndex..<space]) else { continue }
                let path = String(trimmed[trimmed.index(after: space)...])
                totals[Self.appName(from: path), default: 0] += kilobytes * 1024
            }

            let top = totals.sorted { $0.value > $1.value }.prefix(4)
                .map { ProcessUse(id: $0.key, bytes: $0.value) }
            DispatchQueue.main.async { self.processes = top }
        }
    }

    /// The bundle a process belongs to, so every helper lands under its app.
    private static func appName(from path: String) -> String {
        for part in path.split(separator: "/") where part.hasSuffix(".app") {
            return String(part.dropLast(4))
        }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    /// What share of the whole machine one application is holding.
    func share(of process: ProcessUse) -> Double {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(max(process.bytes / total, 0), 1)
    }

    /// Cycles and how much of the original capacity is left, out of the
    /// `AppleSmartBattery` registry entry. The battery's own thermometer comes
    /// with it — the CPU's would need SMC access and an entitlement, this one
    /// needs neither.
    private func readBatteryHealth() -> [Fact] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [] }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return [] }

        var parts: [Fact] = []
        if let nominal = properties["NominalChargeCapacity"] as? Int,
           let design = properties["DesignCapacity"] as? Int, design > 0 {
            parts.append(Fact(name: "Battery health",
                              value: "\(Int((Double(nominal) / Double(design) * 100).rounded()))%"))
        }
        if let cycles = properties["CycleCount"] as? Int {
            parts.append(Fact(name: "Cycles", value: "\(cycles)"))
        }
        // Hundredths of a degree.
        if let raw = properties["Temperature"] as? Int, raw > 0 {
            parts.append(Fact(name: "Battery temp", value: String(format: "%.0f °C", Double(raw) / 100)))
        }
        return parts
    }

    // MARK: - Disk and uptime

    private func readDisk() -> String {
        let url = URL(fileURLWithPath: "/")
        // Important usage, not plain available capacity: it is the number Finder
        // shows, and the two disagree by tens of gigabytes.
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return "" }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB]
        // en_KZ prints 275,12 GB. The panel is written in English throughout,
        // and a comma there reads as a thousands separator.
        formatter.formattingContext = .standalone
        return formatter.string(fromByteCount: free).replacingOccurrences(of: ",", with: ".")
    }

    /// From the boot timestamp rather than a counter: `systemUptime` drifts
    /// across sleep, and this is the figure `uptime(1)` prints.
    private func readUptime() -> String {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return "" }

        let seconds = Int(Date().timeIntervalSince1970) - boot.tv_sec
        guard seconds > 0 else { return "" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \((seconds % 3600) / 60) m" }
        return "\(seconds / 60) m"
    }

    // MARK: - Plumbing

    private static func spell(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) m" }
        return "\(minutes / 60) h \(minutes % 60) m"
    }

    static func gigabytes(_ bytes: Double) -> String {
        let gigabyte = 1024.0 * 1024 * 1024
        guard bytes >= gigabyte else { return String(format: "%.0f MB", bytes / (1024 * 1024)) }
        return String(format: "%.1f GB", bytes / gigabyte)
    }

    private static func shell(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Log.write("shell failed path=\(path) error=\(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
