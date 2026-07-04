import SwiftUI

struct LiveServiceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingEntryID: SetlistEntry.ID?
    @State private var titleDraft = ""

    var body: some View {
        HSplitView {
            setlistPane
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            performanceSurface
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sustainScreenBackground(.live)
        .inspector(isPresented: inspectorPresented) {
            SongInspectorPane(entryID: editingEntryID) { editingEntryID = nil }
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .onAppear { titleDraft = store.activeSetlist.title }
    }

    // MARK: Setlist pane

    private var setlistPane: some View {
        List(selection: cuedSelection) {
            ForEach(Array(store.activeSetlist.entries.enumerated()), id: \.element.id) { index, entry in
                SetlistRowView(
                    index: index + 1,
                    song: store.song(for: entry),
                    entry: entry,
                    isPlaying: store.runtime.playingEntryID == entry.id
                )
                .tag(entry.id)
                .contextMenu {
                    Button("Edit\u{2026}") { editingEntryID = entry.id }
                    Button("Remove", role: .destructive) { store.removeSetlistEntry(entry.id) }
                        .disabled(store.runtime.playingEntryID == entry.id)
                }
            }
            .onMove { store.moveSetlistEntry(from: $0, to: $1) }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top, spacing: 0) { setlistHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { setlistFooter }
        .overlay {
            if store.activeSetlist.entries.isEmpty {
                ContentUnavailableView(
                    "No songs yet",
                    systemImage: "music.note.list",
                    description: Text("Add songs to build the service.")
                )
            }
        }
    }

    private var setlistHeader: some View {
        VStack(spacing: SustainSpace.xs) {
            TextField("Service", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.headline)
                .onSubmit { store.updateActiveSetlistTitle(titleDraft) }

            HStack {
                Text("\(store.activeSetlist.entries.count) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, SustainSpace.md)
        .padding(.vertical, SustainSpace.sm)
        .background(.bar)
    }

    private var setlistFooter: some View {
        HStack {
            Menu {
                if store.songs.isEmpty {
                    Text("No songs in library")
                } else {
                    ForEach(store.songs) { song in
                        Button(song.title) { _ = store.addSongToSetlist(song.id) }
                    }
                    Divider()
                }
                Button("New Song\u{2026}", systemImage: "plus") {
                    let songID = store.addSong()
                    if let entryID = store.addSongToSetlist(songID) {
                        editingEntryID = entryID
                    }
                }
            } label: {
                Label("Add Song", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, SustainSpace.md)
        .padding(.vertical, SustainSpace.sm)
        .background(.bar)
    }

    private var cuedSelection: Binding<SetlistEntry.ID?> {
        Binding {
            store.runtime.cuedEntryID
        } set: { newValue in
            if let newValue { store.cue(entryID: newValue) }
        }
    }

    // MARK: Performance surface

    private var performanceSurface: some View {
        VStack(spacing: SustainSpace.xl) {
            nowNextRow

            CountoffIndicator(beat: store.runtime.countoffBeat, total: store.runtime.countoffTotal)

            Spacer(minLength: 0)

            levelsRow
            channelControls
            transportCluster
            messageStrip
        }
        .padding(SustainSpace.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var nowNextRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: SustainSpace.lg) {
                nowPanel
                nextPanel
            }
            VStack(spacing: SustainSpace.lg) {
                nowPanel
                nextPanel
            }
        }
    }

    private var nowPanel: some View {
        StatePanel(
            label: "NOW",
            isActive: store.runtime.playbackPhase == .songPlaying,
            entry: store.playingEntry,
            song: store.song(for: store.playingEntry),
            emptyText: "No song playing"
        )
    }

    private var nextPanel: some View {
        StatePanel(
            label: "NEXT",
            isActive: false,
            entry: store.cuedEntry,
            song: store.song(for: store.cuedEntry),
            emptyText: "Nothing cued"
        )
    }

    private var levelsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SustainSpace.lg) {
                padFader
                clickFader
            }
            VStack(spacing: SustainSpace.lg) {
                padFader
                clickFader
            }
        }
    }

    private var padFader: some View {
        ChannelFader(
            title: "Pad",
            subtitle: "Atmosphere",
            systemImage: "waveform",
            tint: SustainColor.accent,
            isActive: store.runtime.padState == .playing,
            value: padVolumeBinding,
            onCommit: { store.commitAudioLevels() }
        )
    }

    private var clickFader: some View {
        ChannelFader(
            title: "Click",
            subtitle: "Guide",
            systemImage: "metronome",
            tint: SustainColor.accent,
            isActive: store.runtime.clickState != .off,
            value: clickVolumeBinding,
            onCommit: { store.commitAudioLevels() }
        )
    }

    private var channelControls: some View {
        HStack(spacing: SustainSpace.md) {
            Button {
                store.runtime.clickState == .off ? store.startClick() : store.stopClick()
            } label: {
                Label(store.runtime.clickState == .off ? "Start Click" : "Stop Click", systemImage: "metronome")
            }
            .disabled(store.runtime.playbackPhase == .noSongPlaying)

            Button {
                store.runtime.padState == .off ? store.startPad() : store.stopPad()
            } label: {
                Label(store.runtime.padState == .off ? "Start Pad" : "Stop Pad", systemImage: "waveform")
            }
            .disabled(store.runtime.playbackPhase == .noSongPlaying)

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var transportCluster: some View {
        HStack(spacing: SustainSpace.md) {
            Button { store.cuePreviousSong() } label: {
                Image(systemName: "backward.fill")
                    .frame(minWidth: 36)
            }
            .controlSize(.large)
            .disabled(store.activeSetlist.entries.isEmpty)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button { store.startCuedSong() } label: {
                Label(startTitle, systemImage: isTransition ? "arrow.triangle.2.circlepath" : "play.fill")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(SustainColor.accent)
            .disabled(store.cuedEntry == nil)
            .keyboardShortcut(.return, modifiers: [])

            Button { store.cueNextSong() } label: {
                Image(systemName: "forward.fill")
                    .frame(minWidth: 36)
            }
            .controlSize(.large)
            .disabled(store.activeSetlist.entries.isEmpty)
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button(role: .destructive) { store.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(minWidth: 90)
            }
            .controlSize(.large)
            .tint(SustainColor.destructive)
            .disabled(store.runtime.playbackPhase == .noSongPlaying)
            .keyboardShortcut(".", modifiers: .command)
        }
        .frame(maxWidth: .infinity)
    }

    private var messageStrip: some View {
        HStack(spacing: SustainSpace.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(store.runtime.lastMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Derived

    private var isTransition: Bool {
        store.runtime.playingEntryID != nil && store.runtime.cuedEntryID != store.runtime.playingEntryID
    }

    private var startTitle: String {
        isTransition ? "Transition" : "Start"
    }

    private var inspectorPresented: Binding<Bool> {
        Binding {
            editingEntryID != nil
        } set: { isPresented in
            if !isPresented { editingEntryID = nil }
        }
    }

    private var padVolumeBinding: Binding<Double> {
        Binding { store.padVolume } set: { store.setPadVolumeLive($0) }
    }

    private var clickVolumeBinding: Binding<Double> {
        Binding { store.clickVolume } set: { store.setClickVolumeLive($0) }
    }
}

// MARK: - NOW / NEXT panel

private struct StatePanel: View {
    var label: String
    var isActive: Bool
    var entry: SetlistEntry?
    var song: Song?
    var emptyText: String

    var body: some View {
        SustainPanel(isActive: isActive) {
            VStack(alignment: .leading, spacing: SustainSpace.md) {
                HStack(spacing: SustainSpace.sm) {
                    Circle()
                        .fill(isActive ? SustainColor.accent : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(isActive ? SustainColor.accent : .secondary)
                }

                if let entry, let song {
                    Text(song.title)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: SustainSpace.sm) {
                        MetadataChip(label: "Key", value: entry.resolvedKey(for: song).rawValue)
                        MetadataChip(label: "BPM", value: "\(entry.resolvedBPM(for: song))")
                        MetadataChip(label: "Time", value: song.timeSignature.description)
                    }
                } else {
                    Text(emptyText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, SustainSpace.sm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Setlist row

private struct SetlistRowView: View {
    var index: Int
    var song: Song?
    var entry: SetlistEntry
    var isPlaying: Bool

    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            Text("\(index)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(song?.title ?? "Missing song")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(song == nil ? SustainColor.warning : .primary)

                if let song {
                    Text("\(entry.resolvedKey(for: song).rawValue) · \(entry.resolvedBPM(for: song)) · \(song.timeSignature.description)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: SustainSpace.sm)

            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(SustainColor.accent)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Inspector

private struct SongInspectorPane: View {
    @EnvironmentObject private var store: AppStore
    var entryID: SetlistEntry.ID?
    var onClose: () -> Void

    @State private var titleDraft = ""

    var body: some View {
        Group {
            if let entryID, let entry = store.entry(id: entryID), let song = store.song(for: entry) {
                Form {
                    Section("Song") {
                        TextField("Title", text: $titleDraft)
                            .onSubmit { commitTitle(song) }
                        Picker("Time", selection: timeSignatureBinding(song)) {
                            ForEach(TimeSignature.common, id: \.self) { signature in
                                Text(signature.description).tag(signature)
                            }
                        }
                        LabeledContent("Pads", value: "Included")
                    }

                    Section("This service") {
                        Picker("Key", selection: keyBinding(entryID, song)) {
                            ForEach(MusicalKey.allCases) { key in
                                Text(key.rawValue).tag(key)
                            }
                        }
                        Stepper(
                            "Tempo \(entry.resolvedBPM(for: song)) BPM",
                            value: bpmBinding(entryID, song),
                            in: 40...220
                        )
                        if entry.keyOverride != nil || entry.bpmOverride != nil {
                            Button("Reset to song defaults") {
                                store.updateEntry(entryID, keyOverride: nil, bpmOverride: nil)
                            }
                        }
                    }

                    Section {
                        Button("Remove from setlist", role: .destructive) {
                            store.removeSetlistEntry(entryID)
                            onClose()
                        }
                        .disabled(store.runtime.playingEntryID == entryID)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Edit Song")
                .onAppear { titleDraft = song.title }
                .onChange(of: entryID) { titleDraft = song.title }
            } else {
                ContentUnavailableView(
                    "No song selected",
                    systemImage: "slider.horizontal.3",
                    description: Text("Choose a song to edit its key and tempo.")
                )
            }
        }
    }

    private func commitTitle(_ song: Song) {
        store.updateSong(
            song.id,
            title: titleDraft,
            defaultKey: song.defaultKey,
            defaultBPM: song.defaultBPM,
            timeSignature: song.timeSignature,
            padPackID: PadPack.bundled.id
        )
    }

    private func timeSignatureBinding(_ song: Song) -> Binding<TimeSignature> {
        Binding {
            song.timeSignature
        } set: { signature in
            store.updateSong(
                song.id,
                title: song.title,
                defaultKey: song.defaultKey,
                defaultBPM: song.defaultBPM,
                timeSignature: signature,
                padPackID: PadPack.bundled.id
            )
        }
    }

    private func keyBinding(_ entryID: SetlistEntry.ID, _ song: Song) -> Binding<MusicalKey> {
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

    private func bpmBinding(_ entryID: SetlistEntry.ID, _ song: Song) -> Binding<Int> {
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
}
