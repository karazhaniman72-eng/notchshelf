import SwiftUI

struct SystemView: View {
    @ObservedObject var store: SystemStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            charges
            Rectangle().fill(Theme.hairline).frame(height: 1)
            memory
            Spacer(minLength: 8)

            // The row of quick actions that used to sit here is gone: four
            // glyphs the size of a full stop, each duplicating something the
            // menu bar already does one click away.
            facts
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 4)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Batteries

    private var charges: some View {
        HStack(spacing: 10) {
            if store.devices.isEmpty {
                Text("No batteries found")
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.devices) { device in
                    ChargeCard(device: device)
                }
                // Never stretch two cards across the whole panel: a half-empty
                // row of giants reads as a layout that broke.
                if store.devices.count < 3 {
                    ForEach(0..<(3 - store.devices.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 74)
    }

    // MARK: - Memory

    /// How much memory is gone, and — the only question that follows from it —
    /// who has it.
    ///
    /// There used to be a button here that ran `/usr/sbin/purge` behind the
    /// system's password prompt. It asked for administrator rights, from a panel
    /// in the notch, to drop the disk cache: memory macOS is holding on purpose,
    /// which it fills straight back up while the machine runs slower for having
    /// lost it. A password for a number that moves and comes back is a bad
    /// trade, and the four names below are what anybody was reading the meter
    /// for anyway.
    private var memory: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Memory")
                    .font(Theme.rowText)
                    .foregroundStyle(Theme.textSecondary)
                Text(store.memory.value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(store.memory.caption)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }

            LinearMeter(fraction: store.memory.fraction,
                        tint: store.memory.isCritical ? Theme.alert : Theme.accent)

            eaters
        }
    }

    /// The four applications holding the most, each with its share of the
    /// machine drawn under it. Three of them used to be one line of grey text
    /// beside a button; the figures were true and unreadable, because a name and
    /// a size with nothing between them is a sentence rather than a table.
    private var eaters: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(store.processes) { process in
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.name)
                        .font(Theme.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(SystemStore.gigabytes(process.bytes))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    // Against the whole machine, not against each other: a bar
                    // scaled to the biggest app says Chrome is the worst, which
                    // is not news. Scaled to the RAM in the Mac it says how much
                    // of it Chrome has, which is the question.
                    LinearMeter(fraction: store.share(of: process), height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: 46)
    }

    // MARK: - The rest of what the machine knows

    /// Five readings that were one grey sentence along the bottom edge.
    ///
    /// Each keeps its own word above it now, in a row across the strip that was
    /// black. They are still the quietest thing on the tab — none of them is
    /// news — but a figure with its name over it can be found, and a figure in
    /// the middle of a sentence has to be read for.
    private var facts: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(store.facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.name)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                    Text(fact.value)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: 36)
    }
}

/// One battery, whatever it is attached to.
private struct ChargeCard: View {
    let device: SystemStore.DeviceCharge

    private var tint: Color {
        if device.isCritical { return Theme.alert }
        return device.isOffline ? Theme.textTertiary : Theme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: device.symbol)
                    .accessibilityHidden(true)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text("\(device.percent)%")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(device.isOffline ? Theme.textSecondary : Theme.textPrimary)
                Spacer(minLength: 0)
            }

            LinearMeter(fraction: Double(device.percent) / 100, tint: tint)

            HStack(spacing: 5) {
                Text(device.name)
                    .font(Theme.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if !device.caption.isEmpty {
                    Text(device.caption)
                        .font(Theme.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .fill(Theme.surface.opacity(0.55))
        )
    }
}
