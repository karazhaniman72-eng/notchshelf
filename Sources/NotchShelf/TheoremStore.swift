import AppKit
import PDFKit

/// One theorem a day out of a textbook.
///
/// The rule is the feature: a single statement, sitting in the notch all day,
/// replaced tomorrow whether or not it was learned. A list of three hundred
/// theorems is a thing to avoid; one is a thing to read.
final class TheoremStore: ObservableObject {

    struct Item: Identifiable {
        let id = UUID()
        /// "Теорема", "Лемма", "Определение" — the word the textbook used.
        let kind: String
        /// The opening line, which is nearly always the number and the name.
        let title: String
        let body: String
    }

    /// Where the textbooks live. PDF, plain text or markdown — whatever gets
    /// dropped in.
    let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/s/imanClaude/Study/textbooks", isDirectory: true)

    @Published private(set) var items: [Item] = []
    @Published private(set) var index = 0
    @Published private(set) var source = ""
    @Published private(set) var isReading = false

    private let queue = DispatchQueue(label: "notchshelf.theorem")
    /// Parsing a three-hundred-page PDF is not free, and the file does not
    /// change while the app is running.
    private var parsedFrom: String?

    private let indexKey = "theorem.index"
    private let dayKey = "theorem.day"

    var current: Item? { items.indices.contains(index) ? items[index] : nil }

    var position: String {
        guard !items.isEmpty else { return "" }
        return "\(index + 1) из \(items.count)"
    }

    // MARK: - Reading the shelf

    /// Forgets the parsed book, so a file edited since the app started is read
    /// again.
    func reload() {
        parsedFrom = nil
        activate()
    }

