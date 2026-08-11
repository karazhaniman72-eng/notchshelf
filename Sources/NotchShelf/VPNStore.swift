import Foundation

/// The VPN switch, driven through `scutil --nc`, which is what macOS itself
/// uses for the connections listed in Network settings.
///
/// There is no VPN on this machine yet. Rather than guess at one, the tab reads
/// whatever the system has configured: the moment a connection is added in
/// Network settings it appears here, with no change to the app.
///
/// An app-based VPN with no system configuration — the kind that ships its own
/// client — cannot be switched from here. Those expose nothing to `scutil`, and
/// pretending otherwise would give a switch that silently does nothing.
final class VPNStore: ObservableObject {

    struct Connection: Identifiable, Equatable {
        let id: String
        let name: String
        let isConnected: Bool
    }

    @Published private(set) var connections: [Connection] = []
    @Published private(set) var isBusy = false
    @Published private(set) var checkedAt: Date?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchshelf.vpn", qos: .utility)

    func activate() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        queue.async { [weak self] in
            let listed = Self.list()
            DispatchQueue.main.async {
                guard let self else { return }
                self.connections = listed
                self.checkedAt = Date()
            }
        }
    }

    func toggle(_ connection: Connection) {
        guard !isBusy else { return }
        isBusy = true
        let verb = connection.isConnected ? "stop" : "start"
        Log.write("vpn \(verb) name=\(connection.name)")

        queue.async { [weak self] in
            _ = Shell.run("/usr/sbin/scutil", ["--nc", verb, connection.name])
            // The state does not flip the instant the command returns.
            Thread.sleep(forTimeInterval: 1.2)
            let listed = Self.list()
            DispatchQueue.main.async {
                guard let self else { return }
                self.connections = listed
                self.isBusy = false
                self.checkedAt = Date()
            }
        }
    }

    /// `scutil --nc list` prints one line per service:
    /// `* (Disconnected)   ABC123 PPP (L2TP) "Office" [OnDemand]`
    private static func list() -> [Connection] {
        let output = Shell.run("/usr/sbin/scutil", ["--nc", "list"]) ?? ""
        var found: [Connection] = []

        for line in output.components(separatedBy: "\n") {
            guard line.contains("("), let quoted = line.range(of: "\"") else { continue }
            let rest = line[quoted.upperBound...]
            guard let closing = rest.range(of: "\"") else { continue }
            let name = String(rest[..<closing.lowerBound])
            guard !name.isEmpty else { continue }

            let connected = line.contains("(Connected)")
            found.append(Connection(id: name, name: name, isConnected: connected))
        }
        return found
    }
}
