import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PadLibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("showIncludedPads") private var showIncludedPads = true

    @State private var selection = Set<PadTrack.ID>()
    @State private var selectionAnchor: PadTrack.ID?
    @State private var isImporting = false
    @State private var removal: PadRemovalRequest?
    @State private var notice: String?

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var visiblePads: [PadTrack] {
        store.padTracks.filter { showIncludedPads || !$0.isIncluded }
    }

    private var canReorder: Bool { showIncludedPads }

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(visiblePads) { pad in
                    PadLibraryRow(
                        pad: pad,
                        state: state(for: pad),
                        isSelected: selection.contains(pad.id),
                        assignmentCount: store.padAssignmentCount(pad.id),
                        playbackState: store.padPlaybackState(for: pad.id),
                        canMoveUp: canReorder && store.padTracks.first?.id != pad.id,
                        canMoveDown: canReorder && store.padTracks.last?.id != pad.id,
                        onPlaybackAction: { store.togglePadPlayback(for: pad.id) },
                        onRename: { _ = store.renamePad(pad.id, label: $0, undoManager: undoManager) },
                        onReveal: { reveal(pad) },
                        onLocate: { chooseAudio(replacing: pad.id) },
                        onRemove: { requestRemoval(ids: [pad.id]) },
                        onMove: { _ = store.movePad(pad.id, by: $0, undoManager: undoManager) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { select(pad.id) }
                    .accessibilityAction(named: "Select \(pad.label)") { select(pad.id) }
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
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
            .overlay {
                if visiblePads.isEmpty {
                    ContentUnavailableView(
                        "No custom pads",
                        systemImage: "waveform",
                        description: Text("Add audio files or drop them here.")
                    )
                    .dropDestination(for: URL.self) { urls, _ in
                        importURLs(urls, at: nil)
                        return !urls.isEmpty
                    }
                }
            }
            .onDeleteCommand { requestRemoval(ids: selection) }

            footer
        }
        .padding(.top, SustainLayout.topChrome)
        .background(palette.canvas)
        .onChange(of: showIncludedPads) { _, show in
            if !show { selection = selection.filter { !isIncludedPad($0) } }
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
            Button("Add Audio\u{2026}", systemImage: "plus") { chooseAudio() }
                .buttonStyle(.borderedProminent)
                .tint(palette.activeSignal)
                .disabled(isImporting)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            HStack(spacing: SustainSpace.md) {
                Toggle("Show Included Pads", isOn: $showIncludedPads)
                    .toggleStyle(.checkbox)
                Text("\(visiblePads.count) of \(store.padTracks.count) pads")
                    .foregroundStyle(palette.textSecondary)
                if isImporting { ProgressView().controlSize(.small) }
                if let notice {
                    Text(notice).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer()
                Button("Remove\u{2026}", role: .destructive) { requestRemoval(ids: selection) }
                    .disabled(selection.isEmpty || selection.contains(where: isIncludedPad))
            }
            Text("Sustain plays files as supplied; it does not normalize loudness or repair loop boundaries.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(SustainSpace.md)
        .background(palette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.divider).frame(height: 1)
        }
    }

    @ViewBuilder
    private func rowMenu(for pad: PadTrack) -> some View {
        let isActive = store.padPlaybackState(for: pad.id) != .off
        Button(isActive ? "Stop Pad" : "Play in Rehearse", systemImage: isActive ? "stop.fill" : "play.fill") {
            store.togglePadPlayback(for: pad.id)
        }
        .disabled(!isActive && !state(for: pad).isAvailable)
        Divider()
        if !pad.isIncluded {
            Button("Reveal in Finder", systemImage: "folder") { reveal(pad) }
            Button("Locate or Replace\u{2026}", systemImage: "arrow.triangle.2.circlepath") { chooseAudio(replacing: pad.id) }
            Divider()
            Button("Move Up", systemImage: "arrow.up") { _ = store.movePad(pad.id, by: -1, undoManager: undoManager) }
                .disabled(!canReorder || store.padTracks.first?.id == pad.id)
            Button("Move Down", systemImage: "arrow.down") { _ = store.movePad(pad.id, by: 1, undoManager: undoManager) }
                .disabled(!canReorder || store.padTracks.last?.id == pad.id)
            Divider()
            Button("Remove Pad\u{2026}", systemImage: "trash", role: .destructive) { requestRemoval(ids: [pad.id]) }
                .disabled(isPadAudible(pad.id))
        } else {
            Text("Included pad · Not editable.")
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

    private func select(_ id: PadTrack.ID) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift),
           let anchor = selectionAnchor,
           let start = visiblePads.firstIndex(where: { $0.id == anchor }),
           let end = visiblePads.firstIndex(where: { $0.id == id }) {
            selection.formUnion(visiblePads[min(start, end)...max(start, end)].map(\.id))
        } else if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            selectionAnchor = id
        } else {
            selection = [id]
            selectionAnchor = id
        }
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

    private func chooseAudio(replacing padID: PadTrack.ID? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = padID == nil
        panel.prompt = padID == nil ? "Add Audio" : "Use Audio"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                if let padID, let url = urls.first {
                    await locate(padID, at: url)
                } else if padID == nil {
                    importURLs(urls, at: nil)
                }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
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
        store.padPlaybackState(for: padID) != .off
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var pad: PadTrack
    var state: PadAssetState
    var isSelected: Bool
    var assignmentCount: Int
    var playbackState: PadPlaybackState
    var canMoveUp: Bool
    var canMoveDown: Bool
    var onPlaybackAction: () -> Void
    var onRename: (String) -> Void
    var onReveal: () -> Void
    var onLocate: () -> Void
    var onRemove: () -> Void
    var onMove: (Int) -> Void

    @State private var draft = ""
    @FocusState private var editing: Bool

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var isActive: Bool { playbackState != .off }

    var body: some View {
        HStack(spacing: SustainSpace.lg) {
            Image(systemName: isActive ? "speaker.wave.2.fill" : (pad.isIncluded ? "shippingbox.fill" : "waveform"))
                .foregroundStyle(isActive ? palette.activeSignal : palette.textSecondary)
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
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(isActive ? playbackState.rawValue : stateLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(isActive || state.isAvailable ? palette.activeSignal : palette.warning)
            Text("\(assignmentCount) assigned")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 76, alignment: .trailing)
            Button(action: onPlaybackAction) {
                Image(systemName: isActive ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!isActive && !state.isAvailable)
            .help(isActive ? "Stop \(pad.label)" : "Play \(pad.label) in Rehearse")
            .accessibilityLabel(isActive ? "Stop \(pad.label)" : "Play \(pad.label) in Rehearse")
            if !pad.isIncluded {
                Menu {
                    Button(isActive ? "Stop Pad" : "Play in Rehearse", action: onPlaybackAction)
                        .disabled(!isActive && !state.isAvailable)
                    Divider()
                    Button("Reveal in Finder", action: onReveal)
                    Button("Locate or Replace\u{2026}", action: onLocate)
                    Button("Move Up") { onMove(-1) }
                        .disabled(!canMoveUp)
                    Button("Move Down") { onMove(1) }
                        .disabled(!canMoveDown)
                    Divider()
                    Button("Remove\u{2026}", role: .destructive, action: onRemove)
                        .disabled(isActive)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Actions for \(pad.label)")
            }
        }
        .padding(.vertical, SustainSpace.sm)
        .padding(.horizontal, SustainSpace.sm)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.activeSignal.opacity(0.12))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.activeSignal.opacity(0.7), lineWidth: 1)
            }
        }
        .onAppear { draft = pad.label }
        .onChange(of: pad.label) { _, value in if !editing { draft = value } }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
