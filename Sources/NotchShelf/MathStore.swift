import AppKit

/// Maths in two halves, and the split is the whole idea.
///
/// A language model reads a worded problem better than any parser will, and
/// cannot be trusted with the arithmetic that follows. Asked the apples
/// question outright — twelve in a basket, a third eaten, five added — the
/// local qwen2.5 answers 10. The answer is 13. Asked instead only what to
/// compute, it returns `12 - 12/3 + 5` every time, and does it in four
/// seconds.
///
/// So the model never produces a number. It says what the sum is; `Formula`
/// below works the sum out. Everything on screen with digits in it was
/// computed here.
final class MathStore: ObservableObject {

    struct Entry: Identifiable {
        let id = UUID()
        let source: String
        let result: String
    }

    /// Where a local model is expected to be listening. Nothing leaves the
    /// machine — this is the reason the tab can be pointed at homework.
    private static let host = "http://127.0.0.1:11434"

    /// Preferred first, because it is the one that answers in seconds. The
    /// 36B mixture on this Mac is 23 GB against 16 GB of memory: it would
    /// page from the SSD for every token.
    private static let preferred = ["qwen2.5:14b", "qwen2.5", "qwen3", "llama3", "mistral"]

    @Published var input = "" {
        didSet { reread() }
    }
    /// The number, already worked out. Never comes from the model.
    @Published private(set) var answer = ""
    /// A function of x, ready for the plot. Empty when there is nothing to draw.
    @Published private(set) var plot = ""
    /// The model's one line about what it understood. Only ever prose.
    @Published private(set) var note = ""
    @Published private(set) var isThinking = false
    @Published private(set) var failure = ""
    @Published private(set) var history: [Entry] = []
    /// Which model answered, shown so it is never a mystery who is talking.
    @Published private(set) var model = ""
    /// Curves put aside to compare the next one against. The field always holds
    /// exactly one live formula; anything kept is drawn behind it in grey, so two
    /// or three functions can be looked at together without the panel growing a
    /// list of them to manage.
    @Published private(set) var kept: [String] = []
    /// Half-width of the plotted domain.
    @Published var span: Double = 10
    /// The value of x in the middle of the plot. Zero until the graph is
    /// dragged: a window nailed to the origin is the one window a formula is
    /// least likely to be interesting in.
    @Published var centre: Double = 0

    private var task: URLSessionDataTask?

    // MARK: - Typing

    /// Runs on every keystroke. Anything that is already arithmetic is answered
    /// here and now; the model is not woken for `2+2`.
    private func reread() {
        let text = Formula.plain(input)
        guard !text.isEmpty else {
            answer = ""; plot = ""; note = ""; failure = ""
            return
        }

        // An integral with no limits on it has no number to give — it has a
        // function. Checked before the numeric read, which would only say "not
        // arithmetic" and leave the display empty.
        if let indefinite = Formula.indefinite(text) {
            answer = indefinite
            plot = ""
            failure = ""
            return
        }

        // Anything that comes out as a number is a number, x in it or not:
        // `int(x^2, 0, 1)` is one third, and reading it as a curve because the
        // letter x appears in it drew a flat line instead of answering.
        if let value = try? Formula.value(of: text) {
            answer = Formula.format(value)
            plot = ""
            failure = ""
            return
        }

        if Formula.usesX(text) {
            // A curve has no single answer, so the plot is the answer.
            if Formula.curve(text, from: centre - span, to: centre + span, count: 8).contains(where: { $0 != nil }) {
                plot = text
                answer = ""
                failure = ""
                return
            }
        }

        // Not arithmetic: prose, or a sum still being typed. Either way there is
        // nothing to show until Enter.
        answer = ""
        plot = ""
    }

