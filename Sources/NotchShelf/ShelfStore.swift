import AppKit
import Combine
import ImageIO

struct ShelfItem: Identifiable, Equatable {
    /// The file's own path, not a fresh UUID. A UUID changed every time the
    /// store rebuilt an item for a file it already held, so SwiftUI threw the
    /// card's view away and built a new one in the same place — and the tooltip
    /// riding on that view could end up naming a different card's file.
    var id: String { url.path }
    let url: URL
    let thumbnail: NSImage?
    let date: Date
    /// True when the preview is a file type icon rather than the file's own image.
    let isIcon: Bool

    var timeLabel: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        return formatter.string(from: date)
    }
}

/// Watches the screenshot folder and keeps the list of recent shots.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = [] {
        didSet { persist() }
    }
    @Published private(set) var accessDenied = false

    let folder: URL
    private var known: Set<URL> = []
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"]

    private static let savedKey = "shelf.items"
    private static let copyKey = "shelf.copyOnCapture"
    /// The shelf holds the eight most recent shots, like a clipboard history:
    /// a ninth screenshot pushes the oldest card out. The file on disk stays.
    private static let capacity = 8

    /// A fresh screenshot also lands in the clipboard, so Cmd+V still pastes the
    /// picture the way it did when macOS was set to capture straight to clipboard.
    var copiesToClipboard: Bool {
        get { (UserDefaults.standard.object(forKey: Self.copyKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.copyKey) }
    }

    init() {
        folder = ShelfStore.screenshotFolder()
        known = Set(currentFiles())
        Log.write("watch folder=\(folder.path) existing=\(known.count) denied=\(accessDenied)")
        Log.write("capture target=\(ShelfStore.captureTarget()) copyToClipboard=\(copiesToClipboard)")
        if ShelfStore.captureTarget() == "clipboard" {
            // Nothing is written to disk in that mode, so the shelf would stay empty.
            Log.write("warning: screenshots go to the clipboard only, no files to pick up")
        }
        restore()
        startWatching()
    }

    /// The shelf survives a restart: saved cards come back, and screenshots
    /// taken while the app was closed join them.
    private func restore() {
        let saved = (UserDefaults.standard.array(forKey: Self.savedKey) as? [String]) ?? []
        var urls = saved
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let recent = currentFiles()
            .sorted { modified($0) > modified($1) }
            .prefix(Self.capacity)
        for url in recent where !urls.contains(url) {
            urls.append(url)
        }

        items = urls
            .sorted { modified($0) > modified($1) }
            .prefix(Self.capacity)
            .map { url in
                let preview = ShelfStore.preview(for: url)
                return ShelfItem(url: url,
                                 thumbnail: preview.image,
                                 date: modified(url),
                                 isIcon: preview.isIcon)
            }
        Log.write("restored saved=\(saved.count) recent=\(recent.count) total=\(items.count)")
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: Self.savedKey)
    }

    deinit {
        source?.cancel()
    }

    /// Where macOS saves screenshots. Defaults to the Desktop.
    private static func screenshotFolder() -> URL {
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    /// Where the Shift-Cmd-5 panel sends the shot: "file" by default, "clipboard"
    /// when the user picked Clipboard in that panel.
    private static func captureTarget() -> String {
        UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "target") ?? "file"
    }

    private func currentFiles() -> [URL] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            if accessDenied { accessDenied = false }
            // Everything in the folder shows up, not only pictures: Shift-Cmd-5 also
            // records video, and a file saved there by hand belongs on the shelf too.
            return contents.filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory != true
            }
        } catch {
            accessDenied = true
            Log.write("read failed folder=\(folder.path) error=\(error.localizedDescription)")
            return []
        }
    }

    private func startWatching() {
        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            accessDenied = true
            Log.write("open failed folder=\(folder.path) errno=\(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.rescan() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.descriptor >= 0 { close(self.descriptor) }
        }
        source.resume()
        self.source = source
    }

    /// A screenshot is not written instantly, so the file is read after a short delay.
    private func rescan() {
        let current = Set(currentFiles())
        let fresh = current.subtracting(known)
        known = current

        // The file was deleted in Finder: the card must not linger as a dead entry.
        let gone = items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        if !gone.isEmpty {
            items.removeAll { item in gone.contains { $0.id == item.id } }
            Log.write("removed missing=\(gone.count) total=\(items.count)")
        }

        guard !fresh.isEmpty else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            let sorted = fresh.sorted { lhs, rhs in
                self.modified(lhs) < self.modified(rhs)
            }
            for url in sorted {
                guard !self.items.contains(where: { $0.url == url }) else { continue }
                let preview = ShelfStore.preview(for: url)
                let item = ShelfItem(url: url,
                                     thumbnail: preview.image,
                                     date: self.modified(url),
                                     isIcon: preview.isIcon)
                self.items.insert(item, at: 0)
                Log.write("added file=\(url.lastPathComponent) total=\(self.items.count)")
            }
            if let newest = sorted.last { self.copyToClipboard(newest) }
            self.trim()
        }
    }

    /// Puts the picture itself on the clipboard, not the file path, so pasting into
    /// a chat gives an image. Only new shots go through here — restored cards do not.
    private func copyToClipboard(_ url: URL) {
        guard copiesToClipboard,
              imageExtensions.contains(url.pathExtension.lowercased()),
              let image = NSImage(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        Log.write("copied to clipboard file=\(url.lastPathComponent)")
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Anything dropped on the notch joins the shelf, image or not.
    func add(_ urls: [URL]) {
        var added = 0
        for url in urls {
            guard !items.contains(where: { $0.url == url }) else { continue }
            let preview = ShelfStore.preview(for: url)
            let item = ShelfItem(url: url,
                                 thumbnail: preview.image,
                                 date: modified(url),
                                 isIcon: preview.isIcon)
            items.insert(item, at: 0)
            added += 1
        }
        trim()
        Log.write("dropped count=\(added) total=\(items.count)")
    }

    /// Five deep, like a clipboard history: the sixth shot pushes the oldest one
    /// off the shelf and into the Trash, so the folder never piles up.
    private func trim() {
        guard items.count > Self.capacity else { return }
        let dropped = Array(items.suffix(items.count - Self.capacity))
        items.removeLast(items.count - Self.capacity)
        for item in dropped { discard(item.url) }
    }

    /// The Trash, not `removeItem`: a screenshot pushed off the shelf by accident
    /// can still be dragged back out. Files dropped onto the notch from elsewhere
    /// are left where they are — deleting those was never asked for.
    private func discard(_ url: URL) {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent == folder.standardizedFileURL else {
            Log.write("kept outside file=\(url.lastPathComponent)")
            return
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            known.remove(url)
            Log.write("trashed file=\(url.lastPathComponent)")
        } catch {
            Log.write("trash failed file=\(url.lastPathComponent) error=\(error.localizedDescription)")
        }
    }

    /// The file's own picture where possible, otherwise the file type icon.
    private static func preview(for url: URL) -> (image: NSImage?, isIcon: Bool) {
        if let thumbnail = thumbnail(for: url) { return (thumbnail, false) }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)
        return (icon, true)
    }

    /// A downscaled copy instead of the full screenshot: full-size PNGs would eat
    /// hundreds of megabytes of memory.
    private static func thumbnail(for url: URL, maxPixel: CGFloat = 400) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Drops the card from the shelf. The file on disk stays.
    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
