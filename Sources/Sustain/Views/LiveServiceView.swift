import AppKit
import SwiftUI

/// A 1pt divider with a wider invisible hit area that drag-resizes the setlist column
/// and shows the horizontal-resize cursor on hover.
private struct SetlistResizeHandle: View {
    @Binding var width: Double
    var range: ClosedRange<Double>
    @State private var startWidth: Double?

    var body: some View {
        Divider()
            .overlay(
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let base = startWidth ?? width
                                if startWidth == nil { startWidth = width }
                                width = min(range.upperBound, max(range.lowerBound, base + Double(value.translation.width)))
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            )
    }
}

struct LiveServiceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var editingEntryID: SetlistEntry.ID?
    @State private var isConfirmingClearSetlist = false
    @FocusState private var addSongFocused: Bool
    @AppStorage("liveSetlistWidth") private var setlistWidth = 260.0

    private let setlistWidthRange = 200.0...340.0

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        HStack(spacing: 0) {
            setlistPane
                .frame(width: setlistWidth)

            SetlistResizeHandle(width: $setlistWidth, range: setlistWidthRange)

            performanceSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom trailing editor pane, replacing `.inspector`. `.inspector` is a
            // NavigationSplitView-family feature and — like NavigationSplitView itself —
            // flips the window's top safe-area inset when state changes mid-service (the
            // ~90px "jump on play" bug; see docs/13). A plain conditional pane in this HStack
            // has no such behavior and keeps the setlist visible while editing.
            if editingEntryID != nil {
                Divider()
                SongInspectorPane(entryID: editingEntryID) { editingEntryID = nil }
                    .frame(width: 320)
            }
        }
        .background(palette.canvas)
        .onAppear { store.refreshReadiness() }
        .alert("Clear Setlist?", isPresented: $isConfirmingClearSetlist) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(".", modifiers: .command)
            Button("Clear Setlist", role: .destructive) {
                editingEntryID = nil
                if store.clearActiveSetlist(undoManager: undoManager) {
                    NSAccessibility.post(
                        element: NSApp as Any,
                        notification: .announcementRequested,
                        userInfo: [.announcement: "Setlist cleared"]
                    )
                    addSongFocused = true
                }
            }
        } message: {
            Text("Remove all \(store.activeSetlist.entries.count) songs from \(store.activeSetlist.title)? Songs and pads remain in their libraries.")
        }
    }

    // MARK: Setlist pane

    private var setlistPane: some View {
        List(selection: cuedSelection) {
            ForEach(Array(store.activeSetlist.entries.enumerated()), id: \.element.id) { index, entry in
                SetlistRowView(
                    index: index + 1,
                    song: store.song(for: entry),
                    entry: entry,
                    isPlaying: store.runtime.playingEntryID == entry.id,
                    isCued: store.runtime.cuedEntryID == entry.id,
                    onEdit: { editingEntryID = entry.id }
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
        .tint(palette.activeSignal)
        .scrollContentBackground(.hidden)
        .background(palette.performanceSurface.opacity(0.3))
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
        VStack(alignment: .leading, spacing: SustainSpace.xs) {
            Text(store.activeSetlist.title)
                .font(.headline)
                .lineLimit(1)

            Text("\(store.activeSetlist.entries.count) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SustainSpace.md)
        // Header material fills to the window top; the title insets by topChrome so it aligns
        // with the sidebar brand and the NOW/NEXT cards.
        .padding(.top, SustainLayout.topChrome)
        .padding(.bottom, SustainSpace.sm)
        .background(palette.performanceSurface)
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
            .focused($addSongFocused)

            Spacer()

            if !store.activeSetlist.entries.isEmpty {
                Button("Clear Setlist\u{2026}", role: .destructive) {
                    isConfirmingClearSetlist = true
                }
                .buttonStyle(.borderless)
                .disabled(store.isAnyAudioActivityActive)
                .help(store.isAnyAudioActivityActive
                    ? "Stop playback before clearing the setlist."
                    : "Remove every song from this setlist")
            }
        }
        .padding(.horizontal, SustainSpace.md)
        .padding(.top, SustainSpace.sm)
        // Extra bottom room so Add Song isn't jammed against the window edge.
        .padding(.bottom, SustainSpace.lg)
        .background(palette.performanceSurface)
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
        GeometryReader { geometry in
            ScrollView(.vertical) {
                performanceContents(availableHeight: geometry.size.height)
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .overlay(alignment: .bottom) {
                if let beat = store.runtime.countoffBeat {
                    LiveCountoffBadge(beat: beat, total: store.runtime.countoffTotal)
                        .padding(.bottom, SustainSpace.sm)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func performanceContents(availableHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            FutureSignalPerformanceSurface(state: performanceSurfaceState) {
                VStack(alignment: .leading, spacing: 0) {
                    nowNextReadouts

                    Spacer(minLength: 14)

                    channelStatusRow

                    transportCluster
                        .padding(.top, 22)
                }
            }
            .frame(minHeight: max(360, availableHeight - 250))

            levelsRow
                .padding(16)
                .background(palette.performanceSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(palette.surfaceEdge.opacity(0.45), lineWidth: 1)
                }

            messageStrip

        }
        .padding(.horizontal, 18)
        // The pinned countoff overlay needs scroll extent so notices stay reachable beneath it.
        .padding(.bottom, store.runtime.countoffBeat == nil ? 15 : 90)
        .padding(.top, SustainLayout.topChrome + 10)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var nowNextReadouts: some View {
        VStack(alignment: .leading, spacing: 0) {
            nowReadout
            Rectangle()
                .fill(palette.surfaceEdge.opacity(0.5))
                .frame(height: 1)
                .padding(.vertical, 20)
            nextReadout
        }
    }

    private var nowReadout: some View {
        let song = store.song(for: store.playingEntry)
        return FutureSignalSongReadout(
            role: .now,
            title: song?.title,
            key: song?.defaultKey.rawValue,
            bpm: song?.defaultBPM,
            timeSignature: song?.timeSignature.description,
            clickDescription: liveClickDescription,
            stateLabel: store.runtime.clickState == .countoff ? "Count in" :
                (store.runtime.playingEntryID == nil ? nil : "Playing")
        )
    }

    private var nextReadout: some View {
        let song = store.song(for: store.cuedEntry)
        return FutureSignalSongReadout(
            role: .next,
            title: song?.title,
            key: song?.defaultKey.rawValue,
            bpm: song?.defaultBPM,
            timeSignature: song?.timeSignature.description,
            clickDescription: store.song(for: store.cuedEntry).map { "Click: \($0.clickSubdivision.label)" },
            stateLabel: store.cuedEntry == nil ? nil : "Cued"
        )
    }

    private var channelStatusRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                padChannelStatus.frame(minWidth: 200, maxWidth: .infinity)
                Rectangle()
                    .fill(palette.surfaceEdge.opacity(0.4))
                    .frame(width: 1, height: 42)
                clickChannelStatus.frame(minWidth: 200, maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 12) {
                padChannelStatus
                clickChannelStatus
            }
        }
    }

    private var padChannelStatus: some View {
        FutureSignalOpenChannelStatus(kind: .pad, state: padChannelState, detail: padStatusDetail)
            .accessibilityValue("Pad \(padChannelState.label). \(padStatusDetail)")
    }

    private var clickChannelStatus: some View {
        FutureSignalOpenChannelStatus(kind: .click, state: clickChannelState, detail: clickStatusDetail)
            .accessibilityValue("Click \(clickChannelState.label). \(clickStatusDetail)")
    }

    private var levelsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                padFader.frame(minWidth: 180, maxWidth: .infinity)
                Rectangle()
                    .fill(palette.surfaceEdge.opacity(0.45))
                    .frame(width: 1, height: 55)
                clickFader.frame(minWidth: 180, maxWidth: .infinity)
            }
            VStack(spacing: 12) {
                padFader
                clickFader
            }
        }
    }

    private var padFader: some View {
        VStack(alignment: .leading, spacing: 8) {
            FutureSignalChannelLevel(
                kind: .pad,
                value: padVolumeBinding,
                isActive: store.runtime.padState != .off,
                onCommit: { store.commitAudioLevels() }
            )
            if let controlTitle = store.livePadControlTitle {
                Button(controlTitle) { store.toggleLivePad() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var clickFader: some View {
        VStack(alignment: .leading, spacing: 8) {
            FutureSignalChannelLevel(
                kind: .click,
                value: clickVolumeBinding,
                isActive: store.runtime.clickState != .off,
                onCommit: { store.commitAudioLevels() }
            )
            if store.runtime.playbackPhase == .songPlaying {
                Button(store.runtime.clickState == .off ? "Start Click" : "Stop Click") {
                    store.runtime.clickState == .off ? store.startClick() : store.stopClick()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var transportCluster: some View {
        ViewThatFits(in: .horizontal) {
            transportRow(compact: false)
            transportRow(compact: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func transportRow(compact: Bool) -> some View {
        HStack(spacing: SustainSpace.md) {
            Button { store.cuePreviousSong() } label: {
                Image(systemName: "backward.fill").frame(minWidth: 32)
            }
            .buttonStyle(FutureSignalTransportStyle(role: .secondary))
            .frame(height: 52)
            .disabled(store.activeSetlist.entries.isEmpty)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .help("Previous")

            Button { store.startCuedSong() } label: {
                transportLabel(startTitle, systemImage: isTransition ? "arrow.triangle.2.circlepath" : "play.fill", compact: compact, minWidth: 120)
            }
            .buttonStyle(FutureSignalTransportStyle(role: .primary))
            .frame(height: 52)
            .disabled(store.cuedEntry == nil || store.isCuedSongPlaying || store.runtime.playbackPhase == .songStarting)
            .keyboardShortcut(.return, modifiers: [])
            .help(startTitle)

            Button { store.cueNextSong() } label: {
                Image(systemName: "forward.fill").frame(minWidth: 32)
            }
            .buttonStyle(FutureSignalTransportStyle(role: .secondary))
            .frame(height: 52)
            .disabled(store.activeSetlist.entries.isEmpty)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .help("Next")

            Button(role: .destructive) { store.stop() } label: {
                transportLabel("Stop", systemImage: "stop.fill", compact: compact, minWidth: 72)
            }
            .buttonStyle(FutureSignalTransportStyle(role: .stop))
            .frame(height: 52)
            .disabled(!store.isAnyAudioActivityActive)
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop")
        }
    }

    @ViewBuilder
    private func transportLabel(_ title: String, systemImage: String, compact: Bool, minWidth: CGFloat) -> some View {
        if compact {
            Image(systemName: systemImage).frame(minWidth: 36)
        } else {
            Label(title, systemImage: systemImage).frame(minWidth: minWidth)
        }
    }

    /// Blocking readiness messages to surface as a prominent banner — only when a genuine
    /// fault exists. Excludes the neutral `.notRun` state (also `canStartPlayback == false`)
    /// and drops warning lines (those stay on the routing badge).
    private var blockingReadinessMessage: String? {
        let check = store.systemCheck
        guard !check.canStartPlayback, check != .notRun else { return nil }
        let blocking = check.messages.filter { !$0.hasPrefix("Warning:") }
        return blocking.isEmpty ? nil : blocking.joined(separator: " ")
    }

    private var messageStrip: some View {
        VStack(spacing: SustainSpace.sm) {
            if let prerollMismatchMessage {
                SustainInlineNotice(message: prerollMismatchMessage, kind: .warning)
            }
            if let blockingReadinessMessage {
                // A real blocker (unavailable output, missing pad, invalid BPM) — red.
                SustainInlineNotice(message: blockingReadinessMessage, kind: .error)
            } else {
                // Advisory warnings that don't block playback (e.g. pad + click sharing one
                // output) — orange, so the operator still notices them before service.
                ForEach(store.systemCheck.warnings, id: \.self) { warning in
                    SustainInlineNotice(message: warning, kind: .warning)
                }
            }

            if let pendingLiveClickMessage {
                Text(pendingLiveClickMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: SustainSpace.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(store.runtime.lastMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: SustainSpace.md)
                LiveRoutingBadge(snapshot: store.routingSnapshot)
            }
        }
    }

    // MARK: Derived

    private var performanceSurfaceState: FutureSignalSurfaceState {
        if blockingReadinessMessage != nil { return .blocked }
        if store.runtime.clickState == .countoff { return .countoff }
        if store.runtime.playbackPhase == .songStarting {
            return store.runtime.playingEntryID == nil ? .preparing : .transition
        }
        if store.runtime.playingEntryID != nil { return .playing }
        if store.runtime.padState != .off || store.runtime.clickState != .off { return .preparing }
        return store.runtime.cuedEntryID == nil ? .idle : .cued
    }

    private var padChannelState: FutureSignalChannelState {
        if store.runtime.padState == .off && !store.routingSnapshot.isPadRouteReady { return .unavailable }
        switch store.runtime.padState {
        case .off: return .off
        case .preparing: return .preparing
        case .fadingIn: return .fadingIn
        case .playing: return .playing
        case .fadingOut: return .fadingOut
        }
    }

    private var clickChannelState: FutureSignalChannelState {
        if store.runtime.clickState == .off && !store.routingSnapshot.isClickRouteReady { return .unavailable }
        switch store.runtime.clickState {
        case .off: return .off
        case .preparing: return .preparing
        case .countoff: return .countoff
        case .playing: return .playing
        }
    }

    private var padStatusDetail: String {
        let route = store.routingSnapshot.padRouteName
        if store.runtime.padState == .off && !store.routingSnapshot.isPadRouteReady {
            return store.routingSnapshot.padOutputID == nil
                ? "No pad output selected"
                : "Pad route unavailable · \(route)"
        }
        if store.runtime.padState == .preparing {
            let targetPad = store.song(for: store.cuedEntry).flatMap { store.padTrack(for: $0) }
            let target = targetPad?.label ?? "Pad"
            if let oldID = store.runtime.audiblePadTrackID,
               let oldPad = store.padTracks.first(where: { $0.id == oldID }),
               oldID != targetPad?.id {
                return "Preparing \(target) · \(oldPad.label) still sounding · \(route)"
            }
            return "Preparing \(target) · \(route)"
        }
        if let padID = store.runtime.audiblePadTrackID {
            let pad = store.padTracks.first(where: { $0.id == padID })
            let owner = store.runtime.audiblePadEntryID.flatMap { store.entry(id: $0) }
            let ownerTitle = store.song(for: owner)?.title
            let identity = [pad?.label, ownerTitle].compactMap { $0 }.joined(separator: " · ")
            return "\(identity) · \(route)"
        }
        return "\(route) · No pad sounding"
    }

    private var clickStatusDetail: String {
        if store.runtime.clickState == .off && !store.routingSnapshot.isClickRouteReady {
            return store.routingSnapshot.clickOutputID == nil
                ? "No click output selected"
                : "Click route unavailable · \(store.routingSnapshot.clickRouteName)"
        }
        let route = store.routingSnapshot.clickRouteName
        let song = store.song(for: store.playingEntry) ?? store.song(for: store.cuedEntry)
        let audible = store.audibleClickSubdivision
        if store.runtime.clickState == .off {
            if let song { return "Next start: \(song.clickSubdivision.label) · \(route)" }
            return "No song cued · \(route)"
        }
        if let beat = store.runtime.countoffBeat, let total = store.runtime.countoffTotal {
            return "Beat \(beat) of \(total) · \(route)"
        }
        if store.runtime.clickState == .preparing {
            let target = store.song(for: store.cuedEntry)?.clickSubdivision.label ?? "Click"
            if let audible {
                return "Preparing \(target) · \(audible.label) still audible · \(route)"
            }
            return "Preparing \(target) · \(route)"
        }
        let pattern = audible ?? song?.clickSubdivision ?? .beat
        if let playingSong = store.song(for: store.playingEntry),
           let pending = store.pendingClickSubdivision(for: playingSong.id) {
            return "\(pattern.label) audible · \(pending.label) at next measure · \(route)"
        }
        return "\(pattern.label) · \(route)"
    }

    private var pendingLiveClickMessage: String? {
        guard let song = store.song(for: store.playingEntry),
              let pending = store.pendingClickSubdivision(for: song.id),
              store.runtime.clickState != .off else { return nil }
        let audible = store.audibleClickSubdivision ?? song.clickSubdivision
        return "Current: \(audible.label) · Switching to \(pending.label) next measure"
    }

    private var isTransition: Bool {
        store.runtime.playingEntryID != nil && store.runtime.cuedEntryID != store.runtime.playingEntryID
    }

    private var liveClickDescription: String? {
        guard let song = store.song(for: store.playingEntry) else { return nil }
        if store.runtime.clickState == .off {
            return "Click off · next start: \(song.clickSubdivision.label)"
        }
        if store.runtime.clickState == .preparing {
            let target = store.song(for: store.cuedEntry)?.clickSubdivision.label ?? song.clickSubdivision.label
            return "Preparing click for cue: \(target)"
        }
        let audible = (store.audibleClickSubdivision ?? song.clickSubdivision).label
        if let pending = store.pendingClickSubdivision(for: song.id) {
            return "Click: \(audible) · \(pending.label) at next measure"
        }
        return "Click: \(audible)"
    }

    private var startTitle: String {
        isTransition ? "Transition" : "Start"
    }

    private var prerollMismatchMessage: String? {
        guard store.runtime.playingEntryID == nil,
              let audiblePadID = store.runtime.audiblePadTrackID,
              let audibleOwnerID = store.runtime.audiblePadEntryID,
              audibleOwnerID != store.runtime.cuedEntryID else { return nil }
        let padLabel = store.padTracks.first(where: { $0.id == audiblePadID })?.label ?? "Pad"
        let ownerTitle = store.song(for: store.entry(id: audibleOwnerID))?.title ?? "previous cue"
        let cueTitle = store.song(for: store.cuedEntry)?.title ?? "nothing"
        return "\(padLabel) is still sounding for \(ownerTitle); \(cueTitle) is cued. Start replaces it safely."
    }

    private var padVolumeBinding: Binding<Double> {
        Binding { store.padVolume } set: { store.setPadVolumeLive($0) }
    }

    private var clickVolumeBinding: Binding<Double> {
        Binding { store.clickVolume } set: { store.setClickVolumeLive($0) }
    }
}

// MARK: - Routing badge

/// Compact, pinned count-in for the scrolling performance pane. The full channel
/// status still carries the same beat text; this keeps the numeral in view without
/// covering warnings or the transport at minimum window size.
private struct LiveCountoffBadge: View {
    var beat: Int
    var total: Int?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            Text("COUNT IN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
            Text("\(beat)")
                .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.activeSignal)
            Text("of \(total ?? 0)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, SustainSpace.md)
        .padding(.vertical, SustainSpace.xs)
        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(palette.activeSignal.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Count in, beat \(beat) of \(total ?? 0)")
    }
}

/// Glanceable audio-routing status for the performance surface: which output the
/// pad/click are on, colored by health. Warns only when a selected device or
/// channel is unavailable — a shared single output is a normal, calm state.
private struct LiveRoutingBadge: View {
    var snapshot: AudioRoutingSnapshot
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var hasProblem: Bool { snapshot.hasUnavailableSelection }

    var body: some View {
        HStack(spacing: SustainSpace.xs) {
            Image(systemName: hasProblem ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill")
                .foregroundStyle(hasProblem ? palette.warning : palette.activeSignal)
            Text(snapshot.summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(hasProblem ? snapshot.missingSelectionMessages.joined(separator: " ") : "Audio routing: \(snapshot.summary)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio routing")
        .accessibilityValue(hasProblem ? snapshot.missingSelectionMessages.joined(separator: " ") : snapshot.summary)
    }
}

// MARK: - Setlist row

private struct SetlistRowView: View {
    var index: Int
    var song: Song?
    var entry: SetlistEntry
    var isPlaying: Bool
    var isCued: Bool
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            FutureSignalSetlistRowContent(
                index: index,
                title: song?.title ?? "Missing song",
                detail: song.map { "\($0.defaultKey.rawValue) · \($0.defaultBPM) BPM · \($0.timeSignature.description)" },
                isPlaying: isPlaying,
                isCued: isCued,
                isSelected: isCued,
                isMissing: song == nil
            )

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Adjust \(song?.title ?? "song")")
            .accessibilityLabel("Adjust \(song?.title ?? "song")")
            .padding(.trailing, 4)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
    }
}

// MARK: - Inspector

private struct SongInspectorPane: View {
    @Environment(AppStore.self) private var store
    var entryID: SetlistEntry.ID?
    var onClose: () -> Void

    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Song")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.borderless)
                .help("Close editor")
            }
            .padding(.horizontal, SustainSpace.md)
            .padding(.top, SustainSpace.md)
            .padding(.bottom, SustainSpace.sm)

            Divider()

            editorBody
        }
        .background(.bar)
    }

    @ViewBuilder
    private var editorBody: some View {
        Group {
            if let entryID, let entry = store.entry(id: entryID), let song = store.song(for: entry) {
                Form {
                    Section("Song Library") {
                        TextField("Title", text: $titleDraft)
                            .focused($titleFocused)
                            .onSubmit { commitTitle(song) }
                            .onChange(of: titleFocused) { _, isFocused in
                                if !isFocused { commitTitle(song) }
                            }
                        Picker("Key", selection: keyBinding(song)) {
                            ForEach(MusicalKey.allCases) { key in
                                Text(key.rawValue).tag(key)
                            }
                        }
                        TempoControl(value: bpmBinding(song))
                        Picker("Time", selection: timeSignatureBinding(song)) {
                            ForEach(TimeSignature.common, id: \.self) { signature in
                                Text(signature.description).tag(signature)
                            }
                        }
                        Picker("Subdivision", selection: subdivisionBinding(song)) {
                            ForEach(ClickSubdivision.allCases) { subdivision in
                                Text(subdivision.label)
                                    .accessibilityLabel(subdivision.accessibilityLabel)
                                    .tag(subdivision)
                            }
                        }
                        .disabled(store.runtime.playingEntryID == entryID && store.runtime.clickState == .countoff)
                        .help(store.runtime.playingEntryID == entryID && store.runtime.clickState == .countoff
                            ? "Subdivision can change after countoff"
                            : "Choose clicks per BPM beat")
                        Text("Adds evenly spaced clicks inside each BPM beat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LabeledContent("Pads", value: "Included")
                        Text("Changes update this song everywhere it appears.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                .onAppear { titleDraft = song.title }
                .onChange(of: entryID) { _, _ in titleDraft = song.title }
                .onChange(of: song.title) { _, newTitle in
                    if !titleFocused { titleDraft = newTitle }
                }
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
        guard let current = currentSong(song.id) else { return }
        store.updateSong(
            song.id,
            title: titleDraft,
            defaultKey: current.defaultKey,
            defaultBPM: current.defaultBPM,
            timeSignature: current.timeSignature,
            padPackID: PadPack.bundled.id
        )
        titleDraft = currentSong(song.id)?.title ?? current.title
    }

    private func timeSignatureBinding(_ song: Song) -> Binding<TimeSignature> {
        Binding {
            currentSong(song.id)?.timeSignature ?? song.timeSignature
        } set: { signature in
            guard let current = currentSong(song.id) else { return }
            store.updateSong(
                song.id,
                title: current.title,
                defaultKey: current.defaultKey,
                defaultBPM: current.defaultBPM,
                timeSignature: signature,
                padPackID: PadPack.bundled.id
            )
        }
    }

    private func subdivisionBinding(_ song: Song) -> Binding<ClickSubdivision> {
        Binding {
            store.pendingClickSubdivision(for: song.id) ?? currentSong(song.id)?.clickSubdivision ?? song.clickSubdivision
        } set: { subdivision in
            store.setSongClickSubdivision(song.id, subdivision: subdivision)
        }
    }

    private func keyBinding(_ song: Song) -> Binding<MusicalKey> {
        Binding {
            currentSong(song.id)?.defaultKey ?? song.defaultKey
        } set: { key in
            guard let current = currentSong(song.id) else { return }
            store.updateSong(
                song.id,
                title: current.title,
                defaultKey: key,
                defaultBPM: current.defaultBPM,
                timeSignature: current.timeSignature,
                padPackID: PadPack.bundled.id
            )
        }
    }

    private func bpmBinding(_ song: Song) -> Binding<Int> {
        Binding {
            currentSong(song.id)?.defaultBPM ?? song.defaultBPM
        } set: { bpm in
            guard let current = currentSong(song.id) else { return }
            store.updateSong(
                song.id,
                title: current.title,
                defaultKey: current.defaultKey,
                defaultBPM: bpm,
                timeSignature: current.timeSignature,
                padPackID: PadPack.bundled.id
            )
        }
    }

    private func currentSong(_ songID: Song.ID) -> Song? {
        store.songs.first { $0.id == songID }
    }
}

#Preview("Live detail – countoff") {
    let store = AppStore.preview()
    store.startCuedSong()
    store.runtime.countoffBeat = 2
    store.runtime.countoffTotal = 6
    return LiveServiceView()
        .environment(store)
        .frame(width: 940, height: 660)
}

#Preview("Song editor pane") {
    let store = AppStore.preview()
    let entryID = store.activeSetlist.entries.first?.id
    return SongInspectorPane(entryID: entryID) {}
        .environment(store)
        .frame(width: 320, height: 660)
}
