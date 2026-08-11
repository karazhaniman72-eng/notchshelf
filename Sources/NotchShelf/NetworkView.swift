import SwiftUI

/// Whether the internet works, and if not, whose fault it is.
///
/// The tab used to open with three cards of milliseconds and close with a line
/// of interface names, IP addresses and a timestamp. All of it true, none of it
/// an answer: a number in milliseconds only means something to somebody who
/// already knows what good looks like. Every reading now leads with the word
/// first and carries the figure underneath it, for whoever wants to check.
struct NetworkView: View {
    @ObservedObject var store: NetworkStore

    var body: some View {
        // Nine between the three blocks. The tools moved to the dial under the
        // notch and took a row's worth of height out of every tab, so what the
        // graph at the bottom is drawn in is the slack between these.
        VStack(alignment: .leading, spacing: 9) {
            headline

            HStack(spacing: 14) {
                HopCard(title: "Router", subtitle: "Wi-Fi to the box", probe: store.router, good: 15, poor: 60)
                HopCard(title: "Internet", subtitle: "the line out", probe: store.internet, good: 60, poor: 150)
                HopCard(title: "Names", subtitle: "address lookup", probe: store.dns, good: 100, poor: 300)
            }

            Spacer(minLength: 0)

            // Nothing to say for the first two minutes after a launch, and a
            // heading over an empty strip says it badly.
            if !store.history.isEmpty { recent }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 6)
        // The graph is the last thing on the tab and the panel's bottom corners
        // are rounded by thirty points: without this it sits in the rounding.
        .padding(.bottom, 8)
        // No cross-fade on these. A word replacing a word is animated by
        // SwiftUI as one drawn on top of the other, and "Down" fading through
        // "Checking" is unreadable for the length of the fade.
        .animation(nil, value: store.verdict)
    }

    // MARK: - The answer

    /// One word for the state of the line, and the network it is running over.
    private var headline: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.state.word)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(colour(store.state))

                Text(store.state.detail)
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            network
        }
    }

    /// What we are connected to. The name of a Wi-Fi network is only handed over
    /// to an app with location access, so without it this says what it does
    /// know — the band and how strong the signal is — instead of an empty space
    /// where a name should be.
    private var network: some View {
        HStack(spacing: 11) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.networkName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !store.signalWord.isEmpty {
                        Text(store.signalWord)
                            .font(Theme.captionText)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if store.rate > 0 {
                        Text("\(store.rate) Mbit/s")
                            .font(Theme.captionText)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Image(systemName: store.isWireless ? "wifi" : "cable.connector")
                .accessibilityHidden(true)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(signalColour)
        }
    }

    // MARK: - Lately

    /// The line out, drawn: one point per check, oldest on the left, height is
    /// how long the answer took.
    ///
    /// The word at the top of the tab is about this second, and a line that
    /// drops for ten seconds every few minutes reads "Good" every single time it
    /// is looked at. This is the only place that fault shows. A row of bars said
    /// the same thing, and said it as forty separate readings — a curve is one
    /// reading with a shape, and the shape is the whole point: a flat line is a
    /// good connection, a saw is a bad one.
    private var recent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Lately")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(store.stability)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Int(ceiling)) ms")
                    .font(Theme.captionText)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            LatencyGraph(samples: store.history, ceiling: ceiling)
                .frame(height: 34)
                .animation(Theme.settle, value: store.history.count)
        }
    }

    /// The top of the graph. Never tighter than 120 ms, so a good hour is drawn
    /// as the flat line it is instead of being stretched until every 3 ms wobble
    /// looks like a fault.
    private var ceiling: Double {
        max(120, store.history.compactMap(\.milliseconds).max() ?? 120)
    }

    private var signalColour: Color {
        guard let signal = store.signal else { return Theme.textTertiary }
        if signal >= -70 { return Theme.tint }
        return Theme.alert
    }

    private func colour(_ state: NetworkStore.Health) -> Color {
        switch state {
        case .checking: return Theme.textTertiary
        case .good: return Theme.tint
        // Slow is not broken, and only broken earns red. A dimmed blue says
        // "working, badly" without crying wolf.
        case .slow: return Theme.tint.opacity(0.65)
        case .broken: return Theme.alert
        }
    }
}

