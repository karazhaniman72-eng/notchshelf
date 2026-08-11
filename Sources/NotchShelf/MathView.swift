import AppKit
import SwiftUI

/// Puts the caret after the last character instead of selecting the lot.
///
/// Taking focus selects everything already in the field, and a selection is
/// drawn as a pale slab behind the text — the same artefact the display was
/// rebuilt to be rid of, arriving by a different route every time a tab is left
/// and come back to. `sendAction` will not do it: it walks the responder chain
/// of the key window, and this panel is deliberately not one most of the time.
/// The field editor is asked directly.
enum FieldCaret {
    static func toEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            for window in NSApp.windows {
                guard let editor = window.firstResponder as? NSTextView else { continue }
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
    }
}

/// The calculator, shaped like one: a display across the top, keys underneath,
/// and what has been counted beside them.
///
/// There is no field to fill in any more. A bordered box with a placeholder in
/// it is a form, and a form is a thing you fill in and submit — a calculator is
/// a thing you press. The sum still takes the keyboard, it simply stopped
/// drawing a box around itself: the top line is what has been typed, the line
/// under it is what it comes to.
struct MathView: View {
    @ObservedObject var store: MathStore
    @ObservedObject var state: PanelState

    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            display

            status

            HStack(alignment: .top, spacing: 16) {
                past
                Keypad(store: store)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 0)
        .onAppear {
            state.wantsKeyboard = true
            typing = true
            FieldCaret.toEnd()
        }
        .onChange(of: store.input) { _, value in
            state.isEditing = !value.isEmpty
        }
        .onDisappear {
            state.wantsKeyboard = false
            state.isEditing = false
        }
    }

    /// What was typed, big, and what it comes to underneath it.
    ///
    /// This was the wrong way round: the sum was set small along the top and the
    /// answer was the big figure, so pressing 7 left a large 0 sitting on the
    /// display and a tiny 7 above it — the panel appeared to ignore the key. On
    /// a calculator the big figure is the one being typed. The answer follows it
    /// as it goes, a size down and in the blue, and only settles when there is a
    /// whole sum to settle on.
    private var display: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ZStack(alignment: .trailing) {
                // Zero rather than an empty display: a calculator with nothing
                // typed into it is not broken, it is at zero.
                if store.input.isEmpty {
                    Text("0")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkDim)
                        .allowsHitTesting(false)
                }

                TextField("", text: $store.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($typing)
                    .onSubmit { store.submit() }
            }
            .frame(height: 33)

            Text(store.answer.isEmpty ? " " : "= \(store.answer)")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.tint)
                .lineLimit(1)
                // Twenty digits at full size do not fit any panel; shrinking is
                // what a calculator does instead of hiding the end of a number.
                .minimumScaleFactor(0.5)
                .frame(height: 22)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { store.copyAnswer() }
                .accessibilityAddTraits(.isButton)
                .labelled(store.answer.isEmpty ? "" : "Press to copy")
                .animation(Theme.value, value: store.answer)
        }
    }

    /// One line that always says who is doing the work. Counting is instant and
    /// local; the model is only woken for words, and says so while it thinks.
    /// With nothing to report it explains the sign being typed instead.
    @ViewBuilder
    private var status: some View {
        HStack(spacing: 7) {
            if store.isThinking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                Text("\(store.model) is reading it")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textSecondary)
            } else if !store.failure.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.alert)
                Text(store.failure)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else if !store.note.isEmpty {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tint)
                Text(store.note)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else if !store.hint.isEmpty {
                Text(store.hint)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 14)
    }

    /// What has been counted, newest first.
    ///
    /// Empty, it is one grey line at the top rather than a large glyph in the
    /// middle: a centred illustration in a column that is empty half the time
    /// turns the left half of the tab into a hole.
    @ViewBuilder
    private var past: some View {
        if store.history.isEmpty {
            Text("Nothing counted yet")
                .font(Theme.captionText)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(store.history) { entry in
                        AnswerRow(entry: entry, onRecall: { store.recall(entry) },
                                  onCopy: { store.copy(entry) })
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .fadingBottom(18)
        }
    }
}

