import Accessibility
import SwiftUI

struct SongLibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var selectedSongID: Song.ID?
    @State private var draft = SongDraft.newSong()
    @State private var baseline: SongDraft?
    @State private var isCreating = false
    @State private var isShowingEditor = false
    @State private var pendingAction: PendingAction?
    @State private var isConfirmingDiscard = false

    private enum PendingAction {
        case select(Song.ID, compact: Bool)
        case create(compact: Bool)
        case close
    }

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var hasUnsavedChanges: Bool {
        baseline.map { draft != $0 } ?? false
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 780
            VStack(spacing: 0) {
                SustainScreenHeader(
                    title: "Song Library",
                    subtitle: "Songs, assigned pads, and click settings"
                ) {
                    Button("Add Song", systemImage: "plus") {
                        request(.create(compact: compact))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.activeSignal)
                }

                Rectangle().fill(palette.divider).frame(height: 1)

                if compact {
                    songList(compact: true)
                        .sheet(isPresented: $isShowingEditor) {
                            if baseline != nil {
                                editor
                                    .id(isCreating ? "new-song" : selectedSongID?.uuidString ?? "song")
                                    .frame(minWidth: 440, minHeight: 500)
                                    .interactiveDismissDisabled(hasUnsavedChanges)
                            }
                        }
                } else {
                    HStack(spacing: 0) {
                        songList(compact: false)
                            .frame(width: min(380, max(290, geometry.size.width * 0.36)))
                        Rectangle().fill(palette.divider).frame(width: 1)
                        if baseline != nil {
                            editor
                                .id(isCreating ? "new-song" : selectedSongID?.uuidString ?? "song")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ContentUnavailableView(
                                "Choose a song",
                                systemImage: "music.note.list",
                                description: Text("Select a song to edit it, or add a new song.")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .padding(.top, SustainLayout.topChrome)
            .background(palette.canvas)
            .confirmationDialog(
                "Discard unsaved changes?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    if let pendingAction { perform(pendingAction) }
                    pendingAction = nil
                }
                Button("Keep Editing", role: .cancel) { pendingAction = nil }
            } message: {
                Text("Changes to this song have not been saved.")
            }
            .onAppear {
                if baseline == nil, let first = store.songs.first {
                    load(first.id, compact: false)
                }
                store.dirtySongEditorScreen = hasUnsavedChanges ? .songs : nil
            }
            .onChange(of: hasUnsavedChanges) { _, dirty in
                store.dirtySongEditorScreen = dirty ? .songs : nil
            }
        }
    }

    private func songList(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SustainSpace.md) {
                HStack {
                    Text("SONGS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text("\(store.songs.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, SustainSpace.sm)

                if store.songs.isEmpty {
                    ContentUnavailableView {
                        Label("No songs yet", systemImage: "music.note.list")
                    } description: {
                        Text("Add a song and choose its pad and click settings.")
                    } actions: {
                        Button("Add Song") { request(.create(compact: compact)) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    LazyVStack(spacing: SustainSpace.sm) {
                        ForEach(store.songs) { song in
                            songRow(song, compact: compact)
                        }
                    }
                }
            }
            .padding(SustainSpace.lg)
        }
        .background(palette.canvas)
    }

    private func songRow(_ song: Song, compact: Bool) -> some View {
        let isSelected = selectedSongID == song.id && !isCreating
        let membershipCount = store.activeSetlist.entries.filter { $0.songID == song.id }.count
        let padLabel = song.padTrackID.flatMap { id in store.padTracks.first(where: { $0.id == id })?.label }
            ?? (song.padTrackID == nil ? "No Pad" : "Missing Pad")

        return HStack(spacing: 0) {
            Button {
                request(.select(song.id, compact: compact))
            } label: {
                HStack(alignment: .center, spacing: SustainSpace.sm) {
                    VStack(alignment: .leading, spacing: SustainSpace.xs) {
                        Text(song.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                        Text("\(padLabel) · \(song.defaultBPM) BPM · \(song.timeSignature.description)")
                            .font(.caption)
                            .foregroundStyle(padLabel == "Missing Pad" ? palette.warning : palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: SustainSpace.sm)
                    if membershipCount > 0 {
                        Text("\(membershipCount) in setlist")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, SustainSpace.md)
                .padding(.vertical, SustainSpace.md)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(song.title), assigned pad \(padLabel), \(song.defaultBPM) beats per minute, \(song.timeSignature.description)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Open song editor")

            Button {
                if store.addSongToSetlist(song.id) != nil {
                    AccessibilityNotification.Announcement("Added \(song.title) to setlist").post()
                }
            } label: {
                Image(systemName: "text.badge.plus")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .help("Add \(song.title) to setlist")
            .accessibilityLabel("Add \(song.title) to setlist")
            .padding(.horizontal, SustainSpace.sm)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? palette.activeSignal.opacity(0.12) : palette.performanceSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? palette.activeSignal : palette.surfaceEdge.opacity(0.5), lineWidth: 1)
        }
    }

    private var editor: some View {
        SongEditorView(
            draft: $draft,
            context: .library,
            onSaved: { savedID in
                selectedSongID = savedID
                isCreating = false
                baseline = draft
                isShowingEditor = false
            },
            onClose: { request(.close) },
            onDeleted: {
                isShowingEditor = false
                if let first = store.songs.first {
                    load(first.id, compact: false)
                } else {
                    selectedSongID = nil
                    baseline = nil
                }
            }
        )
    }

    private func request(_ action: PendingAction) {
        if hasUnsavedChanges {
            pendingAction = action
            isConfirmingDiscard = true
        } else {
            perform(action)
        }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case let .select(id, compact):
            load(id, compact: compact)
        case let .create(compact):
            draft = .newSong()
            baseline = draft
            selectedSongID = nil
            isCreating = true
            isShowingEditor = compact
        case .close:
            isShowingEditor = false
            selectedSongID = nil
            baseline = nil
            isCreating = false
        }
    }

    private func load(_ id: Song.ID, compact: Bool) {
        guard let song = store.songs.first(where: { $0.id == id }) else { return }
        selectedSongID = id
        draft = SongDraft(song: song)
        baseline = draft
        isCreating = false
        isShowingEditor = compact
    }
}
