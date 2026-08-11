import AppKit

/// Translation, online first and locally when there is no line out.
///
/// Google has no free official API, so the online path uses the endpoint its own
/// web widget calls — no key, no account, and no promise from Google that it
/// will stay. When it fails for any reason at all, the same sentence goes to the
/// model already installed on this machine instead. Nothing is ever lost to a
/// dead network; it only gets slower.
final class TranslateStore: ObservableObject {

    struct Language: Identifiable, Equatable {
        let code: String
        /// What the local model is told to produce, in its own words. Doubles as
        /// the name shown in the picker.
        let englishName: String
        var id: String { code }
        /// The two or three letters on the button itself.
        var title: String { code.uppercased() }
    }

    /// Everything Google's endpoint answers for, in one list. Three chips were
    /// enough while the tab only ever went RU/EN/ZH; a language that is not on
    /// the row is not translatable at all, which is a strange thing for a
    /// translator to be.
    static let languages: [Language] = [
        ("af", "Afrikaans"), ("sq", "Albanian"), ("am", "Amharic"), ("ar", "Arabic"),
        ("hy", "Armenian"), ("az", "Azerbaijani"), ("eu", "Basque"), ("be", "Belarusian"),
        ("bn", "Bengali"), ("bs", "Bosnian"), ("bg", "Bulgarian"), ("ca", "Catalan"),
        ("ceb", "Cebuano"), ("ny", "Chichewa"), ("zh", "Chinese"), ("zh-TW", "Chinese (Traditional)"),
        ("co", "Corsican"), ("hr", "Croatian"), ("cs", "Czech"), ("da", "Danish"),
        ("nl", "Dutch"), ("en", "English"), ("eo", "Esperanto"), ("et", "Estonian"),
        ("tl", "Filipino"), ("fi", "Finnish"), ("fr", "French"), ("fy", "Frisian"),
        ("gl", "Galician"), ("ka", "Georgian"), ("de", "German"), ("el", "Greek"),
        ("gu", "Gujarati"), ("ht", "Haitian Creole"), ("ha", "Hausa"), ("haw", "Hawaiian"),
        ("iw", "Hebrew"), ("hi", "Hindi"), ("hmn", "Hmong"), ("hu", "Hungarian"),
        ("is", "Icelandic"), ("ig", "Igbo"), ("id", "Indonesian"), ("ga", "Irish"),
        ("it", "Italian"), ("ja", "Japanese"), ("jw", "Javanese"), ("kn", "Kannada"),
        ("kk", "Kazakh"), ("km", "Khmer"), ("rw", "Kinyarwanda"), ("ko", "Korean"),
        ("ku", "Kurdish"), ("ky", "Kyrgyz"), ("lo", "Lao"), ("la", "Latin"),
        ("lv", "Latvian"), ("lt", "Lithuanian"), ("lb", "Luxembourgish"), ("mk", "Macedonian"),
        ("mg", "Malagasy"), ("ms", "Malay"), ("ml", "Malayalam"), ("mt", "Maltese"),
        ("mi", "Maori"), ("mr", "Marathi"), ("mn", "Mongolian"), ("my", "Burmese"),
        ("ne", "Nepali"), ("no", "Norwegian"), ("or", "Odia"), ("ps", "Pashto"),
        ("fa", "Persian"), ("pl", "Polish"), ("pt", "Portuguese"), ("pa", "Punjabi"),
        ("ro", "Romanian"), ("ru", "Russian"), ("sm", "Samoan"), ("gd", "Scots Gaelic"),
        ("sr", "Serbian"), ("st", "Sesotho"), ("sn", "Shona"), ("sd", "Sindhi"),
        ("si", "Sinhala"), ("sk", "Slovak"), ("sl", "Slovenian"), ("so", "Somali"),
        ("es", "Spanish"), ("su", "Sundanese"), ("sw", "Swahili"), ("sv", "Swedish"),
        ("tg", "Tajik"), ("ta", "Tamil"), ("tt", "Tatar"), ("te", "Telugu"),
        ("th", "Thai"), ("tr", "Turkish"), ("tk", "Turkmen"), ("uk", "Ukrainian"),
        ("ur", "Urdu"), ("ug", "Uyghur"), ("uz", "Uzbek"), ("vi", "Vietnamese"),
        ("cy", "Welsh"), ("xh", "Xhosa"), ("yi", "Yiddish"), ("yo", "Yoruba"),
        ("zu", "Zulu")
    ].map { Language(code: $0.0, englishName: $0.1) }

    /// The ones this Mac reaches for, kept at the top of the picker so the
    /// common case is never a scroll through a hundred names.
    static let favourites = ["ru", "en", "kk", "zh"]

    static func name(of code: String) -> String {
        if code == "auto" { return "Detect" }
        return languages.first { $0.code == code }?.englishName ?? code.uppercased()
    }

    enum Engine: Equatable {
        case idle
        case online
        case local(String)
        case failed(String)
    }

    @Published var input = "" { didSet { scheduleTranslate() } }
    @Published private(set) var output = ""
    @Published private(set) var engine: Engine = .idle
    @Published private(set) var isWorking = false
    @Published var source = "auto" {
        didSet {
            // A language pointed at itself answers every sentence with the
            // sentence. Whichever end was just changed keeps the new language
            // and the other end steps aside.
            if source == target { target = oldValue == "auto" ? "en" : oldValue }
            remember(); translate(); loadSample()
        }
    }
    @Published var target = "ru" {
        didSet {
            if target == source { source = "auto" }
            remember(); translate(); loadSample()
        }
    }
    @Published private(set) var localModel = ""
    /// The greeting in the language being translated *from*, shown in the empty
    /// input box.
    @Published private(set) var sourceSample = "hello"
    /// The same greeting in the language being translated *to*.
    ///
    /// An empty translator is two empty boxes, and two empty boxes look like a
    /// tab that failed to load. One real word, really translated on both sides,
    /// says what the tab does without a line of instructions telling anyone —
    /// and says it in the two languages actually picked, which is what "hello →
    /// hello" was failing to do.
    @Published private(set) var sample = ""

