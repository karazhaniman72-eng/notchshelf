import SwiftUI

/// The day, and everything that governs it: what is planned, the month it sits
/// in, the block being timed and the switch that stops the Mac dozing off.
struct PlansView: View {
    @ObservedObject var calendar: CalendarStore
    @ObservedObject var plans: PlansStore
    @ObservedObject var timer: TimerStore
    @ObservedObject var awake: AwakeStore
    @ObservedObject var state: PanelState

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                header
                // The month takes the list's place rather than floating over
                // it: an overlay had to be dismissed, and the only way out was
                // a four point wide cross.
                if state.showsMonth {
                    MonthGrid(calendar: calendar) { picked in
                        withAnimation(Theme.settle) {
                            state.pickedDay = picked
                            state.showsMonth = false
                        }
                    }
                } else {
                    day
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            clock
                .frame(width: 172)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .animation(Theme.settle, value: state.showsMonth)
    }

    // MARK: - Header

    /// The date, what is left of it, and the one switch between the day and the
    /// month it belongs to.
    ///
    /// The month used to unfold when the cursor passed over its name. Hovering
    /// is how the tabs above are switched, so on the way to a tab the calendar
    /// kept springing open under the hand — two gestures with one meaning, and
    /// neither of them reliable.
    private var header: some View {
        HStack(spacing: 8) {
            Text(state.showsMonth ? monthTitle : dayTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 4)

            // Only a day that is not today can be left, and the way back is the
            // one control that appears for it.
            if state.pickedDay != nil, !state.showsMonth {
                GlyphButton(symbol: "arrow.uturn.left", size: 10, diameter: 22) {
                    withAnimation(Theme.touch) { state.pickedDay = nil }
                }
                .labelled("Back to today")
            }

            if !state.showsMonth, state.pickedDay == nil, plans.items.count > 0 {
                Text("\(plans.items.filter(\.isDone).count)/\(plans.items.count)")
                    .font(Theme.captionText)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            Button {
                if !state.showsMonth { calendar.reloadMonth() }
                withAnimation(Theme.swap) { state.showsMonth.toggle() }
            } label: {
                Image(systemName: state.showsMonth ? "list.bullet" : "calendar")
                    .accessibilityHidden(true)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.showsMonth ? Theme.tint : Theme.textTertiary)
                    .frame(width: 26, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(state.showsMonth ? Theme.fillActive : Theme.surface)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .labelled(state.showsMonth ? "Back to the list" : "Show the month")
        }
        .frame(height: 22)
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: state.pickedDay ?? Date())
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: calendar.monthStart)
    }

    // MARK: - Today

    @ViewBuilder
    private var day: some View {
        // A date pressed in the month grid answers for itself, and it answers
        // with the calendar only: a plan file is written for today, and showing
        // today's list under next Thursday's heading would be a lie.
        if let picked = state.pickedDay {
            let events = calendar.events(on: picked)
            if events.isEmpty {
                MessageView(icon: "calendar",
                            title: "Nothing that day",
                            subtitle: "")
            } else {
                rows(events.map { event in
                    Line(id: event.id,
                         text: event.title,
                         trailing: event.rangeLabel,
                         isDone: event.isPast)
                })
            }
        } else if calendar.access == .granted, !calendar.events.isEmpty {
            // Events win when the calendar has any; otherwise the plan written
            // down that morning speaks. An empty calendar is not an empty day.
            rows(calendar.events.map { event in
                Line(id: event.id,
                     text: event.title,
                     trailing: event.rangeLabel,
                     isDone: event.isPast)
            })
        } else if !plans.items.isEmpty {
            rows(plans.items.map { item in
                Line(id: item.id,
                     text: item.text,
                     trailing: "",
                     isDone: item.isDone,
                     toggle: { plans.toggle(item) })
            })
        } else if calendar.access == .granted {
            MessageView(icon: "checkmark.circle",
                        title: "Nothing scheduled",
                        subtitle: "The rest of today is yours")
        } else {
            MessageView(icon: "calendar.badge.exclamationmark",
                        title: "No calendar, no plan file",
                        subtitle: "Plans/today.md is where this tab looks")
        }
    }

