import Foundation

/// Whose fault it is when the internet is slow.
///
/// "The internet is slow" is three different faults wearing the same coat: the Wi-Fi
/// between the Mac and the router, the line past the router, or name lookup
/// that stalls before a single byte is asked for. Each is timed separately, so
/// the tab can name one instead of shrugging.
final class NetworkStore: ObservableObject {

    struct Probe {
        var milliseconds: Double?
        var loss = 0
        var attempted = false

        var isUp: Bool { milliseconds != nil }
        var label: String {
            guard let milliseconds else { return attempted ? "down" : "—" }
            return milliseconds < 10
                ? String(format: "%.1f", milliseconds)
                : String(Int(milliseconds.rounded()))
        }
    }

    @Published private(set) var ssid = ""
    /// "1 (2GHz, 20MHz)" straight from the system, split for display.
    @Published private(set) var channel = ""
    @Published private(set) var phy = ""
    @Published private(set) var rate = 0
    @Published private(set) var signal: Int?
    @Published private(set) var interface = ""
    @Published private(set) var address = ""
    @Published private(set) var gateway = ""
    @Published private(set) var router = Probe()
    @Published private(set) var internet = Probe()
    @Published private(set) var dns = Probe()
    @Published private(set) var isProbing = false
    @Published private(set) var checkedAt: Date?
    /// Whether the Wi-Fi details have come back yet. They take two and a half
    /// seconds, and until they do there is no way to tell a cable from a radio —
    /// so the tab says nothing rather than saying "Wired" about Wi-Fi.
    @Published private(set) var wifiChecked = false

    /// One check of the line out, kept so the tab can say what the last hour
    /// looked like rather than only what this second looks like.
    struct Sample: Identifiable {
        let id: Int
        let at: Date
        let milliseconds: Double?
        let loss: Int

        var isDown: Bool { milliseconds == nil }
        var isRough: Bool { isDown || loss > 0 }
    }

    /// Oldest first, forty of them: one every two minutes with the panel shut,
    /// plus every full pass while the tab is open — a bit over an hour.
    @Published private(set) var history: [Sample] = []

    /// One at a time: three pings on top of each other measure the queue, not
    /// the network.
    private let queue = DispatchQueue(label: "notchshelf.network")
    private var ticker: Timer?
    private var watcher: Timer?
    private var samples = 0
    private static let historyLimit = 40

