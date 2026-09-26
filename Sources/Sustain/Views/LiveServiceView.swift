import AppKit
import SwiftUI

/// A 1pt divider with a wider invisible hit area that drag-resizes the setlist column
/// and shows the horizontal-resize cursor on hover.
private struct SetlistResizeHandle: View {
    @Binding var width: Double
    var range: ClosedRange<Double>
    var onCommit: (Double) -> Void
    @State private var startWidth: Double?
    @FocusState private var isFocused: Bool

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
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let base = startWidth ?? width
                                if startWidth == nil { startWidth = width }
                                width = min(range.upperBound, max(range.lowerBound, base + Double(value.translation.width)))
                            }
                            .onEnded { _ in
                                startWidth = nil
                                onCommit(width)
                            }
                    )
            )
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onMoveCommand { direction in
                switch direction {
                case .left: adjustWidth(by: -20)
                case .right: adjustWidth(by: 20)
                default: break
                }
            }
            .accessibilityLabel("Setlist width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityHint("Use left and right arrows to resize the setlist")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjustWidth(by: 20)
                case .decrement: adjustWidth(by: -20)
                @unknown default: break
                }
            }
    }

    private func adjustWidth(by amount: Double) {
        width = min(range.upperBound, max(range.lowerBound, width + amount))
        onCommit(width)
    }
}

/// Gives both channel cards the taller card's height without imposing a fixed height.
private struct EqualHeightChannelCards: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 460
        let cardWidth = max(0, (width - spacing) / 2)
        let cardProposal = ProposedViewSize(width: cardWidth, height: nil)
        let height = subviews.map { $0.sizeThatFits(cardProposal).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let cardWidth = max(0, (bounds.width - spacing) / 2)
        let cardProposal = ProposedViewSize(width: cardWidth, height: bounds.height)
        subviews[0].place(at: bounds.origin, proposal: cardProposal)
        subviews[1].place(
            at: CGPoint(x: bounds.minX + cardWidth + spacing, y: bounds.minY),
            proposal: cardProposal
        )
    }
}