    private var pending: DispatchWorkItem?
    private var generation = 0
    /// Placeholders have their own ticket. Changing a language fires two
    /// requests, and the answer to the language before last must not land in
    /// the box after it.
    private var sampleTicket = 0
    private static let sourceKey = "translate.source"
    private static let targetKey = "translate.target"

    init() {
        source = UserDefaults.standard.string(forKey: Self.sourceKey) ?? "auto"
        target = UserDefaults.standard.string(forKey: Self.targetKey) ?? "ru"
    }

    func activate() {
        Ollama.pickModel { [weak self] model in
            self?.localModel = model ?? ""
        }
        loadSample()
    }

    /// The greeting, in both of the languages on screen.
    ///
    /// Google only, and quietly: a placeholder is not worth waking the local
    /// model for, and not worth an error message if the line is down. English is
    /// answered without asking anyone — "hello" is already English, and asking
    /// Google to translate it into English is the round trip that made changing
    /// the language feel slow and answered "hello" with "hello".
    private func loadSample() {
        sampleTicket += 1
        let ticket = sampleTicket
        let wantedSource = source
        let wantedTarget = target

        if wantedSource == "auto" || wantedSource == "en" {
            sourceSample = "hello"
        } else {
            online("hello", from: "en", to: wantedSource) { [weak self] translated in
                guard let self, ticket == self.sampleTicket else { return }
                self.sourceSample = translated ?? "hello"
            }
        }

        if wantedTarget == "en" {
            sample = "hello"
            return
        }
        online("hello", from: "en", to: wantedTarget) { [weak self] translated in
            guard let self, ticket == self.sampleTicket else { return }
            self.sample = translated ?? ""
        }
    }

    func clear() {
        input = ""
        output = ""
        engine = .idle
    }

    func swap() {
        guard source != "auto" else {
            source = target
            target = "en"
            return
        }
        let held = source
        source = target
        target = held
        input = output
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    // MARK: - Driving

    /// Typing should not fire a request per keystroke, and a pause is the signal
    /// that a phrase is finished.
    private func scheduleTranslate() {
        pending?.cancel()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            output = ""
            engine = .idle
            isWorking = false
            return
        }
        let task = DispatchWorkItem { [weak self] in self?.translate() }
        pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: task)
    }

    func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generation += 1
        let ticket = generation
        isWorking = true

        online(text) { [weak self] translated in
            guard let self, ticket == self.generation else { return }
            if let translated, !translated.isEmpty {
                self.output = translated
                self.engine = .online
                self.isWorking = false
                return
            }
            // No line out, or Google closed the door. The model on this machine
            // answers the same question.
            self.offline(text, ticket: ticket)
        }
    }

    // MARK: - Online

    private func online(_ text: String,
                        from: String? = nil,
                        to: String? = nil,
                        completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: from ?? source),
            URLQueryItem(name: "tl", value: to ?? target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [Any],
                      let segments = payload.first as? [Any] else {
                    completion(nil)
                    return
                }
                // [[["перевод","source",…],…],…] — the pieces of a long text come
                // back as separate rows and have to be sewn together.
                let joined = segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
                completion(joined.isEmpty ? nil : joined)
            }
        }.resume()
    }

    // MARK: - Local

    private func offline(_ text: String, ticket: Int) {
        let language = Self.languages.first { $0.code == target }?.englishName ?? "Russian"
        let prompt = """
        Translate the text between the markers into \(language). \
        Reply with the translation only: no quotes, no notes, no original.
        <<<\(text)>>>
        """

        Ollama.complete(prompt: prompt, model: localModel) { [weak self] answer in
            guard let self, ticket == self.generation else { return }
            self.isWorking = false
            guard let answer, !answer.isEmpty else {
                self.engine = .failed("No connection, and no local model answered")
                return
            }
            self.output = answer
            self.engine = .local(self.localModel)
        }
    }

    private func remember() {
        UserDefaults.standard.set(source, forKey: Self.sourceKey)
        UserDefaults.standard.set(target, forKey: Self.targetKey)
    }
}

/// The one place that talks to Ollama, shared by the calculator and the
/// translator so a model is picked the same way for both.
enum Ollama {
    static let host = "http://127.0.0.1:11434"

    /// The installed model best suited to a sentence: the biggest one that
    /// still fits comfortably, judged by what is actually pulled on this Mac.
    static func pickModel(_ completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: host + "/api/tags")!)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = payload["models"] as? [[String: Any]] else {
                    completion(nil)
                    return
                }
                let names = models.compactMap { $0["name"] as? String }
                // Anything over about 12 GB does not fit this machine's memory
                // and answers by swapping, which takes minutes.
                let sized = models.compactMap { model -> (String, Int)? in
                    guard let name = model["name"] as? String,
                          let size = model["size"] as? Int else { return nil }
                    return (name, size)
                }
                let fitting = sized.filter { $0.1 < 12_000_000_000 }.sorted { $0.1 > $1.1 }
                completion(fitting.first?.0 ?? names.first)
            }
        }.resume()
    }

    static func complete(prompt: String, model: String, completion: @escaping (String?) -> Void) {
        guard !model.isEmpty else {
            completion(nil)
            return
        }
        var request = URLRequest(url: URL(string: host + "/api/generate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.1]
        ])

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let response = payload["response"] as? String else {
                    completion(nil)
                    return
                }
                completion(response.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.resume()
    }
}
