import Foundation

/// Everything that turns one number into another: money at today's rate, and
/// the units a kitchen or a gym asks for. One store rather than two tabs — the
/// gesture is identical, only the table behind it changes.
final class ConvertStore: ObservableObject {

    /// Five kinds, not seven. Speed and data went out because nobody converts
    /// them: a file size is already printed in the unit it is wanted in, and
    /// knots are for people who own a boat.
    enum Mode: String, CaseIterable, Identifiable {
        case currency, temperature, mass, volume, length

        var id: String { rawValue }

        var title: String {
            switch self {
            case .currency: return "Money"
            case .temperature: return "Temp"
            case .mass: return "Mass"
            case .volume: return "Volume"
            case .length: return "Length"
            }
        }

        /// Units of this kind, in the order they appear on the row.
        var units: [String] {
            switch self {
            case .currency: return []
            case .temperature: return ["°C", "°F", "K"]
            case .mass: return ["g", "kg", "oz", "lb", "t"]
            case .volume: return ["ml", "l", "cup", "pt", "gal"]
            case .length: return ["mm", "cm", "m", "km", "in", "ft", "mi"]
            }
        }
    }

    // MARK: - Published state

    @Published var mode: Mode = .currency { didSet { restoreUnits(); recompute() } }
    @Published var amount = "1" { didSet { recompute() } }
    @Published private(set) var result = ""
    @Published private(set) var updated: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var failure = ""

    /// The currencies actually on screen. Whatever the owner puts here — the
    /// app ships with none of its own opinions beyond a starting five.
    @Published private(set) var currencies: [String] = []
    @Published var from = "" { didSet { remember(); recompute() } }
    @Published var to = "" { didSet { remember(); recompute() } }

    private var rates: [String: Double] = [:]
    private static let currencyKey = "convert.currencies"
    private static let pairKeyPrefix = "convert.pair."
    private static let ratesKey = "convert.rates"
    private static let ratesDateKey = "convert.ratesDate"
    /// Rates are published once a day at the source, so anything fresher than
    /// six hours is the same table again.
    private static let staleAfter: TimeInterval = 6 * 3600

    init() {
        currencies = (UserDefaults.standard.array(forKey: Self.currencyKey) as? [String])
            ?? ["USD", "KZT", "RUB", "EUR", "CNY"]
        if let cached = UserDefaults.standard.dictionary(forKey: Self.ratesKey) as? [String: Double] {
            rates = cached
            updated = UserDefaults.standard.object(forKey: Self.ratesDateKey) as? Date
        }
        loadHistory()
        restoreUnits()
        recompute()
    }

    // MARK: - Activation

    func activate() {
        guard mode == .currency else { return }
        let age = updated.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        if rates.isEmpty || age > Self.staleAfter { reload() }
    }

    /// The refresh button. Always goes to the network, however fresh the table.
    func reload() {
        guard !isLoading else { return }
        isLoading = true
        failure = ""

        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.failure = error.localizedDescription
                    Log.write("rates failed \(error.localizedDescription)")
                    return
                }
                guard let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let table = payload["rates"] as? [String: Double], !table.isEmpty else {
                    self.failure = "The rate service answered with nothing usable"
                    return
                }

