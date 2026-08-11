import SwiftUI

// MARK: - Colour

/// The eyedropper, and what has been picked with it.
///
/// The button used to be a word in the top left corner, above a row of swatches
/// and an empty middle — so the one thing the tab is for was the smallest thing
/// on it and the hardest to find. The dropper is the middle of the tab now and
/// the button is directly under it, where a hand already on its way to the
/// picture lands.
struct ColorView: View {
    @ObservedObject var store: ColorStore

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Button(action: { store.pick() }) {
                VStack(spacing: 9) {
                    Image(systemName: "eyedropper.halffull")
                        .accessibilityHidden(true)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(hovering ? Theme.tint : Theme.textSecondary)

                    Text("Pick a colour")
                        .font(Theme.rowText)
                        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                }
                .frame(width: 190, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                        .fill(hovering ? Theme.fillHover : Theme.surface)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Theme.touch, value: hovering)

            // Anything picked, newest first, centred under the dropper rather
            // than pushed against the left edge of a tab that is otherwise empty.
            HStack(spacing: 10) {
                ForEach(store.swatches) { swatch in
                    SwatchTile(swatch: swatch) { store.copy(swatch.hex) }
                }
            }
            .frame(height: 74)
            .animation(Theme.settle, value: store.swatches.count)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.gutter)
    }
}

private struct SwatchTile: View {
    let swatch: ColorStore.Swatch
    let onCopy: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Color(nsColor: swatch.color))
                .frame(width: 62, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                        .strokeBorder(hovering ? Theme.accent : Theme.hairline, lineWidth: 1)
                )
            Text(swatch.hex)
                .font(Theme.captionText)
                .monospacedDigit()
                .foregroundStyle(hovering ? Theme.tint : Theme.textTertiary)
        }
        .scaleEffect(hovering ? 1.04 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @ObservedObject var store: DownloadsStore
    @ObservedObject var pins: PinStore

    var body: some View {
        Group {
            if store.items.isEmpty {
                MessageView(icon: "arrow.down.circle",
                            title: "Nothing in Downloads",
                            subtitle: "Or macOS has not granted the folder yet")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(store.items) { item in
                            DownloadRow(item: item,
                                        onReveal: { store.reveal(item) },
                                        onPin: { pins.pin(url: item.url) })
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .fadingBottom()
            }
        }
    }
}

private struct DownloadRow: View {
    let item: DownloadsStore.Item
    let onReveal: () -> Void
    let onPin: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 26, height: 26)

            // Name over kind: the icon says roughly what a file is, the words
            // say exactly.
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.kind)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Two columns rather than one run-on line, so sizes line up under
            // sizes and times under times.
            Text(item.size)
                .font(Theme.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 74, alignment: .trailing)

            Text(item.age)
                .font(Theme.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 64, alignment: .trailing)

            GlyphButton(symbol: "pin", size: 11, diameter: 24, action: onPin)
                .labelled("Pin this download")
                .reserved(hovering)
            GlyphButton(symbol: "folder", size: 11, diameter: 24, action: onReveal)
                .labelled("Show in Finder")
                .reserved(hovering)
        }
        .rowBackground(hovering: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .accessibilityAddTraits(.isButton)
        .labelled("Open \(item.name)")
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Reveal in Finder", action: onReveal)
            Button("Pin to screen", action: onPin)
        }
    }
}

// MARK: - Passwords

/// Generate, take, and say what it was for. The saying is the point: a password
/// with no note beside it is a password nobody can ever retire.
struct PasswordView: View {
    @ObservedObject var store: PasswordStore
    @ObservedObject var state: PanelState

    @State private var label = ""
    /// The two halves of "keep one I already have": the password itself and what
    /// it is for, side by side on one line, because they are one thought.
    @State private var ownSecret = ""
    @State private var ownLabel = ""
    @FocusState private var naming: Bool

