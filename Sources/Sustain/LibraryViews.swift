import CoreAudio
import SwiftUI

struct SongLibraryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: SustainSpace.xxl) {
                    librarySummaryPanel

                    SustainPanel {
                        VStack(alignment: .leading, spacing: SustainSpace.lg) {
                            SustainSectionHeader(
                                title: "Songs",
                                value: "\(store.songs.count)",
                                systemImage: "music.note.list",
                                tint: SustainColor.accent,
                                isActive: !store.songs.isEmpty
                            )

                            VStack(spacing: SustainSpace.sm) {
                                ForEach(store.songs) { song in
                                    SongLibraryRow(
                                        song: song,
                                        title: titleBinding(for: song.id),
                                        key: keyBinding(for: song.id),
                                        bpm: bpmBinding(for: song.id),
                                        timeSignature: timeSignatureBinding(for: song.id)
                                    ) {
                                        _ = store.addSongToSetlist(song.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(SustainSpace.screen)
            }
        }
        .sustainScreenBackground(.standard)
    }

    private var header: some View {
        SustainScreenHeader(title: "Song Library", subtitle: "Reusable songs, defaults, and bundled pad source") {
            Button("Add Song", systemImage: "plus") {
                _ = store.addSong()
            }
            .sustainProminentButton()
        }
    }

    private var librarySummaryPanel: some View {
        SustainPanel(material: .regularMaterial, isActive: !store.songs.isEmpty) {
            HStack(alignment: .center, spacing: SustainSpace.xl) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(SustainColor.accent)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    Text("\(store.songs.count) songs ready")
                        .font(.title2.weight(.semibold))
                    Text(store.persistenceStatus)
                        .font(.callout)
                        .foregroundStyle(SustainColor.textSecondary)
                }

                Spacer()

                SignalIndicator(
                    label: "\(store.activeSetlist.entries.count) in setlist",
                    tint: SustainColor.clickActive,
                    isActive: !store.activeSetlist.entries.isEmpty
                )
            }
        }
    }

    private func song(_ songID: Song.ID) -> Song? {
        store.songs.first { $0.id == songID }
    }

    private func updateSong(_ songID: Song.ID, configure: (Song) -> Song) {
        guard let current = song(songID) else { return }
        let updated = configure(current)
        store.updateSong(
            songID,
            title: updated.title,
            defaultKey: updated.defaultKey,
            defaultBPM: updated.defaultBPM,
            timeSignature: updated.timeSignature,
            padPackID: PadPack.bundled.id
        )
    }

    private func titleBinding(for songID: Song.ID) -> Binding<String> {
        Binding {
            song(songID)?.title ?? ""
        } set: { title in
            updateSong(songID) { song in
                var song = song
                song.title = title
                return song
            }
        }
    }

    private func keyBinding(for songID: Song.ID) -> Binding<MusicalKey> {
        Binding {
            song(songID)?.defaultKey ?? .c
        } set: { key in
            updateSong(songID) { song in
                var song = song
                song.defaultKey = key
                return song
            }
        }
    }

    private func bpmBinding(for songID: Song.ID) -> Binding<Int> {
        Binding {
            song(songID)?.defaultBPM ?? 72
        } set: { bpm in
            updateSong(songID) { song in
                var song = song
                song.defaultBPM = bpm
                return song
            }
        }
    }

    private func timeSignatureBinding(for songID: Song.ID) -> Binding<TimeSignature> {
        Binding {
            song(songID)?.timeSignature ?? .fourFour
        } set: { timeSignature in
            updateSong(songID) { song in
                var song = song
                song.timeSignature = timeSignature
                return song
            }
        }
    }

}

private struct SongLibraryRow: View {
    var song: Song
    @Binding var title: String
    @Binding var key: MusicalKey
    @Binding var bpm: Int
    @Binding var timeSignature: TimeSignature
    var onAddToSetlist: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: SustainSpace.lg) {
            VStack(alignment: .leading, spacing: SustainSpace.sm) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)

