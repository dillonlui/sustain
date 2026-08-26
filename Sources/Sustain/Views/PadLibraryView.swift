import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PadLibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @AppStorage("showIncludedPads") private var showIncludedPads = true

    @State private var selection = Set<PadTrack.ID>()
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var isChoosingAudio = false
    @State private var locatePadID: PadTrack.ID?
    @State private var removal: PadRemovalRequest?
    @State private var notice: String?

    private var visiblePads: [PadTrack] {
        store.padTracks.filter { pad in
            let includedVisible = showIncludedPads || !pad.isIncluded || store.padAssignmentCount(pad.id) > 0
            guard includedVisible else { return false }
            guard !searchText.isEmpty else { return true }
            return pad.label.localizedStandardContains(searchText) ||
                (pad.source.originalFilename?.localizedStandardContains(searchText) ?? false)
        }
    }

    private var canReorder: Bool { searchText.isEmpty && showIncludedPads }

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: $selection) {
                ForEach(visiblePads) { pad in
                    PadLibraryRow(
                        pad: pad,
                        state: state(for: pad),
                        assignmentCount: store.padAssignmentCount(pad.id),
                        isAudible: isPadAudible(pad.id),
                        onPlay: { store.playPadInRehearse(pad.id) },
                        onRename: { _ = store.renamePad(pad.id, label: $0, undoManager: undoManager) },
                        onReveal: { reveal(pad) },
                        onLocate: { locatePadID = pad.id },
                        onRemove: { requestRemoval(ids: [pad.id]) },
                        onMove: { _ = store.movePad(pad.id, by: $0, undoManager: undoManager) }
                    )
                    .tag(pad.id)
                    .contextMenu { rowMenu(for: pad) }
                    .dropDestination(for: URL.self) { urls, _ in
                        importURLs(urls, at: store.padTracks.firstIndex(where: { $0.id == pad.id }))
                        return !urls.isEmpty
                    }
                }
                .onMove { offsets, destination in
                    guard canReorder else { return }
                    _ = store.movePads(from: offsets, to: destination, undoManager: undoManager)
                }
            }
            .overlay {
                if visiblePads.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No custom pads" : "No matching pads",
                        systemImage: "waveform",
                        description: Text(searchText.isEmpty ? "Add audio files or drop them here." : "Try another label or filename.")
                    )
                    .dropDestination(for: URL.self) { urls, _ in
                        importURLs(urls, at: nil)
                        return !urls.isEmpty
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search labels and filenames")
            .onDeleteCommand { requestRemoval(ids: selection) }

            footer
        }
        .padding(.top, SustainLayout.topChrome)
        .sustainScreenBackground(.standard)
        .fileImporter(
            isPresented: $isChoosingAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result { importURLs(urls, at: nil) }
        }
        .fileImporter(
            isPresented: Binding(
                get: { locatePadID != nil },
                set: { if !$0 { locatePadID = nil } }
            ),
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard let padID = locatePadID else { return }
            locatePadID = nil
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await locate(padID, at: url) }
        }
        .sheet(item: $removal) { request in
            PadRemovalSheet(request: request, availablePads: store.padTracks) { replacement in
                let removed = store.removePads(
                    request.padIDs,
                    replacementPadID: replacement,
                    undoManager: undoManager
                )
                removal = nil
                if removed {
                    selection.subtract(request.padIDs)
                    announce("Removed \(request.padIDs.count) pad\(request.padIDs.count == 1 ? "" : "s")")
                }
            }
        }
    }

    private var header: some View {
        SustainScreenHeader(title: "Pad Library", subtitle: "Included and custom audio referenced in place") {
            Button("Add Audio\u{2026}", systemImage: "plus") { isChoosingAudio = true }
                .sustainProminentButton()
                .disabled(isImporting)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            HStack(spacing: SustainSpace.md) {
                Toggle("Show Included Pads", isOn: $showIncludedPads)
                    .toggleStyle(.checkbox)
                Text("\(visiblePads.count) of \(store.padTracks.count) pads")
                    .foregroundStyle(.secondary)
                if isImporting { ProgressView().controlSize(.small) }
                if let notice {
                    Text(notice).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Remove\u{2026}", role: .destructive) { requestRemoval(ids: selection) }
                    .disabled(selection.isEmpty || selection.contains(where: isIncludedPad))
            }
            Text("Sustain plays files as supplied; it does not normalize loudness or repair loop boundaries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(SustainSpace.md)
        .background(.bar)
    }

    @ViewBuilder
    private func rowMenu(for pad: PadTrack) -> some View {
        Button("Play in Rehearse", systemImage: "play.fill") { store.playPadInRehearse(pad.id) }
            .disabled(!state(for: pad).isAvailable)
        Divider()
        if !pad.isIncluded {
            Button("Reveal in Finder", systemImage: "folder") { reveal(pad) }
            Button("Locate or Replace\u{2026}", systemImage: "arrow.triangle.2.circlepath") { locatePadID = pad.id }
            Divider()
            Button("Move Up", systemImage: "arrow.up") { _ = store.movePad(pad.id, by: -1, undoManager: undoManager) }
                .disabled(!canReorder || store.padTracks.first?.id == pad.id)
            Button("Move Down", systemImage: "arrow.down") { _ = store.movePad(pad.id, by: 1, undoManager: undoManager) }
                .disabled(!canReorder || store.padTracks.last?.id == pad.id)
            Divider()
            Button("Remove Pad\u{2026}", systemImage: "trash", role: .destructive) { requestRemoval(ids: [pad.id]) }
                .disabled(isPadAudible(pad.id))
        } else {
            Text("Included pads are immutable")
        }
    }

    private func state(for pad: PadTrack) -> PadAssetState {
        if pad.isIncluded { return .available(metadata(for: pad)) }
        return store.padAssetStates[pad.id] ?? .available(metadata(for: pad))
    }

    private func metadata(for pad: PadTrack) -> PadAudioMetadata {
        if case let .external(reference) = pad.source { return reference.audioMetadata }
        return PadAudioMetadata(duration: 0, channelCount: 2, sampleRate: 44_100, decodedByteCount: 0)
    }

    private func isIncludedPad(_ id: PadTrack.ID) -> Bool {
        store.padTracks.first(where: { $0.id == id })?.isIncluded == true
    }

    private func requestRemoval(ids: Set<PadTrack.ID>) {
        let customIDs = ids.filter { !isIncludedPad($0) }
        guard !customIDs.isEmpty else { return }
        guard !customIDs.contains(where: isPadAudible) else {
            announce("Stop the audible pad before removing it")
            return
        }
        removal = PadRemovalRequest(
            padIDs: Set(customIDs),
            assignmentCount: store.songs.filter { $0.padTrackID.map(customIDs.contains) == true }.count
        )
    }

    private func importURLs(_ urls: [URL], at index: Int?) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        notice = "Validating \(urls.count) file\(urls.count == 1 ? "" : "s")\u{2026}"
        Task {
            let result = await store.importPadFiles(urls, at: index, undoManager: undoManager)
            isImporting = false
            let message = importSummary(result)
            notice = message
            selection = Set(result.imported.compactMap { imported in
                store.padTracks.first(where: {
                    guard case let .external(reference) = $0.source else { return false }
                    return reference.fingerprint == imported.reference.fingerprint
                })?.id
            })
            announce(message)
        }
    }

    private func importSummary(_ result: ExternalAudioImportResult) -> String {
        if let persistenceError = result.persistenceError { return persistenceError }
        var parts = ["Added \(result.imported.count)"]
        if !result.failures.isEmpty { parts.append("\(result.failures.count) failed") }
        if !result.skippedDuplicateFilenames.isEmpty { parts.append("\(result.skippedDuplicateFilenames.count) duplicate") }
        if result.wasCancelled { parts.append("cancelled") }
        return parts.joined(separator: ", ")
    }

    private func isPadAudible(_ padID: PadTrack.ID) -> Bool {
        store.runtime.audiblePadTrackID == padID ||
            (store.rehearse.padState != .off && store.rehearse.selectedPadTrackID == padID)
    }

    private func locate(_ padID: PadTrack.ID, at url: URL) async {
        let success = await store.locateExternalPad(padID, at: url)
        announce(success ? "Pad file updated" : store.runtime.lastMessage)
    }

    private func reveal(_ pad: PadTrack) {
        guard !pad.isIncluded else { return }
        Task {
            guard let url = await store.resolvedExternalPadURL(pad.id) else {
                announce(store.runtime.lastMessage)
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func announce(_ message: String) {
        notice = message
        AccessibilityNotification.Announcement(message).post()
    }
}

private struct PadLibraryRow: View {
    var pad: PadTrack
    var state: PadAssetState
    var assignmentCount: Int
    var isAudible: Bool
    var onPlay: () -> Void
    var onRename: (String) -> Void
    var onReveal: () -> Void
    var onLocate: () -> Void
    var onRemove: () -> Void
    var onMove: (Int) -> Void

    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: SustainSpace.lg) {
            Image(systemName: isAudible ? "speaker.wave.2.fill" : (pad.isIncluded ? "shippingbox.fill" : "waveform"))
                .foregroundStyle(isAudible ? SustainColor.accent : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: SustainSpace.xs) {
                if pad.isIncluded {
                    Text(pad.label).font(.headline)
                } else {
                    TextField("Pad label", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .focused($editing)
                        .onSubmit { commitRename() }
                        .onChange(of: editing) { _, focused in if !focused { commitRename() } }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(stateLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(state.isAvailable ? SustainColor.ready : SustainColor.warning)
            Text("\(assignmentCount) assigned")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
            Button(action: onPlay) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!state.isAvailable)
            .help("Play \(pad.label) in Rehearse")
            .accessibilityLabel("Play \(pad.label) in Rehearse")
            if !pad.isIncluded {
                Menu {
                    Button("Play in Rehearse", action: onPlay)
                    Divider()
                    Button("Reveal in Finder", action: onReveal)
                    Button("Locate or Replace\u{2026}", action: onLocate)
                    Button("Move Up") { onMove(-1) }
                    Button("Move Down") { onMove(1) }
                    Divider()
                    Button("Remove\u{2026}", role: .destructive, action: onRemove)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Actions for \(pad.label)")
            }
        }
        .padding(.vertical, SustainSpace.sm)
        .onAppear { draft = pad.label }
        .onChange(of: pad.label) { _, value in if !editing { draft = value } }
        .accessibilityElement(children: .contain)
    }

    private func commitRename() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { draft = pad.label; return }
        if trimmed != pad.label { onRename(trimmed) }
    }

    private var detail: String {
        switch pad.source {
        case let .bundled(key): return "Included \u{2022} \(key.rawValue)"
        case let .external(reference):
            let duration = Duration.seconds(reference.audioMetadata.duration).formatted(.time(pattern: .minuteSecond))
            let channels = reference.audioMetadata.channelCount == 1 ? "Mono" : "Stereo"
            let rate = String(format: "%.1f kHz", reference.audioMetadata.sampleRate / 1_000)
            return "\(reference.originalFilename) \u{2022} \(duration) \u{2022} \(channels) \u{2022} \(rate)"
        }
    }

    private var stateLabel: String {
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
}

private struct PadRemovalRequest: Identifiable {
    let id = UUID()
    var padIDs: Set<PadTrack.ID>
    var assignmentCount: Int
}

private struct PadRemovalSheet: View {
    var request: PadRemovalRequest
    var availablePads: [PadTrack]
    var onRemove: (PadTrack.ID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var replacementPadID: PadTrack.ID?

    private var replacements: [PadTrack] {
        availablePads.filter { !request.padIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SustainSpace.lg) {
            Text("Remove \(request.padIDs.count) Pad\(request.padIDs.count == 1 ? "" : "s")?")
                .font(.title2.weight(.semibold))
            Text(request.assignmentCount == 0
                ? "Source audio files will not be deleted."
                : "\(request.assignmentCount) song assignment\(request.assignmentCount == 1 ? "" : "s") must be replaced atomically. Source audio files will not be deleted.")
                .foregroundStyle(.secondary)
            if request.assignmentCount > 0 {
                Picker("Replace assignments with", selection: $replacementPadID) {
                    Text("No Pad").tag(PadTrack.ID?.none)
                    ForEach(replacements) { pad in Text(pad.label).tag(Optional(pad.id)) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Remove", role: .destructive) { onRemove(replacementPadID) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SustainSpace.xxl)
        .frame(width: 480)
    }
}

#Preview("Pad Library") {
    PadLibraryView()
        .environment(AppStore.preview())
        .frame(width: 960, height: 720)
}
