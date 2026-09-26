import SwiftUI

struct PulseInterpretationEditor: View {
    let timeSignature: TimeSignature
    @Binding var bpm: Int
    @Binding var interpretation: PulseInterpretation
    @Binding var accentPattern: [ClickAccentLevel]?
    @State private var requested: PulseInterpretation?

    private var supportsGrouping: Bool {
        timeSignature.beatUnit == 8 && [6, 9, 12].contains(timeSignature.beatsPerMeasure)
    }

    private var equivalentBPM: Int? {
        guard let requested else { return nil }
        return ClickPulseGrid(timeSignature: timeSignature, pulseInterpretation: interpretation,
                              bpm: bpm, sampleRate: 44_100).equivalentBPM(for: requested)
    }

    var body: some View {
        if supportsGrouping {
            VStack(alignment: .leading, spacing: 6) {
                Text("BPM pulse").font(.callout.weight(.medium))
                Menu(interpretation.label) {
                    ForEach(PulseInterpretation.allCases) { choice in
                        Button(choice.label) {
                            if choice != interpretation { requested = choice }
                        }
                    }
                }
                Text("\(timeSignature.beatsPerMeasure) eighth-note pulses or \(timeSignature.beatsPerMeasure / 3) groups of three per bar. Changing this can change the bar length.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .confirmationDialog("Change BPM pulse?", isPresented: Binding(
                get: { requested != nil },
                set: { if !$0 { requested = nil } }
            )) {
                if let equivalentBPM {
                    Button("Use \(equivalentBPM) BPM (closest bar length)") {
                        bpm = equivalentBPM
                        interpretation = requested ?? interpretation
                        accentPattern = nil
                        requested = nil
                    }
                }
                Button("Keep \(bpm) BPM (change bar length)") {
                    interpretation = requested ?? interpretation
                    accentPattern = nil
                    requested = nil
                }
                Button("Cancel", role: .cancel) { requested = nil }
            } message: {
                Text("\(interpretation.label) → \(requested?.label ?? interpretation.label)")
            }
        }
    }
}

/// Edits a song or rehearsal pattern while keeping the legacy global accent as the fallback.
struct ClickAccentPatternEditor: View {
    let pulseCount: Int
    let fallback: ClickAccentMode
    @Binding var pattern: [ClickAccentLevel]?
    var compact = false

    private var displayed: [ClickAccentLevel] {
        if let pattern, pattern.count == pulseCount { return pattern }
        return (0..<pulseCount).map { index in
            index == 0 && fallback == .downbeat ? .strong : .normal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Beat accents").font(.callout.weight(.medium))
                Spacer()
                if pattern != nil {
                    Button("Reset to default") { pattern = nil }
                        .font(.caption)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                     count: min(compact ? 2 : 4, max(1, pulseCount))), spacing: 6) {
                ForEach(0..<pulseCount, id: \.self) { index in
                    let level = displayed[index]
                    Button {
                        var next = displayed
                        next[index] = level.next
                        pattern = next
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(index + 1)").font(.caption.weight(.semibold))
                            Text(level.label).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Beat \(index + 1), \(level.label)")
                    .help("Beat \(index + 1): \(level.label). Click to change.")
                }
            }
            if displayed.allSatisfy({ $0 == .mute }) {
                Text("Silent bar: no clicks will sound.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct CountoffPolicyEditor: View {
    @Binding var policy: CountoffPolicy
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var stopsAfterCountoff: Binding<Bool> {
        Binding(
            get: { policy.after == .countoffOnly },
            set: { policy.after = $0 && policy.bars > 0 ? .countoffOnly : .continueClick }
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SustainSpace.md) {
                title
                lengthPicker
                stopToggle
            }
            VStack(alignment: .leading, spacing: SustainSpace.sm) {
                title
                HStack(spacing: SustainSpace.md) {
                    lengthPicker
                    stopToggle
                }
            }
            VStack(alignment: .leading, spacing: SustainSpace.sm) {
                title
                lengthPicker
                stopToggle
            }
        }
        .padding(SustainSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: SustainRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: SustainRadius.control)
                .strokeBorder(palette.surfaceEdge.opacity(0.65), lineWidth: 1)
        }
        .help("Choose zero, one, or two countoff bars. Stop click after countoff leaves pads playing.")
    }

    private var title: some View {
        Text("COUNT IN")
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(palette.textSecondary)
            .fixedSize()
    }

    private var lengthPicker: some View {
        Picker("Countoff length", selection: $policy.bars) {
            Text("Off").tag(0)
            Text("1 bar").tag(1)
            Text("2 bars").tag(2)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 184)
        .onChange(of: policy.bars) { _, bars in
            if bars == 0 && policy.after == .countoffOnly {
                policy.after = .continueClick
            }
        }
    }

    private var stopToggle: some View {
        Toggle("Stop click after", isOn: stopsAfterCountoff)
            .toggleStyle(.switch)
            .font(.caption)
            .fixedSize()
            .disabled(policy.bars == 0)
    }
}