                HStack(spacing: SustainSpace.sm) {
                    MetadataChip(label: "Key", value: key.rawValue, tint: SustainColor.padActive)
                    MetadataChip(label: "BPM", value: "\(bpm)", tint: SustainColor.clickActive)
                    MetadataChip(label: "Time", value: timeSignature.description)

                    Label("Included Pads", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(SustainColor.textSecondary)
                }
            }

            Spacer(minLength: SustainSpace.xxl)

            Picker("Key", selection: $key) {
                ForEach(MusicalKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 82)

            Stepper("\(bpm) BPM", value: $bpm, in: 40...220)
                .frame(width: 140)

            Picker("Time", selection: $timeSignature) {
                ForEach(TimeSignature.common, id: \.self) { timeSignature in
                    Text(timeSignature.description).tag(timeSignature)
                }
            }
            .labelsHidden()
            .frame(width: 92)

            Button("Add", systemImage: "text.badge.plus") {
                onAddToSetlist()
            }
        }
        .padding(SustainSpace.lg)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                .stroke(SustainColor.separator, lineWidth: 1)
        )
    }
}

struct AudioSetupView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: SustainSpace.xxl) {
                    routingSummaryPanel

                    HStack(alignment: .top, spacing: SustainSpace.xxl) {
                        padRoutePanel
                        clickRoutePanel
                    }

