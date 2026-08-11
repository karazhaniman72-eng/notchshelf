import AppKit
import EventKit

struct DayEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool

    var timeLabel: String {
        if isAllDay { return "all day" }
        return Self.clock.string(from: start)
    }

    /// Both ends of it. "14:00" says when to stop what you are doing; "14:00–
    /// 15:30" says whether the afternoon survives it.
    var rangeLabel: String {
        if isAllDay { return "all day" }
        return "\(Self.clock.string(from: start))–\(Self.clock.string(from: end))"
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var isPast: Bool { end < Date() }
}

/// Today's calendar events. Access is asked for once, on first use.
final class CalendarStore: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var events: [DayEvent] = []
    @Published private(set) var access: Access = .unknown
    /// Everything in the month on screen, keyed by day number, for the grid that
    /// unfolds out of the corner of the Plans tab.
    @Published private(set) var month: [Int: [DayEvent]] = [:]
    @Published private(set) var monthStart = Calendar.current.startOfDay(for: Date())

    private let store = EKEventStore()

    /// Called when the tab is opened rather than at launch, so the app does not
    /// throw a permission prompt at a user who never opens the calendar.
    func activate() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .denied, .restricted:
            access = .denied
        default:
            request()
        }
    }

    private func request() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = granted ? .granted : .denied
                Log.write("calendar access granted=\(granted) error=\(error?.localizedDescription ?? "none")")
                if granted { self.reload() }
            }
        }
    }

    func reload() {
        guard access == .granted else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .map { event in
                DayEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay
                )
            }
        Log.write("calendar reloaded events=\(events.count)")
        reloadMonth()
    }

    /// Everything on one day of the month on screen, in order. The grid is a
    /// picker, not a picture: pressing a date has to be able to answer what is
    /// on it.
    func events(on day: Date) -> [DayEvent] {
        let calendar = Calendar.current
        let number = calendar.component(.day, from: day)
        guard calendar.isDate(day, equalTo: monthStart, toGranularity: .month) else { return [] }
        return (month[number] ?? []).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
            return lhs.start < rhs.start
        }
    }

    func reloadMonth() {
        guard access == .granted else {
            month = [:]
            return
        }
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: monthStart) else { return }

        let predicate = store.predicateForEvents(withStart: interval.start,
                                                 end: interval.end,
                                                 calendars: nil)
        var grouped: [Int: [DayEvent]] = [:]
        for event in store.events(matching: predicate) {
            // The predicate returns anything that *overlaps* the month, so an
            // event running from 31 July into August arrives here with a start
            // date in July — and bucketing it by day number alone dotted the
            // 31st of August with it.
            guard calendar.isDate(event.startDate, equalTo: monthStart, toGranularity: .month) else { continue }
            let day = calendar.component(.day, from: event.startDate)
            grouped[day, default: []].append(
                DayEvent(id: event.eventIdentifier ?? UUID().uuidString,
                         title: event.title ?? "Untitled",
                         start: event.startDate,
                         end: event.endDate,
                         isAllDay: event.isAllDay)
            )
        }
        month = grouped
    }
}
