import AppKit
import SwiftUI

/// Things stuck to the top of the screen and kept there.
///
/// A pin is its own small window, not a card inside the panel: the point is
/// that it stays visible while the panel is shut and while other apps are in
/// front. It opens small — a reference you glance at, not a second viewer — and
/// from there it is yours to size.
final class PinStore: ObservableObject {

    struct Pin: Identifiable {
        let id = UUID()
        let image: NSImage?
        let text: String
        let source: URL?
        /// The picture as it is on disk, in real pixels. A retina screenshot is
        /// twice the points it draws in, and the number that means anything to
        /// the person who took it is the pixel one.
        var pixelSize: CGSize = .zero
        /// What the window is right now, in points.
        var size: CGSize = .zero

        var isImage: Bool { image != nil }

        var title: String {
            if let source { return source.lastPathComponent }
            return isImage ? "Clipboard image" : "Note"
        }

        /// "2940 × 1912" — the real thing, not what it has been shrunk to.
        var pixelLabel: String {
            guard pixelSize.width > 0 else { return "" }
            return "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        }

        /// How much of full size is on screen.
        var zoom: Double {
            guard let image, image.size.width > 0 else { return 1 }
            return Double(size.width / image.size.width)
        }

        var zoomLabel: String { "\(Int((zoom * 100).rounded()))%" }
    }

    @Published private(set) var pins: [Pin] = []

    private var windows: [UUID: NSPanel] = [:]
    private var hosts: [UUID: NSHostingView<PinView>] = [:]

    /// How big a pin opens. Anything bigger is scaled down to it — a screenshot
    /// of a whole display pinned at full size is a second desktop.
    private static let maxWidth: CGFloat = 210
    private static let maxHeight: CGFloat = 150
    /// The range the buttons may take it to.
    private static let minZoom: CGFloat = 0.05
    private static let maxZoom: CGFloat = 2

    // MARK: - Making one

    func pin(url: URL) {
        if let image = NSImage(contentsOf: url) {
            add(Pin(image: image, text: "", source: url, pixelSize: Self.pixels(of: image)))
            return
        }
        // Not a picture: if it reads as text, pin the text.
        if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            add(Pin(image: nil, text: String(text.prefix(400)), source: url))
            return
        }
        Log.write("pin refused file=\(url.lastPathComponent)")
    }

    func pin(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        add(Pin(image: nil, text: String(trimmed.prefix(400)), source: nil))
    }