    /// Enter. Keeps a finished sum, or asks the model about anything else.
    func submit() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        if !answer.isEmpty {
            remember(source: question, result: answer)
            return
        }
        if !plot.isEmpty { return }
        consult(question)
    }

    func clear() {
        history.removeAll()
        input = ""
        note = ""
        failure = ""
    }

    func copy(_ entry: Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.result, forType: .string)
    }

    /// A sum already worked out, put back on the display.
    ///
    /// Pressing one used to copy it, which is the thing nobody wants from a
    /// calculator's history: what a finished sum is for is doing it again with
    /// one number changed.
    func recall(_ entry: Entry) {
        input = entry.source
    }

    /// The answer on screen, into the clipboard. Pressing it is the gesture,
    /// because selecting it with the cursor drew a pale box over the figure and
    /// cut it off at both ends.
    func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }

    /// What the sign on the key actually asks for.
    ///
    /// A keypad can put ∫ on the screen; only a line of prose can say that the
    /// three things after it are the function and the two ends. Shown while one
    /// of them is being typed and never after — it is a label on the key under
    /// the hand, not advice.
    var hint: String {
        let text = input.lowercased()
        if text.contains("int(") { return "int(f, a, b) — the area under f from a to b" }
        if text.contains("sum(") { return "sum(f, a, b) — f added up over whole x, a to b" }
        if text.contains("deriv(") { return "deriv(f, x) — the slope of f at that x" }
        if text.contains("det(") { return "det(a, b, c, d) — four numbers for 2×2, nine for 3×3" }
        return ""
    }

    // MARK: - The plotted window

    /// Wider or closer, around whatever is in the middle now.
    func zoom(by factor: Double) {
        span = min(max(span * factor, 0.05), 100_000)
    }

    func recentre() {
        centre = 0
        span = 10
    }

    /// Pins the curve on screen and empties the field for the next one.
    ///
    /// Comparing two functions is the reason anybody draws two: what a graph tab
    /// with one slot forces instead is drawing one, remembering its shape, and
    /// drawing the other. Four is the ceiling — past that the greys stop being
    /// tellable apart and the picture is a scribble.
    func keepCurve() {
        let curve = plot
        guard !curve.isEmpty else { return }
        if !kept.contains(curve) { kept.append(curve) }
        if kept.count > 4 { kept.removeFirst() }
        input = ""
    }

    func dropCurves() {
        kept.removeAll()
    }

    /// Several curves at once, for a snapshot: the last one goes in the field,
    /// the rest are the ones already kept.
    func preload(curves: [String]) {
        guard let last = curves.last else { return }
        kept = curves.dropLast().map { Formula.plain($0) }
        input = last
    }

    /// The distance between two grid lines: 5, or 50, or 500, whichever leaves a
    /// readable number of them across the window.
    ///
    /// Only multiples of five, up and down by tens — a grid whose lines land on
    /// 5, 10, 15 is one that can be counted at a glance, and one that lands on
    /// 3.7, 7.4, 11.1 has to be read off the labels every time.
    static func gridStep(across width: Double) -> Double {
        guard width > 0, width.isFinite else { return 5 }
        var step = 5.0
        while width / step > 14 { step *= 10 }
        // Down a decade only while the finer grid still stays readable. Without
        // the second test a window fifteen units tall dropped straight to a step
        // of 0.5 and drew thirty lines — a mesh, not a grid.
        while width / step < 4, width / (step / 10) <= 14, step > 0.0005 { step /= 10 }
        return step
    }

    private func remember(source: String, result: String) {
        history.insert(Entry(source: source, result: result), at: 0)
        history = Array(history.prefix(4))
        input = ""
        note = ""
    }

    // MARK: - The local model

    /// Asks Ollama which models are installed and picks one. Called when the tab
    /// opens, so a model that was pulled since last time is found.
    func activate() {
        guard model.isEmpty, let url = URL(string: Self.host + "/api/tags") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, error == nil,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = root["models"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    self.failure = "Ollama is not answering — sums still work, words do not"
                    Log.write("math: ollama unreachable")
                }
                return
            }

            let names = list.compactMap { $0["name"] as? String }.filter { !$0.contains("embed") }
            let chosen = Self.preferred.compactMap { wanted in
                names.first { $0.hasPrefix(wanted) }
            }.first ?? names.first

            DispatchQueue.main.async {
                self.model = chosen ?? ""
                self.failure = chosen == nil ? "Ollama has no model pulled" : ""
                Log.write("math: model=\(self.model) available=\(names.count)")
            }
        }.resume()
    }

    /// The only prompt in the app. It forbids the one thing the model is bad at.
    private static func prompt(for question: String) -> String {
        """
        Ты разбираешь условие задачи по математике. Считать нельзя — считает программа, \
        твоя арифметика в ответ не попадёт.

        Верни JSON с тремя ключами:
        "expr" — одно выражение, которое даёт ответ. Пустая строка, если считать нечего.
        "plot" — функция от x для графика, без "y=". Пустая строка, если график не нужен.
        "note" — одна короткая строка по-русски: что это выражение считает.

        В expr и plot разрешены только: числа, + - * / ^ ( ) и sqrt ln lg exp sin cos tan abs pi e.
        Никаких слов и единиц измерения внутри выражения.

        Условие: \(question)
        """
    }

    private func consult(_ question: String) {
        guard !model.isEmpty else {
            failure = failure.isEmpty ? "No local model picked yet" : failure
            return
        }
        guard let url = URL(string: Self.host + "/api/generate") else { return }

        task?.cancel()
        isThinking = true
        failure = ""
        note = ""

        let body: [String: Any] = [
            "model": model,
            "prompt": Self.prompt(for: question),
            "stream": false,
            // Ollama's own JSON mode: the reply is grammar-constrained, so it
            // cannot come back wrapped in an apology or a code fence.
            "format": "json",
            "options": ["temperature": 0, "num_predict": 300]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        // A model evicted from memory has to be loaded from disk first, and on a
        // 9 GB model that is the better part of a minute.
        request.timeoutInterval = 120

        let started = Date()
        let job = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            let seconds = Date().timeIntervalSince(started)

            guard let data, error == nil,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reply = root["response"] as? String else {
                DispatchQueue.main.async {
                    self.isThinking = false
                    guard (error as? URLError)?.code != .cancelled else { return }
                    self.failure = "The model did not answer"
                    Log.write("math: request failed \(error?.localizedDescription ?? "?")")
                }
                return
            }

            let parsed = Self.read(reply)
            DispatchQueue.main.async {
                self.isThinking = false
                self.apply(parsed, question: question, seconds: seconds)
            }
        }
        task = job
        job.resume()
    }

    private struct Answer {
        var expression = ""
        var plot = ""
        var note = ""
    }

    /// The model speaks JSON, but only because it was told to. Anything odd in
    /// there is dropped rather than shown.
    private static func read(_ reply: String) -> Answer {
        guard let data = reply.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Answer()
        }
        func text(_ key: String) -> String {
            if let value = root[key] as? String { return value }
            if let value = root[key] as? NSNumber { return value.stringValue }
            return ""
        }
        return Answer(expression: text("expr"), plot: text("plot"), note: text("note"))
    }

    private func apply(_ reply: Answer, question: String, seconds: TimeInterval) {
        note = reply.note.trimmingCharacters(in: .whitespacesAndNewlines)

        let curve = Formula.plain(reply.plot)
        if !curve.isEmpty, Formula.usesX(curve),
           Formula.curve(curve, from: -span, to: span, count: 8).contains(where: { $0 != nil }) {
            plot = curve
        }

        let sum = Formula.plain(reply.expression)
        if !sum.isEmpty, let value = try? Formula.value(of: sum) {
            answer = Formula.format(value)
            history.insert(Entry(source: question, result: "\(sum) = \(answer)"), at: 0)
            history = Array(history.prefix(4))
        } else if plot.isEmpty {
            failure = reply.expression.isEmpty
                ? "Could not tell what to count here"
                : "That expression does not add up: \(reply.expression)"
        }

        Log.write("math: answered in \(Int(seconds))s expr=\(reply.expression) plot=\(reply.plot)")
    }
}