/// The keys. Not because a Mac has no number row, but because half the time the
/// hand is on the trackpad and the panel is one press from the notch — and a
/// calculator with no buttons is a text field pretending.
///
/// The right two columns are the signs a keyboard has no key for. Every one of
/// them computes: ∫ is Simpson's rule over four hundred strips, Σ adds the terms
/// up one by one, d/dx is the slope across the point, and det is a determinant
/// by elimination. Nothing here is a symbol that only looks like maths.
private struct Keypad: View {
    @ObservedObject var store: MathStore

    /// Seven columns, and the seventh is the one that was missing.
    ///
    /// ∫, Σ and d/dx all take a function of x as their first argument, and there
    /// was no way to type an x: the keypad put `int(` on the display and then had
    /// nothing to put inside it. Pressing the integral key and getting a dead
    /// display is exactly the complaint that the calculator "does not count these
    /// functions" — the evaluator has always counted them, the keypad could not
    /// spell them.
    private static let rows: [[String]] = [
        ["C", "(", ")", "÷", "√", "^", "x"],
        ["7", "8", "9", "×", "π", "!", "sin"],
        ["4", "5", "6", "−", "∫", "Σ", "cos"],
        ["1", "2", "3", "+", "d/dx", "det", "tan"],
        // Backspace, not a power key: the keyboard already has ^, and a keypad
        // whose only correction is wiping the whole sum is a keypad you leave.
        // The comma is here because the three new keys need one.
        ["0", ".", ",", "⌫", "%", "ln", "="]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Key(label: key, isAnswer: key == "=") { press(key) }
                    }
                }
            }
        }
        .frame(width: 346)
    }

    private func press(_ key: String) {
        switch key {
        case "C":
            store.input = ""
        case "⌫":
            if !store.input.isEmpty { store.input.removeLast() }
        case "=":
            store.submit()
        // The signs on the keys are the ones a person writes; the evaluator
        // reads the ones a keyboard types.
        case "÷": store.input += "/"
        case "×": store.input += "*"
        case "−": store.input += "-"
        case "π": store.input += "pi"
        case "√": store.input += "sqrt("
        case "∫": store.input += "int("
        case "Σ": store.input += "sum("
        case "d/dx": store.input += "deriv("
        case "det": store.input += "det("
        case "sin", "cos", "tan", "ln": store.input += key + "("
        default: store.input += key
        }
    }
}

private struct Key: View {
    let label: String
    var isAnswer = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                // "d/dx" is four characters wide on a key built for one, and a
                // label that outgrows its key is a label that gets clipped.
                .font(.system(size: label.count > 1 ? 11 : 15,
                              weight: .medium,
                              design: .rounded))
                .foregroundStyle(isAnswer ? Theme.tint : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .frame(width: 46, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .fill(hovering ? Theme.fillHover : Theme.surface)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.touch, value: hovering)
    }
}

// MARK: - The graph

/// A curve, and the two facts anybody looks at a curve for: where it crosses
/// zero and what it does at zero.
///
/// Drawn from the same evaluator that produces the numbers, so what is plotted
/// and what is answered can never disagree. It can be dragged sideways and
/// zoomed, because a window fixed at ±10 around zero is the one window a
/// formula is least likely to be interesting in.
struct PlotView: View {
    @ObservedObject var store: MathStore
    @ObservedObject var state: PanelState

    @FocusState private var typing: Bool
    /// Where the middle of the view was when the drag started.
    @State private var anchor: Double?

    /// Every curve on the picture, in the order they are drawn and coloured.
    ///
    /// Kept first, the one being typed last, so the live curve is on top of the
    /// others and its colour never changes under the hand: keeping a curve moves
    /// it from the end of this list to the end of `kept`, which is the same
    /// place.
    private var drawn: [PlotCurve] {
        var list = store.kept.enumerated().map {
            PlotCurve(index: $0.offset, formula: $0.element, isLive: false)
        }
        if !store.plot.isEmpty {
            list.append(PlotCurve(index: list.count, formula: store.plot, isLive: true))
        }
        return list
    }