    /// A short fade on purpose. The default softens the bottom of a list by
    /// twenty points, which on this tab is most of a two-line row: the last
    /// plan of the day dissolved into the panel's rounding and could not be
    /// read at all. Ten is enough to say "there is more below" while leaving
    /// the words under it legible.
    private func rows(_ lines: [Line]) -> some View {
        GaugedScroll(fade: 10) {
            VStack(spacing: 1) {
                ForEach(lines) { line in
                    LineRow(line: line, count: lines.count)
                }
                // Air after the last row, so a list that ends exactly at the
                // panel's edge is not cut by it.
                Color.clear.frame(height: 6)
            }
        }
    }

    struct Line: Identifiable {
        let id: String
        let text: String
        let trailing: String
        let isDone: Bool
        /// A plan can be ticked off; an event in a calendar can only be read.
        var toggle: (() -> Void)?
    }

    // MARK: - Timer and the awake switch

    private var clock: some View {
        TimerPanel(timer: timer, awake: awake, state: state)
    }
}

/// The block being timed. Its own view because it owns a text field, and a text
/// field owns focus state that the rest of the tab has no business holding.
private struct TimerPanel: View {
    @ObservedObject var timer: TimerStore
    @ObservedObject var awake: AwakeStore
    @ObservedObject var state: PanelState

    @State private var custom = ""
    @FocusState private var typing: Bool

