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
            Text(store.activeSetlist.title)
                .font(.largeTitle.weight(.semibold))
                .padding([.horizontal, .top], 24)
                .padding(.bottom, 8)

            List(store.activeSetlist.entries) { entry in
                if let song = store.song(for: entry) {
                    HStack(spacing: 16) {
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

                        Button("Cue") {
                            store.runtime.cuedEntryID = entry.id
                            store.runtime.lastMessage = "Cued \(song.title)"
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Setlist")
    }
}

struct AudioSetupView: View {
    var body: some View {
        Form {
            Section("Outputs") {
                Picker("Pad Output", selection: .constant("Default Output")) {
                    Text("Default Output").tag("Default Output")
                }

                Picker("Click Output", selection: .constant("Default Output")) {
                    Text("Default Output").tag("Default Output")
                }
            }

            Section("Engine") {
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

            Spacer()
        }
        .padding(28)
        .navigationTitle("System Check")
    }
}