    var body: some View {
        // Found once and handed to both the picture and the line under it: the
        // hunt costs four hundred evaluations per curve, and doing it twice per
        // frame during a drag is four hundred too many.
        let low = store.centre - store.span
        let high = store.centre + store.span
        let curves = drawn
        let found = curves.map { curve in
            RootSet(curve: curve, values: Formula.roots(curve.formula, from: low, to: high))
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("A formula with x in it — sin(x), x^2 − 4", text: $store.input)
                    .inputField()
                    .font(.system(size: 16, design: .rounded))
                    .focused($typing)
                    .frame(maxWidth: .infinity)

                // Keep this one and start another: the only way to see two
                // functions at once, and the reason anybody draws either.
                GlyphButton(symbol: "plus.rectangle.on.rectangle", size: 12, diameter: 28) {
                    withAnimation(Theme.settle) { store.keepCurve() }
                    typing = true
                }
                .labelled("Keep this curve and draw another")
                .reserved(!store.plot.isEmpty)

                // Always on the row, whether there is anything to clear or not:
                // a control that appears only once it has work to do is one
                // nobody can find when they go looking for it.
                HoverButton(title: "Clear curves") {
                    withAnimation(Theme.settle) { store.dropCurves() }
                }
                .labelled("Take the kept curves off")

                GlyphButton(symbol: "minus.magnifyingglass", size: 12, diameter: 28) {
                    withAnimation(Theme.value) { store.zoom(by: 2) }
                }
                .labelled("Wider")
                GlyphButton(symbol: "plus.magnifyingglass", size: 12, diameter: 28) {
                    withAnimation(Theme.value) { store.zoom(by: 0.5) }
                }
                .labelled("Closer")
                // A crosshair said nothing about what it did. The word does.
                HoverButton(title: "Reset") {
                    withAnimation(Theme.settle) { store.recentre() }
                }
                .labelled("Back to zero, at the usual width")
            }

            if curves.isEmpty {
                MessageView(icon: "chart.xyaxis.line",
                            title: "Nothing to draw",
                            subtitle: "Type a formula with an x in it")
            } else {
                FunctionPlot(curves: curves,
                             centre: store.centre,
                             span: store.span,
                             roots: found)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                if anchor == nil { anchor = store.centre }
                                // 548 points of content across the visible span:
                                // a point of cursor is that much of x.
                                let perPoint = 2 * store.span / 548
                                store.centre = (anchor ?? store.centre) - Double(drag.translation.width) * perPoint
                            }
                            .onEnded { _ in anchor = nil }
                    )