/// The last forty checks as a curve, with the gaps drawn as gaps.
///
/// A check that got no answer has no height to plot — it is not "slow", it is
/// nothing — so the line breaks there and a red bar stands in its place. Reading
/// it as zero would have drawn a dead connection as the fastest one on record.
private struct LatencyGraph: View {
    let samples: [NetworkStore.Sample]
    let ceiling: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(Theme.surface.opacity(0.4))

                if samples.count > 1 {
                    // Under the line first, so the stroke sits on top of its
                    // own shading rather than under it.
                    area(in: size)
                        .fill(LinearGradient(colors: [Theme.tint.opacity(0.28), Theme.tint.opacity(0.02)],
                                             startPoint: .top,
                                             endPoint: .bottom))

                    line(in: size)
                        .stroke(Theme.tint,
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }

                ForEach(samples.indices.filter { samples[$0].isDown }, id: \.self) { index in
                    Rectangle()
                        .fill(Theme.alert.opacity(0.75))
                        .frame(width: 2, height: size.height - 8)
                        .position(x: x(of: index, in: size), y: size.height / 2)
                }

                // Where the line is now: the only point on the graph anybody
                // looks for by eye.
                if let last = samples.last, let milliseconds = last.milliseconds, samples.count > 1 {
                    Circle()
                        .fill(Theme.tint)
                        .frame(width: 5, height: 5)
                        .position(x: x(of: samples.count - 1, in: size),
                                  y: y(of: milliseconds, in: size))
                }
            }
        }
    }

    private func x(of index: Int, in size: CGSize) -> CGFloat {
        guard samples.count > 1 else { return size.width / 2 }
        return 4 + (size.width - 8) * CGFloat(index) / CGFloat(samples.count - 1)
    }

    private func y(of milliseconds: Double, in size: CGSize) -> CGFloat {
        let fraction = min(max(milliseconds / ceiling, 0), 1)
        return 4 + (size.height - 8) * (1 - fraction)
    }

    private func line(in size: CGSize) -> Path {
        Path { path in
            var pen = false
            for (index, sample) in samples.enumerated() {
                guard let milliseconds = sample.milliseconds else {
                    pen = false
                    continue
                }
                let point = CGPoint(x: x(of: index, in: size), y: y(of: milliseconds, in: size))
                if pen {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    pen = true
                }
            }
        }
    }

    /// The same curve, closed down to the floor. Built as its own path rather
    /// than by closing the line: the line is broken at every gap, and closing a
    /// broken path fills the gaps back in.
    private func area(in size: CGSize) -> Path {
        Path { path in
            var run: [CGPoint] = []

            func flush() {
                guard run.count > 1 else { run.removeAll(); return }
                path.move(to: CGPoint(x: run[0].x, y: size.height - 4))
                for point in run { path.addLine(to: point) }
                path.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height - 4))
                path.closeSubpath()
                run.removeAll()
            }

            for (index, sample) in samples.enumerated() {
                guard let milliseconds = sample.milliseconds else {
                    flush()
                    continue
                }
                run.append(CGPoint(x: x(of: index, in: size), y: y(of: milliseconds, in: size)))
            }
            flush()
        }
    }
}

/// One leg of the journey out: the word, then the figure behind it.
private struct HopCard: View {
    let title: String
    let subtitle: String
    let probe: NetworkStore.Probe
    let good: Double
    let poor: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            Text(word)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(tint)

            Text(figure)
                .font(Theme.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Theme.surface.opacity(0.5))
        )
    }

    /// Milliseconds turned into the judgement somebody would make from them.
    private var word: String {
        guard let milliseconds = probe.milliseconds else {
            return probe.attempted ? "No answer" : "…"
        }
        if probe.loss > 0 { return "Dropping" }
        if milliseconds <= good { return "Fast" }
        if milliseconds <= poor { return "Fine" }
        return "Slow"
    }

    private var figure: String {
        guard probe.milliseconds != nil else { return subtitle }
        if probe.loss > 0 { return "\(probe.loss)% of packets lost" }
        return "\(probe.label) ms · \(subtitle)"
    }

    private var tint: Color {
        guard let milliseconds = probe.milliseconds else {
            return probe.attempted ? Theme.alert : Theme.inkDim
        }
        if probe.loss > 0 { return Theme.alert }
        // One blue, at two strengths: full for a leg that is quick, dimmed for
        // one that is merely working.
        if milliseconds <= good { return Theme.tint }
        if milliseconds <= poor { return Theme.tint.opacity(0.7) }
        return Theme.textSecondary
    }
}