// MARK: - The engine

/// Turns what somebody wrote down into a number: LaTeX out of a lecture, the
/// `**` a model picked up from Python, a comma where a Russian keyboard puts
/// the decimal point.
///
/// Hand-written rather than `NSExpression`, which raises Objective-C
/// exceptions that Swift cannot catch — one stray bracket took the whole app
/// down with it.
enum Formula {

    struct Failure: Error {}

    // MARK: LaTeX and other dialects

    static func plain(_ source: String) -> String {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // Delimiters and spacing macros mean nothing outside a document.
        for noise in ["$$", "$", "\\displaystyle", "\\limits", "\\left", "\\right",
                      "\\!", "\\,", "\\;", "\\:", "\\quad", "\\qquad", "\\[", "\\]", "\\(", "\\)"] {
            text = text.replacingOccurrences(of: noise, with: "")
        }

        for fraction in ["\\dfrac", "\\tfrac", "\\frac"] {
            text = expand(fraction, arity: 2, in: text) { "((\($0[0]))/(\($0[1])))" }
        }
        text = expand("\\sqrt", arity: 1, in: text) { parts in
            parts.count > 1 ? "((\(parts[0]))^(1/(\(parts[1]))))" : "sqrt(\(parts[0]))"
        }

        for name in ["arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "sin", "cos",
                     "tan", "cot", "ctg", "tg", "sqrt", "exp", "ln", "lg", "log", "abs", "max", "min"] {
            text = text.replacingOccurrences(of: "\\" + name, with: name)
        }
        for (macro, symbol) in ["\\cdot": "*", "\\times": "*", "\\ast": "*", "\\div": "/",
                                "\\pi": "pi", "\\tau": "tau", "\\cdotp": "*"] {
            text = text.replacingOccurrences(of: macro, with: symbol)
        }

        // Subscripts are labels on a variable, not arithmetic.
        text = replacing(#"_\{[^{}]*\}|_[A-Za-z0-9]"#, in: text, with: "")

        text = text.replacingOccurrences(of: "{", with: "(")
        text = text.replacingOccurrences(of: "}", with: ")")
        text = text.replacingOccurrences(of: "**", with: "^")
        text = text.replacingOccurrences(of: "∫", with: "int")
        text = text.replacingOccurrences(of: "Σ", with: "sum")
        text = text.replacingOccurrences(of: "√", with: "sqrt")
        // A comma is the decimal point on a Russian keyboard — except inside
        // `int(x^2, 0, 1)`, where it is what holds the three arguments apart.
        // Both cannot be true of one string, so wherever a name that takes
        // arguments appears, the comma keeps its other meaning.
        let lowered = text.lowercased()
        if !blocks.contains(where: { lowered.contains($0 + "(") }) {
            text = replacing(#"(?<=[0-9]),(?=[0-9])"#, in: text, with: ".")
        }

        // `y = x^2` and `f(x) = x^2` are how a function gets written down; only
        // the right-hand side can be drawn.
        if let equals = text.range(of: "="), text.distance(from: text.startIndex, to: equals.lowerBound) <= 6 {
            text = String(text[equals.upperBound...])
        }

        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Pulls the braced arguments that follow a command and hands them to a
    /// builder. Done by hand because the arguments nest: the numerator of a
    /// fraction is often another fraction, and no regular expression counts
    /// braces.
    private static func expand(_ command: String, arity: Int, in source: String,
                               build: ([String]) -> String) -> String {
        var text = source
        var passes = 0

        while let found = text.range(of: command), passes < 64 {
            passes += 1
            var cursor = found.upperBound
            var arguments: [String] = []
            var index: String?

            // \sqrt[3]{x} — the root's degree, when it is not a square root.
            if cursor < text.endIndex, text[cursor] == "[",
               let close = matching(in: text, from: cursor, open: "[", shut: "]") {
                index = String(text[text.index(after: cursor)..<close])
                cursor = text.index(after: close)
            }

            var complete = true
            for _ in 0..<arity {
                while cursor < text.endIndex, text[cursor] == " " { cursor = text.index(after: cursor) }
                guard cursor < text.endIndex, text[cursor] == "{",
                      let close = matching(in: text, from: cursor, open: "{", shut: "}") else {
                    complete = false
                    break
                }
                arguments.append(String(text[text.index(after: cursor)..<close]))
                cursor = text.index(after: close)
            }
            // Half-typed: leave it exactly as it is and stop looking.
            guard complete else { break }

            if let index { arguments.append(index) }
            text.replaceSubrange(found.lowerBound..<cursor, with: build(arguments))
        }
        return text
    }

    private static func matching(in text: String, from start: String.Index,
                                 open: Character, shut: Character) -> String.Index? {
        var depth = 0
        var cursor = start
        while cursor < text.endIndex {
            if text[cursor] == open { depth += 1 }
            if text[cursor] == shut {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text,
                                              range: NSRange(text.startIndex..., in: text),
                                              withTemplate: template)
    }

    // MARK: Reading

    private enum Token: Equatable {
        case number(Double)
        case name(String)
        case symbol(Character)
        case open, shut
    }

    private static func scan(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var i = 0

        while i < characters.count {
            let c = characters[i]
            if c == " " || c == "\n" || c == "\t" { i += 1; continue }

            if c.isNumber || (c == "." && i + 1 < characters.count && characters[i + 1].isNumber) {
                var digits = ""
                while i < characters.count, characters[i].isNumber || characters[i] == "." {
                    digits.append(characters[i]); i += 1
                }
                // 1e-9 is one number, not a number times a constant.
                if i < characters.count, characters[i] == "e" || characters[i] == "E" {
                    let after = i + 1 < characters.count ? characters[i + 1] : " "
                    let signed = (after == "+" || after == "-") && i + 2 < characters.count && characters[i + 2].isNumber
                    if after.isNumber || signed {
                        digits.append("e"); i += 1
                        if characters[i] == "+" || characters[i] == "-" { digits.append(characters[i]); i += 1 }
                        while i < characters.count, characters[i].isNumber { digits.append(characters[i]); i += 1 }
                    }
                }
                guard let value = Double(digits) else { throw Failure() }
                tokens.append(.number(value))
                continue
            }

            if c.isLetter {
                var word = ""
                while i < characters.count, characters[i].isLetter || characters[i].isNumber {
                    word.append(characters[i]); i += 1
                }
                tokens.append(.name(word.lowercased()))
                continue
            }

            switch c {
            case "(", "[": tokens.append(.open)
            case ")", "]": tokens.append(.shut)
            case "+", "-", "*", "/", "%", "^", "!", ",": tokens.append(.symbol(c))
            case ";": tokens.append(.symbol(","))
            case "−", "–": tokens.append(.symbol("-"))
            case "×", "·", "⋅": tokens.append(.symbol("*"))
            case "÷", ":": tokens.append(.symbol("/"))
            default: throw Failure()
            }
            i += 1
        }
        return tokens
    }

    private static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi
    ]

    /// The four names that take more than one argument, and the only ones whose
    /// first argument is a formula rather than a number: the integral and the
    /// sum have to evaluate it at four hundred different x, the derivative at
    /// two. Everything they return is worked out here, in Double arithmetic —
    /// nothing symbolic, nothing guessed.
    static let blocks: Set<String> = ["int", "sum", "deriv", "det"]

    private static let functions: [String: (Double) -> Double] = [
        "sin": sin, "cos": cos, "tan": tan, "tg": tan,
        "cot": { 1 / tan($0) }, "ctg": { 1 / tan($0) },
        "asin": asin, "acos": acos, "atan": atan,
        "arcsin": asin, "arccos": acos, "arctan": atan,
        "sinh": sinh, "cosh": cosh, "tanh": tanh,
        "sqrt": sqrt, "cbrt": cbrt,
        "ln": log, "log": log, "lg": log10, "log10": log10, "log2": log2,
        "exp": exp, "abs": abs,
        "floor": floor, "ceil": ceil, "round": { $0.rounded() },
        "sign": { $0 == 0 ? 0 : ($0 < 0 ? -1 : 1) }
    ]

    private struct Reader {
        let tokens: [Token]
        let x: Double?
        var at = 0

        var current: Token? { at < tokens.count ? tokens[at] : nil }

        mutating func sum() throws -> Double {
            var value = try product()
            while case .symbol(let c)? = current, c == "+" || c == "-" {
                at += 1
                let next = try product()
                value = c == "+" ? value + next : value - next
            }
            return value
        }

        mutating func product() throws -> Double {
            var value = try signed()
            while true {
                if case .symbol(let c)? = current, c == "*" || c == "/" || c == "%" {
                    at += 1
                    let next = try signed()
                    switch c {
                    case "*": value *= next
                    case "/":
                        guard next != 0 else { throw Failure() }
                        value /= next
                    default:
                        guard next != 0 else { throw Failure() }
                        value = value.truncatingRemainder(dividingBy: next)
                    }
                    continue
                }
                // 2x and 3(4+5) are multiplication with the sign left out.
                switch current {
                case .number, .name, .open: value *= try signed()
                default: return value
                }
            }
        }

        mutating func signed() throws -> Double {
            if case .symbol(let c)? = current, c == "-" || c == "+" {
                at += 1
                let value = try signed()
                return c == "-" ? -value : value
            }
            return try raised()
        }

        mutating func raised() throws -> Double {
            let base = try atom()
            guard case .symbol("^")? = current else { return base }
            at += 1
            // Right to left, and the exponent may carry its own sign.
            let exponent = try signed()
            let value = pow(base, exponent)
            guard value.isFinite else { throw Failure() }
            return value
        }

        /// Factorial is written after the thing it applies to, so it is read
        /// after it too: `5!`, `(n+1)!`, and `4!!` for whoever wants it.
        mutating func atom() throws -> Double {
            var value = try primary()
            while case .symbol("!")? = current {
                at += 1
                value = try Formula.factorial(value)
            }
            return value
        }

        mutating func primary() throws -> Double {
            guard let token = current else { throw Failure() }
            at += 1

            switch token {
            case .number(let value):
                return value

            case .open:
                let value = try sum()
                guard case .shut? = current else { throw Failure() }
                at += 1
                return value

            case .name(let word):
                if word == "x" || word == "х" {
                    guard let x else { throw Failure() }
                    return x
                }
                if let constant = constants[word] { return constant }

                if blocks.contains(word) {
                    guard case .open? = current else { throw Failure() }
                    at += 1
                    return try Formula.evaluate(word, arguments: try arguments(), x: x)
                }

                guard let function = functions[word] else { throw Failure() }
                guard case .open? = current else { throw Failure() }
                at += 1
                let argument = try sum()
                guard case .shut? = current else { throw Failure() }
                at += 1
                let value = function(argument)
                guard value.isFinite else { throw Failure() }
                return value

            default:
                throw Failure()
            }
        }

        /// The arguments of a multi-argument name, split at the commas that
        /// belong to it and handed back unread.
        ///
        /// They cannot be evaluated on the way past: the first argument of an
        /// integral is a function of x, and the whole point is to run it at
        /// hundreds of values of x that nothing outside the brackets knows about.
        mutating func arguments() throws -> [[Token]] {
            var parts: [[Token]] = []
            var piece: [Token] = []
            var depth = 0

            while at < tokens.count {
                let token = tokens[at]
                if token == .shut, depth == 0 {
                    at += 1
                    parts.append(piece)
                    return parts
                }
                if token == .open { depth += 1 }
                if token == .shut { depth -= 1 }
                if depth == 0, token == .symbol(",") {
                    parts.append(piece)
                    piece = []
                    at += 1
                    continue
                }
                piece.append(token)
                at += 1
            }
            // Ran off the end without a closing bracket.
            throw Failure()
        }
    }

    // MARK: Written the way it is written by hand

    /// `sqrt(x^2+1)/2` as `√(x²+1)/2`.
    ///
    /// Only for showing a sum that is already done: the display keeps the plain
    /// text, because that is the thing being edited and a caret cannot be put
    /// between a number and its own superscript. A finished sum is read, not
    /// typed, and reading `x^2 - 4` is reading punctuation.
    static func pretty(_ source: String) -> String {
        var text = source

        for (plain, sign) in [("sqrt(", "√("), ("int(", "∫("), ("sum(", "Σ("),
                              ("deriv(", "d/dx("), ("pi", "π"), ("*", "·"),
                              ("<=", "≤"), (">=", "≥"), ("!=", "≠"), ("inf", "∞")] {
            text = text.replacingOccurrences(of: plain, with: sign)
        }

        // Powers, as long as they are whole numbers: x^12 is x¹², and x^(n+1)
        // stays as it is rather than becoming half a superscript.
        let digits = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
                      "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "^" else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            var cursor = text.index(after: index)
            var raised = ""
            while cursor < text.endIndex, let glyph = digits[String(text[cursor])] {
                // A minus is part of the power only as its first character:
                // x^12-4 is x¹² minus four, not x to the twelve-minus-four.
                if text[cursor] == "-", !raised.isEmpty { break }
                raised += glyph
                cursor = text.index(after: cursor)
            }
            if raised.isEmpty {
                result.append("^")
                index = text.index(after: index)
            } else {
                result += raised
                index = cursor
            }
        }
        return result
    }

    // MARK: The integral with no limits

    /// `int(x^2)dx` — an integral written the way it is written in a textbook,
    /// with no limits on it. There is no number to give back, so it gives back
    /// the function whose slope is the one inside.
    ///
    /// Nothing here is a computer algebra system: it splits the expression into
    /// terms at the top level and integrates each one by the rules everybody
    /// learns first — powers of x, sine, cosine, e^x, 1/x. Anything past that
    /// returns nil and the panel says to add limits instead, which is what the
    /// numeric side is for. It exists because the complaint was the honest one:
    /// pressing ∫ and typing what a textbook prints produced nothing at all.
    static func indefinite(_ source: String) -> String? {
        // "int (x^2) dx" is how it gets typed; the spaces are typing, not maths.
        var text = source.replacingOccurrences(of: " ", with: "")
        // The dx at the end is grammar, not arithmetic.
        text = replacing(#"d\s*x$"#, in: text, with: "")
        guard text.lowercased().hasPrefix("int(") else { return nil }

        let body = String(text.dropFirst(4))
        guard body.hasSuffix(")") else { return nil }
        let inside = String(body.dropLast())
        // A comma means limits were given after all: that one is a number, and
        // the evaluator has already worked it out.
        guard !inside.contains(",") else { return nil }
        guard let result = antiderivative(of: inside) else { return nil }
        return result + " + C"
    }

    /// The terms of a sum, integrated one at a time.
    private static func antiderivative(of expression: String) -> String? {
        let terms = split(expression)
        guard !terms.isEmpty else { return nil }

        var pieces: [String] = []
        for (sign, term) in terms {
            guard let part = integrateTerm(term) else { return nil }
            pieces.append(pieces.isEmpty ? (sign == "-" ? "-" + part : part)
                                         : " \(sign) " + part)
        }
        return pieces.joined()
    }

    /// Breaks a sum into signed terms without touching what is inside brackets.
    private static func split(_ expression: String) -> [(String, String)] {
        var terms: [(String, String)] = []
        var current = ""
        var sign = "+"
        var depth = 0
        var previous: Character?

        for character in expression {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            // A plus after ^ or ( is part of the number, not a join between two
            // terms: x^-2 and (-3) both survive this way.
            let joins = depth == 0 && (character == "+" || character == "-")
                && previous != nil && previous != "^" && previous != "(" && previous != "*" && previous != "/"
            if joins {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    terms.append((sign, current.trimmingCharacters(in: .whitespaces)))
                }
                sign = String(character)
                current = ""
            } else if character == "-", previous == nil {
                sign = "-"
            } else {
                current.append(character)
            }
            if character != " " { previous = character }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { terms.append((sign, last)) }
        return terms
    }

    /// One term. Everything it knows how to integrate is in this switch.
    private static func integrateTerm(_ raw: String) -> String? {
        let term = raw.replacingOccurrences(of: " ", with: "")
        guard !term.isEmpty else { return nil }

        // The named ones, with an optional constant in front: 3sin(x).
        for (pattern, result) in [("sin(x)", "-cos(x)"), ("cos(x)", "sin(x)"),
                                  ("e^x", "e^x"), ("exp(x)", "e^x"),
                                  ("1/x", "ln|x|"), ("sqrt(x)", "(2/3)*x^1.5")] {
            if term == pattern { return result }
            if term.hasSuffix(pattern) {
                let head = String(term.dropLast(pattern.count)).replacingOccurrences(of: "*", with: "")
                guard let factor = Double(head) else { continue }
                if factor == 1 { return result }
                // "2*-cos(x)" is not how anybody writes it: the minus belongs in
                // front of the number.
                if result.hasPrefix("-") {
                    return "-" + trim(factor) + "*" + String(result.dropFirst())
                }
                return trim(factor) + "*" + result
            }
        }

        // c, c*x, c*x^n — the whole of what a polynomial is made of.
        guard let match = firstMatch(#"^([0-9.]*)\*?(x(\^(-?[0-9.]+))?)?$"#, in: term) else { return nil }
        let coefficient = match[1].isEmpty ? 1 : Double(match[1]) ?? 1
        let hasX = !match[2].isEmpty
        let power = match[4].isEmpty ? (hasX ? 1.0 : 0.0) : (Double(match[4]) ?? 1)

        if !hasX { return coefficient == 1 ? "x" : trim(coefficient) + "*x" }
        // The one power the rule does not cover.
        if power == -1 { return coefficient == 1 ? "ln|x|" : trim(coefficient) + "*ln|x|" }

        let raised = power + 1
        let factor = coefficient / raised
        let stem = raised == 1 ? "x" : "x^\(trim(raised))"
        if factor == 1 { return stem }
        // A third is written as a division, the way it is written by hand:
        // x^3/3 rather than 0.333333*x^3.
        let inverse = 1 / factor
        if inverse == inverse.rounded(), abs(inverse) < 1e6 {
            // Dividing by one is not a division.
            if abs(inverse) == 1 { return inverse < 0 ? "-" + stem : stem }
            return inverse < 0 ? "-\(stem)/\(trim(-inverse))" : "\(stem)/\(trim(inverse))"
        }
        return trim(factor) + "*" + stem
    }

    /// Numbers the way a person writes them: 2, not 2.0; 1/3 stays 0.333333.
    private static func trim(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e12
            ? String(Int(value))
            : String(format: "%g", value)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    // MARK: The four that take arguments

    /// One slice of tokens, worked out at one value of x.
    private static func number(_ tokens: [Token], x: Double?) -> Double? {
        guard !tokens.isEmpty else { return nil }
        var reader = Reader(tokens: tokens, x: x)
        guard let value = try? reader.sum(), reader.at == tokens.count, value.isFinite else { return nil }
        return value
    }

    private static func evaluate(_ name: String, arguments: [[Token]], x: Double?) throws -> Double {
        switch name {
        case "int":
            guard arguments.count == 3,
                  let low = number(arguments[1], x: x),
                  let high = number(arguments[2], x: x) else { throw Failure() }
            return try integral(arguments[0], from: low, to: high)

        case "sum":
            guard arguments.count == 3,
                  let low = number(arguments[1], x: x),
                  let high = number(arguments[2], x: x) else { throw Failure() }
            let first = Int(low.rounded())
            let last = Int(high.rounded())
            // A hundred thousand terms is already more than anybody typed on
            // purpose, and the panel must not sit there adding for a minute.
            guard last >= first, last - first <= 100_000 else { throw Failure() }
            var total = 0.0
            for step in first...last {
                guard let term = number(arguments[0], x: Double(step)) else { throw Failure() }
                total += term
            }
            guard total.isFinite else { throw Failure() }
            return total

        case "deriv":
            guard arguments.count == 2, let point = number(arguments[1], x: x) else { throw Failure() }
            // Central difference: the slope of the chord across the point,
            // which is right to about ten figures for anything smooth.
            let step = max(abs(point), 1) * 1e-6
            guard let ahead = number(arguments[0], x: point + step),
                  let behind = number(arguments[0], x: point - step) else { throw Failure() }
            let slope = (ahead - behind) / (2 * step)
            guard slope.isFinite else { throw Failure() }
            return slope

        case "det":
            var values: [Double] = []
            for argument in arguments {
                guard let value = number(argument, x: x) else { throw Failure() }
                values.append(value)
            }
            return try determinant(values)

        default:
            throw Failure()
        }
    }

    /// Simpson's rule over four hundred strips. Exact for anything up to a
    /// cubic, and inside a rounding error of the truth for the rest — which is
    /// the honest thing to offer, since nothing here does symbolic algebra.
    private static func integral(_ tokens: [Token], from: Double, to: Double) throws -> Double {
        guard from.isFinite, to.isFinite else { throw Failure() }
        guard from != to else { return 0 }

        let steps = 400
        let width = (to - from) / Double(steps)
        guard let start = number(tokens, x: from), let end = number(tokens, x: to) else { throw Failure() }

        var total = start + end
        for index in 1..<steps {
            guard let value = number(tokens, x: from + Double(index) * width) else { throw Failure() }
            total += value * (index % 2 == 0 ? 2 : 4)
        }

        let area = total * width / 3
        guard area.isFinite else { throw Failure() }
        return area
    }

    /// The determinant of a square matrix written out row by row: four numbers
    /// are a 2×2, nine are a 3×3, sixteen a 4×4. Gaussian elimination with a
    /// pivot, so a zero in the corner is not a failure.
    private static func determinant(_ values: [Double]) throws -> Double {
        let size = Int(Double(values.count).squareRoot().rounded())
        guard size >= 1, size * size == values.count, size <= 6 else { throw Failure() }

        var rows = (0..<size).map { row in Array(values[row * size ..< (row + 1) * size]) }
        var result = 1.0

        for column in 0..<size {
            var pivot = column
            for row in column..<size where abs(rows[row][column]) > abs(rows[pivot][column]) {
                pivot = row
            }
            guard abs(rows[pivot][column]) > 1e-12 else { return 0 }
            if pivot != column {
                rows.swapAt(pivot, column)
                result = -result
            }
            let head = rows[column][column]
            result *= head
            for row in (column + 1)..<size {
                let factor = rows[row][column] / head
                guard factor != 0 else { continue }
                for cell in column..<size {
                    rows[row][cell] -= factor * rows[column][cell]
                }
            }
        }

        guard result.isFinite else { throw Failure() }
        return result
    }

    /// Gamma, which is what a factorial is once it stops being a count: 5! is
    /// 120 and 0.5! is the number it has to be for the curve through the
    /// integers to be smooth.
    private static func factorial(_ value: Double) throws -> Double {
        guard value > -1, value < 171 else { throw Failure() }
        let result = tgamma(value + 1)
        guard result.isFinite else { throw Failure() }
        return result
    }

    static func value(of text: String, x: Double? = nil) throws -> Double {
        let tokens = try scan(text)
        guard !tokens.isEmpty else { throw Failure() }
        var reader = Reader(tokens: tokens, x: x)
        let value = try reader.sum()
        // Trailing rubbish means the whole thing was misread.
        guard reader.at == tokens.count, value.isFinite else { throw Failure() }
        return value
    }

    static func usesX(_ text: String) -> Bool {
        guard let tokens = try? scan(text) else { return false }
        return tokens.contains(.name("x")) || tokens.contains(.name("х"))
    }

    /// One tokenising pass, many values: the plot asks for a couple of hundred
    /// points every time the cursor moves.
    static func curve(_ text: String, from: Double, to: Double, count: Int) -> [Double?] {
        guard count > 1, let tokens = try? scan(text), !tokens.isEmpty else {
            return Array(repeating: nil, count: max(count, 0))
        }
        let step = (to - from) / Double(count - 1)
        return (0..<count).map { index in
            var reader = Reader(tokens: tokens, x: from + Double(index) * step)
            guard let value = try? reader.sum(), reader.at == tokens.count, value.isFinite else { return nil }
            return value
        }
    }

    /// Where the curve crosses zero inside the window on screen.
    ///
    /// Sign changes first, then the gap is halved forty times, which lands
    /// within a hair of the crossing for anything a panel can draw. Two limits
    /// keep it honest: a curve that dips below zero and back between two samples
    /// is invisible to it, and a jump across an asymptote changes sign without
    /// crossing anything — that one is thrown out by size.
    static func roots(_ text: String, from: Double, to: Double, count: Int = 400) -> [Double] {
        guard count > 1, to > from, let tokens = try? scan(text), !tokens.isEmpty else { return [] }

        func evaluate(_ x: Double) -> Double? {
            var reader = Reader(tokens: tokens, x: x)
            guard let value = try? reader.sum(), reader.at == tokens.count, value.isFinite else { return nil }
            return value
        }

        let step = (to - from) / Double(count)
        var found: [Double] = []
        var lastX = from
        var lastY = evaluate(from)

        for index in 1...count {
            let x = from + Double(index) * step
            let y = evaluate(x)

            if let previous = lastY, let current = y {
                if previous == 0 {
                    found.append(lastX)
                } else if current != 0, (previous < 0) != (current < 0),
                          abs(previous) + abs(current) < 1e9 {
                    found.append(bisect(low: lastX, high: x, evaluate: evaluate))
                }
            }

            lastX = x
            lastY = y
        }

        // Eight is as many as the line under the plot can spell out, and more
        // than that means the window is too wide to read anyway.
        return Array(found.prefix(8))
    }

    private static func bisect(low: Double, high: Double, evaluate: (Double) -> Double?) -> Double {
        var low = low
        var high = high
        guard let start = evaluate(low) else { return low }
        let startsBelow = start < 0

        for _ in 0..<40 {
            let middle = (low + high) / 2
            guard let value = evaluate(middle) else { return middle }
            if value == 0 { return middle }
            if (value < 0) == startsBelow { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(format: "%.6g", value)
    }

    /// The same number for a label on an axis, where six significant figures of
    /// a window nobody chose — "-13.4929" — is precision about an accident.
    static func brief(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e9 { return String(Int(value)) }
        return String(format: "%.3g", value)
    }
}
