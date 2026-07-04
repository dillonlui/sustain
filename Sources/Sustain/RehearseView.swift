import SwiftUI

struct RehearseView: View {
    @EnvironmentObject private var store: AppStore

    private let tempoRange = 40...220

    // The click panel's controls (Accent + Countoff segmented rows, tempo, faders)
    // need ~560pt to lay out without crowding; with the pad column (~400) plus
    // spacing and screen padding the two-column layout needs ~1040pt. Below that we
    // stack, so panels always keep their edge margins instead of overflowing.
    private let twoColumnMinWidth: CGFloat = 1040

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header

                ScrollView {
                    columns(isWide: proxy.size.width >= twoColumnMinWidth)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(SustainSpace.screen)
                }
            }
        }
        .sustainScreenBackground(.rehearse)
    }

    @ViewBuilder
    private func columns(isWide: Bool) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: SustainSpace.xxl) {
                padPanel
                    .frame(minWidth: 360, maxWidth: 440, alignment: .top)
                clickPanel
                    .frame(minWidth: 520, maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(spacing: SustainSpace.xxl) {
                padPanel
                clickPanel
            }
        }
    }

    private var header: some View {
        SustainScreenHeader(title: "Rehearse", subtitle: "Free play pads, click, countoff, and live levels") {
            VStack(alignment: .trailing, spacing: 4) {
                Text(store.audioStatus)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(store.routingSnapshot.summary)
                    .font(.caption)
                    .foregroundStyle(SustainColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var padPanel: some View {
        SustainPanel(material: .regularMaterial, isActive: store.rehearse.padState == .playing) {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: "Pads",
                    value: store.rehearse.padState.rawValue,
                    systemImage: "waveform",
                    tint: SustainColor.padActive,
                    isActive: store.rehearse.padState == .playing
                )

                activePadSurface

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                    ForEach(MusicalKey.allCases) { key in
                        Button {
                            store.startRehearsePad(key: key)
                        } label: {
                            VStack(spacing: SustainSpace.xs) {
                                Text(key.rawValue)
                                    .font(.title3.weight(.semibold))
                                Text(store.rehearse.selectedKey == key && store.rehearse.padState == .playing ? "Live" : "Pad")
                                    .font(.caption)
                                    .foregroundStyle(SustainColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 58)
                        }
                        .sustainBorderedButton(tint: store.rehearse.selectedKey == key && store.rehearse.padState == .playing ? SustainColor.padActive : SustainColor.accent)
                    }
                }

                Button(role: .destructive) {
                    store.stopRehearsePad()
                } label: {
                    Label("Stop Pad", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(store.rehearse.padState == .off)

                messageStrip
            }
        }
    }

    private var clickPanel: some View {
        SustainPanel(material: .regularMaterial, isActive: store.rehearse.clickState != .off) {
            VStack(alignment: .leading, spacing: 22) {
                SustainSectionHeader(
                    title: "Click",
                    value: store.rehearse.clickState.rawValue,
                    systemImage: "metronome",
                    tint: SustainColor.clickActive,
                    isActive: store.rehearse.clickState != .off
                )

                HStack(alignment: .center, spacing: 18) {
                    Button {
                        if store.rehearse.clickState == .off {
                            store.startRehearseClick()
                        } else {
                            store.stopRehearseClick()
                        }
                    } label: {
                        Label(
                            store.rehearse.clickState == .off ? "Play Click" : "Pause Click",
                            systemImage: store.rehearse.clickState == .off ? "play.fill" : "pause.fill"
                        )
                        .frame(minWidth: 148)
                    }
                    .sustainProminentButton(tint: SustainColor.clickActive)
                    .controlSize(.large)

                    LitToggleButton(
                        title: "Countoff",
                        systemImage: "timer",
                        tint: SustainColor.clickActive,
                        isOn: countoffBinding
                    )

                    Picker("Time", selection: timeSignatureBinding) {
                        ForEach(TimeSignature.common, id: \.self) { timeSignature in
                            Text(timeSignature.description).tag(timeSignature)
                        }
                    }
                    .frame(width: 124)
                }

                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accent")
                            .font(.caption)
                            .foregroundStyle(SustainColor.textSecondary)
                        Picker("Accent", selection: clickAccentModeBinding) {
                            ForEach(ClickAccentMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Countoff")
                            .font(.caption)
                            .foregroundStyle(SustainColor.textSecondary)
                        Picker("Countoff Sound", selection: countoffSoundBinding) {
                            ForEach(CountoffSound.allCases) { sound in
                                Text(sound.rawValue).tag(sound)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("\(store.rehearse.bpm)")
                            .font(.system(size: 84, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 150, alignment: .leading)

                        Text("BPM")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(SustainColor.textSecondary)

                        Spacer()

                        Stepper("Tempo", value: bpmBinding, in: tempoRange, step: 1)
                            .labelsHidden()
                    }

                    Slider(value: bpmSliderBinding, in: Double(tempoRange.lowerBound)...Double(tempoRange.upperBound), step: 1)
                        .tint(SustainColor.clickActive)

                    HStack {
                        Text("\(tempoRange.lowerBound)")
                        Spacer()
                        Text("Drag or step to update live")
                        Spacer()
                        Text("\(tempoRange.upperBound)")
                    }
                    .font(.caption)
                    .foregroundStyle(SustainColor.textSecondary)
                }

                volumeConsole

                HStack(spacing: SustainSpace.lg) {
                    RehearseStateTile(label: "Pad", value: activePadText, systemImage: "waveform", tint: SustainColor.padActive, isActive: store.rehearse.padState == .playing)
                    RehearseStateTile(label: "Click", value: clickText, systemImage: "metronome", tint: SustainColor.clickActive, isActive: store.rehearse.clickState != .off)
                }
            }
        }
    }

    private var activePadSurface: some View {
        ZStack(alignment: .leading) {
            AudioPatternView(tint: SustainColor.padActive, isActive: store.rehearse.padState == .playing)
                .frame(height: 82)

            HStack {
                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    Text(store.rehearse.selectedKey.rawValue)
                        .font(SustainType.display)
                        .monospacedDigit()
                    Text(store.rehearse.padState == .playing ? "Pad signal active" : "Select a pad key")
                        .font(.callout)
                        .foregroundStyle(SustainColor.textSecondary)
                }

                Spacer()

                Image(systemName: "speaker.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(store.rehearse.padState == .playing ? SustainColor.padActive : SustainColor.textTertiary)
            }
            .padding(SustainSpace.lg)
        }
        .background(SustainColor.accentSoft, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                .stroke(SustainColor.padActive.opacity(store.rehearse.padState == .playing ? 0.4 : 0.14), lineWidth: 1)
        )
    }

    private var volumeConsole: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            Text("Channels")
                .font(.headline)

            HStack(spacing: SustainSpace.lg) {
                ChannelFader(
                    title: "Pad",
                    subtitle: "Atmosphere level",
                    systemImage: "waveform",
                    tint: SustainColor.padActive,
                    isActive: store.rehearse.padState == .playing,
                    value: padVolumeBinding,
                    onCommit: { store.commitAudioLevels() }
                )

                ChannelFader(
                    title: "Click",
                    subtitle: "Guide level",
                    systemImage: "metronome",
                    tint: SustainColor.clickActive,
                    isActive: store.rehearse.clickState != .off,
                    value: clickVolumeBinding,
                    onCommit: { store.commitAudioLevels() }
                )
            }
        }
    }

    private var messageStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(SustainColor.accent)
            Text(store.rehearse.lastMessage)
                .font(.callout)
            Spacer()
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var activePadText: String {
        store.rehearse.padState == .off ? "Off" : "\(store.rehearse.selectedKey.rawValue) \(store.rehearse.padState.rawValue)"
    }

    private var clickText: String {
        "\(store.rehearse.bpm) BPM \(store.rehearse.timeSignature.description)"
    }

    private var bpmBinding: Binding<Int> {
        Binding {
            store.rehearse.bpm
        } set: { bpm in
            store.setRehearseBPM(bpm)
        }
    }

    private var bpmSliderBinding: Binding<Double> {
        Binding {
            Double(store.rehearse.bpm)
        } set: { bpm in
            store.setRehearseBPM(Int(bpm.rounded()))
        }
    }

    private var countoffBinding: Binding<Bool> {
        Binding {
            store.rehearse.countoffEnabled
        } set: { isEnabled in
            store.setRehearseCountoffEnabled(isEnabled)
        }
    }

    private var timeSignatureBinding: Binding<TimeSignature> {
        Binding {
            store.rehearse.timeSignature
        } set: { timeSignature in
            store.setRehearseTimeSignature(timeSignature)
        }
    }

    private var clickAccentModeBinding: Binding<ClickAccentMode> {
        Binding {
            store.clickSettings.accentMode
        } set: { accentMode in
            store.setClickAccentMode(accentMode)
        }
    }

    private var countoffSoundBinding: Binding<CountoffSound> {
        Binding {
            store.clickSettings.countoffSound
        } set: { countoffSound in
            store.setCountoffSound(countoffSound)
        }
    }

    private var padVolumeBinding: Binding<Double> {
        Binding {
            store.padVolume
        } set: { volume in
            store.setPadVolumeLive(volume)
        }
    }

    private var clickVolumeBinding: Binding<Double> {
        Binding {
            store.clickVolume
        } set: { volume in
            store.setClickVolumeLive(volume)
        }
    }
}

private struct RehearseStateTile: View {
    var label: String
    var value: String
    var systemImage: String
    var tint: Color
    var isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(SustainColor.textSecondary)
                Text(value)
                    .font(.headline)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? tint.opacity(0.4) : SustainColor.separator, lineWidth: 1)
        )
    }
}
