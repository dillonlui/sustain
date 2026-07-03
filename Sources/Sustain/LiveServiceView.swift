import SwiftUI

struct LiveServiceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedSongID: Song.ID?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: SustainSpace.xxl) {
                    stageCarousel
                    primaryControls

                    HStack(alignment: .top, spacing: SustainSpace.xxl) {
                        liveSetlistPanel
                            .frame(maxWidth: .infinity)

                        liveControlPanel
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(SustainSpace.screen)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .sustainScreenBackground(.live)
    }

    private var header: some View {
        SustainScreenHeader(title: "Live Service", subtitle: "Build the service flow, cue songs, and run pad and click from one view.") {
            BrandMarkView()
                .frame(width: 116, height: 52)
        }
    }

    private var stageCarousel: some View {
        HStack(alignment: .center, spacing: SustainSpace.xxl) {
            StageSideSongCard(
                label: "Previous",
                entry: previousStageEntry,
                fallback: "Start of set"
            )
            .frame(width: 230)
            .opacity(0.62)

            StageActiveSongCard(
                entry: stageEntry,
                title: stageTitle,
                subtitle: liveSignalSubtitle,
                cuePosition: cuePositionText,
                isPlaying: store.runtime.playbackPhase == .songPlaying
            )
            .frame(maxWidth: 620)

            StageSideSongCard(
                label: "Next",
                entry: nextStageEntry,
                fallback: "End of set"
            )
            .frame(width: 230)
            .opacity(0.62)
        }
        .animation(.smooth(duration: 0.32), value: store.runtime.playingEntryID)
        .animation(.smooth(duration: 0.32), value: store.runtime.cuedEntryID)
    }

    private var channelConsole: some View {
        VStack(spacing: SustainSpace.lg) {
            ChannelFader(
                title: "Pad",
                subtitle: "Atmosphere",
                systemImage: "waveform",
                tint: SustainColor.padActive,
                isActive: store.runtime.padState == .playing,
                value: padVolumeBinding
            )

            ChannelFader(
                title: "Click",
                subtitle: "Guide",
                systemImage: "metronome",
                tint: SustainColor.clickActive,
                isActive: store.runtime.clickState != .off,
                value: clickVolumeBinding
            )
        }
    }