    /// Whatever is on the clipboard right now — the fastest way to pin a
    /// snippet that is not already a file.
    func pinClipboard() {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            add(Pin(image: image, text: "", source: nil, pixelSize: Self.pixels(of: image)))
            return
        }
        if let text = pasteboard.string(forType: .string) {
            pin(text: text)
        }
    }

    /// True while that file is on the screen, so the shelf strip in the Pin tab
    /// can be a switch rather than a one-way trip. Pressing the same picture
    /// twice used to open a second copy of it with no way back.
    func isPinned(url: URL) -> Bool {
        pins.contains { $0.source == url }
    }

    func toggle(url: URL) {
        if let existing = pins.first(where: { $0.source == url }) {
            unpin(existing.id)
        } else {
            pin(url: url)
        }
    }

    func unpin(_ id: UUID) {
        windows[id]?.orderOut(nil)
        windows[id] = nil
        hosts[id] = nil
        pins.removeAll { $0.id == id }
        Log.write("unpinned total=\(pins.count)")
    }

    func unpinAll() {
        for id in windows.keys { windows[id]?.orderOut(nil) }
        windows.removeAll()
        hosts.removeAll()
        pins.removeAll()
    }

    // MARK: - Size

    /// Bigger or smaller by a step, anchored at the top left so the pin grows
    /// downwards instead of wandering off across the screen.
    func resize(_ id: UUID, by factor: CGFloat) {
        guard let index = pins.firstIndex(where: { $0.id == id }),
              let panel = windows[id] else { return }
        var pin = pins[index]
        guard let image = pin.image, image.size.width > 0 else { return }

        let zoom = min(max(CGFloat(pin.zoom) * factor, Self.minZoom), Self.maxZoom)
        let size = CGSize(width: max((image.size.width * zoom).rounded(), 70),
                          height: max((image.size.height * zoom).rounded(), 46))
        pin.size = size
        pins[index] = pin

        let frame = panel.frame
        panel.setFrame(CGRect(x: frame.minX,
                              y: frame.maxY - size.height,
                              width: size.width,
                              height: size.height),
                       display: true)
        refresh(pin)
        Log.write("pin resized zoom=\(pin.zoomLabel) size=\(Int(size.width))x\(Int(size.height))")
    }

    /// Back to the size it opened at.
    func fit(_ id: UUID) {
        guard let index = pins.firstIndex(where: { $0.id == id }),
              let panel = windows[id] else { return }
        var pin = pins[index]
        let size = Self.size(for: pin)
        pin.size = size
        pins[index] = pin
        let frame = panel.frame
        panel.setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height,
                              width: size.width, height: size.height),
                       display: true)
        refresh(pin)
    }

    private func refresh(_ pin: Pin) {
        hosts[pin.id]?.rootView = PinView(
            pin: pin,
            onClose: { [weak self] in self?.unpin(pin.id) },
            onZoom: { [weak self] factor in self?.resize(pin.id, by: factor) }
        )
    }

    /// True pixels, which is what the file is measured in. `NSImage.size` is
    /// points, and on this screen a screenshot's points are half its pixels.
    private static func pixels(of image: NSImage) -> CGSize {
        var widest = CGSize.zero
        for rep in image.representations where CGFloat(rep.pixelsWide) > widest.width {
            widest = CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
        }
        return widest == .zero ? image.size : widest
    }

    // MARK: - The window

    private func add(_ pin: Pin) {
        var pin = pin
        pin.size = Self.size(for: pin)
        pins.append(pin)

        let panel = NSPanel(contentRect: CGRect(origin: place(pin.size), size: pin.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        // Above ordinary windows and above the shelf panel, so a pin is never
        // buried by the thing it was pinned from.
        panel.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The same reason the shelf panel is told: a pinned note is drawn in the
        // panel's colours, so anything macOS draws inside it — a caret, a
        // selection behind selectable text — has to be told which of the two it
        // is looking at.
        panel.appearance = NSAppearance(named: Skin.shared.isLight ? .aqua : .darkAqua)

        let hosting = NSHostingView(rootView: PinView(
            pin: pin,
            onClose: { [weak self] in self?.unpin(pin.id) },
            onZoom: { [weak self] factor in self?.resize(pin.id, by: factor) }
        ))
        hosting.frame = CGRect(origin: .zero, size: pin.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()

        windows[pin.id] = panel
        hosts[pin.id] = hosting
        Log.write("pinned kind=\(pin.isImage ? "image" : "text") pixels=\(pin.pixelLabel) total=\(pins.count)")
    }

    private static func size(for pin: Pin) -> CGSize {
        guard let image = pin.image, image.size.width > 0, image.size.height > 0 else {
            // Text: a fixed column, as tall as the words need up to a limit.
            let lines = min(max(pin.text.count / 34 + 1, 2), 7)
            return CGSize(width: 200, height: CGFloat(lines) * 17 + 26)
        }
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height, 1)
        return CGSize(width: max((image.size.width * scale).rounded(), 90),
                      height: max((image.size.height * scale).rounded(), 60))
    }

    /// Along the top edge, right of centre, one after another. Every pin can be
    /// dragged anywhere afterwards; this is only where it starts.
    private func place(_ size: CGSize) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let top = screen.frame.maxY - screen.safeAreaInsets.top - size.height - 8
        let step = CGFloat(pins.count - 1)
        let x = screen.frame.maxX - 24 - size.width - step * 26
        return CGPoint(x: max(x, 12), y: max(top - step * 18, 12))
    }
}

/// One pin. The cross is always there rather than on hover — a control you have
/// to discover is a control that traps things on the screen — and the size
/// controls appear under the cursor, with the file's real dimensions beside
/// them.
struct PinView: View {
    let pin: PinStore.Pin
    let onClose: () -> Void
    let onZoom: (CGFloat) -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.body)

            Group {
                if let image = pin.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Text(pin.text)
                        .font(Theme.rowText)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .accessibilityHidden(true)
                    .font(.system(size: 8, weight: .bold))
                    // On the pinned picture rather than on the panel: fixed ink
                    // on a fixed scrim, or the light skin hides it in its own
                    // shadow. See `Theme.onMedia`.
                    .foregroundStyle(Theme.onMedia)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Theme.mediaScrim(0.65)))
                    .contentShape(Rectangle())
                    .labelled("Close this pin")
            }
            .buttonStyle(.plain)
            .padding(5)

            if hovering, pin.isImage {
                VStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        zoomButton("minus", named: "Smaller") { onZoom(1 / 1.25) }
                        Text(pin.zoomLabel)
                            .font(.system(size: 9.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.onMedia)
                            .frame(width: 32)
                        zoomButton("plus", named: "Bigger") { onZoom(1.25) }

                        Spacer(minLength: 4)

                        Text(pin.pixelLabel)
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(Theme.onMedia.opacity(0.7))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Theme.mediaScrim())
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }

    private func zoomButton(_ symbol: String, named name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.onMedia)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Theme.onMedia.opacity(0.22)))
                .contentShape(Rectangle())
        }
        .labelled(name)
        .buttonStyle(.plain)
    }
}