    /// Everything that touches the disk happens off the main thread — listing
    /// the folder included.
    ///
    /// It used to look for the newest book before dispatching, on the reasoning
    /// that reading one directory is instant. It is not: the books live under
    /// ~/Documents, macOS gates that folder, and an app whose permission has
    /// lapsed — which is every rebuild, while the signature stays ad-hoc — has
    /// its `contentsOfDirectory` held while the system decides whether to ask.
    /// A background app never gets asked, so the call simply never returned and
    /// the whole panel froze the moment this tab was opened.
    func activate() {
        guard !isReading else { return }
        isReading = true
        let known = parsedFrom

        queue.async { [weak self] in
            guard let self else { return }

            // The folder is made on first look, so the empty state can point at
            // a place that exists rather than one to be typed out by hand.
            try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)

            guard let book = self.newestBook() else {
                DispatchQueue.main.async {
                    self.items = []
                    self.source = ""
                    self.parsedFrom = nil
                    self.isReading = false
                }
                return
            }

            guard known != book.path else {
                DispatchQueue.main.async {
                    self.isReading = false
                    self.rollDay()
                }
                return
            }

            let text = Self.text(of: book)
            let found = Self.split(text)
            DispatchQueue.main.async {
                self.parsedFrom = book.path
                self.items = found
                self.source = book.lastPathComponent
                self.isReading = false
                self.rollDay()
                Log.write("theorem book=\(book.lastPathComponent) items=\(found.count)")
            }
        }
    }

    /// The most recently added book wins, so dropping a new one in switches to
    /// it without a setting to find.
    private func newestBook() -> URL? {
        let readable = ["pdf", "md", "txt", "markdown", "text"]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return files
            .filter { readable.contains($0.pathExtension.lowercased()) }
            .max { left, right in
                let a = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a < b
            }
    }

    private static func text(of url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return PDFDocument(url: url)?.string ?? ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - The day

    /// Moves on by one if the day has turned over since the last look. Not by
    /// however many days were missed: a theorem skipped is still a theorem not
    /// read.
    private func rollDay() {
        guard !items.isEmpty else { return }
        let defaults = UserDefaults.standard
        let today = Self.stamp(Date())
        let stored = defaults.string(forKey: dayKey)
        var position = defaults.integer(forKey: indexKey)

        if stored != today {
            position = stored == nil ? 0 : position + 1
            defaults.set(today, forKey: dayKey)
            defaults.set(position, forKey: indexKey)
        }
        index = position % items.count
    }

    /// Reading ahead is allowed; tomorrow simply carries on from wherever this
    /// left off.
    func advance(by step: Int) {
        guard !items.isEmpty else { return }
        let moved = ((index + step) % items.count + items.count) % items.count
        index = moved
        UserDefaults.standard.set(moved, forKey: indexKey)
        UserDefaults.standard.set(Self.stamp(Date()), forKey: dayKey)
    }

    func copyCurrent() {
        guard let item = current else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.title + "\n\n" + item.body, forType: .string)
    }

    func revealFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Cutting the book up

    private static let markers = [
        "Теорема", "Лемма", "Определение", "Следствие", "Утверждение",
        "Предложение", "Аксиома", "Свойство", "Принцип", "Критерий",
        "Theorem", "Lemma", "Definition", "Corollary", "Proposition", "Axiom"
    ]

    /// Every statement starts on its own line with the word for what it is —
    /// true of every maths textbook ever set, and of markdown notes taken from
    /// one. Anything between two such lines belongs to the first.
    private static func split(_ raw: String) -> [Item] {
        let text = tidy(raw)
        guard !text.isEmpty else { return [] }

        let pattern = "(?m)^[\\s#*>_-]*(?:" + markers.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return [] }

        var items: [Item] = []
        for (position, match) in matches.enumerated() {
            guard let start = Range(match.range, in: text) else { continue }
            let end = position + 1 < matches.count
                ? Range(matches[position + 1].range, in: text)?.lowerBound ?? text.endIndex
                : text.endIndex

            var block = String(text[start.lowerBound..<end])
                .trimmingCharacters(in: CharacterSet(charactersIn: "#*>_- \t\n"))
            // A whole proof is not a thing to read off a panel; the statement is.
            if block.count > 1700 { block = String(block.prefix(1700)) + "…" }

            let (title, body) = headline(of: block)
            // A line with nothing under it is a contents entry, not a theorem.
            guard body.count > 30 else { continue }
            let kind = markers.first { title.hasPrefix($0) } ?? markers[0]
            items.append(Item(kind: kind, title: title, body: body))
        }
        return items
    }

    /// "Теорема 3.1 (Лагранжа)" off the front, the statement itself after it.
    /// Textbooks name a theorem and then state it, and the two want different
    /// type sizes on screen.
    private static func headline(of block: String) -> (String, String) {
        let limit = block.index(block.startIndex, offsetBy: min(110, block.count))
        let head = block[block.startIndex..<limit]

        // A name ends where the sentence or the line does — whichever comes
        // first, since a heading sits on its own line and an inline statement
        // ends at a full stop. A dash or a colon is only a last resort: they
        // turn up in the middle of the statement too, and cutting there leaves
        // half of it in the title.
        func earliest(_ separators: [String]) -> [Range<Substring.Index>] {
            separators.compactMap { head.range(of: $0) }.sorted { $0.lowerBound < $1.lowerBound }
        }
        let cuts = earliest([". ", ".\n", "\n"]) + earliest([" — ", ": "])

        // A cut that leaves a sentence fragment behind is worse than a clumsy
        // title: the statement is what gets read, and `split` throws away
        // anything with too little of it left.
        var fallback: (String, String)?
        for cut in cuts {
            let title = String(block[block.startIndex..<cut.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(block[cut.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 6, !body.isEmpty else { continue }
            if body.count >= 30 { return (title, body) }
            if fallback == nil { fallback = (title, body) }
        }
        return fallback ?? (String(head).trimmingCharacters(in: .whitespaces), block)
    }

    /// PDF text arrives broken at the width of the page. Lines inside a
    /// paragraph are joined back up, hyphens at a line end are healed, and the
    /// blank lines that separate paragraphs are kept.
    private static func tidy(_ raw: String) -> String {
        var out: [String] = []
        var paragraph = ""
        let decoration = CharacterSet(charactersIn: "#*>_ \t")

        for line in raw.replacingOccurrences(of: "**", with: "")
                       .replacingOccurrences(of: "__", with: "")
                       .components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !paragraph.isEmpty { out.append(paragraph); paragraph = "" }
                out.append("")
                continue
            }
            // A new statement always starts its own paragraph, whatever the
            // line before it was doing — headings and bullets included.
            if markers.contains(where: { trimmed.trimmingCharacters(in: decoration).hasPrefix($0) }),
               !paragraph.isEmpty {
                out.append(paragraph)
                paragraph = ""
            }
            if paragraph.isEmpty {
                paragraph = trimmed
            } else if paragraph.hasSuffix("-") {
                paragraph.removeLast()
                paragraph += trimmed
            } else {
                paragraph += " " + trimmed
            }
        }
        if !paragraph.isEmpty { out.append(paragraph) }
        return out.joined(separator: "\n")
    }
}
