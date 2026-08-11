import AppKit
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Two things done to a picture without it leaving the machine: saved as a
/// different format, or cut out of its background. Both run on frameworks that
/// ship with macOS — no upload, no service, no key.
final class ImageToolStore: ObservableObject {

    enum Format: String, CaseIterable, Identifiable {
        case png, jpeg, heic, tiff, pdf

        var id: String { rawValue }
        var title: String { rawValue.uppercased() }

        var type: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .heic: return .heic
            case .tiff: return .tiff
            case .pdf: return .pdf
            }
        }
    }

    @Published private(set) var sourceURL: URL?
    @Published private(set) var preview: NSImage?
    @Published var format: Format = .jpeg
    @Published private(set) var status = ""
    @Published private(set) var isWorking = false
    @Published private(set) var lastResult: URL?

    private let queue = DispatchQueue(label: "notchshelf.imagetool", qos: .userInitiated)

    func load(_ url: URL) {
        sourceURL = url
        preview = NSImage(contentsOf: url)
        lastResult = nil
        status = preview == nil ? "macOS cannot open \(url.lastPathComponent)" : ""
    }

    func clear() {
        sourceURL = nil
        preview = nil
        lastResult = nil
        status = ""
    }

    /// Find the picture in Finder, for everything that is not on the shelf and
    /// not worth dragging across the screen.
    ///
    /// `begin` rather than `runModal`: a modal loop inside a panel that is
    /// itself borderless and non-activating freezes both. The caller is told
    /// when the dialog is gone so it can let the panel fold up again.
    func choose(completion: @escaping () -> Void) {
        let dialog = NSOpenPanel()
        // PDF as well as pictures. The dialog was set to `.image`, which meant a
        // PDF could not even be picked — the answer to "convert this PDF to PNG"
        // was a file browser with the PDF greyed out.
        dialog.allowedContentTypes = [.image, .pdf]
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories = false
        dialog.prompt = "Use"
        dialog.message = "Pick a picture or a PDF"

        NSApp.activate(ignoringOtherApps: true)
        dialog.begin { [weak self] response in
            if response == .OK, let url = dialog.url { self?.load(url) }
            completion()
        }
    }

    func reveal() {
        guard let lastResult else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastResult])
    }

    // MARK: - Format

    /// Saved beside the original with the same name. Overwriting the source
    /// would make a lossy round trip silent, and there is no undo in a panel.
    func convert() {
        guard let sourceURL, !isWorking else { return }
        isWorking = true
        status = ""
        let target = format

        queue.async { [weak self] in
            let outcome = Self.write(source: sourceURL, as: target)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWorking = false
                switch outcome {
                case .success(let url):
                    self.lastResult = url
                    self.status = "Saved as \(url.lastPathComponent)"
                    Log.write("image converted to=\(target.rawValue) file=\(url.lastPathComponent)")
                case .failure(let message):
                    self.status = message
                    Log.write("image convert failed \(message)")
                }
            }
        }
    }

    private enum Outcome {
        case success(URL)
        case failure(String)
    }

    /// Whatever was handed in, as pixels.
    ///
    /// ImageIO alone was not enough, and PDF is why. `CGImageSourceCreateWithURL`
    /// returns nil for a PDF — it is a drawing, not a picture, and ImageIO only
    /// reads pictures — so every PDF put in front of this tool came back as
    /// "Could not read", including the ones the tool had written itself a moment
    /// earlier. A PDF is drawn here instead: first page, at twice its own size,
    /// which is the resolution a page has to be at before the text on it survives
    /// being turned into pixels.
    private static func read(_ url: URL) -> CGImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        return renderPDF(url)
    }

    static let pdfScale: CGFloat = 2

    private static func renderPDF(_ url: URL) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else { return nil }

        let box = page.getBoxRect(.cropBox)
        let width = Int((box.width * pdfScale).rounded())
        let height = Int((box.height * pdfScale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // White, not transparent: a page is paper, and black text on a
        // transparent PNG is black text on whatever it is dropped onto.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: pdfScale, y: pdfScale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    private static func write(source: URL, as format: Format) -> Outcome {
        guard let image = read(source) else {
            return .failure("Could not read \(source.lastPathComponent)")
        }

        let destination = uniqueURL(for: source, extension: format.rawValue)
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL,
                                                           format.type.identifier as CFString,
                                                           1,
                                                           nil) else {
            return .failure("macOS cannot write \(format.title) here")
        }
        // Quality only means anything to the lossy formats; the others ignore it.
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(writer, image, options as CFDictionary)
        guard CGImageDestinationFinalize(writer) else {
            return .failure("Writing \(format.title) failed")
        }
        return .success(destination)
    }

    // MARK: - Background

    /// `VNGenerateForegroundInstanceMask` — the same cut-out Preview and Photos
    /// use. It runs on the Neural Engine, offline, and takes about a second.
    func removeBackground() {
        guard let sourceURL, !isWorking else { return }
        isWorking = true
        status = "Cutting the subject out…"

        queue.async { [weak self] in
            let outcome = Self.cutOut(sourceURL)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWorking = false
                switch outcome {
                case .success(let url):
                    self.lastResult = url
                    self.preview = NSImage(contentsOf: url)
                    self.status = "Saved as \(url.lastPathComponent)"
                    Log.write("background removed file=\(url.lastPathComponent)")
                case .failure(let message):
                    self.status = message
                    Log.write("background removal failed \(message)")
                }
            }
        }
    }

    private static func cutOut(_ url: URL) -> Outcome {
        guard let image = read(url) else {
            return .failure("Could not read \(url.lastPathComponent)")
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .failure("Vision refused: \(error.localizedDescription)")
        }

        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            return .failure("No subject found in this picture")
        }

        do {
            let masked = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                        from: handler,
                                                        croppedToInstancesExtent: false)
            let cut = CIImage(cvPixelBuffer: masked)
            let context = CIContext()
            guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let data = context.pngRepresentation(of: cut,
                                                       format: .RGBA8,
                                                       colorSpace: colourSpace) else {
                return .failure("Could not encode the cut-out")
            }
            // PNG without argument: the whole point is the transparency, and
            // JPEG would fill it back in with white.
            let destination = uniqueURL(for: url, extension: "png", suffix: "-cutout")
            try data.write(to: destination)
            return .success(destination)
        } catch {
            return .failure("Cut-out failed: \(error.localizedDescription)")
        }
    }

    /// Never silently replaces a file that is already there.
    private static func uniqueURL(for source: URL, extension ext: String, suffix: String = "") -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
