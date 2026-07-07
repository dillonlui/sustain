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

    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: SustainSpace.lg) {
                titleField
                Spacer(minLength: SustainSpace.md)
                controls
            }
            VStack(alignment: .leading, spacing: SustainSpace.md) {
                titleField
                controls
            }
        }
        .padding(SustainSpace.lg)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                .stroke(SustainColor.separator, lineWidth: 1)
        )
        .onAppear { titleDraft = title }
        .onChange(of: title) { _, newValue in
            // Keep the draft in sync when the underlying title changes
            // externally, but never clobber an in-progress edit.
            if !titleFocused { titleDraft = newValue }
        }
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleDraft = title // reject empty; restore last committed value
        } else if trimmed != title {
            title = trimmed
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: SustainSpace.sm) {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                .focused($titleFocused)
                .onSubmit { commitTitle() }
                .onChange(of: titleFocused) { _, isFocused in
                    if !isFocused { commitTitle() } // commit on click-away
                }

            HStack(spacing: SustainSpace.sm) {
                MetadataChip(label: "Key", value: key.rawValue)
                MetadataChip(label: "BPM", value: "\(bpm)")
                MetadataChip(label: "Time", value: timeSignature.description)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: SustainSpace.md) {
            Picker("Key", selection: $key) {
                ForEach(MusicalKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 84)

            Stepper("\(bpm) BPM", value: $bpm, in: 40...220)
                .frame(width: 128)

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
    }
}

struct AudioDeviceDiagnosticRow: View {
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

struct DiagnosticLine: View {
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