    /// The password, then the two things that can be done with it, then the two
    /// settings that shape it.
    ///
    /// It used to read as a row of unlabelled controls: a circular arrow that
    /// might have meant reload, a chip saying "Symbols" that looked like the
    /// button that made a new one, and a word "Take" at the far end of the row
    /// with nothing saying what it took. The two actions are spelled out now and
    /// the settings sit on their own line, below, where settings belong.
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.candidate)
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                        .fill(Theme.fillInput)
                )

            HStack(spacing: 8) {
                ActionButton(symbol: "arrow.triangle.2.circlepath", title: "Another one") {
                    store.generate()
                }
                ActionButton(symbol: "doc.on.doc", title: "Copy and keep", isPrimary: true) {
                    store.take()
                }

                Spacer(minLength: 8)

                Text(store.note.isEmpty ? store.strength : store.note)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            // Lengths to pick from, not a slider to aim at.
            //
            // A mini slider on black is a white lozenge with no visible track:
            // it reads as a stray artefact rather than a control, and nobody
            // needs a password of exactly 27 characters anyway. Six lengths
            // cover every site's rules and each one is a target you can hit.
            HStack(spacing: 6) {
                ForEach(Self.lengths, id: \.self) { length in
                    // Lit by nearest, not by equals: a length of 21 remembered
                    // from the old slider matched none of them, and a row of six
                    // chips with none of them lit reads as a broken control.
                    Chip(title: "\(length)", isSelected: chosenLength == length, padding: 9) {
                        withAnimation(Theme.touch) { store.length = length }
                    }
                }

                ToggleChip(title: "Symbols !@#", isOn: store.useSymbols) {
                    store.useSymbols.toggle()
                }

                Spacer(minLength: 0)
            }

            // One line, two jobs. Naming the generated one takes the same line
            // rather than a fourth of its own: both are "this password, and what
            // it is for", and the tab has no room to say that twice.
            if store.isNaming {
                HStack(spacing: 6) {
                    TextField("What is it for?", text: $label)
                        .inputField()
                        .focused($naming)
                        .onSubmit { commit() }
                        .onExitCommand { cancel() }
                    GlyphButton(symbol: "checkmark", size: 12, diameter: 28) { commit() }
                        .labelled("Keep this password")
                    GlyphButton(symbol: "xmark", size: 12, diameter: 28) { cancel() }
                        .labelled("Do not keep it")
                }
                .onAppear {
                    naming = true
                    state.isEditing = true
                }
            } else {
                HStack(spacing: 6) {
                    SecureField("A password you already have", text: $ownSecret)
                        .inputField()
                        .frame(width: 232)
                        .onSubmit { keepOwn() }
                    TextField("What it is for", text: $ownLabel)
                        .inputField()
                        .frame(maxWidth: .infinity)
                        .onSubmit { keepOwn() }
                    GlyphButton(symbol: "plus", size: 12, diameter: 28) { keepOwn() }
                        .labelled("Keep it in the keychain")
                }
                // Not a button: a click anywhere on the row raises the keyboard
                // for the fields inside it, and those are reachable on their own.
                // hig-disable-next-line swift/on-tap-gesture-without-traits -- see above
                .onTapGesture { state.isEditing = true }
            }

            if store.entries.isEmpty {
                // One grey line, not a centred illustration: everything above it
                // is already the tab, and the space left under all of it is two
                // rows tall.
                Text("Nothing kept yet — kept passwords go to the login keychain")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(store.entries) { entry in
                            PasswordRow(entry: entry,
                                        count: store.entries.count,
                                        onCopy: { store.copy(entry) })
                        }
                    }
                }
                .fadingBottom(16)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 2)
        .animation(Theme.swap, value: store.isNaming)
        .animation(Theme.settle, value: store.entries.count)
        .onDisappear { state.isEditing = false }
    }

    /// Six lengths, enough for every site's rules.
    private static let lengths = [12, 16, 20, 24, 32, 48]

    private var chosenLength: Int {
        Self.lengths.min { abs($0 - store.length) < abs($1 - store.length) } ?? 20
    }

    private func keepOwn() {
        guard store.add(secret: ownSecret, label: ownLabel) else { return }
        ownSecret = ""
        ownLabel = ""
        state.isEditing = false
    }

    private func commit() {
        store.save(label: label)
        label = ""
        state.isEditing = false
    }

    private func cancel() {
        store.cancelNaming()
        label = ""
        state.isEditing = false
    }
}

/// A kept password: its name, when it was made, and one way to get it back.
///
/// There is no bin on this row on purpose — see `PasswordStore.add` for why.
private struct PasswordRow: View {
    let entry: PasswordStore.Entry
    let count: Int
    let onCopy: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "key.fill")
                .accessibilityHidden(true)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14)

            Text(entry.label)
                .font(Theme.scaled(15, count: count, comfortable: 4))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(entry.dateLabel)
                .font(Theme.metaText)
                .foregroundStyle(Theme.textTertiary)

            GlyphButton(symbol: "doc.on.doc", size: 10, diameter: 22, action: onCopy)
                .labelled("Copy the password")
                .reserved(hovering)
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, max(3, Theme.rowPaddingV - CGFloat(max(0, count - 4))))
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(hovering ? Theme.fillHover : .clear)
        )
        .animation(Theme.touch, value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
    }
}

// MARK: - Image tools

/// Format conversion and background removal share a screen because they share a
/// gesture: put a picture here, press the one button, get a file beside it.
struct ImageToolView: View {
    @ObservedObject var store: ImageToolStore
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var state: PanelState
    let mode: ShelfMode

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            dropWell

