import Foundation

/// Open-Meteo: no key, no account, no OAuth. Three fixed cities rather than the
/// one you happen to be standing in — the point is the week ahead in the places
/// that matter, so no location permission is ever asked for.
final class WeatherStore: ObservableObject {

    struct City: Identifiable, Equatable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
    }

    static let cities = [
        City(id: "moscow", name: "Moscow", latitude: 55.7558, longitude: 37.6173),
        City(id: "astana", name: "Astana", latitude: 51.1694, longitude: 71.4491),
        City(id: "almaty", name: "Almaty", latitude: 43.2380, longitude: 76.8829)
    ]

    /// One of the four times of day the grid is built from.
    struct Slot: Identifiable {
        let id: String
        let hour: Int
        let temperature: Int
        /// Chance of precipitation, per cent.
        let precipitation: Int
        let symbol: String
        /// What the symbol says, in words. The glyph is the whole of the sky in
        /// this row — VoiceOver has nothing else to go on.
        let summary: String
        /// Metres per second, and per cent damp — the two readings that decide
        /// what a temperature actually feels like, at that hour of that day
        /// rather than as one figure for the whole tab.
        let wind: Int
        let humidity: Int
    }

    struct Day: Identifiable {
        let id: String
        let title: String
        let slots: [Slot]
    }

    struct Forecast {
        let temperature: Int
        let summary: String
        let symbol: String
        let feelsLike: Int
        let wind: Int
        let humidity: Int
        /// "↑ 05:42 ↓ 20:11 · 14 h 29 m", or empty if the API skipped it.
        let daylight: String
        let days: [Day]
    }

    /// The hours the day is sampled at: before work, midday, late afternoon,
    /// night.
    static let hours = [8, 12, 16, 22]

    @Published private(set) var selected = WeatherStore.cities[0].id
    @Published private(set) var forecasts: [String: Forecast] = [:]
    @Published private(set) var failure: String?
    @Published private(set) var isLoading = false

    private var fetchedAt: [String: Date] = [:]
    /// Weather does not move fast enough to be worth asking twice in a quarter
    /// of an hour.
    private let staleAfter: TimeInterval = 15 * 60

    var current: Forecast? { forecasts[selected] }

    var city: City { Self.cities.first { $0.id == selected } ?? Self.cities[0] }

    func show(_ city: City) {
        guard selected != city.id else { return }
        selected = city.id
        load(city)
    }

    /// Called when the tab appears. Every city is fetched, not just the one on
    /// screen: hovering the other two has to answer instantly, and three small
    /// requests a quarter of an hour is nothing.
    func activate() {
        Self.cities.forEach { load($0) }
    }

    func reload() {
        fetchedAt.removeAll()
        failure = nil
        activate()
    }

    private func load(_ city: City) {
        if let fetched = fetchedAt[city.id], Date().timeIntervalSince(fetched) < staleAfter { return }
        fetchedAt[city.id] = Date()

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]
        guard let url = components?.url else { return }

        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async { self.isLoading = false }

            guard let data, error == nil else {
                // A failed city must not keep its slot in the cache, or the
                // retry button does nothing for fifteen minutes.
                DispatchQueue.main.async {
                    self.fetchedAt[city.id] = nil
                    self.failure = error?.localizedDescription ?? "No answer from the forecast"
                    Log.write("weather failed city=\(city.id) error=\(self.failure ?? "?")")
                }
                return
            }

            guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
                DispatchQueue.main.async {
                    self.fetchedAt[city.id] = nil
                    self.failure = "The forecast came back in a shape we do not read"
                }
                return
            }

            let forecast = Self.build(from: response)
            DispatchQueue.main.async {
                self.forecasts[city.id] = forecast
                self.failure = nil
                Log.write("weather loaded city=\(city.id) days=\(forecast.days.count)")
            }
        }.resume()
    }

    // MARK: - Shaping

    private static func build(from response: Response) -> Forecast {
        var days: [Day] = []
        var slotsByDate: [String: [Slot]] = [:]
        var order: [String] = []

        for (index, stamp) in response.hourly.time.enumerated() {
            // "2026-08-08T08:00" in the city's own time — split rather than
            // parsed, since the API has already done the zone arithmetic.
            let parts = stamp.split(separator: "T")
            guard parts.count == 2, let hour = Int(parts[1].prefix(2)), hours.contains(hour) else { continue }
            let date = String(parts[0])

            let slot = Slot(
                id: stamp,
                hour: hour,
                temperature: Int(response.hourly.temperature.indices.contains(index)
                                 ? response.hourly.temperature[index].rounded() : 0),
                precipitation: response.hourly.precipitation.indices.contains(index)
                    ? (response.hourly.precipitation[index] ?? 0) : 0,
                symbol: symbol(for: response.hourly.code.indices.contains(index) ? response.hourly.code[index] : 0,
                               isDay: (response.hourly.isDay.indices.contains(index) ? response.hourly.isDay[index] : 1) == 1),
                summary: description(for: response.hourly.code.indices.contains(index) ? response.hourly.code[index] : 0),
                wind: Int((response.hourly.wind.indices.contains(index)
                           ? response.hourly.wind[index] : 0).rounded()),
                humidity: response.hourly.humidity.indices.contains(index)
                    ? response.hourly.humidity[index] : 0
            )

            if slotsByDate[date] == nil { order.append(date) }
            slotsByDate[date, default: []].append(slot)
        }

        for date in order {
            days.append(Day(id: date, title: title(for: date), slots: slotsByDate[date] ?? []))
        }

        return Forecast(
            temperature: Int(response.current.temperature.rounded()),
            summary: description(for: response.current.code),
            symbol: symbol(for: response.current.code, isDay: response.current.isDay == 1),
            feelsLike: Int(response.current.feelsLike.rounded()),
            wind: Int(response.current.wind.rounded()),
            humidity: response.current.humidity,
            daylight: daylight(from: response.daily),
            days: days
        )
    }

    /// Sunrise, sunset and how much day there is between them — the figure that
    /// actually changes what an evening is good for.
    private static func daylight(from daily: Response.Daily?) -> String {
        guard let rise = daily?.sunrise.first, let set = daily?.sunset.first,
              let riseTime = time(rise), let setTime = time(set) else { return "" }

        // The length of the day is the difference between the two times either
        // side of it, and printing it as well cost the line its room.
        return String(format: "↑ %02d:%02d  ↓ %02d:%02d",
                      riseTime.hour, riseTime.minute, setTime.hour, setTime.minute)
    }

    private static func time(_ stamp: String) -> (hour: Int, minute: Int)? {
        let parts = stamp.split(separator: "T")
        guard parts.count == 2 else { return nil }
        let clock = parts[1].split(separator: ":")
        guard clock.count >= 2, let hour = Int(clock[0]), let minute = Int(clock[1]) else { return nil }
        return (hour, minute)
    }

    private static func title(for date: String) -> String {
        let source = DateFormatter()
        source.locale = Locale(identifier: "en_US_POSIX")
        source.timeZone = TimeZone(identifier: "UTC")
        source.dateFormat = "yyyy-MM-dd"
        guard let parsed = source.date(from: date) else { return date }

        let label = DateFormatter()
        label.locale = Locale(identifier: "en_US_POSIX")
        label.timeZone = TimeZone(identifier: "UTC")
        label.dateFormat = "EEE d"
        return label.string(from: parsed)
    }

    /// WMO weather codes to SF Symbols, day and night. The only fiddly part of
    /// the tab, kept in one table rather than scattered through the view.
    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.min.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57, 66, 67: return "Freezing rain"
        case 61, 63, 65: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "—"
        }
    }

    // MARK: - Wire format

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let feelsLike: Double
            let humidity: Int
            let code: Int
            let wind: Double
            let isDay: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case feelsLike = "apparent_temperature"
                case humidity = "relative_humidity_2m"
                case code = "weather_code"
                case wind = "wind_speed_10m"
                case isDay = "is_day"
            }
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature: [Double]
            let precipitation: [Int?]
            let code: [Int]
            let isDay: [Int]
            let wind: [Double]
            let humidity: [Int]

            enum CodingKeys: String, CodingKey {
                case time
                case temperature = "temperature_2m"
                case precipitation = "precipitation_probability"
                case code = "weather_code"
                case isDay = "is_day"
                case wind = "wind_speed_10m"
                case humidity = "relative_humidity_2m"
            }
        }

        struct Daily: Decodable {
            let sunrise: [String]
            let sunset: [String]
        }

        let current: Current
        let hourly: Hourly
        let daily: Daily?
    }
}
