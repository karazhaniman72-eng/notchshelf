import AppKit
import Security

/// Generated passwords, and what each one was for.
///
/// The password itself never touches a file: it goes into the login keychain,
/// the same place Safari keeps its own. What is written to disk is a label and a
/// date, which is the part worth reading in a panel.
final class PasswordStore: ObservableObject {

    struct Entry: Identifiable, Codable, Equatable {
        let id: String
        let label: String
        let created: Date

        var dateLabel: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = Calendar.current.isDateInToday(created) ? "HH:mm" : "d MMM"
            return formatter.string(from: created)
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var candidate = ""
    /// Set while the panel is asking what the password is for.
    @Published var isNaming = false
    @Published var length = 20 { didSet { remember(); generate() } }
    @Published var useSymbols = true { didSet { remember(); generate() } }
    @Published private(set) var note = ""

    private static let listKey = "passwords.entries"
    private static let lengthKey = "passwords.length"
    private static let symbolsKey = "passwords.symbols"
    private static let service = "NotchShelf"

    init() {
        if let stored = UserDefaults.standard.object(forKey: Self.lengthKey) as? Int { length = stored }
        if let stored = UserDefaults.standard.object(forKey: Self.symbolsKey) as? Bool { useSymbols = stored }
        if let data = UserDefaults.standard.data(forKey: Self.listKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        generate()
    }

    // MARK: - Making one

    /// `SecRandomCopyBytes`, not `Int.random`: a password is exactly the case
    /// where the generator has to be the cryptographic one.
    func generate() {
        let letters = "abcdefghijkmnopqrstuvwxyz"
        let capitals = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        let digits = "23456789"
        let symbols = "!@#$%^&*-_=+?"
        // No l, I, 0, O anywhere: a password gets read aloud and typed by hand
        // often enough that the lookalikes cost more than they add.
        let alphabet = Array(letters + capitals + digits + (useSymbols ? symbols : ""))

        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else {
            note = "The system refused to produce random bytes"
            return
        }
        candidate = String(bytes.map { alphabet[Int($0) % alphabet.count] })
        note = ""
    }

    /// Strength, said the way a person would: how long the alphabet is and how
    /// many of them there are, turned into bits.
    var strength: String {
        let alphabet = Double(useSymbols ? 70 : 57)
        let bits = Double(length) * log2(alphabet)
        switch bits {
        case ..<60: return "weak · \(Int(bits)) bits"
        case ..<80: return "fair · \(Int(bits)) bits"
        case ..<110: return "strong · \(Int(bits)) bits"
        default: return "overkill · \(Int(bits)) bits"
        }
    }

    // MARK: - Taking one

    /// Copying is what makes a password real, so that is the moment it asks
    /// what it is for — not a step earlier and never afterwards.
    ///
    /// The copy happens here, before the question. It used to happen only after
    /// the question was answered, so pressing the button and then pressing
    /// Enter on an empty name copied nothing, kept nothing and said nothing —
    /// the button promised two things and did neither.
    func take() {
        guard !candidate.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(candidate, forType: .string)
        note = "Copied · name it to keep it"
        isNaming = true
    }

    func save(label rawLabel: String) {
        let label = rawLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !candidate.isEmpty else {
            isNaming = false
            note = "Copied · not kept"
            return
        }

        let id = UUID().uuidString
        guard write(candidate, account: id) else {
            note = "The keychain refused to store it"
            isNaming = false
            return
        }

        entries.insert(Entry(id: id, label: label, created: Date()), at: 0)
        persist()
        isNaming = false
        note = "Copied · kept as \(label)"
        Log.write("password stored label=\(label)")
        generate()
    }

    func cancelNaming() {
        isNaming = false
        note = "Copied · not kept"
    }

    /// Copies a stored password back out. It is read from the keychain each
    /// time rather than held in memory between uses.
    func copy(_ entry: Entry) {
        guard let secret = read(account: entry.id) else {
            note = "Not in the keychain any more"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(secret, forType: .string)
        note = "Copied · \(entry.label)"
    }

    /// A password that already exists somewhere — the one for the router, the
    /// one a bank sent — typed in by hand and named on the same line.
    ///
    /// It goes to exactly the same place a generated one does, because a keychain
    /// with two kinds of entry in it is a keychain you have to remember the rules
    /// of. The field it was typed into is cleared by the caller the moment this
    /// returns true.
    func add(secret: String, label rawLabel: String) -> Bool {
        let label = rawLabel.trimmingCharacters(in: .whitespaces)
        guard !secret.isEmpty else {
            note = "Nothing to keep — the password is empty"
            return false
        }
        guard !label.isEmpty else {
            note = "Give it a name, or it is lost among the others"
            return false
        }

        let id = UUID().uuidString
        guard write(secret, account: id) else {
            note = "The keychain refused to store it"
            return false
        }

        entries.insert(Entry(id: id, label: label, created: Date()), at: 0)
        persist()
        note = "Kept as \(label)"
        Log.write("password added by hand label=\(label)")
        return true
    }

    /// There is deliberately no way to delete one.
    ///
    /// Everything else in this panel throws things away — the shelf, the
    /// clipboard, the sums — and a password is the one thing here that cannot be
    /// got back once it is gone: the keychain entry is the only copy, and the
    /// site it belongs to will not hand it over again. A bin on this row would
    /// sit one careless press away from that.

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.listKey)
    }

    private func remember() {
        UserDefaults.standard.set(length, forKey: Self.lengthKey)
        UserDefaults.standard.set(useSymbols, forKey: Self.symbolsKey)
    }

    // MARK: - Keychain

    private func write(_ secret: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

}
