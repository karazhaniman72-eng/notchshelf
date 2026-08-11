import AppKit

/// Recent copied text. Held in memory only: nothing is ever written to disk,
/// and entries a password manager marks as concealed are skipped outright.
final class ClipboardStore: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let date: Date

        var timeLabel: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let capacity = 15

    init() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount

        let types = pasteboard.types ?? []
        guard !types.contains(concealed), !types.contains(transient) else { return }
        guard let text = pasteboard.string(forType: .string) else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entries.first?.text != trimmed else { return }

        entries.insert(Entry(text: trimmed, date: Date()), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    func copy(_ entry: Entry) {
        lastChange = NSPasteboard.general.changeCount + 1
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries.removeAll()
    }
}