                    HStack(alignment: .top, spacing: SustainSpace.xxl) {
                        diagnosticsPanel
                        enginePanel
                    }
                }
                .padding(SustainSpace.screen)
            }
        }
        .sustainScreenBackground(.audio)
    }

    private var header: some View {
        SustainScreenHeader(title: "Audio Setup", subtitle: "Route pad and click like separate live channels") {
            Button("Refresh Devices", systemImage: "arrow.clockwise") {
                store.refreshAudioDiagnostics()
            }
            .sustainProminentButton()
        }
    }

    private var routingSummaryPanel: some View {
        SustainPanel(material: .regularMaterial, isActive: store.routingSnapshot.independentRoutingEnabled) {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                HStack(alignment: .center, spacing: SustainSpace.lg) {
                    Image(systemName: store.routingSnapshot.independentRoutingEnabled ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(routeStatusTint)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: SustainSpace.xs) {
                        Text(routeStatusTitle)
                            .font(.title2.weight(.semibold))
                        Text(store.routingSnapshot.summary)
                            .font(.callout)
                            .foregroundStyle(SustainColor.textSecondary)
                    }

                    Spacer()

                    SignalIndicator(
                        label: "\(store.routingSnapshot.outputs.count) outputs",
                        tint: routeStatusTint,
                        isActive: store.routingSnapshot.warning == nil
                    )
                }

                if let warning = store.routingSnapshot.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(SustainColor.warning)
                        .padding(SustainSpace.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SustainColor.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
                }
            }
        }
    }

    private var padRoutePanel: some View {
        routePanel(
            title: "Pad Output",
            subtitle: "Atmosphere channel",
            systemImage: "speaker.wave.2.fill",
            tint: SustainColor.padActive,
            routeName: store.routingSnapshot.padRouteName,
            deviceID: store.routingSnapshot.padOutputID,
            selectedOutput: padOutputBinding,
            selectedChannel: padChannelBinding,
            selectedDevice: output(id: store.routingSnapshot.padOutputID),
            isReady: isPadRouteReady
        )
    }

    private var clickRoutePanel: some View {
        routePanel(
            title: "Click Output",
            subtitle: "Guide channel",
            systemImage: "metronome.fill",
            tint: SustainColor.clickActive,
            routeName: store.routingSnapshot.clickRouteName,
            deviceID: store.routingSnapshot.clickOutputID,
            selectedOutput: clickOutputBinding,
            selectedChannel: clickChannelBinding,
            selectedDevice: output(id: store.routingSnapshot.clickOutputID),
            isReady: isClickRouteReady
        )
    }

    private func routePanel(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        routeName: String,
        deviceID: AudioDeviceID?,
        selectedOutput: Binding<AudioDeviceID?>,
        selectedChannel: Binding<AudioOutputChannelSelection>,
        selectedDevice: AudioOutputDevice?,
        isReady: Bool
    ) -> some View {
        SustainPanel(material: .regularMaterial, isActive: isReady) {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: title,
                    value: isReady ? "Ready" : "Check",
                    systemImage: systemImage,
                    tint: isReady ? tint : SustainColor.warning,
                    isActive: isReady
                )

                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    Text(routeName)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(SustainColor.textSecondary)
                }

                RouteSignalView(tint: tint, isReady: isReady)
                    .frame(height: 42)

                Picker("Device", selection: selectedOutput) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(store.routingSnapshot.outputs) { output in
                        Text(output.isDefault ? "\(output.name) (Default)" : output.name)
                            .tag(AudioDeviceID?.some(output.id))
                    }
                }

                Picker("Channel", selection: selectedChannel) {
                    ForEach(AudioOutputChannelSelection.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: SustainSpace.sm) {
                    DiagnosticLine(label: "Device ID", value: deviceIDText(deviceID))
                    DiagnosticLine(label: "Format", value: selectedDevice?.diagnosticSummary ?? "Unavailable")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var diagnosticsPanel: some View {
        SustainPanel {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: "Detected Devices",
                    value: "\(store.routingSnapshot.outputs.count)",
                    systemImage: "externaldrive.connected.to.line.below",
                    tint: SustainColor.accent,
                    isActive: !store.routingSnapshot.outputs.isEmpty
                )

                if store.routingSnapshot.outputs.isEmpty {
                    Label("No audio outputs detected.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SustainColor.warning)
                } else {
                    VStack(alignment: .leading, spacing: SustainSpace.sm) {
                        ForEach(store.routingSnapshot.outputs) { output in
                            AudioDeviceDiagnosticRow(output: output)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var enginePanel: some View {
        SustainPanel {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: "Engine",
                    value: store.audioStatus,
                    systemImage: "cpu",
                    tint: SustainColor.accent,
                    isActive: store.audioStatus != "Stopped"
                )

                VStack(alignment: .leading, spacing: SustainSpace.md) {
                    DiagnosticLine(label: "Pad Playback", value: "Looping bundled MP3 files")
                    DiagnosticLine(label: "Click", value: "Generated from BPM")
                    DiagnosticLine(label: "Countoff", value: "Required before click")
                    DiagnosticLine(label: "Pad Level", value: "\(Int((store.padVolume * 100).rounded()))%")
                    DiagnosticLine(label: "Click Level", value: "\(Int((store.clickVolume * 100).rounded()))%")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var padOutputBinding: Binding<AudioDeviceID?> {
        Binding {
            store.routingSettings.padOutputID
        } set: { outputID in
            store.updateRouting(
                padOutputID: outputID,
                clickOutputID: store.routingSettings.clickOutputID,
                padOutputChannel: storedChannel(store.routingSettings.padOutputChannel),
                clickOutputChannel: storedChannel(store.routingSettings.clickOutputChannel)
            )
        }
    }

    private var clickOutputBinding: Binding<AudioDeviceID?> {
        Binding {
            store.routingSettings.clickOutputID
        } set: { outputID in
            store.updateRouting(
                padOutputID: store.routingSettings.padOutputID,
                clickOutputID: outputID,
                padOutputChannel: storedChannel(store.routingSettings.padOutputChannel),
                clickOutputChannel: storedChannel(store.routingSettings.clickOutputChannel)
            )
        }
    }

    private var padChannelBinding: Binding<AudioOutputChannelSelection> {
        Binding {
            store.routingSettings.padOutputChannel ?? .stereo
        } set: { channel in
            store.updateRouting(
                padOutputID: store.routingSettings.padOutputID,
                clickOutputID: store.routingSettings.clickOutputID,
                padOutputChannel: storedChannel(channel),
                clickOutputChannel: storedChannel(store.routingSettings.clickOutputChannel)
            )
        }
    }

    private var clickChannelBinding: Binding<AudioOutputChannelSelection> {
        Binding {
            store.routingSettings.clickOutputChannel ?? .stereo
        } set: { channel in
            store.updateRouting(
                padOutputID: store.routingSettings.padOutputID,
                clickOutputID: store.routingSettings.clickOutputID,
                padOutputChannel: storedChannel(store.routingSettings.padOutputChannel),
                clickOutputChannel: storedChannel(channel)
            )
        }
    }

    private func storedChannel(_ channel: AudioOutputChannelSelection?) -> AudioOutputChannelSelection? {
        channel == .stereo ? nil : channel
    }

    private func output(id: AudioDeviceID?) -> AudioOutputDevice? {
        guard let id else { return nil }
        return store.routingSnapshot.outputs.first { $0.id == id }
    }

    private func deviceIDText(_ id: AudioDeviceID?) -> String {
        id.map(String.init) ?? "System Default"
    }

    private var routeStatusTitle: String {
        if store.routingSnapshot.warning == nil {
            return "Routes are ready"
        }

        return store.routingSnapshot.independentRoutingEnabled ? "Routes need attention" : "Pad and click are sharing output"
    }

    private var routeStatusTint: Color {
        store.routingSnapshot.warning == nil ? SustainColor.ready : SustainColor.warning
    }

    private var isPadRouteReady: Bool {
        guard let output = output(id: store.routingSnapshot.padOutputID) else { return false }
        return store.routingSnapshot.padOutputChannel.isAvailable(on: output) &&
            !store.routingSnapshot.missingSelectionMessages.contains("Selected pad output is unavailable.") &&
            !store.routingSnapshot.missingSelectionMessages.contains("Selected pad output channel is unavailable.")
    }

    private var isClickRouteReady: Bool {
        guard let output = output(id: store.routingSnapshot.clickOutputID) else { return false }
        return store.routingSnapshot.clickOutputChannel.isAvailable(on: output) &&
            !store.routingSnapshot.missingSelectionMessages.contains("Selected click output is unavailable.") &&
            !store.routingSnapshot.missingSelectionMessages.contains("Selected click output channel is unavailable.")
    }
}

private struct AudioDeviceDiagnosticRow: View {
    var output: AudioOutputDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(output.name)
                    .font(.headline)
                Spacer()
                if output.isDefault {
                    Text("Default")
                        .foregroundStyle(SustainColor.textSecondary)
                }
            }

            Text("ID \(output.id) · \(output.diagnosticSummary)")
                .font(.callout)
                .foregroundStyle(SustainColor.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

private struct RouteSignalView: View {
    var tint: Color
    var isReady: Bool

    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            Circle()
                .fill(tint.opacity(isReady ? 0.92 : 0.34))
                .frame(width: 12, height: 12)
                .shadow(color: isReady ? tint.opacity(0.5) : .clear, radius: 5)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(isReady ? 0.5 : 0.16), tint.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            Image(systemName: "speaker.wave.2")
                .font(.title3)
                .foregroundStyle(isReady ? tint : SustainColor.textTertiary)
        }
        .padding(.horizontal, SustainSpace.md)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct DiagnosticLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(SustainType.label)
                .foregroundStyle(SustainColor.textSecondary)
                .frame(width: 104, alignment: .leading)

            Text(value)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SystemCheckView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: SustainSpace.xxl) {
                    readinessPanel

                    HStack(alignment: .top, spacing: SustainSpace.xxl) {
                        checksPanel
                        runtimePanel
                    }
                }
                .padding(SustainSpace.screen)
            }
        }
        .sustainScreenBackground(.system)
    }

    private var header: some View {
        SustainScreenHeader(title: "System Check", subtitle: "Confirm routing, library, and playback readiness") {
            Button("Run Check", systemImage: "checkmark.shield") {
                store.runSystemCheck()
            }
            .sustainProminentButton()
        }
    }

    private var readinessPanel: some View {
        SustainPanel(material: .regularMaterial, isActive: store.systemCheck.canStartPlayback) {
            ZStack(alignment: .leading) {
                AudioPatternView(tint: readinessTint, isActive: store.systemCheck.canStartPlayback)
                    .frame(height: 108)

                HStack(alignment: .center, spacing: SustainSpace.xl) {
                    Image(systemName: readinessIcon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(readinessTint)
                        .frame(width: 56)

                    VStack(alignment: .leading, spacing: SustainSpace.xs) {
                        Text(readinessTitle)
                            .font(.title.weight(.semibold))
                        Text(readinessSubtitle)
                            .font(.callout)
                            .foregroundStyle(SustainColor.textSecondary)
                    }

                    Spacer()

                    SignalIndicator(
                        label: store.systemCheck.canStartPlayback ? "Ready" : "Blocked",
                        tint: readinessTint,
                        isActive: store.systemCheck.canStartPlayback
                    )
                }
            }
        }
    }

    private var checksPanel: some View {
        SustainPanel {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: "Checks",
                    value: "\(store.systemCheck.messages.count)",
                    systemImage: "checklist.checked",
                    tint: readinessTint,
                    isActive: store.systemCheck.canStartPlayback
                )

                VStack(spacing: SustainSpace.md) {
                    ForEach(store.systemCheck.messages, id: \.self) { message in
                        CheckMessageRow(message: message, canStartPlayback: store.systemCheck.canStartPlayback)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var runtimePanel: some View {
        SustainPanel {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: "Runtime",
                    value: store.runtime.playbackPhase.rawValue,
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: SustainColor.accent,
                    isActive: store.runtime.playbackPhase != .noSongPlaying
                )

                VStack(alignment: .leading, spacing: SustainSpace.md) {
                    DiagnosticLine(label: "Audio", value: store.audioStatus)
                    DiagnosticLine(label: "Routing", value: store.routingSnapshot.summary)
                    DiagnosticLine(label: "Library", value: store.persistenceStatus)
                    DiagnosticLine(label: "Pad", value: store.runtime.padState.rawValue)
                    DiagnosticLine(label: "Click", value: store.runtime.clickState.rawValue)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var readinessIcon: String {
        if store.systemCheck.canStartPlayback {
            return "checkmark.shield.fill"
        }

        return store.systemCheck.messages == SystemCheckResult.notRun.messages ? "shield" : "exclamationmark.shield.fill"
    }

    private var readinessTitle: String {
        if store.systemCheck.canStartPlayback {
            return "Ready for playback"
        }

        return store.systemCheck.messages == SystemCheckResult.notRun.messages ? "Check has not run" : "Playback needs attention"
    }

    private var readinessSubtitle: String {
        if store.systemCheck.canStartPlayback {
            return "Critical requirements are satisfied. Review warnings before service."
        }

        return store.systemCheck.messages.first ?? "Run a system check before playback."
    }

    private var readinessTint: Color {
        store.systemCheck.canStartPlayback ? SustainColor.ready : SustainColor.warning
    }
}

private struct CheckMessageRow: View {
    var message: String
    var canStartPlayback: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SustainSpace.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)

            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SustainSpace.lg)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private var isWarning: Bool {
        message.hasPrefix("Warning:")
    }

    private var icon: String {
        if canStartPlayback && !isWarning {
            return "checkmark.circle.fill"
        }

        return isWarning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"
    }

    private var tint: Color {
        if canStartPlayback && !isWarning {
            return SustainColor.ready
        }

        return isWarning ? SustainColor.warning : SustainColor.destructive
    }
}
