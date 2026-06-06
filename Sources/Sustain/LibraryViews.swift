import SwiftUI

struct SongLibraryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Table(store.songs) {
            TableColumn("Title") { song in
                Text(song.title)
            }
            TableColumn("Key") { song in
                Text(song.defaultKey.rawValue)
            }
            TableColumn("BPM") { song in
                Text("\(song.defaultBPM)")
            }
            TableColumn("Time") { song in
                Text(song.timeSignature.description)
            }
            TableColumn("Pad Pack") { song in
                Text(song.padPack.name)
            }
        }
        .navigationTitle("Song Library")
    }
}

struct SetlistBuilderView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.activeSetlist.title)
                    .font(.largeTitle.weight(.semibold))
                Text(store.persistenceStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Setlist")
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

            Section("Engine") {
                LabeledContent("Status", value: store.audioStatus)
                LabeledContent("Pad Playback", value: "Looping WAV files")
                LabeledContent("Click", value: "Generated from BPM")
                LabeledContent("Countoff", value: "Required before click")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Audio Setup")
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
