import SwiftUI

/// Today and tomorrow, and nothing else.
///
/// The tab used to be a seven-column grid of the whole week. Read across, it was
/// a spreadsheet: four rows of hours against however many days the API returned,
/// with the temperature you actually wanted — the one for right now — the same
/// size as the one for next Thursday. Two days fit the width without crowding,
/// and everything past tomorrow is a guess anyway.
struct WeatherView: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let forecast = store.current {
                header(forecast)

                HStack(alignment: .top, spacing: 20) {
                    if let today = forecast.days.first {
                        column(title: "Today", day: today)
                    }
                    if forecast.days.count > 1 {
                        column(title: "Tomorrow", day: forecast.days[1])
                    }
                }
            } else if let failure = store.failure {
                MessageView(icon: "wifi.slash",
                            title: "No forecast",
                            subtitle: failure,
                            action: ("Try again", { store.reload() }))
            } else {
                MessageView(icon: "cloud.sun", title: "Fetching the forecast", subtitle: "")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 6)
        .frame(maxHeight: .infinity)
        .animation(Theme.settle, value: store.selected)
    }

    // MARK: - Now

    /// The reading worth having is the temperature outside right now, so it is
    /// the biggest thing on the tab and it sits top left, where reading starts.
    ///
    /// The number itself is white. It used to be amber, which said "warm"
    /// whatever it read: eleven degrees and a downpour came out the same colour
    /// as a heatwave. Colour on this tab describes the sky instead — yellow sun,
    /// blue rain, grey cloud — and the figure stays a figure.
    private func header(_ forecast: WeatherStore.Forecast) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(forecast.temperature)°")
                .font(.system(size: 44, weight: .light, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Self.sky(forecast.symbol, size: 17)
                        .accessibilityHidden(true)
                    Text(forecast.summary)
                        .font(Theme.rowText)
                        .foregroundStyle(Theme.textPrimary)
                }
                Text("feels \(forecast.feelsLike)°  ·  \(forecast.wind) m/s  ·  \(forecast.humidity)% damp")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            cities
        }
    }

    /// Hovering is the whole gesture: the cursor is already on its way across
    /// the row, and asking for a click as well would be a click for nothing.
    private var cities: some View {
        HStack(spacing: 4) {
            ForEach(WeatherStore.cities) { city in
                Chip(title: city.name, isSelected: city.id == store.selected) {
                    store.show(city)
                }
                .onHover { inside in
                    if inside { store.show(city) }
                }
            }
        }
    }

    // MARK: - The two days

    private func column(title: String, day: WeatherStore.Day) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            ForEach(WeatherStore.hours, id: \.self) { hour in
                row(day.slots.first { $0.hour == hour }, hour: hour)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The hour, the sky, the temperature — and then, to the right of the
    /// degrees, the wind and the damp for that hour of that day.
    ///
    /// They used to be one pair of figures in a column of their own, headed
    /// "Air": the wind right now, printed once, beside two days of hourly
    /// temperatures it had nothing to do with.
    @ViewBuilder
    private func row(_ slot: WeatherStore.Slot?, hour: Int) -> some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d", hour))
                .font(Theme.metaText)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20, alignment: .leading)

            if let slot {
                Self.sky(slot.symbol, size: 15)
                    .frame(width: 20)
                    .accessibilityLabel(slot.summary)

                Text("\(slot.temperature)°")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    // Wide enough for "−12°" at the larger size: a column that
                    // fits three characters clips the coldest hour of the day.
                    .frame(width: 40, alignment: .leading)

                // A chance nobody would act on is noise: under a fifth and the
                // row stays quiet. The space it would have taken is kept, so
                // the wind reading beside it does not shuffle from row to row.
                HStack(spacing: 3) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                    Text("\(slot.precipitation)%")
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chance of rain \(slot.precipitation) per cent")
                .foregroundStyle(Theme.tint)
                .frame(width: 36, alignment: .leading)
                .opacity(slot.precipitation >= 20 ? 1 : 0)

                Spacer(minLength: 0)

                reading(named: "Wind", symbol: "wind", value: "\(slot.wind)", unit: "m/s")
                    .frame(width: 56, alignment: .leading)
                reading(named: "Humidity", symbol: "humidity.fill", value: "\(slot.humidity)", unit: "%")
                    .frame(width: 48, alignment: .leading)
            } else {
                Text("—")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 22)
    }

    /// The glyph is the name of the reading: without it "3" and "40" are two
    /// numbers with nothing to say. So the row is read as one thing, and the
    /// name is spelled out rather than left to the symbol.
    private func reading(named name: String, symbol: String, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(Theme.inkDim)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value) \(unit)")
    }

    /// Sky in two colours instead of one.
    ///
    /// A weather symbol is two things stacked — a cloud with a sun behind it, a
    /// cloud with rain under it — and painting the whole glyph one colour meant
    /// picking which of the two to describe. The rule that came out of it ("if
    /// it says cloud anywhere, grey") is why a city under broken cloud had no
    /// colour on it at all: every hour of Almaty came out the same grey as fog.
    ///
    /// Each layer gets its own colour now: the cloud stays grey, and what is
    /// behind or under it keeps its own — sun yellow, moon blue, rain and sleet
    /// blue, snow white.
    private static func palette(for symbol: String) -> (Color, Color) {
        let cloud = Theme.textSecondary

        // Order matters: what falls out of a cloud outranks what is behind it,
        // because rain is the fact and the sun behind it is the detail.
        if symbol.contains("snow") { return (cloud, Theme.textPrimary) }
        if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("sleet") {
            return (cloud, Theme.tint)
        }
        if symbol.contains("bolt") { return (cloud, Theme.sun) }
        if symbol.contains("hail") { return (cloud, Theme.textPrimary) }

        if symbol.contains("sun") {
            // `sun.max.fill` is all sun; `cloud.sun.fill` is a cloud with one
            // behind it, and only the second layer is yellow.
            return symbol.contains("cloud") ? (cloud, Theme.sun) : (Theme.sun, Theme.sun)
        }
        if symbol.contains("moon") {
            return symbol.contains("cloud") ? (cloud, Theme.moon) : (Theme.moon, Theme.moon)
        }

        // Fog, haze, plain overcast: grey is the honest answer for those.
        return (cloud, cloud)
    }

    /// The symbol itself, coloured layer by layer.
    private static func sky(_ symbol: String, size: CGFloat) -> some View {
        let colours = palette(for: symbol)
        return Image(systemName: symbol)
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(colours.0, colours.1)
    }
}
