import SwiftUI

/// Fixture-only Rehearse composition for reviewing the Future Signal system.
/// Actions and values are intentionally local; no AppStore or audio engine is connected.
struct FutureSignalRehearseSpecimen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: SustainSpace.lg) {
                    header
                    selectedPadSurface

                    if geometry.size.width >= 1040 {
                        HStack(alignment: .top, spacing: SustainSpace.lg) {
                            padPanel.frame(maxWidth: .infinity)
                            clickPanel.frame(maxWidth: .infinity)
                        }
                    } else {
                        padPanel
                        clickPanel
                    }
                }
                .padding(SustainSpace.screen)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(palette.canvas)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            Text("Rehearse")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Free play pads, click, countoff, and live levels")
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var selectedPadSurface: some View {
        FutureSignalPerformanceSurface(state: .playing) {
            VStack(alignment: .leading, spacing: SustainSpace.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: SustainSpace.xs) {
                        Text("SELECTED PAD")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(palette.textSecondary)
                        Text("C")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()
                    Text("72 BPM · 4/4 · Beat")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }

                HStack(spacing: SustainSpace.section) {
                    FutureSignalOpenChannelStatus(kind: .pad, state: .playing, detail: "C · Included")
                    FutureSignalOpenChannelStatus(kind: .click, state: .playing, detail: "72 BPM · 4/4 · Beat")
                }
            }
        }
        .frame(height: 178)
    }

    private var padPanel: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            sectionHeading("Pads", detail: "C selected · Playing")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: SustainSpace.sm)], spacing: SustainSpace.sm) {
                FutureSignalPadTile(title: "C", detail: "Included", isSelected: true, isPlaying: true) {}
                FutureSignalPadTile(title: "D", detail: "Included") {}
                FutureSignalPadTile(title: "E", detail: "Included") {}
                FutureSignalPadTile(title: "F", detail: "Included") {}
                FutureSignalPadTile(title: "G", detail: "Included") {}
                FutureSignalPadTile(title: "A", detail: "Included") {}
            }

            HStack {
                Toggle("Show Included Pads", isOn: .constant(true))
                    .toggleStyle(.checkbox)
                Spacer()
                Button(role: .destructive) {} label: {
                    Label("Stop Pad", systemImage: "stop.fill")
                }
            }

            FutureSignalChannelLevel(kind: .pad, value: .constant(0.42), isActive: true)
        }
        .padding(SustainSpace.lg)
        .background(panelBackground)
    }

    private var clickPanel: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            sectionHeading("Click", detail: "Playing")

            HStack(spacing: SustainSpace.md) {
                Button {} label: {
                    Label("Pause Click", systemImage: "pause.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.activeSignal)

                Toggle("Countoff", isOn: .constant(true))

                Picker("Time", selection: .constant(TimeSignature.fourFour)) {
                    ForEach(TimeSignature.common, id: \.self) { signature in
                        Text(signature.description).tag(signature)
                    }
                }
                .frame(width: 112)
            }

            HStack(alignment: .firstTextBaseline, spacing: SustainSpace.sm) {
                Text("72")
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text("BPM")
                    .font(.title3)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Stepper("Tempo", value: .constant(72), in: 40...220)
                    .labelsHidden()
            }

            HStack(spacing: SustainSpace.md) {
                Picker("Accent", selection: .constant(ClickAccentMode.downbeat)) {
                    ForEach(ClickAccentMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Picker("Countoff Sound", selection: .constant(CountoffSound.counted)) {
                    ForEach(CountoffSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
            }

            Picker("Subdivision", selection: .constant(ClickSubdivision.beat)) {
                ForEach(ClickSubdivision.allCases) { subdivision in
                    Text(subdivision.compactLabel)
                        .accessibilityLabel(subdivision.accessibilityLabel)
                        .tag(subdivision)
                }
            }
            .pickerStyle(.segmented)

            FutureSignalChannelLevel(kind: .click, value: .constant(0.75), isActive: true)
        }
        .padding(SustainSpace.lg)
        .background(panelBackground)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(palette.performanceSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(palette.surfaceEdge, lineWidth: 1)
            }
    }
}

#Preview("Future Signal · Rehearse 1200 × 700") {
    FutureSignalRehearseSpecimen()
        .frame(width: 1200, height: 700)
        .preferredColorScheme(.dark)
}

#Preview("Future Signal · Rehearse stacked") {
    FutureSignalRehearseSpecimen()
        .frame(width: 760, height: 700)
        .preferredColorScheme(.dark)
}