            VStack(alignment: .leading, spacing: 10) {
                // Three ways in, in the order they get used: the shelf, a file
                // chosen in Finder, or a picture dropped on the well. Only two
                // of them existed before, and the obvious one — go and find the
                // file — was the one missing.
                ActionButton(symbol: "folder", title: "Choose in Finder") { choose() }

                if mode == .convert {
                    HStack(spacing: 3) {
                        ForEach(ImageToolStore.Format.allCases) { format in
                            Chip(title: format.title, isSelected: store.format == format) {
                                store.format = format
                            }
                        }
                    }
                    ActionButton(symbol: "arrow.triangle.2.circlepath",
                                 title: store.isWorking ? "Converting…" : "Convert",
                                 isPrimary: store.sourceURL != nil) { store.convert() }
                } else {
                    ActionButton(symbol: "person.and.background.dotted",
                                 title: store.isWorking ? "Cutting…" : "Remove background",
                                 isPrimary: store.sourceURL != nil) { store.removeBackground() }
                }

                if !store.status.isEmpty {
                    Text(store.status)
                        .font(Theme.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                if store.lastResult != nil {
                    ActionButton(symbol: "magnifyingglass", title: "Show the file") { store.reveal() }
                }

                Spacer(minLength: 0)

                if !shelf.items.isEmpty {
                    Text("From the shelf")
                        .font(Theme.captionText)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 6) {
                        ForEach(shelf.items.prefix(5)) { item in
                            Button {
                                store.load(item.url)
                            } label: {
                                Group {
                                    if let thumbnail = item.thumbnail {
                                        Image(nsImage: thumbnail)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Theme.surface
                                    }
                                }
                                .frame(width: 46, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(store.sourceURL == item.url ? Theme.tint : Theme.hairline,
                                                      lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 2)
    }

    /// A Finder dialog takes the focus away from the panel, and a panel that
    /// loses focus folds itself up — with the dialog it opened still on screen.
    /// Pinning it for the length of the choice is what keeps the two together.
    private func choose() {
        let wasPinned = state.isPinned
        state.isPinned = true
        store.choose { state.isPinned = wasPinned }
    }

    private var dropWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Theme.surface)

            if let preview = store.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "photo")
                        .accessibilityHidden(true)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.inkDim)
                    Text("Drop a picture or a PDF")
                        .font(Theme.captionText)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: 210, height: 168)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { store.load(url) }
            }
            return true
        }
    }
}

// MARK: - VPN

struct VPNView: View {
    @ObservedObject var store: VPNStore

    var body: some View {
        Group {
            if store.connections.isEmpty {
                MessageView(icon: "lock.shield",
                            title: "No VPN configured",
                            subtitle: "Add one in Network settings and it appears here",
                            action: ("Open Network settings", { openSettings() }))
            } else {
                VStack(spacing: 1) {
                    ForEach(store.connections) { connection in
                        VPNRow(connection: connection, isBusy: store.isBusy) {
                            store.toggle(connection)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 4)
            }
        }
        .onAppear { store.activate() }
        .onDisappear { store.deactivate() }
    }

    private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct VPNRow: View {
    let connection: VPNStore.Connection
    let isBusy: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connection.isConnected ? Theme.accent : Theme.inkDim)
                .frame(width: 7, height: 7)

            Text(connection.name)
                .font(Theme.rowText)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 8)

            Text(connection.isConnected ? "connected" : "off")
                .font(Theme.metaText)
                .foregroundStyle(Theme.textTertiary)

            HoverButton(title: connection.isConnected ? "Disconnect" : "Connect", action: action)
                .disabled(isBusy)
        }
        .rowBackground(hovering: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Who is watching

struct PrivacyView: View {
    @ObservedObject var store: PrivacyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SensorCard(title: "Microphone",
                           symbol: "mic",
                           isActive: store.microphoneInUse,
                           caption: store.listeners.first?.name ?? (store.microphoneInUse ? "in use" : "idle"))
                SensorCard(title: "Camera",
                           symbol: "video",
                           isActive: store.cameraInUse,
                           caption: store.cameraInUse ? "in use" : "idle")
                SensorCard(title: "Location",
                           symbol: "location",
                           isActive: store.locationEnabled,
                           caption: store.locationEnabled ? "services on" : "services off",
                           isAlarming: false)
            }

            if store.listeners.isEmpty {
                Text(store.microphoneInUse
                     ? "Something is recording, but macOS will not name it"
                     : "Nothing is listening")
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(store.listeners) { user in
                            HStack(spacing: 9) {
                                if let icon = user.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                }
                                Text(user.name)
                                    .font(Theme.rowText)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: 8)
                                Text("microphone")
                                    .font(Theme.metaText)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .rowBackground(hovering: false)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                // Three labels for three settings pages, worded the same way:
                // "Microphone settings / Camera / Location" read as one button
                // and two nouns.
                HoverButton(title: "Microphone settings") { store.openPrivacySettings("Microphone") }
                HoverButton(title: "Camera settings") { store.openPrivacySettings("Camera") }
                HoverButton(title: "Location settings") { store.openPrivacySettings("LocationServices") }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
    }
}

private struct SensorCard: View {
    let title: String
    let symbol: String
    let isActive: Bool
    let caption: String
    /// Red means "someone is using this right now". Location services being
    /// switched on is a setting, not an event, so it never earns the colour.
    var isAlarming: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: isActive ? "\(symbol).fill" : "\(symbol).slash")
                    .accessibilityHidden(true)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? (isAlarming ? Theme.alert : Theme.textSecondary) : Theme.textTertiary)
                Text(title)
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            Text(caption)
                .font(Theme.captionText)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