    private var liveSetlistPanel: some View {
        SustainPanel(material: .regularMaterial, isActive: !store.activeSetlist.entries.isEmpty) {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: store.activeSetlist.title,
                    value: "\(store.activeSetlist.entries.count)",
                    systemImage: "list.bullet",
                    tint: SustainColor.accent,
                    isActive: !store.activeSetlist.entries.isEmpty
                )

                addSongFlow

                Divider()

                if store.activeSetlist.entries.isEmpty {
                    EmptyLiveSetlistView()
                } else {
                    VStack(spacing: SustainSpace.sm) {
                        ForEach(Array(store.activeSetlist.entries.enumerated()), id: \.element.id) { index, entry in
                            if let song = store.song(for: entry) {
                                LiveSetlistEntryRow(
                                    index: index + 1,
                                    entry: entry,
                                    song: song,
                                    isCued: store.runtime.cuedEntryID == entry.id,
                                    isPlaying: store.runtime.playingEntryID == entry.id,
                                    key: keyBinding(for: entry.id, song: song),
                                    bpm: bpmBinding(for: entry.id, song: song),
                                    onCue: { store.cue(entryID: entry.id) },
                                    onRemove: { store.removeSetlistEntry(entry.id) }
                                )
                            } else {
                                MissingLiveSetlistEntryRow(
                                    index: index + 1,
                                    onRemove: { store.removeSetlistEntry(entry.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var addSongFlow: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            TextField("Service Title", text: setlistTitleBinding)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: SustainSpace.md) {
                Picker("Song", selection: selectedSongBinding) {
                    Text("Choose Song").tag(Song.ID?.none)
                    ForEach(store.songs) { song in
                        Text(song.title).tag(Song.ID?.some(song.id))
                    }
                }
                .frame(maxWidth: .infinity)

                Button("Add", systemImage: "plus") {
                    addSelectedSongToSetlist()
                }
                .sustainProminentButton()
                .disabled(selectedSongBinding.wrappedValue == nil)

                Button("New", systemImage: "music.note") {
                    createSongAndAddToSetlist()
                }
                .sustainBorderedButton(tint: SustainColor.accent)
            }

            HStack(spacing: SustainSpace.md) {
                Text(addSongHint)
                    .font(.caption)
                    .foregroundStyle(SustainColor.textSecondary)
                    .lineLimit(2)

                Spacer()

                Button("Clear", systemImage: "trash") {
                    store.clearSetlist()
                }
                .sustainBorderedButton(tint: SustainColor.destructive)
                .disabled(store.activeSetlist.entries.isEmpty || store.runtime.playbackPhase != .noSongPlaying)
            }
        }
    }

    private var liveControlPanel: some View {
        SustainPanel {
            VStack(alignment: .leading, spacing: SustainSpace.lg) {
                SustainSectionHeader(
                    title: "Pad & Click",
                    value: store.runtime.playbackPhase.rawValue,
                    systemImage: "slider.horizontal.3",
                    tint: store.runtime.playbackPhase == .noSongPlaying ? SustainColor.accent : SustainColor.padActive,
                    isActive: store.runtime.playbackPhase != .noSongPlaying
                )

                HStack(spacing: 10) {
                    Button("Start Click", systemImage: "metronome") {
                        store.startClick()
                    }
                    .disabled(store.runtime.playbackPhase == .noSongPlaying || store.runtime.clickState != .off)

                    Button("Stop Click", systemImage: "speaker.slash") {
                        store.stopClick()
                    }
                    .disabled(store.runtime.clickState == .off)

                    Button("Start Pad", systemImage: "waveform") {
                        store.startPad()
                    }
                    .disabled(store.runtime.playbackPhase == .noSongPlaying || store.runtime.padState == .playing)

                    Button("Stop Pad", systemImage: "pause.circle") {
                        store.stopPad()
                    }
                    .disabled(store.runtime.padState == .off)
                }
                .sustainBorderedButton()
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)

                channelConsole
                messageStrip
            }
        }
    }

    private var liveSignalSubtitle: String {
        guard let playingEntry = store.playingEntry,
              let song = store.song(for: playingEntry) else {
            return "Cue a song, then start when the room is ready."
        }

        let key = playingEntry.resolvedKey(for: song).rawValue
        let bpm = playingEntry.resolvedBPM(for: song)
        return "\(song.title) | \(key) | \(bpm) BPM"
    }

    private var stageEntry: SetlistEntry? {
        store.playingEntry ?? store.cuedEntry
    }

    private var stageTitle: String {
        if store.playingEntry != nil {
            return "Currently Playing"
        }
        if store.cuedEntry != nil {
            return "Ready to Start"
        }
        return "No Song Selected"
    }

    private var stageIndex: Int? {
        guard let entry = stageEntry else { return nil }
        return store.activeSetlist.entries.firstIndex(where: { $0.id == entry.id })
    }

    private var previousStageEntry: SetlistEntry? {
        guard let stageIndex, stageIndex > store.activeSetlist.entries.startIndex else { return nil }
        return store.activeSetlist.entries[store.activeSetlist.entries.index(before: stageIndex)]
    }

    private var nextStageEntry: SetlistEntry? {
        guard let stageIndex else { return nil }
        let nextIndex = store.activeSetlist.entries.index(after: stageIndex)
        guard nextIndex < store.activeSetlist.entries.endIndex else { return nil }
        return store.activeSetlist.entries[nextIndex]
    }

    private var padVolumeBinding: Binding<Double> {
        Binding {
            store.padVolume
        } set: { volume in
            store.setPadVolume(volume)
        }
    }

    private var clickVolumeBinding: Binding<Double> {
        Binding {
            store.clickVolume
        } set: { volume in
            store.setClickVolume(volume)
        }
    }

    private var addSongHint: String {
        if store.songs.isEmpty {
            return "Create a song, then tune it in the Song Library."
        }
        return "Add from the library or create a new song directly in the service flow."
    }

    private var selectedSongBinding: Binding<Song.ID?> {
        Binding {
            selectedSongID ?? store.songs.first?.id
        } set: { songID in
            selectedSongID = songID
        }
    }

    private var setlistTitleBinding: Binding<String> {
        Binding {
            store.activeSetlist.title
        } set: { title in
            store.updateActiveSetlistTitle(title)
        }
    }

    private func addSelectedSongToSetlist() {
        guard let songID = selectedSongBinding.wrappedValue else { return }
        _ = store.addSongToSetlist(songID)
    }

    private func createSongAndAddToSetlist() {
        let songID = store.addSong()
        selectedSongID = songID
        _ = store.addSongToSetlist(songID)
    }

    private func keyBinding(for entryID: SetlistEntry.ID, song: Song) -> Binding<MusicalKey> {
        Binding {
            store.entry(id: entryID)?.resolvedKey(for: song) ?? song.defaultKey
        } set: { key in
            let entry = store.entry(id: entryID)
            store.updateEntry(
                entryID,
                keyOverride: key == song.defaultKey ? nil : key,
                bpmOverride: entry?.bpmOverride
            )
        }
    }

    private func bpmBinding(for entryID: SetlistEntry.ID, song: Song) -> Binding<Int> {
        Binding {
            store.entry(id: entryID)?.resolvedBPM(for: song) ?? song.defaultBPM
        } set: { bpm in
            let entry = store.entry(id: entryID)
            store.updateEntry(
                entryID,
                keyOverride: entry?.keyOverride,
                bpmOverride: bpm == song.defaultBPM ? nil : bpm
            )
        }
    }

    private var primaryControls: some View {
        HStack(spacing: SustainSpace.lg) {
            Button {
                store.cuePreviousSong()
            } label: {
                Label("Previous", systemImage: "backward.fill")
                    .font(.headline)
                    .frame(width: 150, height: 46)
            }
            .sustainBorderedButton(tint: SustainColor.accent)
            .controlSize(.large)
            .disabled(store.activeSetlist.entries.isEmpty)

            Button {
                store.startCuedSong()
            } label: {
                Label("Start Song", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 190, height: 54)
            }
            .sustainProminentButton()
            .controlSize(.large)
            .disabled(store.cuedEntry == nil)

            Button {
                store.cueNextSong()
            } label: {
                Label("Next", systemImage: "forward.fill")
                    .font(.headline)
                    .frame(width: 150, height: 46)
            }
            .sustainBorderedButton(tint: SustainColor.accent)
            .controlSize(.large)
            .disabled(store.activeSetlist.entries.isEmpty)

            Button(role: .destructive) {
                store.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(width: 130, height: 46)
            }
            .sustainBorderedButton(tint: SustainColor.destructive)
            .controlSize(.large)
            .disabled(store.runtime.playbackPhase == .noSongPlaying)
        }
        .frame(maxWidth: .infinity)
    }

    private var messageStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(SustainColor.accent)
            Text(store.runtime.lastMessage)
                .font(.callout)
            Spacer()
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var cuePositionText: String {
        guard let cuedID = store.runtime.cuedEntryID,
              let index = store.activeSetlist.entries.firstIndex(where: { $0.id == cuedID }) else {
            return "-"
        }

        return "\(index + 1) of \(store.activeSetlist.entries.count)"
    }
}

private struct StageActiveSongCard: View {
    @EnvironmentObject private var store: AppStore

    var entry: SetlistEntry?
    var title: String
    var subtitle: String
    var cuePosition: String
    var isPlaying: Bool

    var body: some View {
        SustainPanel(material: .regularMaterial, isActive: entry != nil) {
            ZStack {
                TopographicFieldView(
                    tint: isPlaying ? SustainColor.padActive : SustainColor.clickActive,
                    animated: false
                )
                .opacity(0.22)
                .frame(height: 230)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(spacing: SustainSpace.xl) {
                    SignalIndicator(
                        label: cuePosition,
                        tint: isPlaying ? SustainColor.padActive : SustainColor.clickActive,
                        isActive: entry != nil
                    )

                    VStack(spacing: SustainSpace.sm) {
                        Text(title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(SustainColor.textSecondary)

                        if let entry, let song = store.song(for: entry) {
                            Text(song.title)
                                .font(.system(size: 46, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)

                            HStack(spacing: SustainSpace.md) {
                                MetadataChip(label: "Key", value: entry.resolvedKey(for: song).rawValue, tint: SustainColor.padActive)
                                MetadataChip(label: "BPM", value: "\(entry.resolvedBPM(for: song))", tint: SustainColor.clickActive)
                                MetadataChip(label: "Time", value: song.timeSignature.description)
                            }
                        } else {
                            Text("No Song Selected")
                                .font(.system(size: 42, weight: .semibold, design: .rounded))
                                .foregroundStyle(SustainColor.textSecondary)
                        }

                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(SustainColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, SustainSpace.xxl)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct StageSideSongCard: View {
    @EnvironmentObject private var store: AppStore

    var label: String
    var entry: SetlistEntry?
    var fallback: String

    var body: some View {
        VStack(spacing: SustainSpace.md) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(SustainColor.textTertiary)

            VStack(spacing: SustainSpace.sm) {
                if let entry, let song = store.song(for: entry) {
                    Text(song.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("\(entry.resolvedKey(for: song).rawValue) | \(entry.resolvedBPM(for: song)) BPM")
                        .font(.caption)
                        .foregroundStyle(SustainColor.textSecondary)
                        .monospacedDigit()
                } else {
                    Text(fallback)
                        .font(.headline)
                        .foregroundStyle(SustainColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(SustainSpace.lg)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                    .stroke(SustainColor.separator, lineWidth: 1)
            )
        }
    }
}

private struct LiveSetlistEntryRow: View {
    var index: Int
    var entry: SetlistEntry
    var song: Song
    var isCued: Bool
    var isPlaying: Bool
    @Binding var key: MusicalKey
    @Binding var bpm: Int
    var onCue: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            HStack(alignment: .center, spacing: SustainSpace.md) {
                ZStack {
                    Circle()
                        .fill(rowTint.opacity(isCued || isPlaying ? 0.18 : 0.08))
                        .frame(width: 32, height: 32)
                    Text("\(index)")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isCued || isPlaying ? rowTint : SustainColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    HStack(spacing: SustainSpace.sm) {
                        Text(song.title)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if isPlaying {
                            SignalIndicator(label: "Playing", tint: SustainColor.padActive, isActive: true)
                        } else if isCued {
                            SignalIndicator(label: "Cued", tint: SustainColor.clickActive, isActive: true)
                        }
                    }

                    HStack(spacing: SustainSpace.sm) {
                        MetadataChip(label: "Key", value: entry.resolvedKey(for: song).rawValue, tint: SustainColor.padActive)
                        MetadataChip(label: "BPM", value: "\(entry.resolvedBPM(for: song))", tint: SustainColor.clickActive)
                        MetadataChip(label: "Time", value: song.timeSignature.description)
                    }
                }

                Spacer()
            }

            HStack(spacing: SustainSpace.md) {
                Picker("Key", selection: $key) {
                    ForEach(MusicalKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 82)

                Stepper("\(bpm) BPM", value: $bpm, in: 40...220)
                    .frame(width: 142)

                Spacer()

                Button("Cue", systemImage: "arrow.forward.circle") {
                    onCue()
                }
                .disabled(isCued)

                Button("Remove", systemImage: "trash") {
                    onRemove()
                }
                .disabled(isPlaying)
            }
        }
        .padding(SustainSpace.lg)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                .stroke(isCued || isPlaying ? rowTint.opacity(0.36) : SustainColor.separator, lineWidth: 1)
        )
    }

    private var rowTint: Color {
        isPlaying ? SustainColor.padActive : SustainColor.clickActive
    }
}

private struct MissingLiveSetlistEntryRow: View {
    var index: Int
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: SustainSpace.lg) {
            Text("\(index)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SustainColor.warning)
                .frame(width: 32)

            Label("Missing song reference", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(SustainColor.warning)

            Spacer()

            Button("Remove", systemImage: "trash") {
                onRemove()
            }
        }
        .padding(SustainSpace.lg)
        .background(SustainColor.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                .stroke(SustainColor.warning.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct EmptyLiveSetlistView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SustainSpace.sm) {
            Label("No songs in the service flow", systemImage: "music.note.list")
                .font(.headline)
                .foregroundStyle(SustainColor.textSecondary)
            Text("Choose a song above and add it when you are ready to build the run of service.")
                .font(.callout)
                .foregroundStyle(SustainColor.textSecondary)
        }
        .padding(SustainSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
    }
}
