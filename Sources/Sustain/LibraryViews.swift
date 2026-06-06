import CoreAudio
import SwiftUI

struct SongLibraryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Song Library")
                        .font(.largeTitle.weight(.semibold))
                    Text(store.persistenceStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Add Song", systemImage: "plus") {
                    _ = store.addSong()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 8)

            List(store.songs) { song in
                HStack(alignment: .center, spacing: 14) {
                    TextField("Title", text: titleBinding(for: song.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)

                    Picker("Key", selection: keyBinding(for: song.id)) {
                        ForEach(MusicalKey.allCases) { key in
                            Text(key.rawValue).tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 82)

                    Stepper(
                        "\(song.defaultBPM) BPM",
                        value: bpmBinding(for: song.id),
                        in: 40...220
                    )
                    .frame(width: 140)

                    Picker("Time", selection: timeSignatureBinding(for: song.id)) {
                        ForEach(TimeSignature.common, id: \.self) { timeSignature in
                            Text(timeSignature.description).tag(timeSignature)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)

                    Picker("Pad Source", selection: padPackBinding(for: song.id)) {
                        ForEach(store.padPacks) { padPack in
                            Text(padPack.name).tag(padPack.id)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 150)

                    Button("Add to Setlist", systemImage: "text.badge.plus") {
                        _ = store.addSongToSetlist(song.id)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Song Library")
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
            padPackID: updated.padPack.id
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

    private func padPackBinding(for songID: Song.ID) -> Binding<PadPack.ID> {
        Binding {
            song(songID)?.padPack.id ?? store.padPacks.first?.id ?? PadPack.bundled.id
        } set: { padPackID in
            updateSong(songID) { song in
                var song = song
                song.padPack = store.padPacks.first { $0.id == padPackID } ?? song.padPack
                return song
            }
        }
    }
}

struct SetlistBuilderView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedSongID: Song.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Setlist Title", text: setlistTitleBinding)
                        .font(.largeTitle.weight(.semibold))
                        .textFieldStyle(.plain)
                    Text(store.persistenceStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Song", selection: selectedSongBinding) {
                    Text("Choose Song").tag(Song.ID?.none)
                    ForEach(store.songs) { song in
                        Text(song.title).tag(Song.ID?.some(song.id))
                    }
                }
                .frame(width: 220)

                Button("Add", systemImage: "plus") {
                    addSelectedSongToSetlist()
                }
                .disabled(selectedSongBinding.wrappedValue == nil)

                Button("Clear", systemImage: "trash") {
                    store.clearSetlist()
                }
                .disabled(store.activeSetlist.entries.isEmpty || store.runtime.playbackPhase != .noSongPlaying)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 8)

            List(store.activeSetlist.entries) { entry in
                if let song = store.song(for: entry) {
                    HStack(alignment: .center, spacing: 16) {
                        Image(systemName: store.runtime.cuedEntryID == entry.id ? "arrow.forward.circle.fill" : "circle")
                            .foregroundStyle(store.runtime.cuedEntryID == entry.id ? Color.sustainSage : .secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .font(.headline)
                            Text("\(entry.resolvedKey(for: song).rawValue) · \(entry.resolvedBPM(for: song)) BPM · \(song.timeSignature.description)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("Key", selection: keyBinding(for: entry.id, song: song)) {
                            ForEach(MusicalKey.allCases) { key in
                                Text(key.rawValue).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 86)

                        Stepper(
                            "\(store.entry(id: entry.id)?.resolvedBPM(for: song) ?? song.defaultBPM) BPM",
                            value: bpmBinding(for: entry.id, song: song),
                            in: 40...220
                        )
                        .frame(width: 148)

                        Button("Cue", systemImage: "arrow.forward.circle") {
                            store.cue(entryID: entry.id)
                        }
                        .disabled(store.runtime.cuedEntryID == entry.id)

                        Button("Remove", systemImage: "trash") {
                            store.removeSetlistEntry(entry.id)
                        }
                        .disabled(store.runtime.playingEntryID == entry.id)
                    }
                    .padding(.vertical, 8)
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Missing song reference")
                            .font(.headline)
                        Spacer()
                        Button("Remove", systemImage: "trash") {
                            store.removeSetlistEntry(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Setlist")
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
}

struct AudioSetupView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("Outputs") {
                LabeledContent("Routing", value: store.routingSnapshot.summary)
                LabeledContent("Detected Outputs", value: "\(store.routingSnapshot.outputs.count)")

                Picker("Pad Output", selection: padOutputBinding) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(store.routingSnapshot.outputs) { output in
                        Text(output.isDefault ? "\(output.name) (Default)" : output.name)
                            .tag(AudioDeviceID?.some(output.id))
                    }
                }

                Picker("Click Output", selection: clickOutputBinding) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(store.routingSnapshot.outputs) { output in
                        Text(output.isDefault ? "\(output.name) (Default)" : output.name)
                            .tag(AudioDeviceID?.some(output.id))
                    }
                }

                if let warning = store.routingSnapshot.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                DisclosureGroup("Detected Devices") {
                    ForEach(store.routingSnapshot.outputs) { output in
                        HStack {
                            Text(output.name)
                            Spacer()
                            if output.isDefault {
                                Text("Default")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Engine") {
                LabeledContent("Status", value: store.audioStatus)
                LabeledContent("Pad Playback", value: "Looping bundled MP3 files")
                LabeledContent("Click", value: "Generated from BPM")
                LabeledContent("Countoff", value: "Required before click")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Audio Setup")
    }

    private var padOutputBinding: Binding<AudioDeviceID?> {
        Binding {
            store.routingSettings.padOutputID
        } set: { outputID in
            store.updateRouting(
                padOutputID: outputID,
                clickOutputID: store.routingSettings.clickOutputID
            )
        }
    }

    private var clickOutputBinding: Binding<AudioDeviceID?> {
        Binding {
            store.routingSettings.clickOutputID
        } set: { outputID in
            store.updateRouting(
                padOutputID: store.routingSettings.padOutputID,
                clickOutputID: outputID
            )
        }
    }
}

struct SystemCheckView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Check")
                        .font(.largeTitle.weight(.semibold))
                    Text("Playback is blocked when critical requirements are missing.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Run Check", systemImage: "checkmark.shield") {
                    store.runSystemCheck()
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(store.systemCheck.messages, id: \.self) { message in
                HStack(spacing: 12) {
                    Image(systemName: store.systemCheck.canStartPlayback ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.systemCheck.canStartPlayback ? Color.sustainSage : .orange)
                    Text(message)
                    Spacer()
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            GroupBox("Runtime") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Audio", value: store.audioStatus)
                    LabeledContent("Routing", value: store.routingSnapshot.summary)
                    LabeledContent("Library", value: store.persistenceStatus)
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding(28)
        .navigationTitle("System Check")
    }
}