                self.rates = table
                self.updated = Date()
                UserDefaults.standard.set(table, forKey: Self.ratesKey)
                UserDefaults.standard.set(self.updated, forKey: Self.ratesDateKey)
                self.recompute()
                Log.write("rates loaded count=\(table.count)")
            }
        }.resume()
    }

    // MARK: - The list of currencies

    /// Anything the source knows, so the field takes a code and checks it
    /// against the table rather than against a list written into the app.
    var knownCodes: [String] { rates.keys.sorted() }

    /// The codes offered first in the picker, and it keeps itself: whatever gets
    /// converted goes to the top of the list, so the six currencies actually
    /// used are the six at hand.
    ///
    /// There used to be a row of chips along the bottom of the tab for editing
    /// this by hand — a second thing to read under an answer, on the tab that is
    /// meant to be the smallest in the panel.
    private func promote(_ code: String) {
        guard mode == .currency, code.count == 3, !code.isEmpty else { return }
        guard rates.isEmpty || rates[code] != nil else { return }
        guard currencies.first != code else { return }

        currencies.removeAll { $0 == code }
        currencies.insert(code, at: 0)
        if currencies.count > 6 { currencies.removeLast(currencies.count - 6) }
        UserDefaults.standard.set(currencies, forKey: Self.currencyKey)
    }

    func swap() {
        let held = from
        from = to
        to = held
    }

    var units: [String] { mode == .currency ? currencies : mode.units }

    /// Everything else the rate table knows, under the divider in the picker.
    /// A currency that is not on a list of five is not untranslatable — it was
    /// only ever off a list.
    var otherUnits: [String] {
        guard mode == .currency else { return [] }
        return knownCodes.filter { !currencies.contains($0) }
    }

    var updatedLabel: String {
        guard mode == .currency else { return "" }
        guard let updated else { return "never fetched" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(updated) ? "HH:mm" : "d MMM HH:mm"
        return formatter.string(from: updated)
    }

    // MARK: - The arithmetic

    private func recompute() {
        let raw = amount.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(raw.trimmingCharacters(in: .whitespaces)) else {
            result = ""
            return
        }
        guard !from.isEmpty, !to.isEmpty else {
            result = ""
            return
        }

        let converted: Double?
        switch mode {
        case .currency:
            converted = convertMoney(value)
        case .temperature:
            converted = Self.convertTemperature(value, from: from, to: to)
        default:
            converted = Self.convertLinear(value, from: from, to: to, table: Self.factors)
        }

        guard let converted else {
            result = ""
            return
        }
        result = Self.format(converted)
    }

    /// What one unit of a currency is worth in another. Nil while the table has
    /// not been fetched, so the row shows nothing rather than a made-up figure.
    func rate(from source: String, to target: String) -> Double? {
        guard let base = rates[source], let quote = rates[target], base > 0 else { return nil }
        return quote / base
    }

    /// Every rate in the table is quoted against the dollar, so anything to
    /// anything is two steps through it.
    private func convertMoney(_ value: Double, into code: String? = nil) -> Double? {
        guard let source = rates[from], let target = rates[code ?? to], source > 0 else { return nil }
        return value / source * target
    }

    private static func convertTemperature(_ value: Double, from: String, to: String) -> Double? {
        let celsius: Double
        switch from {
        case "°C": celsius = value
        case "°F": celsius = (value - 32) * 5 / 9
        case "K": celsius = value - 273.15
        default: return nil
        }
        switch to {
        case "°C": return celsius
        case "°F": return celsius * 9 / 5 + 32
        case "K": return celsius + 273.15
        default: return nil
        }
    }

    /// Everything that is not temperature is one multiplication: the value goes
    /// to the base unit of its kind and comes back out in the other one.
    private static func convertLinear(_ value: Double,
                                      from: String,
                                      to: String,
                                      table: [String: Double]) -> Double? {
        guard let source = table[from], let target = table[to], target > 0 else { return nil }
        return value * source / target
    }

    private static let factors: [String: Double] = [
        // mass, in grams
        "g": 1, "kg": 1000, "oz": 28.349523125, "lb": 453.59237, "t": 1_000_000,
        // volume, in millilitres
        "ml": 1, "l": 1000, "cup": 236.5882365, "pt": 473.176473, "gal": 3785.411784,
        // length, in millimetres
        "mm": 1, "cm": 10, "m": 1000, "km": 1_000_000,
        "in": 25.4, "ft": 304.8, "mi": 1_609_344
    ]

    /// Money wants two decimals, a gram wants none, and 0.000123 wants all it
    /// can get. The number decides, not a setting.
    static func format(_ value: Double) -> String {
        let magnitude = abs(value)
        let places: Int
        switch magnitude {
        case 0: places = 0
        case ..<0.001:
            // Six decimals is a wall, not a number: a millimetre is 0.000001 km
            // and 0.00000062 miles, and both came out "0.000001" — two different
            // lengths printed the same. Count places from the first digit that
            // is not a zero instead, so three real figures always survive.
            places = min(12, 3 - Int(floor(log10(magnitude))) - 1)
        case ..<1: places = 4
        default: places = 2
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = places
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - What has already been worked out

    /// One conversion that actually happened, kept so it can be read back or
    /// picked up again.
    struct Entry: Identifiable, Codable, Equatable {
        var id: String { "\(mode)\(from)\(to)\(amount)" }
        let mode: String
        let amount: String
        let from: String
        let result: String
        let to: String
    }

    @Published private(set) var history: [Entry] = []

    private static let historyKey = "convert.history"
    /// Kept, not shown: the tab has room for four or five, and the rest are
    /// there so a mode switched away from and back has not forgotten itself.
    private static let historyLimit = 24

    /// Writes down what is on screen. Called when the answer is asked for
    /// rather than as it is typed: recording every keystroke would fill the
    /// list with 1, 12, 125 on the way to 1250.
    func record() {
        guard !result.isEmpty, !from.isEmpty, !to.isEmpty else { return }
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let entry = Entry(mode: mode.rawValue, amount: trimmed,
                          from: from, result: result, to: to)
        // The same sum asked twice is one line, moved back to the top.
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        saveHistory()
    }

    /// Puts a past conversion back in the boxes. The kind goes first: setting it
    /// restores that kind's saved pair, which would otherwise overwrite the two
    /// units just handed in.
    func restore(_ entry: Entry) {
        if let kind = Mode(rawValue: entry.mode), kind != mode { mode = kind }
        from = entry.from
        to = entry.to
        amount = entry.amount
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let saved = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        history = saved
    }

    // MARK: - Remembering the last pair per mode

    private func remember() {
        UserDefaults.standard.set([from, to], forKey: Self.pairKeyPrefix + mode.rawValue)
        promote(to)
        promote(from)
    }

    private func restoreUnits() {
        let available = units
        guard !available.isEmpty else { return }
        let saved = UserDefaults.standard.array(forKey: Self.pairKeyPrefix + mode.rawValue) as? [String]
        let first = saved?.first ?? available.first ?? ""
        let second = saved?.last ?? available.dropFirst().first ?? available.first ?? ""
        from = available.contains(first) ? first : (available.first ?? "")
        to = available.contains(second) ? second : (available.last ?? "")
    }
}