    /// The clock is the whole right-hand column: one big ring at the top of it,
    /// and the lengths to set it to underneath.
    ///
    /// It used to be a small ring with the buttons stacked beside it, which left
    /// the bottom of the column as a strip of nothing — Iman's words were that
    /// the space under the timer made no sense. A dial reads as a dial at 110
    /// points and as an ornament at 66.
    var body: some View {
        VStack(alignment: .center, spacing: 9) {
            RingGauge(progress: timer.progress, diameter: 108, lineWidth: 7) {
                VStack(spacing: 1) {
                    Text(timer.clock)
                        .font(.system(size: timer.clock.count > 5 ? 22 : 26,
                                      weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)

                    Text(timer.phase.title)
                        .font(.system(size: 11))
                        .foregroundStyle(timer.isRunning ? Theme.textSecondary : Theme.textTertiary)
                }
            }

            // Two buttons, and both of them obvious. There used to be a third —
            // a skip-to-the-end arrow labelled with nothing, which read as
            // "next" and answered "next what?".
            HStack(spacing: 2) {
                GlyphButton(symbol: timer.isRunning ? "pause.fill" : "play.fill",
                            size: 14, diameter: 32) { timer.toggle() }
                    .labelled(timer.isRunning ? "Pause" : "Start")
                // Nothing to restart while the block has not started: the button
                // stays in place and stops pretending.
                // Always there. It used to appear only once a block had started,
                // on the argument that there is nothing to restart before then —
                // but the one moment somebody reaches for it is when the clock
                // is showing something they did not mean, and a control that is
                // absent until it is needed is one nobody knows exists.
                GlyphButton(symbol: "arrow.counterclockwise", size: 12, diameter: 28) { timer.reset() }
                    .labelled("Put the clock back to the full block")
            }

            // Three lengths and any other one, under the dial they set.
            // Four controls across a 172 point column: the padding is what gives,
            // not the row — at the old size "other" hung over the edge of the
            // panel where it could be read but not pressed.
            HStack(spacing: 3) {
                ForEach(TimerStore.presets, id: \.self) { minutes in
                    Chip(title: TimerStore.shortLabel(minutes),
                         isSelected: minutes == timer.preset && !isCustom,
                         padding: 5) {
                        custom = ""
                        typing = false
                        timer.select(minutes)
                    }
                    .fixedSize()
                }

                // "min" as a placeholder read as a fourth preset named min.
                // "other" says what it is: any length, typed.
                TextField("other", text: $custom)
                    .textFieldStyle(.plain)
                    .font(Theme.metaText)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isCustom ? Theme.accent : Theme.textSecondary)
                    .focused($typing)
                    .frame(width: 42, height: 26)
                    .background(
                        Capsule().fill(isCustom ? Theme.fillActive : Theme.fillInput)
                    )
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    .onSubmit { apply() }
                    .onChange(of: typing) { _, focused in
                        state.isEditing = focused
                        if !focused { apply() }
                    }
                    .labelled("Any number of minutes")
            }

            // The switch that has nothing to do with the timer and everything
            // to do with sitting still: hold the Mac awake until it is turned
            // off again.
            HStack(spacing: 7) {
                Button(action: { awake.toggle() }) {
                    HStack(spacing: 5) {
                        Image(systemName: awake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .accessibilityHidden(true)
                            .font(.system(size: 11, weight: .semibold))
                        Text(awake.isOn ? "Awake" : "Keep awake")
                            .font(Theme.captionText)
                    }
                    .foregroundStyle(awake.isOn ? Theme.accent : Theme.textTertiary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        Capsule().fill(awake.isOn ? Theme.fillActive : Theme.surface)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Two lines used to live here: the tally of blocks done today and
            // the countdown to the next Claude Code window. Both were small grey
            // text in the corner of a tab that is supposed to show the day, and
            // neither was ever acted on — which is the definition of the noise
            // this tab was told to lose.

            Spacer(minLength: 0)
        }
        .onAppear {
            custom = TimerStore.presets.contains(timer.preset) ? "" : String(timer.preset)
        }
    }

    private var isCustom: Bool { !TimerStore.presets.contains(timer.preset) }

    private func apply() {
        guard let minutes = Int(custom.trimmingCharacters(in: .whitespaces)), minutes > 0 else {
            custom = isCustom ? String(timer.preset) : ""
            return
        }
        timer.select(minutes)
        custom = String(timer.preset)
    }
}

/// The month, with the days that carry something marked under the number. One
/// month, the one we are in: stepping through the year belongs in a calendar
/// app, and the arrows that did it were two more things to hit by accident.
private struct MonthGrid: View {
    @ObservedObject var calendar: CalendarStore
    /// The grid is a picker. It used to be a picture: dots under the numbers
    /// said something was on that day and there was no way to ask what.
    let onPick: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(weekdayTitles, id: \.self) { title in
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(cells, id: \.id) { cell in
                DayCell(cell: cell) {
                    guard let day = cell.day, let date = date(of: day) else { return }
                    onPick(date)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func date(of day: Int) -> Date? {
        let current = Calendar.current
        var parts = current.dateComponents([.year, .month], from: calendar.monthStart)
        parts.day = day
        return current.date(from: parts)
    }

    /// Monday first: the week starts where the working week does here.
    ///
    /// Two letters where one would repeat, because the headings are keyed by
    /// their own text: single initials gave Thursday Tuesday's id and Sunday
    /// Saturday's, and SwiftUI quietly dropped both columns. Numbering them
    /// instead only moved the collision — the numbers then matched the day
    /// cells' ids, and the first six days of the month disappeared.
    private var weekdayTitles: [String] { ["M", "Tu", "W", "Th", "F", "Sa", "Su"] }

    struct Cell: Identifiable {
        let id: Int
        let day: Int?
        let isToday: Bool
        let marks: Int
    }

    private var cells: [Cell] {
        let current = Calendar.current
        guard let interval = current.dateInterval(of: .month, for: calendar.monthStart) else { return [] }
        let days = current.range(of: .day, in: .month, for: calendar.monthStart)?.count ?? 30
        // `weekday` is 1 for Sunday, so Monday-first needs the shift.
        let firstWeekday = (current.component(.weekday, from: interval.start) + 5) % 7

        var built: [Cell] = (0..<firstWeekday).map { Cell(id: -$0 - 1, day: nil, isToday: false, marks: 0) }
        let today = current.dateComponents([.year, .month, .day], from: Date())
        let shown = current.dateComponents([.year, .month], from: calendar.monthStart)

        for day in 1...days {
            let isToday = today.day == day && today.month == shown.month && today.year == shown.year
            built.append(Cell(id: day,
                              day: day,
                              isToday: isToday,
                              marks: min(calendar.month[day]?.count ?? 0, 3)))
        }
        return built
    }
}

private struct DayCell: View {
    let cell: MonthGrid.Cell
    let onPick: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 1) {
            Text(cell.day.map(String.init) ?? "")
                .font(.system(size: 12.5, weight: cell.isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(colour)

            HStack(spacing: 2) {
                ForEach(0..<cell.marks, id: \.self) { _ in
                    Circle()
                        .fill(Theme.tint)
                        .frame(width: 2.5, height: 2.5)
                }
            }
            .frame(height: 3)
        }
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(cell.isToday ? Theme.fillActive : (hovering ? Theme.fillHover : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 && cell.day != nil }
        .onTapGesture {
            guard cell.day != nil else { return }
            onPick()
        }
        .accessibilityAddTraits(cell.day == nil ? [] : .isButton)
        .animation(Theme.touch, value: hovering)
    }

    private var colour: Color {
        if cell.day == nil { return .clear }
        if cell.isToday { return Theme.tint }
        return cell.marks > 0 ? Theme.textPrimary : Theme.textTertiary
    }
}

private struct LineRow: View {
    let line: PlansView.Line
    /// How long the list is. Three plans are worth reading in full size; ten of
    /// them at that size would be a list you scroll to see any of.
    let count: Int
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let toggle = line.toggle {
                // The box is the whole gesture, and it writes straight into the
                // markdown — the same tick Obsidian would put there.
                Button(action: toggle) {
                    Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
                        .accessibilityHidden(true)
                        .font(.system(size: 12.5, weight: line.isDone ? .semibold : .regular))
                        .foregroundStyle(line.isDone ? Theme.accent : (hovering ? Theme.textSecondary : Theme.textTertiary))
                        .frame(width: 16, height: 17)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .labelled(line.isDone ? "Untick it" : "Tick it off")
            } else {
                Circle()
                    .fill(line.isDone ? Theme.inkDim : Theme.textSecondary)
                    .frame(width: 6, height: 6)
                    .frame(width: 16, height: 17)
            }

            // Two lines, not one, and all of it under the cursor. A plan is a
            // sentence, and a sentence cut off at the width of the panel is a
            // plan you have to remember rather than read.
            Text(line.text)
                .font(Theme.scaled(15, count: count, comfortable: 3, floor: 12.5))
                .foregroundStyle(line.isDone ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(line.isDone, color: Theme.inkDim)
                // Two lines, always. It used to open to six under the cursor,
                // which pushed every row below it down the list while the hand
                // was still on it; the whole line is on the tooltip instead.
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .labelled(line.text)

            Spacer(minLength: 8)

            if !line.trailing.isEmpty {
                Text(line.trailing)
                    .font(Theme.metaText)
                    .monospacedDigit()
                    .foregroundStyle(line.isDone ? Theme.inkDim : Theme.textSecondary)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(hovering ? Theme.fillHover : .clear)
        )
        // The whole row ticks it off, not just the circle.
        //
        // A sixteen point circle at the left edge of a four-hundred point row is
        // a target you have to aim at, and the thing anybody's eye is on is the
        // sentence beside it. The circle stays — it is what says the row can be
        // ticked at all — but pressing the words does the same thing. Rows with
        // no toggle (calendar events) take no press: there is nothing to do to
        // an appointment from here.
        .contentShape(Rectangle())
        .onTapGesture { line.toggle?() }
        .accessibilityAddTraits(line.toggle == nil ? [] : .isButton)
        .animation(Theme.touch, value: hovering)
        .onHover { hovering = $0 }
        .animation(Theme.drop, value: line.isDone)
    }
}