// MARK: - Screen recording

/// Recording the screen, from the shelf that will hold the result.
///
/// One press for the obvious thing and one for the one that needs a decision:
/// the whole screen goes straight away, a region hands over to the system
/// selector because dragging out a rectangle is a thing macOS already does
/// properly. Everything else on this page is the two or three switches that
/// change what ends up in the file, and they are switches rather than a menu
/// because all three are answered at a glance.
///
/// While a recording runs the page is the clock and the stop button, nothing
/// else: the tab has one job at that moment and offering the switches that no
/// longer apply would be offering to change a thing already being written.
struct RecordView: View {
    @ObservedObject var store: RecordStore

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            // The refusal is written above the controls, never instead of them.
            // It replaced them at first, and that is a trap: macOS refuses the
            // first recording, the person grants the permission, comes back —
            // and the tab is still an error message with no button on it to try
            // again with.
            if let failure = store.failure, store.stage == .idle {
                Button(action: { store.openPermissionSettings() }) {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                            .font(.system(size: 11, weight: .semibold))
                        Text(failure)
                            .font(Theme.metaText)
                        Text("Open the settings pane")
                            .font(Theme.metaText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .foregroundStyle(Theme.alert)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .labelled("Open Privacy & Security, where screen recording is granted")
            }

            switch store.stage {
            case .idle: idle
            case .recording: running
            case .delegated: waiting
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.gutter)
        .animation(Theme.settle, value: store.stage)
        .animation(Theme.settle, value: store.failure)
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 14) {
            Button(action: { store.startFullScreen() }) {
                VStack(spacing: 9) {
                    Image(systemName: "record.circle")
                        .accessibilityHidden(true)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(hovering ? Theme.tint : Theme.textSecondary)

                    Text("Record the screen")
                        .font(Theme.rowText)
                        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textTertiary)
                }
                .frame(width: 214, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                        .fill(hovering ? Theme.fillHover : Theme.surface)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Theme.touch, value: hovering)

            ActionButton(symbol: "viewfinder", title: "Record a part") {
                store.startRegion()
            }

            // What goes into the file. Off-by-default sound sits last: it is the
            // one of the three with a bearing on the room the Mac is in.
            HStack(spacing: 8) {
                ToggleChip(title: "Pointer", isOn: store.showsCursor) {
                    store.showsCursor.toggle()
                }
                ToggleChip(title: "Clicks", isOn: store.showsClicks) {
                    store.showsClicks.toggle()
                }
                ToggleChip(title: "Microphone", isOn: store.capturesAudio) {
                    store.capturesAudio.toggle()
                }
            }

            Text("The film lands on the shelf and nowhere else")
                .font(Theme.captionText)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // The live thing on this tab, so it wears the colour — and it
                // breathes, because a clock that has stopped and a clock that is
                // running look identical for the second between two ticks.
                Circle()
                    .fill(Theme.tint)
                    .frame(width: 12, height: 12)
                    .opacity(Int(store.elapsed) % 2 == 0 ? 1 : 0.35)
                    .animation(Theme.value, value: store.elapsed)

                Text(store.elapsedLabel)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tint)
            }

            Text("Recording the whole screen")
                .font(Theme.metaText)
                .foregroundStyle(Theme.textSecondary)

            ActionButton(symbol: "stop.fill", title: "Stop and keep it", isPrimary: true) {
                store.stop()
            }
            .padding(.top, 2)
        }
    }

    // MARK: Handed to the system

    private var waiting: some View {
        MessageView(icon: "viewfinder",
                    title: "Choose the part to record",
                    subtitle: "macOS is holding the selector. Its own stop button, up in the menu bar, ends the recording.")
    }
}
