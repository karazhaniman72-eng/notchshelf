import AppKit

/// The day's plan, read out of the knowledge base rather than a calendar.
/// Calendar access is refused on this machine, and an empty tab saying so is
/// worth less than the list that is already written down every morning.
///
/// The list is not read-only. Ticking a line here writes `- [x]` back into the
/// markdown, which is the same thing Obsidian would have written — the panel is
/// a second way into the file, not a copy of it.
final class PlansStore: ObservableObject {

    struct Item: Identifiable {
        /// File and line rather than a fresh UUID: the identity has to survive
        /// the reload that follows every tick.
        let id: String
        let text: String
        /// From goals rather than today's plan — shown lighter.
        let isGoal: Bool
        let isDone: Bool
        let file: String
        let line: Int
    }

    /// The vault. Nothing else in the app knows this path, and if it moves the
    /// tab simply falls back to saying so.
    private let vault = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/s/imanClaude/Plans", isDirectory: true)

    @Published private(set) var items: [Item] = []
    @Published private(set) var source = ""

    /// Re-read on every open: the file is edited by hand during the day.
    ///
    /// Off the main thread, because the vault lives under ~/Documents. macOS
    /// gates that folder, and when the app's permission has lapsed — which is
    /// every rebuild while the signature is ad-hoc — reading a file there does
    /// not fail, it waits. A background app is never shown the dialogue it is
    /// waiting for, so the read never returns and the panel freezes with it.
    func reload() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            if let plans = self.read("today.md", section: "## Планы", isGoal: false), !plans.isEmpty {
                self.publish(plans, from: "Plans/today.md")
                return
            }
            if let goals = self.read("goals.md", section: "## Долгосрочные", isGoal: true), !goals.isEmpty {
                self.publish(goals, from: "Plans/goals.md")
                return
            }
            self.publish([], from: "")
            Log.write("plans empty vault=\(self.vault.path)")
        }
    }

    private func publish(_ found: [Item], from file: String) {
        DispatchQueue.main.async {
            self.items = found
            self.source = file
            guard !found.isEmpty else { return }
            Log.write("plans loaded items=\(found.count) done=\(found.filter(\.isDone).count)")
        }
    }

    /// Bullets under one heading, stopping at the next one.
    private func read(_ name: String, section: String, isGoal: Bool) -> [Item]? {
        guard let text = try? String(contentsOf: vault.appendingPathComponent(name), encoding: .utf8) else {
            Log.write("plans missing file=\(name)")
            return nil
        }

        var collecting = false
        var found: [Item] = []
        for (number, line) in text.components(separatedBy: "\n").enumerated() {
            if line.hasPrefix("## ") {
                if collecting { break }
                collecting = line.trimmingCharacters(in: .whitespaces) == section
                continue
            }
            guard collecting, line.hasPrefix("- ") else { continue }

            var body = String(line.dropFirst(2))
            var done = false
            if body.hasPrefix("[ ] ") {
                body = String(body.dropFirst(4))
            } else if body.lowercased().hasPrefix("[x] ") {
                body = String(body.dropFirst(4))
                done = true
            }

            found.append(Item(id: "\(name):\(number)",
                              text: Self.plain(body),
                              isGoal: isGoal,
                              isDone: done,
                              file: name,
                              line: number))
        }
        return found
    }

    /// Ticks or unticks one line in the file it came from. Unticking takes the
    /// box away again rather than leaving `- [ ]` behind: the plan is written
    /// in plain bullets, and it should still look that way tomorrow.
    func toggle(_ item: Item) {
        // Same reason as `reload`: the write goes to a gated folder, and a
        // gated folder can hold the call. A tick must never freeze the panel.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let url = self.vault.appendingPathComponent(item.file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }

            var lines = text.components(separatedBy: "\n")
            guard lines.indices.contains(item.line) else { return }

            let rewritten = Self.flip(lines[item.line])
            guard rewritten != lines[item.line] else { return }
            lines[item.line] = rewritten

            do {
                try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                Log.write("plans toggled file=\(item.file) line=\(item.line) done=\(!item.isDone)")
            } catch {
                Log.write("plans write failed \(error.localizedDescription)")
                return
            }
            self.reload()
        }
    }

    private static func flip(_ line: String) -> String {
        guard let dash = line.firstIndex(of: "-"),
              line[line.startIndex..<dash].allSatisfy({ $0 == " " || $0 == "\t" }) else { return line }
        let space = line.index(after: dash)
        guard space < line.endIndex, line[space] == " " else { return line }

        let head = String(line[...space])
        let rest = String(line[line.index(after: space)...])

        if rest.hasPrefix("[ ] ") { return head + "[x] " + String(rest.dropFirst(4)) }
        if rest.lowercased().hasPrefix("[x] ") { return head + String(rest.dropFirst(4)) }
        return head + "[x] " + rest
    }

    /// Markdown is for the editor, not for a panel: links keep their words and
    /// lose their addresses, code fences and bold markers just go.
    private static func plain(_ line: String) -> String {
        var text = line
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]+\)"#) {
            text = regex.stringByReplacingMatches(in: text,
                                                  range: NSRange(text.startIndex..., in: text),
                                                  withTemplate: "$1")
        }
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: "**", with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }
}
