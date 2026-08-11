import AppKit
import UniformTypeIdentifiers

/// Colours picked off the screen. The system sampler does the picking; this
/// only remembers what came back, because the value is always needed twice.
final class ColorStore: ObservableObject {

    struct Swatch: Identifiable {
        let id = UUID()
        let hex: String
        let color: NSColor
    }

    @Published private(set) var swatches: [Swatch] = []

    func pick() {
        NSColorSampler().show { [weak self] picked in
            guard let self, let picked else { return }
            let rgb = picked.usingColorSpace(.sRGB) ?? picked
            let hex = String(format: "#%02X%02X%02X",
                             Int((rgb.redComponent * 255).rounded()),
                             Int((rgb.greenComponent * 255).rounded()),
                             Int((rgb.blueComponent * 255).rounded()))
            self.swatches.insert(Swatch(hex: hex, color: rgb), at: 0)
            self.swatches = Array(self.swatches.prefix(8))
            self.copy(hex)
            Log.write("colour picked \(hex)")
        }
    }

    func copy(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }
}

/// The last few things that landed in Downloads. The shelf catches screenshots;
/// this catches everything that arrives from a browser, and drags out the same
/// way.
final class DownloadsStore: ObservableObject {

    struct Item: Identifiable {
        let id: String
        let url: URL
        let name: String
        let detail: String
        let icon: NSImage
        /// "PNG image", "Folder" — what the Finder would call it.
        let kind: String
        /// "1.2 MB", or the number of things inside a folder.
        let size: String
        /// "12 min ago" reads faster than a date does, and the exact stamp is
        /// still one hover away in the Finder.
        let age: String
    }

    @Published private(set) var items: [Item] = []

    private let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)

    /// Off the main thread for the same reason the theorem shelf is: a folder
    /// macOS gates — and Downloads is one — can hold `contentsOfDirectory` for
    /// as long as it likes when the app's permission has lapsed, and a held call
    /// on the main thread is a frozen panel.
    func reload() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.read()
        }
    }

    private func read() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let listing = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else {
            DispatchQueue.main.async { self.items = [] }
            Log.write("downloads unreadable — folder access may be denied")
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM HH:mm"

        let ago = RelativeDateTimeFormatter()
        ago.locale = Locale(identifier: "en_US_POSIX")
        ago.unitsStyle = .abbreviated

        let built = listing
            .compactMap { url -> (URL, Date, Int, Bool)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      let modified = values.contentModificationDate else { return nil }
                return (url, modified, values.fileSize ?? 0, values.isDirectory ?? false)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map { url, modified, size, isDirectory in
                let sizeText: String
                if isDirectory {
                    let count = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
                    sizeText = count == 1 ? "1 item" : "\(count) items"
                } else {
                    sizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                }
                return Item(id: url.path,
                            url: url,
                            name: url.lastPathComponent,
                            detail: "\(formatter.string(from: modified)) · \(sizeText)",
                            icon: NSWorkspace.shared.icon(forFile: url.path),
                            kind: Self.kind(of: url, isDirectory: isDirectory),
                            size: sizeText,
                            age: ago.localizedString(for: modified, relativeTo: Date()))
            }

        DispatchQueue.main.async { self.items = built }
    }

    /// What the Finder calls this sort of file, straight from the system's own
    /// table of types rather than a list of extensions kept here.
    private static func kind(of url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "Folder" }
        if let type = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription {
            return type
        }
        return url.pathExtension.uppercased()
    }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
