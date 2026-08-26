import SwiftUI

struct RehearseView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("showIncludedPads") private var showIncludedPads = true
    @State private var padSearchText = ""

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
            // Clear the window's traffic-light / title-bar zone (the screen fills to the top).
            .padding(.top, SustainLayout.topChrome)
        }
        .sustainScreenBackground(.rehearse)
        .searchable(text: $padSearchText, prompt: "Search pads")
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

                if visiblePads.isEmpty {
                    ContentUnavailableView(
                        padSearchText.isEmpty ? "No visible pads" : "No matching pads",
                        systemImage: "waveform",
                        description: Text(padSearchText.isEmpty ? "Show included pads or add custom audio in Pad Library." : "Try another label or filename.")
                    )
                    .frame(minHeight: 180)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], spacing: 10) {
                        ForEach(visiblePads) { pad in
                        Button {
                            store.startRehearsePad(padID: pad.id)
                        } label: {
                            VStack(spacing: SustainSpace.xs) {
                                Text(pad.label)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .multilineTextAlignment(.center)
                                Text(padButtonDetail(pad))
                                    .font(.caption2)
                                    .foregroundStyle(SustainColor.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
                        }
                        .sustainBorderedButton(tint: isActive(pad) ? SustainColor.padActive : SustainColor.accent)
                        .disabled(!padState(pad).isAvailable)
                        .help("\(pad.label). \(padStateLabel(padState(pad)))")
                        .accessibilityLabel("\(pad.label), \(padVoiceDisambiguator(pad))")
                        .accessibilityValue(isActive(pad) ? "Playing" : padStateLabel(padState(pad)))
                        }
                    }
                }

                Toggle("Show Included Pads", isOn: $showIncludedPads)
                    .toggleStyle(.checkbox)

                Button(role: .destructive) {
                    store.stopRehearsePad()
                } label: {
                    Label("Stop Pad", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(store.rehearse.padState == .off)
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
                                Text(sound.label).tag(sound)
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
                    Text(store.rehearse.selectedPadLabel)
                        .font(SustainType.display)
                        .lineLimit(3)
                        .truncationMode(.tail)
                    Text(store.rehearse.padState == .playing ? "Pad signal active" : "Select a pad")
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
        .help(store.rehearse.selectedPadLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected pad")
        .accessibilityValue("\(store.rehearse.selectedPadLabel), \(store.rehearse.padState.rawValue)")
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

    private var activePadText: String {
        store.rehearse.padState == .off ? "Off" : "\(store.rehearse.selectedPadLabel) \(store.rehearse.padState.rawValue)"
    }

    private var visiblePads: [PadTrack] {
        store.padTracks.filter { pad in
            guard showIncludedPads || !pad.isIncluded else { return false }
            guard !padSearchText.isEmpty else { return true }
            return pad.label.localizedStandardContains(padSearchText) ||
                (pad.source.originalFilename?.localizedStandardContains(padSearchText) ?? false)
        }
    }

    private func isActive(_ pad: PadTrack) -> Bool {
        store.rehearse.selectedPadTrackID == pad.id && store.rehearse.padState != .off
    }

    private func padState(_ pad: PadTrack) -> PadAssetState {
        if pad.isIncluded {
            return .available(PadAudioMetadata(duration: 0, channelCount: 2, sampleRate: 44_100, decodedByteCount: 0))
        }
        return store.padAssetStates[pad.id] ?? {
            if case let .external(reference) = pad.source { return .available(reference.audioMetadata) }
            return .missing
        }()
    }

    private func padButtonDetail(_ pad: PadTrack) -> String {
        if isActive(pad) { return "Live" }
        if !padState(pad).isAvailable { return padStateLabel(padState(pad)) }
        return pad.isIncluded ? "Included" : (pad.source.originalFilename ?? "Custom")
    }

    private func padVoiceDisambiguator(_ pad: PadTrack) -> String {
        pad.isIncluded ? "included \(pad.source.bundledKey?.rawValue ?? "pad")" : (pad.source.originalFilename ?? pad.id.uuidString)
    }

    private func padStateLabel(_ state: PadAssetState) -> String {
        switch state {
        case .available: "Available"
        case .preparing: "Checking"
        case .externalVolumeUnavailable: "Volume unavailable"
        case .permissionDenied: "Permission needed"
        case .missing: "Missing"
        case .changed: "File changed"
        case .unsupportedOrProtected: "Unsupported"
        case .unreadable: "Unreadable"
        }
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

#Preview("Rehearse") {
    RehearseView()
        .environment(AppStore.preview())
        .frame(width: 940, height: 720)
}
