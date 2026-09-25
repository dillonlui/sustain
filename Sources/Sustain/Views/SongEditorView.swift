import SwiftUI

enum SongEditorContext: Equatable {
    case library
    case live(SetlistEntry.ID)
}

/// Keeps related controls at their natural widths and wraps only when the pane needs it.
private struct ClickFieldsLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measure(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = measure(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func measure(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > availableWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }

        return (CGSize(width: proposal.width ?? usedWidth, height: y + rowHeight), positions)
    }
}

/// The same song fields and save behavior in Song Library and the Live editor.
struct SongEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    @Binding var draft: SongDraft
    var context: SongEditorContext
    var onSaved: (Song.ID) -> Void
    var onClose: () -> Void
    var onDeleted: () -> Void = {}

    @State private var isChoosingPad = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var songID: Song.ID? { draft.id }

    private var assignedPadLabel: String {
        guard let padID = draft.padTrackID else { return "No Pad" }
        return store.padTracks.first(where: { $0.id == padID })?.label ?? "Missing Pad"
    }

    private var assignedPadUnavailable: Bool {
        guard let padID = draft.padTrackID,
              let pad = store.padTracks.first(where: { $0.id == padID }),
              !pad.isIncluded else { return false }
        return store.padAssetStates[padID].map { !$0.isAvailable } ?? false
    }

    private var assignmentCount: Int {
        guard let songID else { return 0 }
        return store.activeSetlist.entries.filter { $0.songID == songID }.count
    }

    private var isPlayingSong: Bool {
        guard let songID else { return false }
        return store.playingEntry?.songID == songID
    }

    private var subdivisionLocked: Bool {
        isPlayingSong && store.runtime.clickState == .countoff
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: SustainSpace.xl) {
                    songSection
                    clickSection
                    if let errorMessage {
                        SustainInlineNotice(message: errorMessage, kind: .error)
                    }
                    actionSection
                }
                .padding(SustainSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            footer
        }
        .background(palette.panel)
        .sheet(isPresented: $isChoosingPad) {
            SongPadChooser(
                selectedPadID: draft.padTrackID,
                padTracks: store.padTracks,
                assetStates: store.padAssetStates
            ) { selected in
                draft.padTrackID = selected
                isChoosingPad = false
            }
        }
        .confirmationDialog(
            "Delete “\(draft.title)”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Song", role: .destructive) {
                guard let songID else { return }
                store.deleteSong(songID)
                onDeleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the song from your library and every setlist. This can’t be undone.")
        }
        .onAppear {
            if songID == nil { titleFocused = true }
        }
    }

    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: SustainSpace.xxs) {
                Text(songID == nil ? "New Song" : "Edit Song")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                if songID != nil, case .library = context {
                    Text("\(assignmentCount) in setlist")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            Button("Close", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityLabel("Close song editor")
        }
        .padding(.horizontal, SustainSpace.lg)
        .padding(.vertical, SustainSpace.md)
    }

    private var songSection: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            sectionTitle("Song", symbol: "music.note")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SustainSpace.md) {
                    titleField.frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                    padField.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: SustainSpace.md) {
                    titleField
                    padField
                }
            }
        }
        .padding(SustainSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.performanceSurface, in: RoundedRectangle(cornerRadius: SustainRadius.panel))
    }

    private var clickSection: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            sectionTitle("Click", symbol: "metronome")
            ClickFieldsLayout(spacing: SustainSpace.sm) {
                tempoField.frame(width: 135, alignment: .leading)
                timeSignatureField.frame(width: 120, alignment: .leading)
                subdivisionField.frame(width: 200, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SustainSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.performanceSurface, in: RoundedRectangle(cornerRadius: SustainRadius.panel))
    }

    @ViewBuilder
    private var actionSection: some View {
        if let songID {
            VStack(alignment: .leading, spacing: SustainSpace.md) {
                sectionTitle("Actions", symbol: "ellipsis.circle")
                switch context {
                case .library:
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: SustainSpace.md) {
                            addToSetlistButton(songID)
                            deleteSongButton
                        }
                        VStack(alignment: .leading, spacing: SustainSpace.md) {
                            addToSetlistButton(songID)
                            deleteSongButton
                        }
                    }
                case let .live(entryID):
                    Button("Remove from Setlist", systemImage: "minus.circle", role: .destructive) {
                        store.removeSetlistEntry(entryID)
                        onDeleted()
                    }
                    .disabled(store.runtime.playingEntryID == entryID)
                }
            }
            .padding(SustainSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.performanceSurface, in: RoundedRectangle(cornerRadius: SustainRadius.panel))
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            Text("Title").font(.callout.weight(.medium))
            TextField("Song title", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .accessibilityLabel("Song title")
        }
    }

    private var padField: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            Text("Assigned Pad").font(.callout.weight(.medium))
            Button {
                isChoosingPad = true
            } label: {
                HStack {
                    Image(systemName: "waveform")
                    Text(assignedPadLabel).lineLimit(1)
                    Spacer(minLength: SustainSpace.sm)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Assigned Pad, \(assignedPadLabel)")
            if draft.padTrackID == nil {
                Text("No Pad plays click and countoff only.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if assignedPadLabel == "Missing Pad" {
                Text("The assigned pad is missing. Choose another pad before saving.")
                    .font(.caption)
                    .foregroundStyle(palette.warning)
            } else if assignedPadUnavailable {
                Text("This pad's audio is unavailable. Open Pad Library from the chooser to locate it.")
                    .font(.caption)
                    .foregroundStyle(palette.warning)
            }
            if isPlayingSong {
                Text("Pad assignment changes take effect at the next start.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var tempoField: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            Text("Tempo").font(.callout.weight(.medium))
            TempoControl(value: $draft.defaultBPM, label: "")
        }
    }

    private var timeSignatureField: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            Text("Time Signature").font(.callout.weight(.medium))
            Picker("Time Signature", selection: $draft.timeSignature) {
                ForEach(TimeSignature.common, id: \.self) { signature in
                    Text(signature.description).tag(signature)
                }
            }
            .labelsHidden()
        }
    }

    private var subdivisionField: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            Text("Subdivision").font(.callout.weight(.medium))
            Picker("Subdivision", selection: $draft.clickSubdivision) {
                ForEach(ClickSubdivision.allCases) { subdivision in
                    Text(subdivision.label)
                        .accessibilityLabel(subdivision.accessibilityLabel)
                        .tag(subdivision)
                }
            }
            .labelsHidden()
            .disabled(subdivisionLocked)
            .help(subdivisionLocked ? "Subdivision can change after countoff" : "Choose clicks per BPM beat")
            Text("Adds evenly spaced clicks inside each BPM beat.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func addToSetlistButton(_ songID: Song.ID) -> some View {
        Button("Add to Setlist", systemImage: "text.badge.plus") {
            _ = store.addSongToSetlist(songID)
        }
    }

    private var deleteSongButton: some View {
        Button("Delete Song", systemImage: "trash", role: .destructive) {
            isConfirmingDelete = true
        }
        .disabled(isPlayingSong)
        .help(isPlayingSong ? "Stop playback before deleting this song" : "Delete song and its setlist entries")
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onClose)
            Spacer()
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(SustainSpace.lg)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(palette.textPrimary)
    }

    private func save() {
        guard let savedID = store.saveSongDraft(draft) else {
            errorMessage = store.persistenceStatus
            return
        }
        errorMessage = nil
        if let saved = store.songs.first(where: { $0.id == savedID }) {
            draft = SongDraft(song: saved)
        }
        onSaved(savedID)
    }
}