                legend(curves, roots: found)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .onAppear {
            state.wantsKeyboard = true
            typing = true
            FieldCaret.toEnd()
        }
        .onChange(of: store.input) { _, value in
            state.isEditing = !value.isEmpty
        }
        .onDisappear {
            state.wantsKeyboard = false
            state.isEditing = false
        }
    }

    /// Which line is which, and how many times each of them crosses.
    ///
    /// This row used to be a list of the live curve's roots — "x = −3.14, 0,
    /// 3.14" — which was the right figures for the wrong picture the moment
    /// there was more than one curve on it: three functions drawn together and
    /// one function's roots printed underneath, in the one blue all three were
    /// nearly drawn in. The figures moved onto the picture, where each crossing
    /// is ringed in its own curve's colour and pressing one names it. What is
    /// left down here is the key: the colour, the formula, and how often it
    /// meets zero in the window.
    private func legend(_ curves: [PlotCurve], roots: [RootSet]) -> some View {
        HStack(spacing: 12) {
            ForEach(curves) { curve in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(Theme.curve(curve.index))
                        .frame(width: 12, height: 2.5)
                    Text(Formula.pretty(curve.formula))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(curve.isLive ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                    let count = roots.first { $0.curve.index == curve.index }?.values.count ?? 0
                    if count > 0 {
                        Text("×\(count)")
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 6)

            Text("x from \(Formula.brief(store.centre - store.span)) to \(Formula.brief(store.centre + store.span))")
                .font(Theme.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(height: 16)
    }
}

/// One line on the picture: what to draw, and which colour it owns.
struct PlotCurve: Identifiable, Equatable {
    let index: Int
    let formula: String
    let isLive: Bool

    var id: Int { index }
}

/// Where one curve crosses zero.
struct RootSet {
    let curve: PlotCurve
    let values: [Double]
}

private struct FunctionPlot: View {
    let curves: [PlotCurve]
    let centre: Double
    let span: Double
    let roots: [RootSet]

    /// Where the cursor is over the picture, in points. Nil when it is elsewhere.
    @State private var cursor: CGPoint?
    /// The crossing that was last pressed, and the moment it was: it names
    /// itself for a few seconds and then gets out of the way.
    @State private var picked: PickedRoot?
    @State private var forget: DispatchWorkItem?
    /// How much of each curve has been drawn, 0 to 1. Runs once whenever the
    /// set of formulas changes; panning and zooming do not restart it.
    @State private var sweep: Double = 1
    @State private var isDrawing = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let count = max(Int(size.width / 2), 2)
            let low = centre - span
            let high = centre + span
            let samples = curves.map { Formula.curve($0.formula, from: low, to: high, count: count) }
            // The window holds every curve on the picture, not just the live one.
            //
            // It used to be scaled to the curve being typed and to that one
            // alone, which is right for one curve and useless for three: with
            // tan(x) in the field, sin and cos were two flat lines along the
            // middle, because a window wide enough for an asymptote has no room
            // left for anything that lives between −1 and 1. Taken across all of
            // them, with the outer twentieth of the readings thrown away first,
            // tan is the one that gets clipped and the other two are drawn.
            let range = Self.window(across: samples)
            let zeroX = Self.placeX(0, low: low, high: high, width: size.width)
            let zeroY = Self.placeY(0, in: range, height: size.height)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .fill(Theme.surface.opacity(0.45))

                grid(low: low, high: high, range: range, size: size)

                // The axes, drawn only where they actually fall inside the view.
                Path { path in
                    if (low...high).contains(0) {
                        path.move(to: CGPoint(x: zeroX, y: 0))
                        path.addLine(to: CGPoint(x: zeroX, y: size.height))
                    }
                    if range.contains(0) {
                        path.move(to: CGPoint(x: 0, y: zeroY))
                        path.addLine(to: CGPoint(x: size.width, y: zeroY))
                    }
                }
                .stroke(Theme.ink.opacity(0.3), lineWidth: 1)

                // Zero itself, named. Two axes crossing at an unlabelled point
                // is a cross, not an origin — the complaint was exactly this.
                if (low...high).contains(0), range.contains(0) {
                    Text("0")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: zeroX - 8, y: zeroY + 9)
                }

                // One colour each, all at full strength. The kept ones used to be
                // drawn in fading greys behind a blue live one, which said which
                // was being typed and nothing about which was which.
                ForEach(Array(zip(curves, samples)), id: \.0.id) { curve, values in
                    Self.path(for: values, count: count, range: range, size: size,
                              from: 1 - sweep)
                        .stroke(Theme.curve(curve.index),
                                style: StrokeStyle(lineWidth: curve.isLive ? 1.9 : 1.5,
                                                   lineCap: .round, lineJoin: .round))
                }

                // The pen: one dot per curve, sitting at the left end of what has
                // been drawn so far, travelling from the right edge to the left
                // and pulling the line out behind it. Gone the moment it lands.
                if isDrawing {
                    ForEach(Array(zip(curves, samples)), id: \.0.id) { curve, values in
                        if let point = Self.pen(for: values, count: count, range: range,
                                                size: size, at: 1 - sweep) {
                            Circle()
                                .fill(Theme.curve(curve.index))
                                .frame(width: 6, height: 6)
                                .position(point)
                        }
                    }
                }

                // Every crossing marked where it happens, in the colour of the
                // curve that makes it, so a ring on the axis belongs to a line.
                ForEach(roots.indices, id: \.self) { index in
                    let set = roots[index]
                    ForEach(set.values, id: \.self) { root in
                        Circle()
                            .strokeBorder(Theme.curve(set.curve.index), lineWidth: 1.5)
                            .background(Circle().fill(Theme.body))
                            .frame(width: 7, height: 7)
                            .position(x: Self.placeX(root, low: low, high: high, width: size.width),
                                      y: zeroY)
                    }
                }

                pickedTag(low: low, high: high, size: size, zeroY: zeroY)

                readout(low: low, high: high, range: range, size: size, zeroY: zeroY)

                // The two ends of the vertical window, and nothing else. The
                // formula used to be printed in the top right corner, where it
                // landed on the curve it was labelling — and it is already
                // spelled out in the field directly above the picture.
                VStack {
                    HStack {
                        Text(Formula.brief(range.upperBound))
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text(Formula.brief(range.lowerBound))
                        Spacer()
                    }
                }
                .font(Theme.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .padding(7)
            }
            // Pointing at the curve is the question "what is it here?", and it
            // is asked far more often than it is worth clicking for.
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): cursor = point
                case .ended: cursor = nil
                }
            }
            // Pressing a crossing asks the other question: which curve is this
            // one, and where exactly does it cross? The rings are seven points
            // across, which is too small to aim at, so the press is taken
            // anywhere within twenty points of one and the nearest wins.
            .onTapGesture(coordinateSpace: .local) { point in
                pick(at: point, low: low, high: high, width: size.width, zeroY: zeroY)
            }
            .onChange(of: curves) { _, _ in redraw() }
            .onAppear { redraw() }
        }
    }

    /// Names the crossing nearest the press, if there is one near enough.
    private func pick(at point: CGPoint, low: Double, high: Double,
                      width: CGFloat, zeroY: CGFloat) {
        var best: (root: PickedRoot, distance: CGFloat)?
        for set in roots {
            for value in set.values {
                let x = Self.placeX(value, low: low, high: high, width: width)
                let distance = hypot(x - point.x, zeroY - point.y)
                guard distance < 20, distance < (best?.distance ?? .greatestFiniteMagnitude) else { continue }
                best = (PickedRoot(curve: set.curve, x: value, at: CGPoint(x: x, y: zeroY)), distance)
            }
        }

        forget?.cancel()
        withAnimation(Theme.drop) { picked = best?.root }
        guard best != nil else { return }
        let task = DispatchWorkItem { withAnimation(Theme.pop) { picked = nil } }
        forget = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }

    /// The label on a pressed crossing: which curve, and the value it crosses at
    /// in full rather than the two decimals the ring is drawn to.
    @ViewBuilder
    private func pickedTag(low: Double, high: Double, size: CGSize, zeroY: CGFloat) -> some View {
        if let picked {
            VStack(spacing: 1) {
                Text(Formula.pretty(picked.curve.formula) + " = 0")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text("x = \(Formula.format(picked.x))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.curve(picked.curve.index))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.body.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.curve(picked.curve.index).opacity(0.5), lineWidth: 1)
                    )
            )
            .fixedSize()
            // Above the ring, and never off either edge of the picture.
            .position(x: min(max(picked.at.x, 60), size.width - 60),
                      y: max(24, picked.at.y - 28))
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Runs the pen across the picture once. Skipped entirely when the machine
    /// has been told to keep movement down — the curve is simply there.
    private func redraw() {
        picked = nil
        guard !Theme.reduceMotion else {
            sweep = 1
            isDrawing = false
            return
        }
        sweep = 0
        isDrawing = true
        withAnimation(.easeOut(duration: 0.55)) { sweep = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { isDrawing = false }
    }

    /// Dashed lines every 5, or every 50, or every 500 — whatever the window
    /// asks for. Dashed rather than solid because the grid is the paper the
    /// curve is drawn on, and paper does not compete with ink.
    private func grid(low: Double, high: Double, range: ClosedRange<Double>, size: CGSize) -> some View {
        let stepX = MathStore.gridStep(across: high - low)
        let stepY = MathStore.gridStep(across: range.upperBound - range.lowerBound)
        let dash = StrokeStyle(lineWidth: 1, dash: [2, 5])

        return ZStack {
            Path { path in
                for value in stride(from: (low / stepX).rounded(.up) * stepX, through: high, by: stepX) {
                    let x = Self.placeX(value, low: low, high: high, width: size.width)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for value in stride(from: (range.lowerBound / stepY).rounded(.up) * stepY,
                                    through: range.upperBound, by: stepY) {
                    let y = Self.placeY(value, in: range, height: size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Theme.ink.opacity(0.11), style: dash)

            // Only the vertical lines are numbered, and only along the bottom:
            // a number against every line in both directions is a spreadsheet
            // laid over a picture.
            ForEach(Array(stride(from: (low / stepX).rounded(.up) * stepX, through: high, by: stepX)),
                    id: \.self) { value in
                let x = Self.placeX(value, low: low, high: high, width: size.width)
                // Zero is already named at the origin, and a number closer than
                // its own width to the edge is a number cut in half by it.
                if abs(value) > stepX / 2, x > 18, x < size.width - 18 {
                    Text(Formula.brief(value))
                        .font(.system(size: 10.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: x, y: size.height - 11)
                }
            }
        }
    }

    /// What the curve is doing where the cursor is: the point itself, and where
    /// that point stands on each axis.
    @ViewBuilder
    private func readout(low: Double, high: Double, range: ClosedRange<Double>,
                         size: CGSize, zeroY: CGFloat) -> some View {
        // The curve being typed, or the last one kept if the field is empty:
        // hovering answers for one curve, and that is the one it answers for.
        let leading = curves.last
        if let cursor, let leading, size.width > 1 {
            let x = low + Double(cursor.x / size.width) * (high - low)
            let y = try? Formula.value(of: leading.formula, x: x)
            let pointX = Self.placeX(x, low: low, high: high, width: size.width)

            ZStack {
                // Down to the x axis and across to the y axis: the two readings
                // are the point's shadow on each of them.
                Path { path in
                    path.move(to: CGPoint(x: pointX, y: 0))
                    path.addLine(to: CGPoint(x: pointX, y: size.height))
                }
                .stroke(Theme.tint.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                if let y, y.isFinite, range.contains(y) {
                    let pointY = Self.placeY(y, in: range, height: size.height)

                    Path { path in
                        path.move(to: CGPoint(x: 0, y: pointY))
                        path.addLine(to: CGPoint(x: size.width, y: pointY))
                    }
                    .stroke(Theme.tint.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    Circle()
                        .fill(Theme.tint)
                        .frame(width: 7, height: 7)
                        .position(x: pointX, y: pointY)

                    // y against the left edge, x against the bottom: each figure
                    // sits on the axis it belongs to.
                    PlotTag(text: Formula.brief(y))
                        .position(x: 26, y: max(10, min(size.height - 10, pointY)))
                    PlotTag(text: Formula.brief(x))
                        .position(x: max(24, min(size.width - 24, pointX)), y: size.height - 10)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// One curve as a path, jumps and all.
    ///
    /// `from` is where the pen currently is, as a fraction of the width: 0 draws
    /// the whole curve, 0.4 draws the right-hand three fifths of it. Sliced by
    /// sample rather than by path length, so the pen keeps a steady speed across
    /// the picture instead of racing the flat parts and crawling the steep ones.
    private static func path(for samples: [Double?], count: Int,
                             range: ClosedRange<Double>, size: CGSize,
                             from: Double = 0) -> Path {
        let first = max(0, min(samples.count - 1, Int(from * Double(samples.count))))
        return Path { path in
            var pen = false
            var lastY: CGFloat?
            for index in first..<samples.count {
                let sample = samples[index]
                guard let sample, range.contains(sample) else {
                    pen = false
                    lastY = nil
                    continue
                }
                let x = size.width * CGFloat(index) / CGFloat(max(count - 1, 1))
                let y = placeY(sample, in: range, height: size.height)
                // An asymptote is a jump, not a line: tan(x) must not be drawn
                // with a vertical stroke through the whole plot.
                if let lastY, abs(y - lastY) > size.height * 0.6 { pen = false }
                if pen {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y))
                    pen = true
                }
                lastY = y
            }
        }
    }

    /// Where the pen is: the leading end of the part already drawn. Nil where
    /// the curve has nothing at that x — the pen has run into an asymptote and
    /// there is no point to sit on.
    private static func pen(for samples: [Double?], count: Int,
                            range: ClosedRange<Double>, size: CGSize,
                            at fraction: Double) -> CGPoint? {
        let index = max(0, min(samples.count - 1, Int(fraction * Double(samples.count))))
        guard let sample = samples[index], range.contains(sample) else { return nil }
        return CGPoint(x: size.width * CGFloat(index) / CGFloat(max(count - 1, 1)),
                       y: placeY(sample, in: range, height: size.height))
    }

    private static func placeX(_ value: Double, low: Double, high: Double, width: CGFloat) -> CGFloat {
        guard high > low else { return width / 2 }
        return width * CGFloat((value - low) / (high - low))
    }

    private static func placeY(_ value: Double, in range: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        let extent = range.upperBound - range.lowerBound
        guard extent > 0 else { return height / 2 }
        return height * (1 - CGFloat((value - range.lowerBound) / extent))
    }

    /// The window that holds every curve worth holding.
    ///
    /// Each curve is measured on its own first, then the windows are joined —
    /// except for a curve whose window is more than six times taller than the
    /// tightest one, which is left out of the join and simply clipped. That one
    /// rule is what makes sin, cos and tan drawn together legible: tan wants a
    /// window forty units tall and the other two live inside two, so joining all
    /// three honestly would draw sin and cos as one flat line along the middle.
    /// The tall one is the one that gives way, because a curve that runs off the
    /// top of the picture still reads as a curve running off the top, and a
    /// curve flattened into the axis reads as nothing at all.
    private static func window(across curves: [[Double?]]) -> ClosedRange<Double> {
        let windows = curves.filter { $0.contains { $0 != nil } }.map { window(for: $0) }
        guard let first = windows.first else { return -1...1 }
        guard windows.count > 1 else { return first }

        let extents = windows.map { $0.upperBound - $0.lowerBound }
        let tightest = extents.min() ?? 1
        let kept = zip(windows, extents)
            .filter { $0.1 <= max(tightest * 6, 0.000_001) }
            .map { $0.0 }
        let joining = kept.isEmpty ? windows : kept

        let low = joining.map(\.lowerBound).min() ?? -1
        let high = joining.map(\.upperBound).max() ?? 1
        return low < high ? low...high : (low - 1)...(low + 1)
    }

    /// The vertical window of one curve. Taken off the middle of the sorted
    /// values rather than the extremes: one point near an asymptote is worth a
    /// million, and scaling to it flattens the whole curve into a line.
    private static func window(for samples: [Double?]) -> ClosedRange<Double> {
        let values = samples.compactMap { $0 }.sorted()
        guard let first = values.first, let last = values.last else { return -1...1 }

        let trim = values.count / 40
        var low = values[min(trim, values.count - 1)]
        var high = values[max(values.count - 1 - trim, 0)]
        if low == high { low -= 1; high += 1 }

        // Zero belongs on the plot whenever it is anywhere near the curve.
        if low > 0, low < (high - low) { low = 0 }
        if high < 0, -high < (high - low) { high = 0 }

        let padding = (high - low) * 0.1
        return max(low - padding, first - padding)...min(high + padding, last + padding)
    }
}

/// A crossing that has been pressed: which curve it belongs to, where it is in
/// x, and where on the picture the ring was drawn.
private struct PickedRoot: Equatable {
    let curve: PlotCurve
    let x: Double
    let at: CGPoint
}

/// A figure read off the plot, on a plate dark enough to survive landing on the
/// curve it is describing.
private struct PlotTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.body.opacity(0.85))
            )
            .fixedSize()
    }
}

/// A sum already done. Pressing it puts it back on the display, which is what a
/// history is for: the next sum is usually the last one with a number changed.
/// The copy button is still here, one press to the right, for the times the
/// answer itself is what is wanted.
///
/// Written the way it was meant rather than the way it was typed — `√(x²+1)`,
/// not `sqrt(x^2+1)`. Nothing is being edited on this row, so nothing is lost by
/// setting it properly.
private struct AnswerRow: View {
    let entry: MathStore.Entry
    let onRecall: () -> Void
    let onCopy: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(Formula.pretty(entry.source))
                .font(Theme.rowText)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Formula.pretty(entry.result))
                .font(Theme.metaText)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            GlyphButton(symbol: "doc.on.doc", size: 10, diameter: 22, action: onCopy)
                .labelled("Copy this line")
                .reserved(hovering)
        }
        .rowBackground(hovering: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onRecall)
        .labelled("Press to put it back on the display")
    }
}