struct LiveServiceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var editingEntryID: SetlistEntry.ID?
    @State private var inspectorDirty = false
    @State private var pendingEditingEntryID: SetlistEntry.ID?
    @State private var pendingNewLiveSong = false
    @State private var isConfirmingEditorSwitch = false
    @State private var isCreatingLiveSong = false
    @State private var isSetlistExpanded = false
    @State private var isConfirmingClearSetlist = false
    @State private var pendingRemovalEntryID: SetlistEntry.ID?
    @FocusState private var addSongFocused: Bool
    @AppStorage("liveSetlistWidth") private var savedSetlistWidth = 260.0
    @State private var setlistWidth = 260.0

    private let setlistWidthRange = 200.0...340.0

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width < (editingEntryID == nil ? 680 : setlistWidth + 700) {
                compactLayout(height: geometry.size.height)
                    .sheet(isPresented: Binding(
                        get: { editingEntryID != nil },
                        set: { if !$0 && !inspectorDirty { editingEntryID = nil } }
                    )) {
                        SongInspectorPane(entryID: editingEntryID, compact: true, isDirty: $inspectorDirty) {
                            editingEntryID = nil
                            inspectorDirty = false
                        }
                            .frame(minWidth: 400, minHeight: 500)
                            .interactiveDismissDisabled(inspectorDirty)
                    }
            } else {
                HStack(spacing: 0) {
                    setlistPane(compact: false)
                        .frame(width: setlistWidth)

                    SetlistResizeHandle(width: $setlistWidth, range: setlistWidthRange) { savedSetlistWidth = $0 }

                    performanceSurface(compactTop: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // A plain conditional pane avoids the safe-area jump caused by `.inspector`.
                    if editingEntryID != nil {
                        Divider()
                        SongInspectorPane(entryID: editingEntryID, isDirty: $inspectorDirty) {
                            editingEntryID = nil
                            inspectorDirty = false
                        }
                            .frame(width: 320)
                    }
                }
            }
        }
        .background(palette.canvas)
        .onAppear {
            setlistWidth = min(setlistWidthRange.upperBound, max(setlistWidthRange.lowerBound, savedSetlistWidth))
            store.refreshReadiness()
        }
        .onChange(of: inspectorDirty) { _, dirty in
            store.dirtySongEditorScreen = dirty ? .live : nil
        }
        .alert("Clear Setlist?", isPresented: $isConfirmingClearSetlist) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(".", modifiers: .command)
            Button("Clear Setlist", role: .destructive) {
                editingEntryID = nil
                inspectorDirty = false
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
            Text("Remove all \(store.activeSetlist.entries.count) songs from \(store.activeSetlist.title)? Songs and pads remain in their libraries.\(inspectorDirty ? " Unsaved changes in the open editor will be discarded." : "")")
        }
        .confirmationDialog(
            "Remove song and discard unsaved changes?",
            isPresented: Binding(
                get: { pendingRemovalEntryID != nil },
                set: { if !$0 { pendingRemovalEntryID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove and Discard", role: .destructive) {
                if let pendingRemovalEntryID { removeEntry(pendingRemovalEntryID) }
                pendingRemovalEntryID = nil
            }
            Button("Keep Editing", role: .cancel) { pendingRemovalEntryID = nil }
        } message: {
            Text("The open song editor has unsaved changes.")
        }
        .confirmationDialog(
            "Discard unsaved song changes?",
            isPresented: $isConfirmingEditorSwitch,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                if pendingNewLiveSong {
                    editingEntryID = nil
                    isCreatingLiveSong = true
                } else {
                    editingEntryID = pendingEditingEntryID
                }
                pendingEditingEntryID = nil
                pendingNewLiveSong = false
                inspectorDirty = false
            }
            Button("Keep Editing", role: .cancel) {
                pendingEditingEntryID = nil
                pendingNewLiveSong = false
            }
        }
        .sheet(isPresented: $isCreatingLiveSong) {
            NewLiveSongSheet { entryID in
                isCreatingLiveSong = false
                editingEntryID = entryID
                inspectorDirty = false
            } onCancel: {
                isCreatingLiveSong = false
            }
        }
    }

    // MARK: Setlist pane

    private func compactLayout(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: SustainSpace.md) {
                Button {
                    isSetlistExpanded.toggle()
                } label: {
                    Label("Setlist", systemImage: "list.bullet")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isSetlistExpanded ? "Hide setlist" : "Show setlist")

                Spacer(minLength: 0)

                Text(store.song(for: store.cuedEntry)?.title ?? "Nothing cued")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, SustainSpace.md)
            .padding(.top, SustainLayout.topChrome + SustainSpace.sm)
            .padding(.bottom, SustainSpace.sm)
            .background(palette.performanceSurface)

            if isSetlistExpanded {
                setlistPane(compact: true)
                    .frame(height: min(300, height * 0.42))
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            performanceSurface(compactTop: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func setlistPane(compact: Bool) -> some View {
        List {
            ForEach(Array(store.activeSetlist.entries.enumerated()), id: \.element.id) { index, entry in
                SetlistRowView(
                    index: index + 1,
                    song: store.song(for: entry),
                    padDescription: store.song(for: entry).map(padDescription) ?? "Missing Pad",
                    entry: entry,
                    isPlaying: store.runtime.playingEntryID == entry.id,
                    isCued: store.runtime.cuedEntryID == entry.id,
                    onCue: { store.cue(entryID: entry.id) },
                    onEdit: { openEditor(for: entry.id) }
                )
                .contextMenu {
                    Button("Edit\u{2026}") { openEditor(for: entry.id) }
                    Button("Remove", role: .destructive) { requestRemoveEntry(entry.id) }
                        .disabled(store.runtime.playingEntryID == entry.id)
                }
            }
            .onMove { store.moveSetlistEntry(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.performanceSurface.opacity(0.3))
        .safeAreaInset(edge: .top, spacing: 0) { setlistHeader(compact: compact) }
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

    private func setlistHeader(compact: Bool) -> some View {
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
        .padding(.top, compact ? SustainSpace.sm : SustainLayout.topChrome)
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
                    if inspectorDirty {
                        pendingNewLiveSong = true
                        isConfirmingEditorSwitch = true
                    } else {
                        isCreatingLiveSong = true
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

    // MARK: Performance surface

    private func openEditor(for entryID: SetlistEntry.ID) {
        guard editingEntryID != entryID else { return }
        if inspectorDirty {
            pendingEditingEntryID = entryID
            isConfirmingEditorSwitch = true
        } else {
            editingEntryID = entryID
        }
    }

    private func requestRemoveEntry(_ entryID: SetlistEntry.ID) {
        if editingEntryID == entryID && inspectorDirty {
            pendingRemovalEntryID = entryID
        } else {
            removeEntry(entryID)
        }
    }

    private func removeEntry(_ entryID: SetlistEntry.ID) {
        if editingEntryID == entryID {
            editingEntryID = nil
            inspectorDirty = false
        }
        store.removeSetlistEntry(entryID)
    }

    private func performanceSurface(compactTop: Bool) -> some View {
        GeometryReader { geometry in
            let isNarrow = geometry.size.width < 520
            ScrollView(.vertical) {
                performanceContents(availableWidth: geometry.size.width, isNarrow: isNarrow, compactTop: compactTop)
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func performanceContents(availableWidth: CGFloat, isNarrow: Bool, compactTop: Bool) -> some View {
        VStack(spacing: 12) {
            if isNarrow { messageStrip }

            FutureSignalPerformanceSurface(state: performanceSurfaceState) {
                VStack(alignment: .leading, spacing: 20) {
                    nowNextReadouts
                    transportCluster
                        .overlay {
                            if let beat = store.runtime.countoffBeat {
                                FutureSignalCountoffBadge(
                                    beat: beat,
                                    total: store.runtime.countoffTotal,
                                    bars: store.activeLiveCountoffPolicy?.bars
                                        ?? store.song(for: store.playingEntry)?.countoffPolicy.bars
                                        ?? 1
                                )
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            channelCardsRow(availableWidth: availableWidth)

            if !isNarrow { messageStrip }

        }
        .padding(.horizontal, 18)
        .padding(.bottom, 15)
        .padding(.top, compactTop ? 12 : SustainLayout.topChrome + 10)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var nowNextReadouts: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.playingEntry != nil || store.cuedEntry == nil {
                nowReadout
            }
            if store.playingEntry != nil && store.cuedEntry != nil ||
                store.playingEntry == nil && store.cuedEntry == nil {
                Rectangle()
                    .fill(palette.surfaceEdge.opacity(0.5))
                    .frame(height: 1)
                    .padding(.vertical, 20)
            }
            if store.cuedEntry != nil || store.playingEntry == nil {
                nextReadout
            }
        }
    }

    private var nowReadout: some View {
        let song = store.song(for: store.playingEntry)
        return FutureSignalSongReadout(
            role: .now,
            title: song?.title,
            padDescription: song.map(padDescription),
            bpm: store.effectiveBPM(for: store.playingEntry, song: song),
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
            padDescription: song.map(padDescription),
            bpm: store.effectiveBPM(for: store.cuedEntry, song: song),
            timeSignature: song?.timeSignature.description,
            clickDescription: song.map { "Click: \($0.clickSubdivision.label) · \(pulseLabel(for: $0))\($0.countoffPolicy.after == .countoffOnly ? " · stops after countoff" : "")" },
            stateLabel: store.cuedEntry == nil ? nil : "Cued"
        )
    }

    private func padDescription(_ song: Song) -> String {
        guard let padID = song.padTrackID else { return "No Pad" }
        guard let pad = store.padTracks.first(where: { $0.id == padID }) else { return "Missing Pad" }
        return "Pad: \(pad.label)"
    }

    private func pulseLabel(for song: Song) -> String {
        ClickPulseGrid(timeSignature: song.timeSignature,
                       pulseInterpretation: song.pulseInterpretation,
                       bpm: max(40, song.defaultBPM), sampleRate: 44_100).pulseUnitLabel
    }

    @ViewBuilder
    private func channelCardsRow(availableWidth: CGFloat) -> some View {
        if availableWidth >= 460 {
            EqualHeightChannelCards(spacing: 12) {
                padCard
                clickCard
            }
        } else {
            VStack(spacing: 12) {
                padCard
                    .fixedSize(horizontal: false, vertical: true)
                clickCard
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var padCard: some View {
        channelCard {
            padChannelStatus
            padFader
        }
    }

    private var clickCard: some View {
        channelCard {
            clickChannelStatus
            clickFader
        }
    }

    private func channelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18, content: content)
            .accessibilityElement(children: .contain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(palette.performanceSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(palette.surfaceEdge.opacity(0.55), lineWidth: 1)
            }
    }

    private var padChannelStatus: some View {
        FutureSignalOpenChannelStatus(kind: .pad, state: padChannelState, detail: padOutputDetail, showsStateLabel: false, detailLineLimit: 1)
            .accessibilityLabel("Pad \(padChannelState.label)")
            .accessibilityValue("Pad output: \(padOutputDetail)")
    }

    private var clickChannelStatus: some View {
        FutureSignalOpenChannelStatus(kind: .click, state: clickChannelState, detail: clickOutputDetail, showsStateLabel: false, detailLineLimit: 1)
            .accessibilityLabel("Click \(clickChannelState.label)")
            .accessibilityValue("Click output: \(clickOutputDetail)")
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
            .keyboardShortcut(editingEntryID == nil && !isCreatingLiveSong
                              ? KeyboardShortcut(.leftArrow, modifiers: []) : nil)
            .help("Previous")
            .accessibilityLabel("Previous song")

            Button { store.startCuedSong() } label: {
                transportLabel(startTitle, systemImage: isTransition ? "arrow.triangle.2.circlepath" : "play.fill", compact: compact, minWidth: 120)
            }
            .buttonStyle(FutureSignalTransportStyle(role: .primary))
            .frame(height: 52)
            .disabled(store.cuedEntry == nil || store.isCuedSongPlaying || store.runtime.playbackPhase == .songStarting)
            .keyboardShortcut(editingEntryID == nil && !isCreatingLiveSong
                              ? KeyboardShortcut(.return, modifiers: []) : nil)
            .help(startTitle)
            .accessibilityLabel(startTitle)

            Button { store.cueNextSong() } label: {
                Image(systemName: "forward.fill").frame(minWidth: 32)
            }
            .buttonStyle(FutureSignalTransportStyle(role: .secondary))
            .frame(height: 52)
            .disabled(store.activeSetlist.entries.isEmpty)
            .keyboardShortcut(editingEntryID == nil && !isCreatingLiveSong
                              ? KeyboardShortcut(.rightArrow, modifiers: []) : nil)
            .help("Next")
            .accessibilityLabel("Next song")

            Button(role: .destructive) { store.stop() } label: {
                transportLabel("Stop", systemImage: "stop.fill", compact: compact, minWidth: 72)
            }
            .buttonStyle(FutureSignalTransportStyle(role: .stop))
            .frame(height: 52)
            .disabled(!store.isAnyAudioActivityActive)
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop")
            .accessibilityLabel("Stop playback")
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

            HStack(spacing: SustainSpace.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(store.runtime.lastMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(store.runtime.lastMessage)
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

    private var padOutputDetail: String {
        store.routingSnapshot.padOutputID == nil
            ? "No pad output selected"
            : store.routingSnapshot.padRouteName
    }

    private var clickOutputDetail: String {
        store.routingSnapshot.clickOutputID == nil
            ? "No click output selected"
            : store.routingSnapshot.clickRouteName
    }

    private var isTransition: Bool {
        store.runtime.playingEntryID != nil && store.runtime.cuedEntryID != store.runtime.playingEntryID
    }

    private var liveClickDescription: String? {
        guard let song = store.song(for: store.playingEntry) else { return nil }
        let activePolicy = store.activeLiveCountoffPolicy ?? song.countoffPolicy
        let nextPolicyDetail = song.countoffPolicy.after == .countoffOnly ? " · stops after countoff" : ""
        let activePolicyDetail = activePolicy.after == .countoffOnly ? " · stops after countoff" : ""
        let changedPolicyDetail = activePolicy != song.countoffPolicy ? " · new countoff setting at next start" : ""
        let pulseDetail = " · \(pulseLabel(for: song))"
        if store.runtime.clickState == .off {
            return "Click off · next start: \(song.clickSubdivision.label)\(pulseDetail)\(nextPolicyDetail)"
        }
        if store.runtime.clickState == .preparing {
            let target = store.song(for: store.cuedEntry)?.clickSubdivision.label ?? song.clickSubdivision.label
            return "Preparing click for cue: \(target)\(pulseDetail)\(nextPolicyDetail)"
        }
        let audible = (store.audibleClickSubdivision ?? song.clickSubdivision).label
        if let pending = store.pendingClickSubdivision(for: song.id) {
            let pendingDetail = pending == store.audibleClickSubdivision &&
                song.clickAccentPattern != store.audibleClickAccentPattern
                ? "beat accents at next measure" : "\(pending.label) at next measure"
            return "Click: \(audible)\(pulseDetail) · \(pendingDetail)\(activePolicyDetail)\(changedPolicyDetail)"
        }
        return "Click: \(audible)\(pulseDetail)\(activePolicyDetail)\(changedPolicyDetail)"
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

/// Count-in badge, displayed over the Live transport without changing its layout.
struct FutureSignalCountoffBadge: View {
    var beat: Int
    var total: Int?
    var bars: Int = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var pulsesPerBar: Int { max(1, (total ?? 1) / max(1, bars)) }
    private var barNumber: Int { min(max(1, bars), (max(1, beat) - 1) / pulsesPerBar + 1) }
    private var beatInBar: Int { (max(1, beat) - 1) % pulsesPerBar + 1 }
    private var accessibilityText: String {
        bars > 1
            ? "Count in, bar \(barNumber) of \(bars), beat \(beatInBar) of \(pulsesPerBar)"
            : "Count in, beat \(beat) of \(total ?? 0)"
    }

    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            Text("COUNT IN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
            if bars > 1 {
                Text("BAR \(barNumber)/\(bars)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            Text("\(bars > 1 ? beatInBar : beat)")
                .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.activeSignal)
            Text("of \(bars > 1 ? pulsesPerBar : total ?? 0)")
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
        .accessibilityLabel(accessibilityText)
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
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var index: Int
    var song: Song?
    var padDescription: String
    var entry: SetlistEntry
    var isPlaying: Bool
    var isCued: Bool
    var onCue: () -> Void
    var onEdit: () -> Void

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var pulseLabel: String? {
        guard let song else { return nil }
        return ClickPulseGrid(timeSignature: song.timeSignature,
                              pulseInterpretation: song.pulseInterpretation,
                              bpm: max(40, song.defaultBPM), sampleRate: 44_100).pulseUnitLabel
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onCue) {
                FutureSignalSetlistRowContent(
                    index: index,
                    title: song?.title ?? "Missing song",
                    detail: song.map { "\(padDescription) · \(store.effectiveBPM(for: entry, song: $0) ?? $0.defaultBPM) \(pulseLabel ?? "BPM")\(store.liveTempoOverrides[entry.id] == nil ? "" : " session") · \($0.timeSignature.description)\($0.countoffPolicy.after == .countoffOnly ? " · Countoff only" : "")" },
                    isPlaying: isPlaying,
                    isCued: isCued,
                    isSelected: isCued,
                    isMissing: song == nil,
                    showsContainer: false
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Cue this song")

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Adjust \(song?.title ?? "song")")
            .accessibilityLabel("Adjust \(song?.title ?? "song")")
            .frame(width: 30, height: 30)
            .padding(.trailing, SustainSpace.xs)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPlaying ? palette.activeSignal.opacity(0.08) :
                        isCued ? palette.surfaceEdge.opacity(0.16) : .clear)
        }
        .overlay {
            if isCued {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.cuedEdge.opacity(contrast == .increased ? 1 : 0.72), lineWidth: 1)
            }
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Inspector

private struct SongInspectorPane: View {
    @Environment(AppStore.self) private var store
    var entryID: SetlistEntry.ID?
    var compact = false
    @Binding var isDirty: Bool
    var onClose: () -> Void

    @State private var draft = SongDraft.newSong()
    @State private var baseline: SongDraft?
    @State private var isConfirmingDiscard = false

    var body: some View {
        Group {
            if let entryID, baseline != nil {
                SongEditorView(
                    draft: $draft,
                    context: .live(entryID),
                    onSaved: { _ in
                        baseline = draft
                        isDirty = false
                        onClose()
                    },
                    onClose: requestClose,
                    onDeleted: onClose
                )
                .id(entryID)
            } else {
                ContentUnavailableView(
                    "No song selected",
                    systemImage: "slider.horizontal.3",
                    description: Text("Choose a song to edit its pad and click settings.")
                )
            }
        }
        .onAppear { loadEntry() }
        .onChange(of: entryID) { _, _ in loadEntry() }
        .onChange(of: draft) { _, _ in
            isDirty = baseline.map { draft != $0 } ?? false
        }
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive, action: onClose)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Changes to this song have not been saved.")
        }
    }

    private func loadEntry() {
        guard let entryID, let entry = store.entry(id: entryID),
              let song = store.song(for: entry) else {
            baseline = nil
            return
        }
        draft = SongDraft(song: song)
        baseline = draft
        isDirty = false
    }

    private func requestClose() {
        if let baseline, draft != baseline {
            isConfirmingDiscard = true
        } else {
            onClose()
        }
    }
}

private struct NewLiveSongSheet: View {
    @Environment(AppStore.self) private var store
    var onCreated: (SetlistEntry.ID) -> Void
    var onCancel: () -> Void

    @State private var draft = SongDraft.newSong()
    @State private var isConfirmingDiscard = false

    var body: some View {
        SongEditorView(
            draft: $draft,
            context: .library,
            onSaved: { songID in
                if let entryID = store.addSongToSetlist(songID) {
                    onCreated(entryID)
                }
            },
            onClose: {
                if draft != .newSong() {
                    isConfirmingDiscard = true
                } else {
                    onCancel()
                }
            }
        )
        .frame(minWidth: 440, minHeight: 520)
        .interactiveDismissDisabled(draft != .newSong())
        .confirmationDialog(
            "Discard new song?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Song", role: .destructive, action: onCancel)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This song has not been saved.")
        }
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
    return SongInspectorPane(entryID: entryID, isDirty: .constant(false)) {}
        .environment(store)
        .frame(width: 320, height: 660)
}
