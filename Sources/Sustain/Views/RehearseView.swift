import SwiftUI

struct RehearseView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private let tempoRange = 40...220

    // The click panel's controls (Accent + Countoff segmented rows, tempo, faders)
    // need ~560pt to lay out without crowding; with the pad column (~400) plus
    // spacing and screen padding the two-column layout needs ~960pt. This is the
    // detail pane width, after the root sidebar has taken its 220pt. Below that we
    // stack, so panels always keep their edge margins instead of overflowing.
    private let twoColumnMinWidth: CGFloat = 960

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: SustainSpace.xxl) {
                        performanceStatus
                        columns(availableWidth: proxy.size.width)
                    }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(SustainSpace.screen)
                }
            }
            // Clear the window's traffic-light / title-bar zone (the screen fills to the top).
            .padding(.top, SustainLayout.topChrome)
        }
        .background(palette.canvas)
    }

    @ViewBuilder
    private func columns(availableWidth: CGFloat) -> some View {
        if availableWidth >= twoColumnMinWidth {
            let padWidth = min(440, availableWidth - 2 * SustainSpace.screen - SustainSpace.xxl - 520)
            HStack(alignment: .top, spacing: SustainSpace.xxl) {
                padPanel
                    .frame(width: padWidth, alignment: .top)
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
        HStack(alignment: .top, spacing: SustainSpace.lg) {
            VStack(alignment: .leading, spacing: SustainSpace.xs) {
                Text("Rehearse")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Free play pads, click, countoff, and live levels")
                    .font(.callout)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: SustainSpace.md)
            VStack(alignment: .trailing, spacing: 4) {
                Text(store.audioStatus)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(store.routingSnapshot.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(store.routingSnapshot.summary)
            }
        }
        .padding(.horizontal, SustainSpace.screen)
        .padding(.top, SustainSpace.sm)
    }

    private var performanceStatus: some View {
        FutureSignalPerformanceSurface(state: performanceSurfaceState) {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: SustainSpace.xs) {
                        Text("SELECTED PAD")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(palette.textSecondary)
                        Text(store.rehearse.selectedPadLabel)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                            .help(store.rehearse.selectedPadLabel)
                    }
                    Spacer(minLength: SustainSpace.md)
                    Text(clickText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: SustainSpace.section) {
                    padStatus
                        .frame(maxWidth: .infinity)
                    clickStatus
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 72)
                .overlay {
                    if let beat = store.rehearse.countoffBeat {
                        FutureSignalCountoffBadge(
                            beat: beat,
                            total: store.rehearse.countoffTotal,
                            bars: store.rehearse.activeCountoffPolicy?.bars
                                ?? store.rehearse.countoffPolicy.bars
                        )
                        .allowsHitTesting(false)
                    }
                }
                Text(store.rehearse.lastMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(store.rehearse.lastMessage)
            }
        }
    }

    private var padStatus: some View {
        FutureSignalOpenChannelStatus(kind: .pad, state: padChannelState, detail: padStatusDetail)
    }

    private var clickStatus: some View {
        FutureSignalOpenChannelStatus(kind: .click, state: clickChannelState, detail: clickStatusDetail)
    }

    private var padPanel: some View {
        VStack(alignment: .leading, spacing: SustainSpace.lg) {
                sectionHeading("Pads")

                if visiblePads.isEmpty {
                    ContentUnavailableView(
                        "No pads available",
                        systemImage: "waveform",
                        description: Text("Add custom audio in Pad Library.")
                    )
                    .frame(minHeight: 180)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], spacing: 10) {
                        ForEach(visiblePads) { pad in
                            FutureSignalPadTile(
                                title: pad.label,
                                detail: padButtonDetail(pad),
                                isSelected: store.rehearse.selectedPadTrackID == pad.id,
                                isPlaying: store.rehearse.selectedPadTrackID == pad.id && store.rehearse.padState == .playing,
                                isAvailable: padState(pad).isAvailable
                            ) {
                                store.startRehearsePad(padID: pad.id)
                            }
                            .help("\(pad.label), \(padVoiceDisambiguator(pad)). \(padStateLabel(padState(pad)))")
                            .accessibilityLabel("\(pad.label), \(padVoiceDisambiguator(pad))")
                        }
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
        }
        .padding(SustainSpace.lg)
        .background(panelBackground)
    }

    private var clickPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
                sectionHeading("Click", state: clickChannelState.label)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 18) {
                        playClickButton
                        timeSignaturePicker
                    }
                    VStack(alignment: .leading, spacing: SustainSpace.sm) {
                        playClickButton
                        timeSignaturePicker
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        accentPicker
                        countoffSoundPicker
                    }
                    VStack(alignment: .leading, spacing: SustainSpace.md) {
                        accentPicker
                        countoffSoundPicker
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Subdivision")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    Picker("Subdivision", selection: clickSubdivisionBinding) {
                        ForEach(ClickSubdivision.allCases) { subdivision in
                            Text(subdivision.compactLabel)
                                .accessibilityLabel(subdivision.accessibilityLabel)
                                .tag(subdivision)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(store.rehearse.clickState == .countoff)
                    .help(store.rehearse.clickState == .countoff
                        ? "Subdivision can change after countoff"
                        : "Choose clicks per BPM beat")
                    Text("Clicks per BPM beat")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                PulseInterpretationEditor(timeSignature: store.rehearse.timeSignature,
                                          bpm: bpmBinding,
                                          interpretation: pulseInterpretationBinding,
                                          accentPattern: accentPatternBinding)
                    .disabled(store.rehearse.clickState != .off)
                ClickAccentPatternEditor(pulseCount: rehearsePulseCount,
                                         fallback: store.clickSettings.accentMode,
                                         pattern: accentPatternBinding)
                    .disabled(store.rehearse.clickState == .countoff)
                CountoffPolicyEditor(policy: countoffPolicyBinding)
                    .disabled(store.rehearse.clickState == .countoff)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        HStack(alignment: .center, spacing: 4) {
                            Text("\(store.rehearse.bpm)")
                                .font(.system(size: 84, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(minWidth: 112, alignment: .leading)

                            Stepper("Tempo", value: bpmBinding, in: tempoRange, step: 1)
                                .labelsHidden()
                                .accessibilityLabel("Adjust tempo")
                        }

                        Text(rehearsePulseGrid.pulseUnitLabel)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        TapTempoControl(context: .rehearse, presentation: .tile)
                    }

                    Slider(value: bpmSliderBinding, in: Double(tempoRange.lowerBound)...Double(tempoRange.upperBound), step: 1)
                        .tint(palette.activeSignal)
                        .accessibilityLabel("Tempo")
                        .accessibilityValue("\(store.rehearse.bpm) beats per minute")

                    HStack {
                        Text("\(tempoRange.lowerBound)")
                        Spacer()
                        Text("Drag or step to update live")
                        Spacer()
                        Text("\(tempoRange.upperBound)")
                    }
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                }

                volumeConsole
        }
        .padding(SustainSpace.lg)
        .background(panelBackground)
    }

    private var playClickButton: some View {
        Button {
            if store.rehearse.clickState == .off {
                store.startRehearseClick()
            } else {
                store.stopRehearseClick()
            }
        } label: {
            Label(
                store.rehearse.clickState == .off ? "Play Click" : "Stop Click",
                systemImage: store.rehearse.clickState == .off ? "play.fill" : "stop.fill"
            )
            .frame(minWidth: 148)
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.activeSignal)
        .controlSize(.large)
    }

    private var timeSignaturePicker: some View {
        Picker("Time", selection: timeSignatureBinding) {
            ForEach(TimeSignature.common, id: \.self) { timeSignature in
                Text(timeSignature.description).tag(timeSignature)
            }
        }
        .frame(width: 124)
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accent")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Picker("Accent", selection: clickAccentModeBinding) {
                ForEach(ClickAccentMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var countoffSoundPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Countoff")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Picker("Countoff Sound", selection: countoffSoundBinding) {
                ForEach(CountoffSound.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var volumeConsole: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            Text("Channels")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: SustainSpace.lg) {
                    padLevel
                    clickLevel
                }
                VStack(spacing: SustainSpace.lg) {
                    padLevel
                    clickLevel
                }
            }
        }
    }

    private var padLevel: some View {
        FutureSignalChannelLevel(
            kind: .pad,
            value: padVolumeBinding,
            isActive: store.rehearse.padState != .off,
            onCommit: { store.commitAudioLevels() }
        )
        .frame(minWidth: 160)
    }

    private var clickLevel: some View {
        FutureSignalChannelLevel(
            kind: .click,
            value: clickVolumeBinding,
            isActive: store.rehearse.clickState != .off,
            onCommit: { store.commitAudioLevels() }
        )
        .frame(minWidth: 160)
    }

    private func sectionHeading(_ title: String, state: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            if let state {
                Text(state)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
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

    private var performanceSurfaceState: FutureSignalSurfaceState {
        if store.rehearse.clickState == .countoff { return .countoff }
        if store.rehearse.padState == .preparing || store.rehearse.clickState == .preparing {
            return .preparing
        }
        if store.rehearse.padState == .fadingIn || store.rehearse.padState == .fadingOut {
            return .transition
        }
        if store.rehearse.padState == .playing || store.rehearse.clickState == .playing {
            return .playing
        }
        if padChannelState == .unavailable { return .warning }
        return .idle
    }

    private var padChannelState: FutureSignalChannelState {
        if store.rehearse.padState == .off,
           let selectedID = store.rehearse.selectedPadTrackID,
           let selectedPad = store.padTracks.first(where: { $0.id == selectedID }),
           !padState(selectedPad).isAvailable {
            return .unavailable
        }
        return switch store.rehearse.padState {
        case .off: .off
        case .preparing: .preparing
        case .fadingIn: .fadingIn
        case .playing: .playing
        case .fadingOut: .fadingOut
        }
    }

    private var clickChannelState: FutureSignalChannelState {
        switch store.rehearse.clickState {
        case .off: .off
        case .preparing: .preparing
        case .countoff: .countoff
        case .playing: .playing
        }
    }

    private var clickStatusDetail: String {
        if store.rehearse.clickState == .off {
            return "Next start: \(store.rehearse.clickSubdivision.label)"
        }
        return clickText
    }

    private var padStatusDetail: String {
        guard padChannelState == .unavailable,
              let selectedID = store.rehearse.selectedPadTrackID,
              let selectedPad = store.padTracks.first(where: { $0.id == selectedID }) else {
            return store.rehearse.selectedPadLabel
        }
        return "\(selectedPad.label) · \(padStateLabel(padState(selectedPad)))"
    }

    private var visiblePads: [PadTrack] {
        store.padTracks
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
        if !padState(pad).isAvailable { return padStateLabel(padState(pad)) }
        return ""
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
        let subdivision = store.rehearse.clickState == .off
            ? store.rehearse.clickSubdivision
            : (store.audibleClickSubdivision ?? store.rehearse.clickSubdivision)
        let policy = store.rehearse.clickState == .off
            ? store.rehearse.countoffPolicy
            : (store.rehearse.activeCountoffPolicy ?? store.rehearse.countoffPolicy)
        let ending = policy.after == .countoffOnly ? " · Click stops after countoff" : ""
        let nextStart = store.rehearse.clickState != .off && policy != store.rehearse.countoffPolicy
            ? " · new countoff setting at next start" : ""
        let pendingAccents = store.pendingRehearseClickSubdivision != nil &&
            store.rehearse.clickAccentPattern != store.audibleClickAccentPattern
            ? " · beat accents at next measure" : ""
        let pendingSubdivision = store.pendingRehearseClickSubdivision.flatMap { requested in
            requested == subdivision ? nil : " · switching to \(requested.label) at next measure"
        } ?? ""
        return "\(store.rehearse.bpm) \(rehearsePulseGrid.pulseUnitLabel) · \(store.rehearse.timeSignature.description) · \(subdivision.label)\(ending)\(nextStart)\(pendingSubdivision)\(pendingAccents)"
    }

    private var rehearsePulseGrid: ClickPulseGrid {
        ClickPulseGrid(timeSignature: store.rehearse.timeSignature,
                       pulseInterpretation: store.rehearse.pulseInterpretation,
                       bpm: store.rehearse.bpm, sampleRate: 44_100)
    }

    private var rehearsePulseCount: Int { rehearsePulseGrid.pulseCount }

    private var pulseInterpretationBinding: Binding<PulseInterpretation> {
        Binding(get: { store.rehearse.pulseInterpretation },
                set: { store.setRehearsePulseInterpretation($0) })
    }

    private var accentPatternBinding: Binding<[ClickAccentLevel]?> {
        Binding(get: { store.rehearse.clickAccentPattern },
                set: { store.setRehearseAccentPattern($0) })
    }

    private var countoffPolicyBinding: Binding<CountoffPolicy> {
        Binding(get: { store.rehearse.countoffPolicy },
                set: { store.setRehearseCountoffPolicy($0) })
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

    private var clickSubdivisionBinding: Binding<ClickSubdivision> {
        Binding {
            store.pendingRehearseClickSubdivision ?? store.rehearse.clickSubdivision
        } set: { subdivision in
            store.setRehearseClickSubdivision(subdivision)
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

#Preview("Rehearse") {
    RehearseView()
        .environment(AppStore.preview())
        .frame(width: 940, height: 720)
}