    /// "1 (2GHz, 20MHz)" arrives as one string; only the band is worth the
    /// width on screen.
    var band: String {
        guard let open = channel.firstIndex(of: "("), let close = channel.firstIndex(of: ")") else { return "" }
        let inside = channel[channel.index(after: open)..<close]
        return inside.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    var channelNumber: String {
        channel.components(separatedBy: " ").first ?? ""
    }

    /// dBm means nothing to most people; the word next to it does.
    var signalWord: String {
        guard let signal else { return "" }
        switch signal {
        case (-50)...: return "excellent"
        case (-60)..<(-50): return "good"
        case (-70)..<(-60): return "fair"
        default: return "weak"
        }
    }

    /// The whole point of the tab: one word, and the reason behind it.
    ///
    /// Every branch names the leg that is at fault, because "the internet is
    /// slow" is three different faults wearing the same coat and the tab exists
    /// to tell them apart.
    enum Health {
        case checking
        case good
        case slow(String)
        case broken(String)

        var word: String {
            switch self {
            case .checking: return "Checking"
            case .good: return "Good"
            case .slow: return "Slow"
            case .broken: return "Down"
            }
        }

        var detail: String {
            switch self {
            case .checking: return "measuring the line"
            case .good: return "everything answers on time"
            case .slow(let why), .broken(let why): return why
            }
        }
    }

    var state: Health {
        guard router.attempted else { return .checking }
        if gateway.isEmpty { return .broken("nothing to connect through") }
        if !router.isUp { return .broken("the router is not answering") }
        // The legs are timed one after another, and a leg that has not been
        // tried yet is not a leg that failed. Reading `isUp` without this said
        // "Down — nothing past the router" for the second and a half between
        // the router answering and the line being asked at all.
        guard internet.attempted else { return .checking }
        if !internet.isUp { return .broken("the router answers, nothing past it") }
        guard dns.attempted else { return .checking }
        if !dns.isUp { return .broken("names do not resolve") }
        if internet.loss > 0 { return .slow("losing \(internet.loss)% of packets on the line") }
        if router.loss > 0 { return .slow("losing \(router.loss)% to the router — weak Wi-Fi") }
        if let lookup = dns.milliseconds, lookup > 300 { return .slow("the line is fine, names are slow") }
        if let ping = internet.milliseconds, ping > 150 { return .slow("the line takes \(Int(ping)) ms to answer") }
        return .good
    }

    /// Used only to re-run the tab's animation when the reading changes.
    var verdict: String { state.word + state.detail }

    /// Whether this is Wi-Fi at all, or a cable.
    var isWireless: Bool { !phy.isEmpty || !channel.isEmpty }

    /// The name of the network, or the best description available without it.
    ///
    /// macOS 15 and later hand the SSID to an app only if it holds location
    /// access — every source reports `<redacted>` otherwise, `system_profiler`
    /// and CoreWLAN alike. Rather than an empty space where a name belongs, the
    /// tab says what it does know.
    var networkName: String {
        if !ssid.isEmpty, ssid != "<redacted>" { return ssid }
        guard wifiChecked else { return "…" }
        guard isWireless else { return "Wired" }
        return band.isEmpty ? "Wi-Fi" : "Wi-Fi · \(band)"
    }

    /// What the line has been like lately, in a sentence.
    ///
    /// "Good" at the top of the tab is about this second. A line that drops for
    /// ten seconds every few minutes reads as good every time it is looked at,
    /// which is exactly the fault that is hardest to catch — so the history is
    /// kept and summed up here.
    var stability: String {
        guard let first = history.first else { return "" }
        let rough = history.filter(\.isRough).count
        let span = Self.spell(Date().timeIntervalSince(first.at))
        guard rough > 0 else { return "steady for the last \(span)" }
        return "\(rough) rough \(rough == 1 ? "check" : "checks") in the last \(span)"
    }

    private static func spell(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        guard minutes >= 60 else { return "\(max(minutes, 1)) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    // MARK: - Life

    /// The slow watch, running whether or not anyone is looking: one ping every
    /// two minutes. Without it the history would only ever cover the seconds the
    /// tab happened to be open, which is no history at all.
    func watch() {
        guard watcher == nil else { return }
        sample()
        let timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    private func sample() {
        // The full pass records its own reading; two pings at once would only
        // measure each other.
        guard !isProbing else { return }
        queue.async { [weak self] in
            let probe = Self.ping("1.1.1.1")
            DispatchQueue.main.async { self?.record(probe) }
        }
    }

    private func record(_ probe: Probe) {
        samples += 1
        history.append(Sample(id: samples,
                              at: Date(),
                              milliseconds: probe.milliseconds,
                              loss: probe.loss))
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    func activate() {
        refresh()
        guard ticker == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func deactivate() {
        ticker?.invalidate()
        ticker = nil
    }

    /// One pass, in the order the answers are wanted: where we are plugged in,
    /// then the three timings, then the Wi-Fi details — which cost two and a
    /// half seconds and decide nothing.
    func refresh() {
        guard !isProbing else { return }
        isProbing = true

        queue.async { [weak self] in
            guard let self else { return }
            let link = Self.readLink()
            DispatchQueue.main.async {
                self.gateway = link.gateway
                self.interface = link.interface
                self.address = link.address
            }

            let router = link.gateway.isEmpty ? Probe(attempted: true) : Self.ping(link.gateway)
            DispatchQueue.main.async { self.router = router }

            // 1.1.1.1 by address, never by name: a stalled lookup would
            // otherwise be reported as a dead line.
            let internet = Self.ping("1.1.1.1")
            DispatchQueue.main.async {
                self.internet = internet
                self.record(internet)
            }

            let dns = Self.resolve("apple.com")
            DispatchQueue.main.async {
                self.dns = dns
                self.checkedAt = Date()
                self.isProbing = false
                Log.write("network router=\(router.label) internet=\(internet.label) dns=\(dns.label)")
            }

            self.readWiFi(on: link.interface)
        }
    }

    // MARK: - What we are connected to

    /// Which interface carries the default route, its address, and the router
    /// behind it. Two processes, both finished in milliseconds.
    private static func readLink() -> (gateway: String, interface: String, address: String) {
        let route = Shell.run("/sbin/route", ["-n", "get", "default"]) ?? ""
        let gateway = field("gateway:", in: route)
        let interface = field("interface:", in: route)
        let address = interface.isEmpty
            ? ""
            : (Shell.run("/usr/sbin/ipconfig", ["getifaddr", interface]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        return (gateway, interface, address)
    }

    /// The slow half: `system_profiler` takes two and a half seconds, so it runs
    /// behind the numbers rather than in front of them.
    private func readWiFi(on interface: String) {
        guard let output = Shell.run("/usr/sbin/system_profiler", ["SPAirPortDataType", "-json"]),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPAirPortDataType"] as? [[String: Any]],
              let interfaces = sections.first?["spairport_airport_interfaces"] as? [[String: Any]] else {
            DispatchQueue.main.async {
                self.ssid = ""
                self.wifiChecked = true
            }
            return
        }

        let card = interfaces.first { ($0["_name"] as? String) == interface } ?? interfaces.first
        guard let current = card?["spairport_current_network_information"] as? [String: Any] else {
            DispatchQueue.main.async {
                self.ssid = ""
                self.wifiChecked = true
            }
            return
        }

        let name = current["_name"] as? String ?? ""
        let channel = current["spairport_network_channel"] as? String ?? ""
        let phy = current["spairport_network_phymode"] as? String ?? ""
        let rate = (current["spairport_network_rate"] as? NSNumber)?.intValue
            ?? Int(current["spairport_network_rate"] as? String ?? "") ?? 0
        // "-25 dBm / -83 dBm" — the signal is the first half.
        let noise = current["spairport_signal_noise"] as? String ?? ""
        let signal = Int(noise.components(separatedBy: " ").first ?? "")

        DispatchQueue.main.async {
            self.ssid = name
            self.channel = channel
            self.phy = phy
            self.rate = rate
            self.signal = signal
            self.wifiChecked = true
        }
    }

    private static func field(_ key: String, in text: String) -> String {
        for line in text.components(separatedBy: .newlines) where line.contains(key) {
            return line.components(separatedBy: key).last?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        return ""
    }

    // MARK: - How well it works

    /// Three packets a third of a second apart: enough to see loss, over inside
    /// a second.
    private static func ping(_ host: String) -> Probe {
        var probe = Probe(attempted: true)
        guard let output = Shell.run("/sbin/ping", ["-c", "3", "-i", "0.3", "-t", "4", host]) else { return probe }

        for line in output.components(separatedBy: .newlines) {
            if line.contains("packet loss"),
               let part = line.components(separatedBy: ",").first(where: { $0.contains("packet loss") }) {
                let digits = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "%").first ?? ""
                probe.loss = Int(Double(digits) ?? 0)
            }
            if line.contains("round-trip"), let numbers = line.components(separatedBy: "= ").last {
                let parts = numbers.components(separatedBy: "/")
                if parts.count > 1 { probe.milliseconds = Double(parts[1]) }
            }
        }
        return probe
    }

    /// `dig` reports the query time itself, which is the lookup alone without
    /// the cost of starting the program.
    private static func resolve(_ name: String) -> Probe {
        var probe = Probe(attempted: true)
        guard let output = Shell.run("/usr/bin/dig", [name, "+noall", "+stats", "+time=3", "+tries=1"]) else {
            return probe
        }
        for line in output.components(separatedBy: .newlines) where line.contains("Query time:") {
            let digits = line.components(separatedBy: " ").compactMap { Double($0) }
            probe.milliseconds = digits.first
        }
        return probe
    }
}
