import CoreAudio
import Foundation
import Observation

enum AppScreen: String, CaseIterable, Identifiable {
    case live = "Live Service"
    case rehearse = "Rehearse"
    case songs = "Song Library"
    case pads = "Pad Library"

    var id: String { rawValue }
}

enum PlaybackPhase: String {
    case noSongPlaying = "No Song Playing"
    case songStarting = "Song Starting"
    case songPlaying = "Song Playing"
}

enum PadPlaybackState: String {
    case off = "Off"
    case preparing = "Preparing"
    case fadingIn = "Fading In"
    case playing = "Playing"
    case fadingOut = "Fading Out"
}

enum ClickPlaybackState: String {
    case off = "Off"
    case preparing = "Preparing"
    case countoff = "Countoff"
    case playing = "Playing"
}

struct RuntimeSession: Equatable {
    var playingEntryID: SetlistEntry.ID?
    var cuedEntryID: SetlistEntry.ID?
    var audiblePadTrackID: PadTrack.ID?
    var audiblePadEntryID: SetlistEntry.ID?
    var playbackPhase: PlaybackPhase = .noSongPlaying
    var padState: PadPlaybackState = .off
    var clickState: ClickPlaybackState = .off
    var countoffBeat: Int?
    var countoffTotal: Int?
    var lastMessage = "Ready"
}

struct RehearseSession: Equatable {
    var selectedKey: MusicalKey = .c
    var selectedPadTrackID: PadTrack.ID? = PadTrack.includedID(for: .c)
    var selectedPadLabel = "C"
    var padState: PadPlaybackState = .off
    var clickState: ClickPlaybackState = .off
    var countoffBeat: Int?
    var countoffTotal: Int?
    var bpm: Int = 72
    var timeSignature: TimeSignature = .fourFour
    var clickSubdivision: ClickSubdivision = .beat
    var pulseInterpretation: PulseInterpretation = .legacy
    var clickAccentPattern: [ClickAccentLevel]? = nil
    var countoffPolicy: CountoffPolicy = .rehearseDefault
    var activeCountoffPolicy: CountoffPolicy? = nil
    var countoffEnabled = true
    var lastMessage = "Ready to rehearse"
}

struct SystemCheckResult: Equatable {
    var canStartPlayback: Bool
    var messages: [String]
    var warnings: [String] = []

    static let notRun = SystemCheckResult(
        canStartPlayback: false,
        messages: ["System check has not run yet."]
    )
}

struct AudioRouteChangePrompt: Identifiable, Equatable {
    var id = UUID()
    var detectedOutputID: AudioDeviceID
    var detectedOutputName: String
    var previousPadOutputID: AudioDeviceID?
    var previousPadOutputName: String
    var previousPadOutputChannel: AudioOutputChannelSelection
    var previousClickOutputID: AudioDeviceID?
    var previousClickOutputName: String
    var previousClickOutputChannel: AudioOutputChannelSelection
    var message: String
}

struct SaveErrorPrompt: Identifiable, Equatable {
    var id = UUID()
    var message: String
}

private struct ActiveSetlistContentState {
    var setlist: Setlist
    var cuedEntryID: SetlistEntry.ID?
}

@MainActor
@Observable
final class AppStore {
    // UI state — observed with property-level granularity, so a view re-renders only for the
    // exact fields it reads. (Migrated off ObservableObject/@Published, whose object-level
    // invalidation re-rendered every view on any change — the root of the Live layout flip and
    // a latent re-render storm; see docs/13, docs/14.)
    var selectedScreen: AppScreen = .live
    var dirtySongEditorScreen: AppScreen?
    var pendingScreenNavigation: AppScreen?
    var songs: [Song]
    var padPacks: [PadPack]
    var padTracks: [PadTrack]
    var activeSetlist: Setlist
    var runtime = RuntimeSession()
    var rehearse = RehearseSession()
    var systemCheck = SystemCheckResult.notRun
    var audioStatus: String
    var persistenceStatus: String
    var routingSettings: AudioRoutingSettings
    var routingSnapshot: AudioRoutingSnapshot
    var padVolume: Double
    var clickVolume: Double
    var clickSettings: ClickSettings
    var audibleClickSubdivision: ClickSubdivision?
    var audibleClickAccentPattern: [ClickAccentLevel]?
    var activeLiveCountoffPolicy: CountoffPolicy?
    var pendingRehearseClickSubdivision: ClickSubdivision?
    var pendingLiveClickSubdivision: ClickSubdivision?
    var pendingLiveClickSongID: Song.ID?
    var midiControllerSettings: MIDIControllerSettings
    var midiAvailableSources: [MIDIControllerSource] = []
    var midiServiceState: MIDIControllerServiceState = .stopped
    var midiLearnState: MIDILearnState = .idle
    var liveTapTempo = TapTempoEstimator()
    var rehearseTapTempo = TapTempoEstimator()
    var liveTempoOverrides: [SetlistEntry.ID: Int] = [:]
    var tapTempoMessage: String?
    var padAssetStates: [PadTrack.ID: PadAssetState] = [:]
    var audioRouteChangePrompt: AudioRouteChangePrompt?
    /// Set when a library save fails after a retry — drives a blocking alert so the operator
    /// isn't left believing edits are saved when they're not.
    var saveErrorPrompt: SaveErrorPrompt?

    // Infrastructure / private state — never read from a view body, so exclude from observation.
    /// True when the in-memory library is newer than what's on disk (a save failed). Lets a
    /// later successful save or an app-quit flush recover the work.
    @ObservationIgnored private var hasUnsavedChanges = false
    @ObservationIgnored private let audioEngine: AudioControlling
    @ObservationIgnored private let libraryStore: LocalLibraryStore?
    @ObservationIgnored private let audioRoutingProvider: AudioRoutingProviding
    @ObservationIgnored private let audioHardwareMonitor: AudioHardwareMonitoring
    @ObservationIgnored private let powerStateMonitor: PowerStateMonitoring
    @ObservationIgnored private let countoffDurationMultiplier: Double
    @ObservationIgnored private let externalAudioReferencer: any ExternalAudioReferencing
    @ObservationIgnored private let midiController: MIDIControlling
    @ObservationIgnored private let persistenceWriteBlockReason: String?
    @ObservationIgnored private var midiLearnCoordinator = MIDILearnCoordinator()
    @ObservationIgnored private var midiMappingResolver = MIDIControllerMappingResolver()
    @ObservationIgnored private var liveTapEntryID: SetlistEntry.ID?
    @ObservationIgnored private var lastRehearseCountoffPolicy: CountoffPolicy = .rehearseDefault
    @ObservationIgnored private var midiLearnTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var clickStateTask: Task<Void, Never>?
    @ObservationIgnored private var padStateTask: Task<Void, Never>?
    @ObservationIgnored private var liveStartGeneration: UInt64 = 0
    @ObservationIgnored private var clickChangeGeneration: UInt64 = 0
    @ObservationIgnored private var clickChangeInFlight = false
    @ObservationIgnored private var rehearsePadPreparationGeneration: UInt64 = 0
    @ObservationIgnored private var audioRoutingFailureMessage: String?

    init(
        songs: [Song],
        padPacks: [PadPack]? = nil,
        padTracks: [PadTrack]? = nil,
        activeSetlist: Setlist,
        audioEngine: AudioControlling = SilentAudioEngine(),
        libraryStore: LocalLibraryStore? = nil,
        audioRoutingProvider: AudioRoutingProviding = CoreAudioRoutingProvider(),
        audioHardwareMonitor: AudioHardwareMonitoring = NoopAudioHardwareMonitor(),
        powerStateMonitor: PowerStateMonitoring = NoopPowerStateMonitor(),
        routingSettings: AudioRoutingSettings = .default,
        padVolume: Double = 0.42,
        clickVolume: Double = 0.75,
        clickSettings: ClickSettings = .default,
        midiControllerSettings: MIDIControllerSettings = .disabled,
        midiController: MIDIControlling = NoopMIDIController(),
        externalAudioReferencer: any ExternalAudioReferencing = ExternalAudioReferenceService(),
        persistenceStatus: String = "Using seed library",
        persistenceWriteBlockReason: String? = nil,
        countoffDurationMultiplier: Double = 1.0
    ) {
        self.songs = normalizedIncludedBundleSongs(songs)
        self.padPacks = [PadPack.bundled]
        self.padTracks = padTracks ?? PadTrack.included
        self.activeSetlist = activeSetlist
        self.audioEngine = audioEngine
        self.libraryStore = libraryStore
        self.audioRoutingProvider = audioRoutingProvider
        self.audioHardwareMonitor = audioHardwareMonitor
        self.powerStateMonitor = powerStateMonitor
        self.routingSettings = routingSettings
        self.padVolume = min(1, max(0, padVolume))
        self.clickVolume = min(1, max(0, clickVolume))
        self.clickSettings = clickSettings
        self.midiControllerSettings = midiControllerSettings
        self.midiController = midiController
        self.externalAudioReferencer = externalAudioReferencer
        self.persistenceWriteBlockReason = persistenceWriteBlockReason
        self.audioStatus = audioEngine.statusSummary
        self.persistenceStatus = persistenceStatus
        self.routingSnapshot = audioRoutingProvider.snapshot(settings: routingSettings)
        self.countoffDurationMultiplier = countoffDurationMultiplier
        runtime.cuedEntryID = activeSetlist.entries.first?.id
        audioEngine.setPadVolume(self.padVolume)
        audioEngine.setClickVolume(self.clickVolume)
        configureAudioRouting()
        audioHardwareMonitor.start { [weak self] in
            self?.handleAudioHardwareChanged()
        }
        powerStateMonitor.start { [weak self] in
            self?.handleSystemWake()
        }
        preloadCuedPad()
        let externalPadIDs = self.padTracks.compactMap { track in
            if case .external = track.source { track.id } else { nil }
        }
        if !externalPadIDs.isEmpty {
            Task { @MainActor [weak self] in
                for padID in externalPadIDs {
                    guard let self else { return }
                    await self.refreshExternalPadState(padID)
                }
                self?.refreshReadiness()
            }
        }
        midiController.eventHandler = { [weak self] event in self?.receiveMIDI(event) }
        midiController.sourceLifecycleHandler = { [weak self] uniqueID in
            self?.midiMappingResolver.reset(sourceUniqueID: uniqueID)
            self?.syncMIDIServiceState()
        }
        if midiControllerSettings.isEnabled { midiController.start() }
        syncMIDIServiceState()
    }

    var playingEntry: SetlistEntry? {
        entry(id: runtime.playingEntryID)
    }

    var cuedEntry: SetlistEntry? {
        entry(id: runtime.cuedEntryID)
    }

    /// True when the cued entry is the one already playing — i.e. Start would be a
    /// no-op restart. Used to disable the Start control so it can't interrupt the
    /// live song (`startCuedSong()` also guards this authoritatively).
    var isCuedSongPlaying: Bool {
        runtime.playingEntryID != nil && runtime.cuedEntryID == runtime.playingEntryID
    }

    /// Live-performance truth includes song identity, countoff/click, idle pad pre-roll,
    /// preparation, playback, and fades. Merely viewing the Live screen is irrelevant.
    var isLivePerformanceActive: Bool {
        runtime.playingEntryID != nil ||
            runtime.playbackPhase != .noSongPlaying ||
            runtime.padState != .off ||
            runtime.clickState != .off
    }

    /// Content-destructive actions and the updater use audio truth, not the selected screen
    /// or only the playing-song identity. Rehearse preparation/playback is included too.
    var isAnyAudioActivityActive: Bool {
        isLivePerformanceActive ||
            rehearse.padState != .off ||
            rehearse.clickState != .off
    }

    /// The only state in which the cued song's pad may be pre-rolled. A fading pad is
    /// deliberately not idle even after its owning song identity has been cleared.
    var isFullyIdleForCuedPad: Bool {
        runtime.playingEntryID == nil &&
            runtime.playbackPhase == .noSongPlaying &&
            runtime.clickState == .off &&
            runtime.padState == .off &&
            runtime.audiblePadTrackID == nil &&
            rehearse.padState == .off &&
            rehearse.clickState == .off
    }

    var livePadControlTitle: String? {
        if runtime.playingEntryID != nil {
            return runtime.padState == .off ? "Start Pad" : "Stop Pad"
        }
        if runtime.padState != .off { return "Stop Cued Pad" }
        guard isFullyIdleForCuedPad,
              let cuedEntry,
              let song = song(for: cuedEntry),
              padTrack(for: song) != nil else {
            return nil
        }
        return "Play Cued Pad"
    }

    func song(for entry: SetlistEntry?) -> Song? {
        guard let entry else { return nil }
        return songs.first { $0.id == entry.songID }
    }

    func padTrack(for song: Song) -> PadTrack? {
        guard let padTrackID = song.padTrackID else { return nil }
        return padTracks.first { $0.id == padTrackID }
    }

    private func beginPadFadeInState(for padID: PadTrack.ID, rehearse isRehearse: Bool) {
        padStateTask?.cancel()
        if isRehearse {
            rehearse.padState = .fadingIn
        } else {
            runtime.padState = .fadingIn
        }
        padStateTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.25))
            guard !Task.isCancelled else { return }
            if isRehearse {
                if rehearse.selectedPadTrackID == padID { rehearse.padState = .playing }
            } else if runtime.audiblePadTrackID == padID {
                runtime.padState = .playing
            }
        }
    }

    func entry(id: SetlistEntry.ID?) -> SetlistEntry? {
        guard let id else { return nil }
        return activeSetlist.entries.first { $0.id == id }
    }

    func cueNextSong() {
        guard let currentID = runtime.cuedEntryID,
              let index = activeSetlist.entries.firstIndex(where: { $0.id == currentID }) else {
            runtime.cuedEntryID = activeSetlist.entries.first?.id
            return
        }

        let nextIndex = activeSetlist.entries.index(after: index)
        guard nextIndex < activeSetlist.entries.endIndex else {
            runtime.lastMessage = "End of setlist"
            return
        }

        runtime.cuedEntryID = activeSetlist.entries[nextIndex].id
        resetLiveTapSequence()
        runtime.lastMessage = "Cued next song"
        preloadCuedPad()
    }

    func cuePreviousSong() {
        guard let currentID = runtime.cuedEntryID,
              let index = activeSetlist.entries.firstIndex(where: { $0.id == currentID }),
              index > activeSetlist.entries.startIndex else {
            runtime.lastMessage = "Already at first song"
            return
        }

        runtime.cuedEntryID = activeSetlist.entries[activeSetlist.entries.index(before: index)].id
        resetLiveTapSequence()
        runtime.lastMessage = "Cued previous song"
        preloadCuedPad()
    }

    func cue(entryID: SetlistEntry.ID) {
        guard let entry = entry(id: entryID), let song = song(for: entry) else {
            runtime.lastMessage = "Could not cue song"
            return
        }

        runtime.cuedEntryID = entryID
        resetLiveTapSequence()
        runtime.lastMessage = "Cued \(song.title)"
        preloadCuedPad()
        refreshReadiness()
    }

    func startCuedSong() {
        guard let cuedEntry, let cuedSong = song(for: cuedEntry) else {
            runtime.lastMessage = "No song cued"
            return
        }

        // Re-pressing Start on the song that is already playing must not interrupt
        // it with a fresh countoff and a pad self-crossfade. Cueing does not
        // auto-advance, so the cued entry is the playing entry until the operator
        // cues the next song — an easy accidental double-press mid-service.
        guard cuedEntry.id != runtime.playingEntryID else {
            runtime.lastMessage = "\(cuedSong.title) is already playing"
            return
        }

        prepareCurrentAudioRoutingForStart()
        let validation = validate(entry: cuedEntry, song: cuedSong)
        guard validation.canStartPlayback else {
            systemCheck = validation
            runtime.lastMessage = "Playback blocked by system check"
            return
        }

        liveStartGeneration &+= 1
        cancelPendingClickChange()
        let startGeneration = liveStartGeneration
        let previousRuntime = runtime
        let preparedClickSettings = clickSettings
        let preparedBPM = effectiveBPM(for: cuedEntry, song: cuedSong) ?? cuedSong.defaultBPM
        stopRehearsalForLiveSession()
        runtime.playbackPhase = .songStarting
        let assignedPad = padTrack(for: cuedSong)
        let preservesMatchingPreroll = previousRuntime.playingEntryID == nil &&
            assignedPad?.id == previousRuntime.audiblePadTrackID
        if assignedPad != nil, !preservesMatchingPreroll { runtime.padState = .preparing }

        let prepareClick: @MainActor @Sendable (PreparedPad?) -> Void = { [weak self] preparedPad in
            guard let self else { return }
            self.audioEngine.prepareClick(
                bpm: preparedBPM,
                timeSignature: cuedSong.timeSignature,
                subdivision: cuedSong.clickSubdivision,
                pulseInterpretation: cuedSong.pulseInterpretation,
                accentPattern: cuedSong.clickAccentPattern,
                countoffPolicy: cuedSong.countoffPolicy,
                settings: preparedClickSettings
            ) { [weak self] clickResult in
                guard let self else { return }
                guard self.liveStartGeneration == startGeneration else {
                    if let preparedPad { self.audioEngine.discardPreparedPad(preparedPad) }
                    return
                }
                guard self.runtime.cuedEntryID == cuedEntry.id,
                      self.song(for: cuedEntry)?.padTrackID == cuedSong.padTrackID else {
                    if let preparedPad { self.audioEngine.discardPreparedPad(preparedPad) }
                    self.restoreRuntimeAfterFailedPreparation(
                        previousRuntime,
                        message: "Cue changed before playback was ready"
                    )
                    return
                }
                guard let latestSong = self.song(for: cuedEntry),
                      self.effectiveBPM(for: cuedEntry, song: latestSong) == preparedBPM,
                      latestSong.timeSignature == cuedSong.timeSignature,
                      latestSong.clickSubdivision == cuedSong.clickSubdivision,
                      latestSong.pulseInterpretation == cuedSong.pulseInterpretation,
                      latestSong.clickAccentPattern == cuedSong.clickAccentPattern,
                      latestSong.countoffPolicy == cuedSong.countoffPolicy,
                      self.clickSettings == preparedClickSettings else {
                    if let preparedPad { self.audioEngine.discardPreparedPad(preparedPad) }
                    self.restoreRuntimeAfterFailedPreparation(previousRuntime, message: "Click settings changed; preparing again")
                    self.startCuedSong()
                    return
                }
                do {
                    let preparedClick = try clickResult.get()
                    let countoffStartedAt = ContinuousClock.now
                    // Commit only after every target resource is ready. These activation calls
                    // schedule already-owned buffers and are deliberately nonthrowing.
                    if let preparedPad {
                        guard self.audioEngine.activatePad(preparedPad) else {
                            self.restoreRuntimeAfterFailedPreparation(
                                previousRuntime,
                                message: "Pad preparation was superseded; try again"
                            )
                            self.refreshAudioStatus()
                            return
                        }
                        self.runtime.audiblePadTrackID = preparedPad.padID
                        self.runtime.audiblePadEntryID = cuedEntry.id
                        self.beginPadFadeInState(for: preparedPad.padID, rehearse: false)
                    } else if preservesMatchingPreroll {
                        // The pad player keeps its loop position; only ownership is promoted.
                        self.runtime.audiblePadEntryID = cuedEntry.id
                    } else {
                        self.beginLivePadFadeOut(message: nil)
                    }
                    self.clickStateTask?.cancel()
                    try self.audioEngine.activateClick(preparedClick)
                    self.audibleClickSubdivision = cuedSong.clickSubdivision
                    self.audibleClickAccentPattern = cuedSong.clickAccentPattern
                    self.activeLiveCountoffPolicy = cuedSong.countoffPolicy
                    self.runtime.playingEntryID = cuedEntry.id
                    self.runtime.playbackPhase = .songPlaying
                    if cuedSong.countoffPolicy.hasCountoff {
                        self.beginCountoff(
                            for: cuedEntry.id,
                            songTitle: cuedSong.title,
                            bpm: preparedBPM,
                            timeSignature: cuedSong.timeSignature,
                            pulseInterpretation: cuedSong.pulseInterpretation,
                            policy: cuedSong.countoffPolicy,
                            startedAt: countoffStartedAt
                        )
                        self.runtime.lastMessage = "Countoff started for \(cuedSong.title)"
                    } else {
                        self.runtime.clickState = .playing
                        self.runtime.lastMessage = "Click playing for \(cuedSong.title)"
                    }
                    self.refreshAudioStatus()
                } catch {
                    if let preparedPad { self.audioEngine.discardPreparedPad(preparedPad) }
                    self.restoreRuntimeAfterFailedPreparation(
                        previousRuntime,
                        message: error.localizedDescription
                    )
                    self.refreshAudioStatus()
                }
            }
        }

        if preservesMatchingPreroll {
            prepareClick(nil)
        } else if let assignedPad {
            audioEngine.preparePad(assignedPad) { result in
                do {
                    guard self.liveStartGeneration == startGeneration else {
                        if case let .success(prepared) = result { self.audioEngine.discardPreparedPad(prepared) }
                        return
                    }
                    prepareClick(try result.get())
                }
                catch {
                    self.restoreRuntimeAfterFailedPreparation(
                        previousRuntime,
                        message: error.localizedDescription
                    )
                    self.refreshAudioStatus()
                }
            }
        } else {
            prepareClick(nil)
        }
    }

    func stop() {
        // The menu and MIDI action both promise to stop all audio, including Rehearse.
        if rehearse.padState != .off { stopRehearsePad() }
        if rehearse.clickState != .off { stopRehearseClick() }
        liveStartGeneration &+= 1
        cancelPendingClickChange()
        audioEngine.cancelPendingPadPreparation()
        clickStateTask?.cancel()
        clearCountoff()
        audioEngine.stopClick()
        audibleClickSubdivision = nil
        audibleClickAccentPattern = nil
        activeLiveCountoffPolicy = nil
        runtime.clickState = .off
        runtime.playingEntryID = nil
        runtime.playbackPhase = .noSongPlaying
        if runtime.padState != .off || runtime.audiblePadTrackID != nil {
            beginLivePadFadeOut(message: "Stopped")
        } else {
            runtime.lastMessage = "Stopped"
        }
        refreshAudioStatus()
    }

    func navigate(to screen: AppScreen) {
        guard screen != selectedScreen else { return }
        if dirtySongEditorScreen == selectedScreen {
            pendingScreenNavigation = screen
        } else {
            selectedScreen = screen
        }
    }

    func resolvePendingNavigation(discardChanges: Bool) {
        defer { pendingScreenNavigation = nil }
        guard discardChanges, let pendingScreenNavigation else { return }
        dirtySongEditorScreen = nil
        selectedScreen = pendingScreenNavigation
    }

    func startClick() {
        guard let playingEntry, let song = song(for: playingEntry) else {
            runtime.lastMessage = "Start a song before starting click"
            return
        }

        guard runtime.clickState == .off else {
            runtime.lastMessage = "Click is already active"
            return
        }

        let bpm = effectiveBPM(for: playingEntry, song: song) ?? song.defaultBPM
        let preparedClickSettings = clickSettings
        liveStartGeneration &+= 1
        let generation = liveStartGeneration
        runtime.clickState = .preparing

        audioEngine.prepareClick(
            bpm: bpm,
            timeSignature: song.timeSignature,
            subdivision: song.clickSubdivision,
            pulseInterpretation: song.pulseInterpretation,
            accentPattern: song.clickAccentPattern,
            countoffPolicy: song.countoffPolicy,
            settings: preparedClickSettings
        ) { [weak self] result in
            guard let self else { return }
            guard self.liveStartGeneration == generation,
                  self.runtime.playingEntryID == playingEntry.id,
                  self.runtime.clickState == .preparing else { return }
            guard let latestSong = self.song(for: playingEntry),
                  self.effectiveBPM(for: playingEntry, song: latestSong) == bpm,
                  latestSong.timeSignature == song.timeSignature,
                  latestSong.clickSubdivision == song.clickSubdivision,
                  latestSong.pulseInterpretation == song.pulseInterpretation,
                  latestSong.clickAccentPattern == song.clickAccentPattern,
                  latestSong.countoffPolicy == song.countoffPolicy,
                  self.clickSettings == preparedClickSettings else {
                self.runtime.clickState = .off
                self.startClick()
                return
            }
            do {
                try self.audioEngine.activateClick(result.get())
                self.audibleClickSubdivision = song.clickSubdivision
                self.audibleClickAccentPattern = song.clickAccentPattern
                self.activeLiveCountoffPolicy = song.countoffPolicy
                if song.countoffPolicy.hasCountoff {
                    self.beginCountoff(
                        for: playingEntry.id,
                        songTitle: song.title,
                        bpm: bpm,
                        timeSignature: song.timeSignature,
                        pulseInterpretation: song.pulseInterpretation,
                        policy: song.countoffPolicy,
                        startedAt: ContinuousClock.now
                    )
                    self.runtime.lastMessage = "Countoff started for \(song.title)"
                } else {
                    self.runtime.clickState = .playing
                    self.runtime.lastMessage = "Click playing for \(song.title)"
                }
                self.refreshAudioStatus()
            } catch {
                self.runtime.clickState = .off
                self.runtime.lastMessage = error.localizedDescription
                self.refreshAudioStatus()
            }
        }
    }

    func stopClick() {
        liveStartGeneration &+= 1
        cancelPendingClickChange()
        clickStateTask?.cancel()
        clearCountoff()
        audioEngine.stopClick()
        audibleClickSubdivision = nil
        audibleClickAccentPattern = nil
        activeLiveCountoffPolicy = nil
        runtime.clickState = .off
        runtime.lastMessage = "Click stopped"
        refreshAudioStatus()
    }

    /// MIDI/UI-safe context action. A playing entry always owns this control; only the
    /// fully-idle no-song state can target the cued entry.
    func toggleLivePad() {
        if runtime.playingEntryID != nil {
            runtime.padState == .off ? startPad() : stopPad()
        } else if runtime.padState == .off {
            startCuedPad()
        } else {
            stopPad()
        }
    }

    func startCuedPad() {
        guard isFullyIdleForCuedPad else {
            runtime.lastMessage = runtime.playingEntryID == nil
                ? "Wait for Live audio to become fully idle"
                : "The current song owns the Pad control"
            return
        }
        guard let cuedEntry, let song = song(for: cuedEntry) else {
            runtime.lastMessage = "No song cued"
            return
        }
        guard let pad = padTrack(for: song) else {
            runtime.lastMessage = song.padTrackID == nil ? "This song is set to No Pad" : "The assigned pad is missing"
            return
        }

        prepareCurrentAudioRoutingForStart()
        let validation = validate(entry: cuedEntry, song: song)
        guard validation.canStartPlayback else {
            systemCheck = validation
            runtime.lastMessage = "Pad blocked by system check"
            return
        }

        liveStartGeneration &+= 1
        let generation = liveStartGeneration
        runtime.padState = .preparing
        audioEngine.preparePad(pad) { [weak self] result in
            guard let self else { return }
            do {
                let prepared = try result.get()
                guard self.liveStartGeneration == generation,
                      self.runtime.playingEntryID == nil,
                      self.runtime.playbackPhase == .noSongPlaying,
                      self.runtime.clickState == .off,
                      self.runtime.padState == .preparing,
                      self.rehearse.padState == .off,
                      self.rehearse.clickState == .off,
                      self.runtime.cuedEntryID == cuedEntry.id,
                      self.song(for: cuedEntry)?.padTrackID == prepared.padID else {
                    self.audioEngine.discardPreparedPad(prepared)
                    if self.liveStartGeneration == generation { self.runtime.padState = .off }
                    return
                }
                guard self.audioEngine.activatePad(prepared) else {
                    self.runtime.padState = .off
                    self.runtime.lastMessage = "Pad preparation was superseded; try again"
                    self.refreshAudioStatus()
                    return
                }
                self.runtime.audiblePadTrackID = prepared.padID
                self.runtime.audiblePadEntryID = cuedEntry.id
                self.beginPadFadeInState(for: prepared.padID, rehearse: false)
                self.runtime.lastMessage = "Cued pad playing for \(song.title)"
                self.refreshAudioStatus()
            } catch {
                guard self.liveStartGeneration == generation else { return }
                self.runtime.padState = .off
                self.runtime.lastMessage = error.localizedDescription
                self.refreshAudioStatus()
            }
        }
    }

    func startPad() {
        guard let playingEntry, let song = song(for: playingEntry) else {
            startCuedPad()
            return
        }
        guard let pad = padTrack(for: song) else {
            runtime.lastMessage = song.padTrackID == nil ? "This song is set to No Pad" : "The assigned pad is missing"
            return
        }
        liveStartGeneration &+= 1
        let generation = liveStartGeneration
        runtime.padState = .preparing
        audioEngine.preparePad(pad) { [weak self] result in
            guard let self else { return }
            guard self.liveStartGeneration == generation else {
                if case let .success(prepared) = result { self.audioEngine.discardPreparedPad(prepared) }
                return
            }
            do {
                let prepared = try result.get()
                guard self.runtime.playingEntryID == playingEntry.id,
                      self.runtime.padState == .preparing,
                      self.song(for: playingEntry)?.padTrackID == prepared.padID else {
                    self.audioEngine.discardPreparedPad(prepared)
                    return
                }
                guard self.audioEngine.activatePad(prepared) else {
                    self.runtime.padState = self.runtime.audiblePadTrackID == nil ? .off : .playing
                    self.runtime.lastMessage = "Pad preparation was superseded; try again"
                    self.refreshAudioStatus()
                    return
                }
                self.runtime.audiblePadTrackID = prepared.padID
                self.runtime.audiblePadEntryID = playingEntry.id
                self.beginPadFadeInState(for: prepared.padID, rehearse: false)
                self.runtime.lastMessage = "Pad started"
                self.refreshAudioStatus()
            } catch {
                guard self.liveStartGeneration == generation else { return }
                self.runtime.padState = self.runtime.audiblePadTrackID == nil ? .off : .playing
                self.runtime.lastMessage = error.localizedDescription
                self.refreshAudioStatus()
            }
        }
    }

    func stopPad() {
        liveStartGeneration &+= 1
        audioEngine.cancelPendingPadPreparation()
        beginLivePadFadeOut(message: "Pad stopped")
    }

    func startRehearsePad(key: MusicalKey) {
        guard let pad = padTracks.first(where: { $0.id == PadTrack.includedID(for: key) }) else {
            rehearse.lastMessage = "Included pad is unavailable"
            return
        }
        startRehearsePad(padID: pad.id)
    }

    func startRehearsePad(padID: PadTrack.ID) {
        guard let pad = padTracks.first(where: { $0.id == padID }) else {
            rehearse.lastMessage = "Pad is unavailable"
            return
        }
        switch padAssetStates[padID] ?? audioEngine.padAssetState(for: pad) {
        case .available: break
        case .preparing: rehearse.lastMessage = "\(pad.label) is still preparing"; return
        case .externalVolumeUnavailable: rehearse.lastMessage = "Reconnect the volume containing \(pad.label)"; return
        case .permissionDenied: rehearse.lastMessage = "Locate \(pad.label) to grant file access"; return
        case .missing: rehearse.lastMessage = "Locate the missing file for \(pad.label)"; return
        case .changed: rehearse.lastMessage = "Confirm the changed file for \(pad.label) in Pad Library"; return
        case .unsupportedOrProtected: rehearse.lastMessage = "\(pad.label) is unsupported or protected audio"; return
        case .unreadable: rehearse.lastMessage = "\(pad.label) could not be read"; return
        }
        if rehearse.selectedPadTrackID == padID, rehearse.padState != .off {
            rehearse.lastMessage = "\(pad.label) is already playing"
            return
        }
        stopLiveSessionForRehearsal()
        rehearse.selectedPadTrackID = padID
        rehearse.selectedPadLabel = pad.label
        if let key = pad.source.bundledKey { rehearse.selectedKey = key }
        prepareCurrentAudioRoutingForStart()
        rehearsePadPreparationGeneration &+= 1
        let preparationGeneration = rehearsePadPreparationGeneration
        rehearse.padState = .preparing
        audioEngine.preparePad(pad) { [weak self] result in
            guard let self else { return }
            do {
                let prepared = try result.get()
                guard self.rehearsePadPreparationGeneration == preparationGeneration,
                      self.rehearse.padState == .preparing,
                      self.rehearse.selectedPadTrackID == prepared.padID else {
                    self.audioEngine.discardPreparedPad(prepared)
                    return
                }
                guard self.audioEngine.activatePad(prepared) else {
                    self.rehearse.padState = .off
                    self.rehearse.lastMessage = "Pad preparation was superseded; try again"
                    self.refreshAudioStatus()
                    return
                }
                self.beginPadFadeInState(for: prepared.padID, rehearse: true)
                self.rehearse.lastMessage = "\(pad.label) playing in Rehearse"
                self.refreshAudioStatus()
            } catch {
                guard self.rehearsePadPreparationGeneration == preparationGeneration else { return }
                self.rehearse.padState = .off
                self.rehearse.lastMessage = error.localizedDescription
                self.refreshAudioStatus()
            }
        }
    }

    func playPadInRehearse(_ padID: PadTrack.ID) {
        selectedScreen = .rehearse
        startRehearsePad(padID: padID)
    }

    /// One playback identity for pad controls shown on different screens.
    func padPlaybackState(for padID: PadTrack.ID) -> PadPlaybackState {
        if runtime.audiblePadTrackID == padID, runtime.padState != .off {
            return runtime.padState
        }
        if rehearse.selectedPadTrackID == padID, rehearse.padState != .off {
            return rehearse.padState
        }
        return .off
    }

    func togglePadPlayback(for padID: PadTrack.ID) {
        if runtime.audiblePadTrackID == padID, runtime.padState != .off {
            stopPad()
        } else if rehearse.selectedPadTrackID == padID, rehearse.padState != .off {
            stopRehearsePad()
        } else {
            playPadInRehearse(padID)
        }
    }

    func stopRehearsePad() {
        rehearsePadPreparationGeneration &+= 1
        padStateTask?.cancel()
        audioEngine.cancelPendingPadPreparation()
        audioEngine.stopPad()
        rehearse.padState = .off
        rehearse.lastMessage = "Pad stopped"
        refreshAudioStatus()
    }

    func startRehearseClick() {
        cancelPendingClickChange()
        stopLiveSessionForRehearsal()
        prepareCurrentAudioRoutingForStart()
        liveStartGeneration &+= 1
        let generation = liveStartGeneration
        let preparedBPM = rehearse.bpm
        let preparedSignature = rehearse.timeSignature
        let preparedSubdivision = rehearse.clickSubdivision
        let preparedPulse = rehearse.pulseInterpretation
        let preparedAccents = rehearse.clickAccentPattern
        let preparedPolicy = rehearse.countoffEnabled
            ? rehearse.countoffPolicy
            : CountoffPolicy(bars: 0, after: .continueClick)
        let preparedClickSettings = clickSettings
        rehearse.clickState = .preparing
        rehearse.countoffBeat = nil
        rehearse.countoffTotal = nil

        audioEngine.prepareClick(
            bpm: preparedBPM,
            timeSignature: preparedSignature,
            subdivision: preparedSubdivision,
            pulseInterpretation: preparedPulse,
            accentPattern: preparedAccents,
            countoffPolicy: preparedPolicy,
            settings: preparedClickSettings
        ) { [weak self] result in
            guard let self else { return }
            guard self.liveStartGeneration == generation,
                  self.rehearse.clickState == .preparing else { return }
            guard self.rehearse.bpm == preparedBPM,
                  self.rehearse.timeSignature == preparedSignature,
                  self.rehearse.clickSubdivision == preparedSubdivision,
                  self.rehearse.pulseInterpretation == preparedPulse,
                  self.rehearse.clickAccentPattern == preparedAccents,
                  (self.rehearse.countoffEnabled ? self.rehearse.countoffPolicy : CountoffPolicy(bars: 0, after: .continueClick)) == preparedPolicy,
                  self.clickSettings == preparedClickSettings else {
                self.startRehearseClick()
                return
            }
            do {
                try self.audioEngine.activateClick(result.get())
                self.audibleClickSubdivision = self.rehearse.clickSubdivision
                self.audibleClickAccentPattern = self.rehearse.clickAccentPattern
                self.rehearse.activeCountoffPolicy = preparedPolicy
                if preparedPolicy.hasCountoff {
                    self.beginRehearseCountoff()
                    self.rehearse.lastMessage = "Countoff started at \(self.rehearse.bpm) BPM"
                } else {
                    self.rehearse.clickState = .playing
                    self.rehearse.countoffBeat = nil
                    self.rehearse.countoffTotal = nil
                    self.rehearse.lastMessage = "Click playing at \(self.rehearse.bpm) BPM"
                }
                self.refreshAudioStatus()
            } catch {
                self.rehearse.clickState = .off
                self.rehearse.countoffBeat = nil
                self.rehearse.countoffTotal = nil
                self.rehearse.lastMessage = error.localizedDescription
                self.refreshAudioStatus()
            }
        }
    }

    func stopRehearseClick() {
        liveStartGeneration &+= 1
        cancelPendingClickChange()
        clickStateTask?.cancel()
        audioEngine.stopClick()
        audibleClickSubdivision = nil
        audibleClickAccentPattern = nil
        rehearse.activeCountoffPolicy = nil
        rehearse.clickState = .off
        rehearse.countoffBeat = nil
        rehearse.countoffTotal = nil
        rehearse.lastMessage = "Click stopped"
        refreshAudioStatus()
    }

    func setRehearseBPM(_ bpm: Int) {
        rehearse.bpm = min(220, max(40, bpm))

        guard rehearse.clickState != .off else {
            rehearse.lastMessage = "Click set to \(rehearse.bpm) BPM"
            return
        }

        restartActiveRehearseClickIfNeeded(message: "Click updated to \(rehearse.bpm) BPM")
    }

    func effectiveBPM(for entry: SetlistEntry?, song: Song? = nil) -> Int? {
        guard let entry, let song = song ?? self.song(for: entry) else { return nil }
        return liveTempoOverrides[entry.id] ?? song.defaultBPM
    }

    private func resetLiveTapSequence() {
        liveTapTempo.reset()
        liveTapEntryID = runtime.cuedEntryID
        tapTempoMessage = nil
    }

    func tapTempo(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if selectedScreen == .rehearse {
            guard rehearse.clickState == .off else { return }
            rehearseTapTempo.tap(at: time)
            tapTempoMessage = rehearseTapTempo.didResetOnLastTap ? "Tap sequence reset" : nil
            return
        }
        guard selectedScreen == .live, let cuedEntry,
              cuedEntry.id != runtime.playingEntryID,
              runtime.clickState == .off, runtime.playbackPhase != .songStarting else { return }
        if liveTapEntryID != cuedEntry.id { resetLiveTapSequence() }
        liveTapTempo.tap(at: time)
        tapTempoMessage = liveTapTempo.didResetOnLastTap ? "Tap sequence reset" : nil
    }

    @discardableResult
    func useTappedTempo(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        if selectedScreen == .rehearse {
            guard rehearse.clickState == .off, let bpm = rehearseTapTempo.bpm(at: time) else { return false }
            setRehearseBPM(bpm)
            rehearseTapTempo.reset()
            return true
        }
        guard selectedScreen == .live, let cuedEntry,
              cuedEntry.id != runtime.playingEntryID,
              runtime.clickState == .off, runtime.playbackPhase != .songStarting,
              let bpm = liveTapTempo.bpm(at: time) else { return false }
        liveTempoOverrides[cuedEntry.id] = bpm
        liveTapTempo.reset()
        liveStartGeneration &+= 1
        audioEngine.cancelPendingPadPreparation()
        runtime.lastMessage = "Session tempo set to \(bpm) BPM"
        refreshReadiness()
        return true
    }

    @discardableResult
    func saveCuedTempoAsSongDefault() -> Bool {
        guard let cuedEntry, cuedEntry.id != runtime.playingEntryID,
              let bpm = liveTempoOverrides[cuedEntry.id],
              runtime.clickState == .off, runtime.playbackPhase != .songStarting,
              let index = songs.firstIndex(where: { $0.id == cuedEntry.songID }) else { return false }
        let previousBPM = songs[index].defaultBPM
        songs[index].defaultBPM = bpm
        let saved = saveLibrary()
        if saved { liveTempoOverrides[cuedEntry.id] = nil }
        else { songs[index].defaultBPM = previousBPM }
        refreshReadiness()
        runtime.lastMessage = saved ? "Saved \(bpm) BPM as song default" : "Could not save tempo"
        return saved
    }

    func setRehearseTimeSignature(_ timeSignature: TimeSignature) {
        rehearse.timeSignature = timeSignature
        let pulseCount = ClickPulseGrid(timeSignature: timeSignature,
                                        pulseInterpretation: rehearse.pulseInterpretation,
                                        bpm: rehearse.bpm, sampleRate: 44_100).pulseCount
        if rehearse.clickAccentPattern?.count != pulseCount { rehearse.clickAccentPattern = nil }

        guard rehearse.clickState != .off else { return }
        restartActiveRehearseClickIfNeeded(message: "Click updated to \(timeSignature.description)")
    }

    func setRehearsePulseInterpretation(_ interpretation: PulseInterpretation) {
        guard rehearse.clickState == .off else { return }
        rehearse.pulseInterpretation = interpretation
        let pulseCount = ClickPulseGrid(timeSignature: rehearse.timeSignature,
                                        pulseInterpretation: interpretation,
                                        bpm: rehearse.bpm, sampleRate: 44_100).pulseCount
        if rehearse.clickAccentPattern?.count != pulseCount { rehearse.clickAccentPattern = nil }
        rehearse.lastMessage = "BPM pulse set to \(interpretation.label)"
    }

    func setRehearseAccentPattern(_ pattern: [ClickAccentLevel]?) {
        guard rehearse.clickState != .countoff else { return }
        let pulseCount = ClickPulseGrid(timeSignature: rehearse.timeSignature,
                                        pulseInterpretation: rehearse.pulseInterpretation,
                                        bpm: rehearse.bpm, sampleRate: 44_100).pulseCount
        guard pattern == nil || pattern?.count == pulseCount else { return }
        rehearse.clickAccentPattern = pattern
        if rehearse.clickState == .playing {
            pendingRehearseClickSubdivision = rehearse.clickSubdivision
            preparePendingRehearseSubdivision()
            rehearse.lastMessage = "Switching beat accents at next measure"
        } else if rehearse.clickState == .preparing {
            startRehearseClick()
        } else {
            rehearse.lastMessage = pattern == nil ? "Beat accents reset" : "Beat accents set"
        }
    }

    func setRehearseCountoffPolicy(_ policy: CountoffPolicy) {
        guard rehearse.clickState != .countoff else { return }
        var normalized = policy
        if normalized.bars == 0 { normalized.after = .continueClick }
        guard normalized.isValid else { return }
        rehearse.countoffPolicy = normalized
        rehearse.countoffEnabled = normalized.hasCountoff
        if normalized.hasCountoff { lastRehearseCountoffPolicy = normalized }
        rehearse.lastMessage = normalized.after == .countoffOnly
            ? "Click will stop after countoff"
            : "Countoff set to \(normalized.bars) bar\(normalized.bars == 1 ? "" : "s")"
    }

    func setRehearseCountoffEnabled(_ isEnabled: Bool) {
        guard rehearse.clickState != .countoff else { return }
        if !isEnabled && rehearse.countoffPolicy.hasCountoff {
            lastRehearseCountoffPolicy = rehearse.countoffPolicy
        }
        rehearse.countoffEnabled = isEnabled
        rehearse.countoffPolicy = isEnabled
            ? lastRehearseCountoffPolicy
            : CountoffPolicy(bars: 0, after: .continueClick)
        rehearse.lastMessage = isEnabled ? "Countoff enabled" : "Countoff disabled"
    }

    func pendingClickSubdivision(for songID: Song.ID) -> ClickSubdivision? {
        pendingLiveClickSongID == songID ? pendingLiveClickSubdivision : nil
    }

    func setRehearseClickSubdivision(_ subdivision: ClickSubdivision) {
        guard rehearse.clickState != .countoff else { return }
        guard rehearse.clickSubdivision != subdivision || pendingRehearseClickSubdivision != nil else { return }
        if rehearse.clickState == .playing {
            pendingRehearseClickSubdivision = subdivision
            rehearse.lastMessage = "Switching to \(subdivision.label) at next measure"
            preparePendingRehearseSubdivision()
        } else {
            rehearse.clickSubdivision = subdivision
            if rehearse.clickState == .preparing { startRehearseClick() }
            rehearse.lastMessage = "Subdivision set to \(subdivision.label)"
        }
    }

    @discardableResult
    func setSongClickSubdivision(_ songID: Song.ID, subdivision: ClickSubdivision) -> Bool {
        guard let index = songs.firstIndex(where: { $0.id == songID }) else { return false }
        let active = playingEntry?.songID == songID && runtime.clickState != .off
        guard !active || runtime.clickState != .countoff else { return false }
        guard songs[index].clickSubdivision != subdivision || pendingLiveClickSubdivision != nil else { return true }
        if active && runtime.clickState == .playing {
            pendingLiveClickSongID = songID
            pendingLiveClickSubdivision = subdivision
            runtime.lastMessage = "Switching to \(subdivision.label) at next measure"
            preparePendingLiveSubdivision()
            return true
        }
        guard songs[index].clickSubdivision != subdivision else { return true }
        songs[index].clickSubdivision = subdivision
        saveLibrary()
        if active && runtime.clickState == .preparing {
            liveStartGeneration &+= 1
            runtime.clickState = .off
            startClick()
        }
        runtime.lastMessage = "Click subdivision set to \(subdivision.label)"
        return true
    }

    private func preparePendingLiveSubdivision() {
        guard !clickChangeInFlight,
              let songID = pendingLiveClickSongID,
              let subdivision = pendingLiveClickSubdivision,
              let song = songs.first(where: { $0.id == songID }),
              playingEntry?.songID == songID,
              runtime.clickState == .playing else { return }
        clickChangeInFlight = true
        let generation = clickChangeGeneration
        let bpm = effectiveBPM(for: playingEntry, song: song) ?? song.defaultBPM
        let signature = song.timeSignature
        let pulse = song.pulseInterpretation
        let accents = song.clickAccentPattern
        let settings = clickSettings
        audioEngine.prepareClick(
            bpm: bpm,
            timeSignature: signature,
            subdivision: subdivision,
            pulseInterpretation: pulse,
            accentPattern: accents,
            countoffPolicy: CountoffPolicy(bars: 0, after: .continueClick),
            settings: settings
        ) { [weak self] result in
            guard let self, self.clickChangeGeneration == generation else { return }
            guard self.pendingLiveClickSubdivision == subdivision,
                  self.effectiveBPM(for: self.playingEntry) == bpm,
                  self.song(for: self.playingEntry)?.timeSignature == signature,
                  self.song(for: self.playingEntry)?.pulseInterpretation == pulse,
                  self.song(for: self.playingEntry)?.clickAccentPattern == accents else {
                self.clickChangeInFlight = false
                self.preparePendingLiveSubdivision()
                return
            }
            do {
                self.audioEngine.scheduleClickChange(try result.get()) { [weak self] outcome in
                    guard let self, self.clickChangeGeneration == generation,
                          self.playingEntry?.songID == songID else { return }
                    self.clickChangeInFlight = false
                    switch outcome {
                    case .success:
                        self.audibleClickSubdivision = subdivision
                        self.audibleClickAccentPattern = accents
                        if self.pendingLiveClickSubdivision == subdivision,
                           let index = self.songs.firstIndex(where: { $0.id == songID }),
                           self.songs[index].clickAccentPattern == accents,
                           self.songs[index].pulseInterpretation == pulse {
                            self.songs[index].clickSubdivision = subdivision
                            self.pendingLiveClickSubdivision = nil
                            self.pendingLiveClickSongID = nil
                            self.saveLibrary()
                            self.runtime.lastMessage = "Click switched to \(subdivision.label)"
                        } else {
                            self.preparePendingLiveSubdivision()
                        }
                    case .failure(let error):
                        if self.pendingLiveClickSubdivision == subdivision,
                           let index = self.songs.firstIndex(where: { $0.id == songID }),
                           self.songs[index].clickAccentPattern == accents {
                            self.songs[index].clickSubdivision = self.audibleClickSubdivision ?? .beat
                            self.songs[index].clickAccentPattern = self.audibleClickAccentPattern
                            self.pendingLiveClickSubdivision = nil
                            self.pendingLiveClickSongID = nil
                            self.saveLibrary()
                            self.runtime.lastMessage = "Could not change click rhythm: \(error.localizedDescription)"
                        } else {
                            self.preparePendingLiveSubdivision()
                        }
                    }
                }
            } catch {
                self.clickChangeInFlight = false
                if self.pendingLiveClickSubdivision == subdivision,
                   let index = self.songs.firstIndex(where: { $0.id == songID }),
                   self.songs[index].clickAccentPattern == accents {
                    self.songs[index].clickSubdivision = self.audibleClickSubdivision ?? .beat
                    self.songs[index].clickAccentPattern = self.audibleClickAccentPattern
                    self.pendingLiveClickSubdivision = nil
                    self.pendingLiveClickSongID = nil
                    self.saveLibrary()
                    self.runtime.lastMessage = "Could not change click rhythm: \(error.localizedDescription)"
                } else {
                    self.preparePendingLiveSubdivision()
                }
            }
        }
    }

    private func preparePendingRehearseSubdivision() {
        guard !clickChangeInFlight,
              let subdivision = pendingRehearseClickSubdivision,
              rehearse.clickState == .playing else { return }
        clickChangeInFlight = true
        let generation = clickChangeGeneration
        let bpm = rehearse.bpm
        let signature = rehearse.timeSignature
        let pulse = rehearse.pulseInterpretation
        let accents = rehearse.clickAccentPattern
        let settings = clickSettings
        audioEngine.prepareClick(
            bpm: bpm,
            timeSignature: signature,
            subdivision: subdivision,
            pulseInterpretation: pulse,
            accentPattern: accents,
            countoffPolicy: CountoffPolicy(bars: 0, after: .continueClick),
            settings: settings
        ) { [weak self] result in
            guard let self, self.clickChangeGeneration == generation else { return }
            guard self.pendingRehearseClickSubdivision == subdivision,
                  self.rehearse.bpm == bpm,
                  self.rehearse.timeSignature == signature,
                  self.rehearse.pulseInterpretation == pulse,
                  self.rehearse.clickAccentPattern == accents else {
                self.clickChangeInFlight = false
                self.preparePendingRehearseSubdivision()
                return
            }
            do {
                self.audioEngine.scheduleClickChange(try result.get()) { [weak self] outcome in
                    guard let self, self.clickChangeGeneration == generation else { return }
                    self.clickChangeInFlight = false
                    switch outcome {
                    case .success:
                        self.audibleClickSubdivision = subdivision
                        self.audibleClickAccentPattern = accents
                        if self.pendingRehearseClickSubdivision == subdivision,
                           self.rehearse.clickAccentPattern == accents {
                            self.rehearse.clickSubdivision = subdivision
                            self.pendingRehearseClickSubdivision = nil
                            self.rehearse.lastMessage = "Click switched to \(subdivision.label)"
                        } else {
                            self.preparePendingRehearseSubdivision()
                        }
                    case .failure(let error):
                        if self.pendingRehearseClickSubdivision == subdivision,
                           self.rehearse.clickAccentPattern == accents {
                            self.rehearse.clickAccentPattern = self.audibleClickAccentPattern
                            self.pendingRehearseClickSubdivision = nil
                            self.rehearse.lastMessage = "Could not change click rhythm: \(error.localizedDescription)"
                        } else {
                            self.preparePendingRehearseSubdivision()
                        }
                    }
                }
            } catch {
                self.clickChangeInFlight = false
                if self.pendingRehearseClickSubdivision == subdivision,
                   self.rehearse.clickAccentPattern == accents {
                    self.rehearse.clickAccentPattern = self.audibleClickAccentPattern
                    self.pendingRehearseClickSubdivision = nil
                    self.rehearse.lastMessage = "Could not change click rhythm: \(error.localizedDescription)"
                } else {
                    self.preparePendingRehearseSubdivision()
                }
            }
        }
    }

    private func cancelPendingClickChange() {
        clickChangeGeneration &+= 1
        clickChangeInFlight = false
        pendingLiveClickSubdivision = nil
        pendingLiveClickSongID = nil
        pendingRehearseClickSubdivision = nil
        audioEngine.cancelScheduledClickChange()
    }

    func setClickAccentMode(_ accentMode: ClickAccentMode) {
        clickSettings.accentMode = accentMode
        rehearse.lastMessage = "\(accentMode.rawValue) click selected"
        runtime.lastMessage = "\(accentMode.rawValue) click selected"
        restartActiveRehearseClickIfNeeded(message: "Click accent updated")
        saveLibrary()
    }

    func setCountoffSound(_ countoffSound: CountoffSound) {
        clickSettings.countoffSound = countoffSound
        rehearse.lastMessage = "\(countoffSound.label) countoff selected"
        runtime.lastMessage = "\(countoffSound.label) countoff selected"
        saveLibrary()
    }

    func setMIDIEnabled(_ enabled: Bool) {
        midiControllerSettings.isEnabled = enabled
        if enabled { midiController.start() } else {
            cancelMIDILearn()
            midiMappingResolver.resetAllSources()
            midiController.stop()
        }
        syncMIDIServiceState()
        saveLibrary()
    }

    func setMIDISelectedSource(_ selection: MIDIControllerSelection) {
        midiControllerSettings.selectedSource = selection
        midiMappingResolver.resetAllSources()
        saveLibrary()
    }

    func beginMIDILearn(for action: MIDIAction) {
        guard midiControllerSettings.isEnabled else {
            midiLearnState = .idle
            runtime.lastMessage = "Enable MIDI Controller before learning"
            return
        }
        midiLearnTimeoutTask?.cancel()
        midiLearnCoordinator.begin(action)
        midiLearnState = midiLearnCoordinator.state
        midiLearnTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            self.midiLearnCoordinator.timeOut()
            self.midiLearnState = self.midiLearnCoordinator.state
        }
    }

    func cancelMIDILearn() {
        midiLearnTimeoutTask?.cancel()
        midiLearnTimeoutTask = nil
        midiLearnCoordinator.cancel()
        midiLearnState = .idle
    }

    @discardableResult
    func commitMIDILearn(useAnyController: Bool = false) -> Bool {
        guard midiLearnCoordinator.commit(
            into: &midiControllerSettings,
            useAnyController: useAnyController
        ) else {
            midiLearnState = midiLearnCoordinator.state
            return false
        }
        midiLearnTimeoutTask?.cancel()
        midiLearnTimeoutTask = nil
        midiLearnState = .idle
        saveLibrary()
        return true
    }

    func clearMIDIMapping(for action: MIDIAction) {
        midiControllerSettings.mappings.removeAll { $0.action == action }
        saveLibrary()
    }

    func midiMapping(for action: MIDIAction) -> MIDIMapping? {
        midiControllerSettings.mappings.first { $0.action == action }
    }

    private func receiveMIDI(_ event: MIDIMessage) {
        if case .listening = midiLearnCoordinator.state {
            midiLearnCoordinator.receive(
                event,
                sources: midiAvailableSources,
                settings: midiControllerSettings
            )
            midiLearnState = midiLearnCoordinator.state
            if case .listening = midiLearnState {} else { midiLearnTimeoutTask?.cancel() }
            return
        }
        guard let action = midiMappingResolver.action(for: event, settings: midiControllerSettings) else { return }
        dispatchMIDIAction(action)
    }

    private func dispatchMIDIAction(_ action: MIDIAction) {
        switch action {
        case .startTransition: startCuedSong()
        case .nextCue: cueNextSong()
        case .previousCue: cuePreviousSong()
        case .stopAll: stop()
        case .toggleClick:
            guard runtime.playingEntryID != nil else {
                runtime.lastMessage = "MIDI Toggle click ignored: no live song is playing"
                return
            }
            runtime.clickState == .off ? startClick() : stopClick()
        case .togglePad: toggleLivePad()
        case .tapTempo: tapTempo()
        }
    }

    private func syncMIDIServiceState() {
        midiAvailableSources = midiController.availableSources
        midiServiceState = midiController.state
    }

    private func restartActiveRehearseClickIfNeeded(message: String) {
        guard rehearse.clickState != .off else { return }
        cancelPendingClickChange()
        liveStartGeneration &+= 1
        let generation = liveStartGeneration

        audioEngine.prepareClick(
            bpm: rehearse.bpm,
            timeSignature: rehearse.timeSignature,
            subdivision: rehearse.clickSubdivision,
            pulseInterpretation: rehearse.pulseInterpretation,
            accentPattern: rehearse.clickAccentPattern,
            countoffPolicy: CountoffPolicy(bars: 0, after: .continueClick),
            settings: clickSettings
        ) { [weak self] result in
            guard let self else { return }
            guard self.liveStartGeneration == generation,
                  self.rehearse.clickState != .off else { return }
            do {
                self.clickStateTask?.cancel()
                try self.audioEngine.activateClick(result.get())
                self.audibleClickSubdivision = self.rehearse.clickSubdivision
                self.audibleClickAccentPattern = self.rehearse.clickAccentPattern
                self.rehearse.clickState = .playing
                self.rehearse.countoffBeat = nil
                self.rehearse.countoffTotal = nil
                self.rehearse.lastMessage = message
                self.refreshAudioStatus()
            } catch {
                self.rehearse.lastMessage = error.localizedDescription
                self.refreshAudioStatus()
            }
        }
    }

    /// Applies pad volume to the engine and state without persisting — for continuous
    /// slider drags. Call `commitAudioLevels()` on release to persist once.
    func setPadVolumeLive(_ volume: Double) {
        padVolume = min(1, max(0, volume))
        audioEngine.setPadVolume(padVolume)
        let percent = Int((padVolume * 100).rounded())
        rehearse.lastMessage = "Pad volume set to \(percent)%"
        runtime.lastMessage = "Pad volume set to \(percent)%"
        refreshAudioStatus()
    }

    func setPadVolume(_ volume: Double) {
        setPadVolumeLive(volume)
        saveLibrary()
    }

    func setClickVolumeLive(_ volume: Double) {
        clickVolume = min(1, max(0, volume))
        audioEngine.setClickVolume(clickVolume)
        let percent = Int((clickVolume * 100).rounded())
        rehearse.lastMessage = "Click volume set to \(percent)%"
        runtime.lastMessage = "Click volume set to \(percent)%"
        refreshAudioStatus()
    }

    func setClickVolume(_ volume: Double) {
        setClickVolumeLive(volume)
        saveLibrary()
    }

    /// Persists the current audio levels once (called when a level slider drag ends).
    func commitAudioLevels() {
        saveLibrary()
    }

    @discardableResult
    func addSong() -> Song.ID {
        let padPack = padPacks.first ?? .bundled
        let song = Song(
            title: "New Song",
            defaultKey: .c,
            defaultBPM: 72,
            timeSignature: .fourFour,
            padPack: padPack
        )
        songs.append(song)
        saveLibrary()
        persistenceStatus = "Added song \(song.title)"
        return song.id
    }

    /// Validates and commits a song editor draft as one library change. A draft without an ID
    /// never appears in the library until this succeeds.
    @discardableResult
    func saveSongDraft(_ draft: SongDraft) -> Song.ID? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            persistenceStatus = "Enter a song title"
            return nil
        }
        guard (40...220).contains(draft.defaultBPM) else {
            persistenceStatus = "BPM must be between 40 and 220"
            return nil
        }
        guard draft.countoffPolicy.isValid else {
            persistenceStatus = "Choose a valid countoff setting"
            return nil
        }
        let draftPulseCount = ClickPulseGrid(
            timeSignature: draft.timeSignature,
            pulseInterpretation: draft.pulseInterpretation,
            bpm: draft.defaultBPM,
            sampleRate: 44_100
        ).pulseCount
        guard draft.clickAccentPattern == nil || draft.clickAccentPattern?.count == draftPulseCount else {
            persistenceStatus = "Reset beat accents after changing the pulse or meter"
            return nil
        }
        let assignedPad = draft.padTrackID.flatMap { id in padTracks.first { $0.id == id } }
        guard draft.padTrackID == nil || assignedPad != nil else {
            persistenceStatus = "The selected pad is unavailable"
            return nil
        }

        let current: Song?
        if let id = draft.id {
            guard let existing = songs.first(where: { $0.id == id }) else {
                persistenceStatus = "Could not find song to update"
                return nil
            }
            current = existing
        } else {
            current = nil
        }

        let id = current?.id ?? UUID()
        let updated = Song(
            id: id,
            title: title,
            defaultKey: assignedPad?.source.bundledKey ?? current?.defaultKey ?? .c,
            defaultBPM: draft.defaultBPM,
            timeSignature: draft.timeSignature,
            clickSubdivision: draft.clickSubdivision,
            pulseInterpretation: draft.pulseInterpretation,
            clickAccentPattern: draft.clickAccentPattern,
            countoffPolicy: draft.countoffPolicy,
            padPack: current?.padPack ?? .bundled,
            padTrackID: draft.padTrackID
        )
        if updated == current { return id }

        let playingThisSong = playingEntry?.songID == id
        let activeClick = playingThisSong && runtime.clickState != .off
        let activeEntry = playingEntry
        let currentEffectiveBPM = effectiveBPM(for: activeEntry, song: current)
        let updatedEffectiveBPM = effectiveBPM(for: activeEntry, song: updated)
        let retimeClick = activeClick && current.map {
            currentEffectiveBPM != updatedEffectiveBPM || $0.timeSignature != updated.timeSignature ||
            $0.pulseInterpretation != updated.pulseInterpretation
        } == true
        let subdivisionChanged = current?.clickSubdivision != updated.clickSubdivision
        let accentChanged = current?.clickAccentPattern != updated.clickAccentPattern
        let rhythmChanged = subdivisionChanged || accentChanged
        if activeClick && runtime.clickState == .countoff && rhythmChanged && !retimeClick {
            persistenceStatus = "Wait for the countoff to finish before changing click rhythm"
            return nil
        }

        if retimeClick {
            do {
                // A playing click takes the new tempo and meter immediately, without another countoff.
                // Starting it before mutating the library leaves the draft uncommitted on failure.
                try audioEngine.startClick(
                    bpm: updatedEffectiveBPM ?? updated.defaultBPM,
                    timeSignature: updated.timeSignature,
                    subdivision: updated.clickSubdivision,
                    pulseInterpretation: updated.pulseInterpretation,
                    accentPattern: updated.clickAccentPattern,
                    countoffPolicy: CountoffPolicy(bars: 0, after: .continueClick),
                    settings: clickSettings
                )
                cancelPendingClickChange()
                audibleClickSubdivision = updated.clickSubdivision
                audibleClickAccentPattern = updated.clickAccentPattern
            } catch {
                persistenceStatus = "Could not update click: \(error.localizedDescription)"
                runtime.lastMessage = persistenceStatus
                refreshAudioStatus()
                return nil
            }
        }

        if let index = songs.firstIndex(where: { $0.id == id }) {
            songs[index] = updated
        } else {
            songs.append(updated)
        }

        if retimeClick {
            clickStateTask?.cancel()
            clearCountoff()
            runtime.clickState = .playing
        } else if activeClick && rhythmChanged && runtime.clickState == .playing {
            // Follow the existing live subdivision path: switch at the next measure.
            pendingLiveClickSongID = id
            pendingLiveClickSubdivision = updated.clickSubdivision
            preparePendingLiveSubdivision()
        } else if activeClick && rhythmChanged && runtime.clickState == .preparing {
            liveStartGeneration &+= 1
            runtime.clickState = .off
            startClick()
        }

        saveLibrary()
        preloadCuedPad()
        refreshReadiness()
        runtime.lastMessage = activeClick && rhythmChanged && !retimeClick && runtime.clickState == .playing
            ? "Saved \(title); switching click rhythm at next measure"
            : playingThisSong ? "Updated \(title) live" : "Saved \(title)"
        refreshAudioStatus()
        return id
    }

    @discardableResult
    func updateSong(
        _ songID: Song.ID,
        title: String,
        defaultKey: MusicalKey,
        defaultBPM: Int,
        timeSignature: TimeSignature,
        padPackID: PadPack.ID
    ) -> Bool {
        guard let songIndex = songs.firstIndex(where: { $0.id == songID }) else {
            persistenceStatus = "Could not update song"
            return false
        }

        let current = songs[songIndex]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = Song(
            id: songID,
            title: trimmedTitle.isEmpty ? current.title : trimmedTitle,
            defaultKey: defaultKey,
            defaultBPM: min(220, max(40, defaultBPM)),
            timeSignature: timeSignature,
            clickSubdivision: current.clickSubdivision,
            pulseInterpretation: current.pulseInterpretation,
            clickAccentPattern: current.clickAccentPattern,
            countoffPolicy: current.countoffPolicy,
            padPack: .bundled,
            padTrackID: current.padTrackID
        )

        guard updated != current else { return true }

        let playingThisSong = playingEntry?.songID == songID
        let activeEntry = playingEntry
        let currentEffectiveBPM = effectiveBPM(for: activeEntry, song: current)
        let updatedEffectiveBPM = effectiveBPM(for: activeEntry, song: updated)
        let shouldUpdateClick = playingThisSong && runtime.clickState != .off &&
            (updatedEffectiveBPM != currentEffectiveBPM || updated.timeSignature != current.timeSignature)

        if shouldUpdateClick {
            do {
                cancelPendingClickChange()
                // A live metadata correction should take effect immediately, but must not
                // trigger another verbal count-in in the middle of a song.
                try audioEngine.startClick(
                    bpm: updatedEffectiveBPM ?? updated.defaultBPM,
                    timeSignature: updated.timeSignature,
                    subdivision: updated.clickSubdivision,
                    pulseInterpretation: updated.pulseInterpretation,
                    accentPattern: updated.clickAccentPattern,
                    countoffPolicy: CountoffPolicy(bars: 0, after: .continueClick),
                    settings: clickSettings
                )
                audibleClickSubdivision = updated.clickSubdivision
                audibleClickAccentPattern = updated.clickAccentPattern
            } catch {
                runtime.lastMessage = "Could not update click: \(error.localizedDescription)"
                refreshAudioStatus()
                return false
            }
        }

        songs[songIndex] = updated

        if shouldUpdateClick {
            clickStateTask?.cancel()
            clearCountoff()
            runtime.clickState = .playing
        }
        saveLibrary()
        preloadCuedPad()
        refreshReadiness()
        runtime.lastMessage = playingThisSong
            ? "Updated \(updated.title) live"
            : "Updated \(updated.title)"
        refreshAudioStatus()
        return true
    }

    @discardableResult
    func setSongPadTrackID(_ songID: Song.ID, padTrackID: PadTrack.ID?) -> Bool {
        guard let index = songs.firstIndex(where: { $0.id == songID }) else {
            persistenceStatus = "Could not update song"
            return false
        }
        if let padTrackID, !padTracks.contains(where: { $0.id == padTrackID }) {
            persistenceStatus = "The selected pad is unavailable"
            return false
        }
        let includedKey = padTrackID.flatMap { id in padTracks.first { $0.id == id }?.source.bundledKey }
        guard songs[index].padTrackID != padTrackID ||
            (includedKey != nil && songs[index].defaultKey != includedKey) else { return true }
        songs[index].padTrackID = padTrackID
        if let key = includedKey {
            songs[index].defaultKey = key
        }
        saveLibrary()
        refreshReadiness()
        runtime.lastMessage = runtime.audiblePadEntryID.flatMap({ entry(id: $0)?.songID }) == songID
            ? "Pad assignment updated for the next start"
            : "Pad assignment updated"
        return true
    }

    /// Removes a song from the library along with any setlist entries that reference it.
    /// Refuses while one of those entries is the song currently playing — stop first.
    func deleteSong(_ songID: Song.ID) {
        guard let songIndex = songs.firstIndex(where: { $0.id == songID }) else {
            persistenceStatus = "Could not delete song"
            return
        }

        let referencesPlaying = activeSetlist.entries.contains {
            $0.songID == songID && $0.id == runtime.playingEntryID
        }
        guard !referencesPlaying else {
            persistenceStatus = "Stop playback before deleting the playing song"
            return
        }

        let title = songs[songIndex].title
        for entry in activeSetlist.entries where entry.songID == songID {
            liveTempoOverrides[entry.id] = nil
        }
        activeSetlist.entries.removeAll { $0.songID == songID }

        // Repair the cued selection if it pointed at an entry we just removed.
        if let cuedID = runtime.cuedEntryID,
           !activeSetlist.entries.contains(where: { $0.id == cuedID }) {
            runtime.cuedEntryID = activeSetlist.entries.first?.id
        }

        songs.remove(at: songIndex)
        persistenceStatus = "Deleted \(title)"
        saveLibrary()
        preloadCuedPad()
    }

    @discardableResult
    func addSongToSetlist(_ songID: Song.ID) -> SetlistEntry.ID? {
        guard let song = songs.first(where: { $0.id == songID }) else {
            runtime.lastMessage = "Could not add song to setlist"
            return nil
        }

        let entry = SetlistEntry(songID: songID)
        activeSetlist.entries.append(entry)

        if runtime.cuedEntryID == nil {
            runtime.cuedEntryID = entry.id
        }

        runtime.lastMessage = "Added \(song.title) to setlist"
        saveLibrary()
        preloadCuedPad()
        return entry.id
    }

    func removeSetlistEntry(_ entryID: SetlistEntry.ID) {
        guard runtime.playingEntryID != entryID else {
            runtime.lastMessage = "Stop playback before removing the playing song"
            return
        }

        guard let index = activeSetlist.entries.firstIndex(where: { $0.id == entryID }) else {
            runtime.lastMessage = "Could not remove setlist entry"
            return
        }

        let removedEntry = activeSetlist.entries.remove(at: index)
        liveTempoOverrides[entryID] = nil
        if runtime.cuedEntryID == removedEntry.id {
            runtime.cuedEntryID = activeSetlist.entries[safe: index]?.id ?? activeSetlist.entries.last?.id
            resetLiveTapSequence()
        }

        runtime.lastMessage = "Removed song from setlist"
        saveLibrary()
    }

    func moveSetlistEntry(from source: IndexSet, to destination: Int) {
        activeSetlist.entries.move(fromOffsets: source, toOffset: destination)
        runtime.lastMessage = "Reordered setlist"
        saveLibrary()
    }

    func updateActiveSetlistTitle(_ title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            persistenceStatus = "Setlist title cannot be blank"
            return
        }

        activeSetlist.title = trimmedTitle
        saveLibrary()
    }

    /// Adds every valid external reference as one ordered, atomic content edit. Validation,
    /// coordinated reads, and bookmark work happen behind the non-main-actor service.
    func importPadFiles(
        _ urls: [URL],
        at insertionIndex: Int? = nil,
        undoManager: UndoManager? = nil
    ) async -> ExternalAudioImportResult {
        let existing = padTracks.compactMap { track -> ExternalAudioReference? in
            guard case let .external(reference) = track.source else { return nil }
            return reference
        }
        var result = await externalAudioReferencer.importReferences(from: urls, existing: existing)
        guard !result.imported.isEmpty else {
            runtime.lastMessage = result.wasCancelled ? "Pad import cancelled" : "No pads were added"
            return result
        }

        let original = padTracks
        let newTracks = result.imported.map {
            PadTrack(id: UUID(), label: $0.initialLabel, source: .external($0.reference))
        }
        let index = min(max(0, insertionIndex ?? padTracks.endIndex), padTracks.endIndex)
        padTracks.insert(contentsOf: newTracks, at: index)
        if !saveLibrary() {
            padTracks = original
            runtime.lastMessage = "Pads were validated but could not be saved"
            result.imported = []
            result.persistenceError = runtime.lastMessage
            return result
        }
        if let undoManager {
            let importedIDs = Set(newTracks.map(\.id))
            undoManager.registerUndo(withTarget: self) { target in
                _ = target.removePads(importedIDs, replacementPadID: nil, undoManager: undoManager)
            }
            undoManager.setActionName(newTracks.count == 1 ? "Add Pad" : "Add Pads")
        }
        runtime.lastMessage = "Added \(newTracks.count) pad\(newTracks.count == 1 ? "" : "s")"
        return result
    }

    func padAssignmentCount(_ padID: PadTrack.ID) -> Int {
        songs.lazy.filter { $0.padTrackID == padID }.count
    }

    @discardableResult
    func renamePad(_ padID: PadTrack.ID, label: String, undoManager: UndoManager? = nil) -> Bool {
        guard let index = padTracks.firstIndex(where: { $0.id == padID }), !padTracks[index].isIncluded else {
            runtime.lastMessage = "Included pads cannot be renamed"
            return false
        }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            runtime.lastMessage = "Pad labels cannot be blank"
            return false
        }
        let previous = padTracks[index].label
        guard previous != trimmed else { return true }
        padTracks[index].label = trimmed
        guard saveLibrary() else {
            padTracks[index].label = previous
            return false
        }
        undoManager?.registerUndo(withTarget: self) { target in
            _ = target.renamePad(padID, label: previous, undoManager: undoManager)
        }
        undoManager?.setActionName("Rename Pad")
        runtime.lastMessage = "Renamed pad to \(trimmed)"
        return true
    }

    @discardableResult
    func movePad(_ padID: PadTrack.ID, by offset: Int, undoManager: UndoManager? = nil) -> Bool {
        guard let source = padTracks.firstIndex(where: { $0.id == padID }) else { return false }
        let destination = min(max(0, source + offset), padTracks.count - 1)
        guard destination != source else { return false }
        let previous = padTracks
        let track = padTracks.remove(at: source)
        padTracks.insert(track, at: destination)
        guard saveLibrary() else {
            padTracks = previous
            return false
        }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restorePadOrder(previous, undoManager: undoManager)
        }
        undoManager?.setActionName("Move Pad")
        runtime.lastMessage = "Moved \(track.label)"
        return true
    }

    @discardableResult
    func movePads(from offsets: IndexSet, to destination: Int, undoManager: UndoManager? = nil) -> Bool {
        guard !offsets.isEmpty else { return false }
        let previous = padTracks
        padTracks.move(fromOffsets: offsets, toOffset: destination)
        guard saveLibrary() else {
            padTracks = previous
            return false
        }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restorePadOrder(previous, undoManager: undoManager)
        }
        undoManager?.setActionName("Reorder Pads")
        runtime.lastMessage = "Reordered pads"
        return true
    }

    /// Removes custom pads and atomically rewrites every assignment to the selected
    /// replacement (or intentional No Pad). Included and currently audible pads are refused.
    @discardableResult
    func removePads(
        _ padIDs: Set<PadTrack.ID>,
        replacementPadID: PadTrack.ID?,
        undoManager: UndoManager? = nil
    ) -> Bool {
        let targets = padTracks.filter { padIDs.contains($0.id) }
        guard !targets.isEmpty else { return false }
        guard targets.allSatisfy({ !$0.isIncluded }) else {
            runtime.lastMessage = "Included pads cannot be removed"
            return false
        }
        if let audiblePadTrackID = runtime.audiblePadTrackID, padIDs.contains(audiblePadTrackID) {
            runtime.lastMessage = "Stop the audible pad before removing it"
            return false
        }
        if rehearse.padState != .off,
           let rehearsePadID = rehearse.selectedPadTrackID,
           padIDs.contains(rehearsePadID) {
            runtime.lastMessage = "Stop the audible pad before removing it"
            return false
        }
        if let replacementPadID {
            guard !padIDs.contains(replacementPadID), padTracks.contains(where: { $0.id == replacementPadID }) else {
                runtime.lastMessage = "Choose an available replacement pad"
                return false
            }
        }

        let previousTracks = padTracks
        let previousSongs = songs
        for index in songs.indices where songs[index].padTrackID.map(padIDs.contains) == true {
            songs[index].padTrackID = replacementPadID
        }
        padTracks.removeAll { padIDs.contains($0.id) }
        guard saveLibrary() else {
            padTracks = previousTracks
            songs = previousSongs
            return false
        }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restorePadCatalog(tracks: previousTracks, songs: previousSongs, undoManager: undoManager)
        }
        undoManager?.setActionName(targets.count == 1 ? "Remove Pad" : "Remove Pads")
        refreshReadiness()
        runtime.lastMessage = "Removed \(targets.count) pad\(targets.count == 1 ? "" : "s")"
        return true
    }

    private func restorePadOrder(_ tracks: [PadTrack], undoManager: UndoManager?) {
        let current = padTracks
        padTracks = tracks
        guard saveLibrary() else {
            padTracks = current
            return
        }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restorePadOrder(current, undoManager: undoManager)
        }
        undoManager?.setActionName("Reorder Pads")
    }

    private func restorePadCatalog(tracks: [PadTrack], songs restoredSongs: [Song], undoManager: UndoManager?) {
        let currentTracks = padTracks
        let currentSongs = songs
        padTracks = tracks
        songs = restoredSongs
        guard saveLibrary() else {
            padTracks = currentTracks
            songs = currentSongs
            return
        }
        undoManager?.registerUndo(withTarget: self) { target in
            target.restorePadCatalog(tracks: currentTracks, songs: currentSongs, undoManager: undoManager)
        }
        undoManager?.setActionName("Remove Pads")
        refreshReadiness()
    }

    /// Validate-then-commit repair. The pad ID, label, order, and all song assignments remain
    /// stable. If persistence fails, the prior recoverable reference stays authoritative.
    @discardableResult
    func locateExternalPad(_ padID: PadTrack.ID, at url: URL) async -> Bool {
        guard let index = padTracks.firstIndex(where: { $0.id == padID }),
              case .external = padTracks[index].source else {
            runtime.lastMessage = "Included pads cannot be relinked"
            return false
        }
        let previous = padTracks[index]
        do {
            let reference = try await externalAudioReferencer.createReference(for: url)
            guard padTracks.indices.contains(index), padTracks[index].id == padID else {
                runtime.lastMessage = "The pad changed before the file was ready"
                return false
            }
            padTracks[index].source = .external(reference)
            if !saveLibrary() {
                padTracks[index] = previous
                runtime.lastMessage = "Could not save the replacement file reference"
                return false
            }
            padAssetStates[padID] = .available(reference.audioMetadata)
            refreshReadiness()
            runtime.lastMessage = "Located \(previous.label)"
            return true
        } catch {
            runtime.lastMessage = error.localizedDescription
            return false
        }
    }

    func refreshExternalPadState(_ padID: PadTrack.ID) async {
        guard let track = padTracks.first(where: { $0.id == padID }),
              case let .external(reference) = track.source else { return }
        padAssetStates[padID] = .preparing
        let inspectedState = await externalAudioReferencer.inspect(reference)
        guard let currentTrack = padTracks.first(where: { $0.id == padID }),
              case let .external(currentReference) = currentTrack.source,
              currentReference == reference else { return }
        padAssetStates[padID] = inspectedState
    }

    func resolvedExternalPadURL(_ padID: PadTrack.ID) async -> URL? {
        guard let track = padTracks.first(where: { $0.id == padID }),
              case let .external(reference) = track.source else { return nil }
        do {
            return try await externalAudioReferencer.withCoordinatedRead(of: reference) { $0 }
        } catch {
            runtime.lastMessage = error.localizedDescription
            return nil
        }
    }

    /// Clears only the active setlist. Song and pad libraries are intentionally untouched.
    /// The store owns the guard and atomic mutation; callers may supply the window's standard
    /// UndoManager so the content operation participates in Edit > Undo/Redo.
    @discardableResult
    func clearActiveSetlist(undoManager: UndoManager? = nil) -> Bool {
        guard !activeSetlist.entries.isEmpty else {
            runtime.lastMessage = "Setlist is already empty"
            return false
        }

        guard !isAnyAudioActivityActive else {
            runtime.lastMessage = "Stop playback before clearing the setlist"
            return false
        }

        let previous = ActiveSetlistContentState(
            setlist: activeSetlist,
            cuedEntryID: runtime.cuedEntryID
        )
        applyActiveSetlistState(
            ActiveSetlistContentState(
                setlist: Setlist(id: activeSetlist.id, title: activeSetlist.title, entries: []),
                cuedEntryID: nil
            ),
            message: "Cleared setlist"
        )
        registerSetlistUndo(previous, with: undoManager, actionName: "Clear Setlist")
        return true
    }

    /// Compatibility for existing call sites while the UI moves to the explicitly named API.
    func clearSetlist() {
        clearActiveSetlist()
    }

    private func applyActiveSetlistState(_ state: ActiveSetlistContentState, message: String) {
        activeSetlist = state.setlist
        liveTempoOverrides.removeAll()
        resetLiveTapSequence()
        runtime.cuedEntryID = state.cuedEntryID.flatMap { candidate in
            activeSetlist.entries.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? activeSetlist.entries.first?.id
        runtime.playingEntryID = nil
        runtime.playbackPhase = .noSongPlaying
        runtime.lastMessage = message
        refreshReadiness()
        runtime.lastMessage = message
        saveLibrary()
    }

    private func registerSetlistUndo(
        _ state: ActiveSetlistContentState,
        with undoManager: UndoManager?,
        actionName: String
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            guard !store.isAnyAudioActivityActive else {
                store.runtime.lastMessage = "Stop playback before changing the setlist"
                return
            }
            let inverse = ActiveSetlistContentState(
                setlist: store.activeSetlist,
                cuedEntryID: store.runtime.cuedEntryID
            )
            let restoringEntries = !state.setlist.entries.isEmpty
            store.applyActiveSetlistState(
                state,
                message: restoringEntries ? "Restored setlist" : "Cleared setlist"
            )
            store.registerSetlistUndo(
                inverse,
                with: undoManager,
                actionName: restoringEntries ? "Clear Setlist" : "Restore Setlist"
            )
        }
        undoManager.setActionName(actionName)
    }

    func updateRouting(
        padOutputID: AudioDeviceID?,
        clickOutputID: AudioDeviceID?,
        padOutputChannel: AudioOutputChannelSelection? = nil,
        clickOutputChannel: AudioOutputChannelSelection? = nil
    ) {
        stopAudioForManualRoutingChangeIfNeeded()
        routingSettings = AudioRoutingSettings(
            padOutputID: padOutputID,
            padOutputName: outputName(for: padOutputID),
            padOutputChannel: padOutputChannel,
            clickOutputID: clickOutputID,
            clickOutputName: outputName(for: clickOutputID),
            clickOutputChannel: clickOutputChannel
        )
        routingSnapshot = audioRoutingProvider.snapshot(settings: routingSettings)
        configureAudioRouting()
        saveLibrary()
    }

    func refreshAudioDiagnostics() {
        refreshRoutingSnapshot()
        runtime.lastMessage = "Audio diagnostics refreshed"
    }

    private func stopAudioForManualRoutingChangeIfNeeded() {
        guard runtime.playbackPhase != .noSongPlaying || runtime.padState != .off || runtime.clickState != .off ||
                rehearse.padState != .off || rehearse.clickState != .off else {
            return
        }

        stopAudioAfterHardwareChange(message: "Audio routing changed. Playback stopped so outputs can be rechecked.")
    }

    func keepCurrentAudioRouting() {
        guard let prompt = audioRouteChangePrompt else { return }
        audioRouteChangePrompt = nil
        routingSettings = AudioRoutingSettings(
            padOutputID: prompt.previousPadOutputID,
            padOutputName: prompt.previousPadOutputName,
            padOutputChannel: prompt.previousPadOutputChannel == .stereo ? nil : prompt.previousPadOutputChannel,
            clickOutputID: prompt.previousClickOutputID,
            clickOutputName: prompt.previousClickOutputName,
            clickOutputChannel: prompt.previousClickOutputChannel == .stereo ? nil : prompt.previousClickOutputChannel
        )
        routingSnapshot = audioRoutingProvider.snapshot(settings: routingSettings)
        configureAudioRouting()
        saveLibrary()
        runtime.lastMessage = "Kept current audio output settings"
    }

    func switchToDetectedAudioOutput() {
        guard let prompt = audioRouteChangePrompt else { return }
        audioRouteChangePrompt = nil
        updateRouting(
            padOutputID: prompt.detectedOutputID,
            clickOutputID: prompt.detectedOutputID,
            padOutputChannel: nil,
            clickOutputChannel: nil
        )
        runtime.lastMessage = "Switched audio outputs to \(prompt.detectedOutputName)"
    }

    func runSystemCheck() {
        audioEngine.prepare()
        refreshRoutingSnapshot()
        configureAudioRouting()
        refreshAudioStatus()

        if let cuedEntry, let cuedSong = song(for: cuedEntry) {
            systemCheck = validate(entry: cuedEntry, song: cuedSong)
            runtime.lastMessage = systemCheck.canStartPlayback ? "System check passed" : "System check needs attention"
        } else {
            systemCheck = SystemCheckResult(
                canStartPlayback: false,
                messages: ["Cue a song before running the system check."]
            )
            runtime.lastMessage = "No song cued"
        }
    }

    /// Lightweight readiness re-check for the Live safety-net. Pure `validate()` only — never
    /// prepares the engine or reconfigures routing (that is `runSystemCheck()`'s job), so it is
    /// safe to call on screen entry and on state changes, including during playback.
    func refreshReadiness() {
        if let cuedEntry, let cuedSong = song(for: cuedEntry) {
            systemCheck = validate(entry: cuedEntry, song: cuedSong)
        } else {
            systemCheck = .notRun
        }
    }

    private func beginCountoff(
        for entryID: SetlistEntry.ID,
        songTitle: String,
        bpm: Int,
        timeSignature: TimeSignature,
        pulseInterpretation: PulseInterpretation,
        policy: CountoffPolicy,
        startedAt: ContinuousClock.Instant
    ) {
        clickStateTask?.cancel()
        runtime.clickState = .countoff

        let beats = ClickPulseGrid(timeSignature: timeSignature,
                                   pulseInterpretation: pulseInterpretation,
                                   bpm: bpm, sampleRate: 44_100).pulseCount * policy.bars
        let secondsPerBeat = bpm > 0
            ? max(0, (60.0 / Double(bpm)) * countoffDurationMultiplier)
            : 0
        let clock = ContinuousClock()
        let elapsed = max(0, durationInSeconds(startedAt.duration(to: clock.now)))
        let initialBeat = secondsPerBeat > 0
            ? min(beats, Int(elapsed / secondsPerBeat) + 1)
            : 1
        runtime.countoffTotal = beats
        runtime.countoffBeat = initialBeat

        clickStateTask = Task { @MainActor in
            if initialBeat < beats {
                for beat in (initialBeat + 1)...beats {
                    let deadline = startedAt.advanced(by: .seconds(secondsPerBeat * Double(beat - 1)))
                    do {
                        try await clock.sleep(until: deadline)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled,
                          runtime.playingEntryID == entryID,
                          runtime.clickState == .countoff else {
                        return
                    }
                    runtime.countoffBeat = beat
                }
            }

            let countoffEnd = startedAt.advanced(by: .seconds(secondsPerBeat * Double(beats)))
            do {
                try await clock.sleep(until: countoffEnd)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  runtime.playingEntryID == entryID,
                  runtime.clickState == .countoff else {
                return
            }

            if audioEngine.supportsAudioCountoffCompletion {
                let completionDeadline = clock.now.advanced(by: .seconds(2))
                while !audioEngine.countoffHasCompleted {
                    if !audioEngine.isEngineRunning || clock.now >= completionDeadline {
                        audioEngine.stopClick()
                        audibleClickSubdivision = nil
                        audibleClickAccentPattern = nil
                        activeLiveCountoffPolicy = nil
                        runtime.countoffBeat = nil
                        runtime.countoffTotal = nil
                        runtime.clickState = .off
                        runtime.lastMessage = "Click stopped: countoff audio did not complete"
                        refreshAudioStatus()
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                    guard !Task.isCancelled,
                          runtime.playingEntryID == entryID,
                          runtime.clickState == .countoff else { return }
                }
            }

            runtime.countoffBeat = nil
            runtime.countoffTotal = nil
            if policy.after == .countoffOnly {
                audioEngine.stopClick()
                audibleClickSubdivision = nil
                audibleClickAccentPattern = nil
                activeLiveCountoffPolicy = nil
                runtime.clickState = .off
                runtime.lastMessage = "Countoff finished for \(songTitle); click off"
                refreshAudioStatus()
            } else {
                runtime.clickState = .playing
                runtime.lastMessage = "Click playing for \(songTitle)"
            }
        }
    }

    private func durationInSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func beginRehearseCountoff() {
        clickStateTask?.cancel()
        rehearse.clickState = .countoff
        let policy = rehearse.countoffPolicy
        let beats = ClickPulseGrid(timeSignature: rehearse.timeSignature,
                                   pulseInterpretation: rehearse.pulseInterpretation,
                                   bpm: rehearse.bpm, sampleRate: 44_100).pulseCount * policy.bars
        let secondsPerBeat = rehearse.bpm > 0
            ? max(0, (60.0 / Double(rehearse.bpm)) * countoffDurationMultiplier)
            : 0
        let clock = ContinuousClock()
        let startedAt = clock.now
        rehearse.countoffBeat = 1
        rehearse.countoffTotal = beats

        clickStateTask = Task { @MainActor in
            if beats > 1 {
                for beat in 2...beats {
                    let deadline = startedAt.advanced(by: .seconds(secondsPerBeat * Double(beat - 1)))
                    do {
                        try await clock.sleep(until: deadline)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, rehearse.clickState == .countoff else { return }
                    rehearse.countoffBeat = beat
                }
            }

            let countoffEnd = startedAt.advanced(by: .seconds(secondsPerBeat * Double(beats)))
            do {
                try await clock.sleep(until: countoffEnd)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  rehearse.clickState == .countoff else {
                return
            }

            if audioEngine.supportsAudioCountoffCompletion {
                let completionDeadline = clock.now.advanced(by: .seconds(2))
                while !audioEngine.countoffHasCompleted {
                    if !audioEngine.isEngineRunning || clock.now >= completionDeadline {
                        audioEngine.stopClick()
                        audibleClickSubdivision = nil
                        audibleClickAccentPattern = nil
                        rehearse.countoffBeat = nil
                        rehearse.countoffTotal = nil
                        rehearse.clickState = .off
                        rehearse.activeCountoffPolicy = nil
                        rehearse.lastMessage = "Click stopped: countoff audio did not complete"
                        refreshAudioStatus()
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                    guard !Task.isCancelled, rehearse.clickState == .countoff else { return }
                }
            }

            rehearse.countoffBeat = nil
            rehearse.countoffTotal = nil
            if policy.after == .countoffOnly {
                audioEngine.stopClick()
                audibleClickSubdivision = nil
                audibleClickAccentPattern = nil
                rehearse.clickState = .off
                rehearse.activeCountoffPolicy = nil
                rehearse.lastMessage = "Countoff finished; click off"
                refreshAudioStatus()
            } else {
                rehearse.clickState = .playing
                rehearse.lastMessage = "Click playing at \(rehearse.bpm) BPM"
            }
        }
    }

    private func stopLiveSessionForRehearsal() {
        guard runtime.playbackPhase != .noSongPlaying || runtime.clickState != .off ||
                runtime.padState != .off || runtime.audiblePadTrackID != nil else { return }

        liveStartGeneration &+= 1
        cancelPendingClickChange()
        clickStateTask?.cancel()
        padStateTask?.cancel()
        audioEngine.cancelPendingPadPreparation()
        clearCountoff()
        if runtime.clickState != .off {
            audioEngine.stopClick()
        }
        if runtime.padState != .off {
            audioEngine.stopPad()
        }
        runtime.clickState = .off
        audibleClickSubdivision = nil
        audibleClickAccentPattern = nil
        activeLiveCountoffPolicy = nil
        runtime.padState = .off
        runtime.audiblePadTrackID = nil
        runtime.audiblePadEntryID = nil
        runtime.playingEntryID = nil
        runtime.playbackPhase = .noSongPlaying
        runtime.lastMessage = "Live playback stopped for rehearsal"
    }

    private func stopRehearsalForLiveSession() {
        cancelPendingClickChange()
        rehearsePadPreparationGeneration &+= 1
        clickStateTask?.cancel()
        padStateTask?.cancel()
        audioEngine.cancelPendingPadPreparation()

        if rehearse.clickState != .off {
            audioEngine.stopClick()
        }
        if rehearse.padState != .off {
            audioEngine.stopPad()
        }

        rehearse.clickState = .off
        rehearse.activeCountoffPolicy = nil
        rehearse.countoffBeat = nil
        rehearse.countoffTotal = nil
        audibleClickSubdivision = nil
        audibleClickAccentPattern = nil
        rehearse.padState = .off
        rehearse.lastMessage = "Rehearsal stopped"
    }

    private func restoreRuntimeAfterFailedPreparation(_ previous: RuntimeSession, message: String) {
        // Cue navigation performed while decoding is a user decision and must not be rolled
        // back. Only the audio/ownership truth from before the attempt is restored.
        let currentCue = runtime.cuedEntryID
        runtime = previous
        runtime.cuedEntryID = currentCue
        runtime.lastMessage = message
    }

    private func beginLivePadFadeOut(message: String?) {
        padStateTask?.cancel()
        audioEngine.stopPad()
        guard runtime.audiblePadTrackID != nil else {
            runtime.padState = .off
            runtime.audiblePadEntryID = nil
            if let message { runtime.lastMessage = message }
            refreshAudioStatus()
            return
        }

        runtime.padState = .fadingOut
        if let message { runtime.lastMessage = message }
        padStateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.runtime.padState == .fadingOut else { return }
            self.runtime.padState = .off
            self.runtime.audiblePadTrackID = nil
            self.runtime.audiblePadEntryID = nil
            self.refreshAudioStatus()
        }
        refreshAudioStatus()
    }

    private func clearCountoff() {
        runtime.countoffBeat = nil
        runtime.countoffTotal = nil
    }

    private func preloadCuedPad() {
        guard let cuedEntry, let song = song(for: cuedEntry), let pad = padTrack(for: song) else { return }
        audioEngine.preparePad(pad) { [weak self] result in
            guard let self, case let .success(prepared) = result else { return }
            self.audioEngine.discardPreparedPad(prepared)
        }
    }

    private func countoffDuration(bpm: Int, timeSignature: TimeSignature) -> TimeInterval {
        guard bpm > 0 else { return 0 }
        return (60.0 / Double(bpm)) * Double(max(1, timeSignature.beatsPerMeasure))
    }

    @discardableResult
    private func saveLibrary() -> Bool {
        if let persistenceWriteBlockReason {
            hasUnsavedChanges = true
            persistenceStatus = persistenceWriteBlockReason
            if saveErrorPrompt == nil {
                saveErrorPrompt = SaveErrorPrompt(message: persistenceWriteBlockReason)
            }
            return false
        }
        guard let libraryStore else {
            persistenceStatus = "Seed library is not persisted"
            return true
        }

        let snapshot = LibrarySnapshot(
            songs: songs,
            padPacks: padPacks,
            padTracks: padTracks,
            activeSetlist: activeSetlist,
            routingSettings: routingSettings,
            padVolume: padVolume,
            clickVolume: clickVolume,
            clickSettings: clickSettings,
            midiControllerSettings: midiControllerSettings
        )

        // Retry once — most write failures are transient (a brief lock, momentary I/O hiccup).
        for attempt in 1...2 {
            do {
                try libraryStore.saveLibrary(snapshot)
                persistenceStatus = "Library saved"
                hasUnsavedChanges = false
                saveErrorPrompt = nil
                return true
            } catch {
                if attempt == 2 {
                    // Persistent failure: mark the work unsaved and raise a visible alert so the
                    // operator knows, rather than silently losing edits on next launch.
                    hasUnsavedChanges = true
                    persistenceStatus = "Library save failed: \(error.localizedDescription)"
                    if saveErrorPrompt == nil {
                        saveErrorPrompt = SaveErrorPrompt(
                            message: "Sustain couldn't save your library (\(error.localizedDescription)). Your changes are kept in memory — try again, and don't quit until it succeeds."
                        )
                    }
                }
            }
        }
        return false
    }

    /// Re-attempt a save the user asked to retry from the save-failure alert.
    func retryFailedSave() {
        saveErrorPrompt = nil
        saveLibrary()
    }

    /// Flush unsaved work — call on app quit / scene backgrounding as a last-chance backstop.
    @discardableResult
    func flushPendingSaveIfNeeded() -> Bool {
        guard hasUnsavedChanges else { return true }
        return saveLibrary()
    }

    /// Sparkle's relaunch gate calls this while transport is idle. Library data is saved
    /// eagerly, but a prior failure must be retried before the updater may quit the app.
    @discardableResult
    func flushForUpdaterRelaunch() -> Bool {
        let librarySaved = flushPendingSaveIfNeeded()
        let preferencesSaved = UserDefaults.standard.synchronize()
        return librarySaved && preferencesSaved
    }

    private func configureAudioRouting() {
        do {
            try audioEngine.configureRouting(routingSnapshot)
            audioRoutingFailureMessage = nil
        } catch {
            audioRoutingFailureMessage = "Audio routing failed: \(error.localizedDescription)"
            runtime.lastMessage = audioRoutingFailureMessage ?? "Audio routing failed"
        }
        refreshAudioStatus()
    }

    private func prepareCurrentAudioRoutingForStart() {
        refreshRoutingSnapshot()

        guard !audioEngine.isEngineRunning else {
            return
        }

        configureAudioRouting()
    }

    private func refreshAudioStatus() {
        audioStatus = audioEngine.statusSummary
    }

    private func refreshRoutingSnapshot() {
        routingSnapshot = audioRoutingProvider.snapshot(settings: routingSettings)
        normalizeRoutingSettingsFromSnapshot()
    }

    private func outputName(for outputID: AudioDeviceID?) -> String? {
        guard let outputID else { return nil }
        return routingSnapshot.outputs.first { $0.id == outputID }?.name
    }

    private func normalizeRoutingSettingsFromSnapshot() {
        let normalized = RoutingSettingsNormalizer.normalize(routingSettings, snapshot: routingSnapshot)
        if normalized != routingSettings {
            routingSettings = normalized
        }
    }

    private func handleAudioHardwareChanged(
        forceValidation: Bool = false,
        readyMessage: String = "Audio devices updated"
    ) {
        let previousSnapshot = routingSnapshot
        refreshRoutingSnapshot()
        guard forceValidation || routingSnapshot != previousSnapshot else { return }

        if let cuedEntry, let cuedSong = song(for: cuedEntry) {
            systemCheck = validate(entry: cuedEntry, song: cuedSong)
        }

        if !routingSnapshot.missingSelectionMessages.isEmpty {
            audioRouteChangePrompt = nil
            stopAudioAfterHardwareChange(message: routingSnapshot.missingSelectionMessages.joined(separator: " "))
            return
        }

        let isPlaying = runtime.playbackPhase != .noSongPlaying
            || rehearse.padState != .off
            || rehearse.clickState != .off

        if isPlaying {
            // Keep playing when the devices we're actually using are unchanged: with the same
            // resolved output IDs (or the same nil "follow default"), the running engine is
            // provably unaffected — it's pinned to those devices, or its default output node
            // already tracks the OS default. A bumped cable or an unrelated default switch no
            // longer silences the service mid-song. We still surface the prompt so the operator
            // can switch on purpose. If our output IDs actually shifted (e.g. a replug reassigned
            // one), fall through to the safe stop so routing can be re-established.
            let outputsUnchanged = routingSnapshot.padOutputID == previousSnapshot.padOutputID
                && routingSnapshot.clickOutputID == previousSnapshot.clickOutputID
            if outputsUnchanged {
                runtime.lastMessage = readyMessage
                refreshAudioStatus()
                setRouteChangePrompt(from: routingSnapshot, previousSnapshot: previousSnapshot)
                return
            }

            stopAudioAfterHardwareChange(message: "Audio devices changed. Playback stopped so routing can be rechecked.")
            setRouteChangePrompt(from: routingSnapshot, previousSnapshot: previousSnapshot)
            return
        }

        runtime.lastMessage = readyMessage
        setRouteChangePrompt(from: routingSnapshot, previousSnapshot: previousSnapshot)
    }

    private func handleSystemWake() {
        if midiControllerSettings.isEnabled {
            midiMappingResolver.resetAllSources()
            midiController.refresh()
            syncMIDIServiceState()
        }
        handleAudioHardwareChanged(
            forceValidation: true,
            readyMessage: "System woke. Audio routing checked."
        )
    }

    private func stopAudioAfterHardwareChange(message: String) {
        liveStartGeneration &+= 1
        cancelPendingClickChange()
        clickStateTask?.cancel()
        padStateTask?.cancel()
        audioEngine.cancelPendingPadPreparation()
        clearCountoff()
        audioEngine.stopAll()
        runtime.clickState = .off
        audibleClickSubdivision = nil
        audibleClickAccentPattern = nil
        activeLiveCountoffPolicy = nil
        runtime.padState = .off
        runtime.audiblePadTrackID = nil
        runtime.audiblePadEntryID = nil
        runtime.playingEntryID = nil
        runtime.playbackPhase = .noSongPlaying
        rehearse.clickState = .off
        rehearse.activeCountoffPolicy = nil
        rehearse.countoffBeat = nil
        rehearse.countoffTotal = nil
        rehearse.padState = .off
        rehearse.lastMessage = message
        runtime.lastMessage = message
        refreshAudioStatus()
    }

    private func setRouteChangePrompt(
        from snapshot: AudioRoutingSnapshot,
        previousSnapshot: AudioRoutingSnapshot
    ) {
        guard let detectedOutput = snapshot.outputs.first(where: \.isDefault) ?? snapshot.outputs.first else {
            audioRouteChangePrompt = nil
            return
        }

        audioRouteChangePrompt = AudioRouteChangePrompt(
            detectedOutputID: detectedOutput.id,
            detectedOutputName: detectedOutput.name,
            previousPadOutputID: previousSnapshot.padOutputID,
            previousPadOutputName: previousSnapshot.padOutputName,
            previousPadOutputChannel: previousSnapshot.padOutputChannel,
            previousClickOutputID: previousSnapshot.clickOutputID,
            previousClickOutputName: previousSnapshot.clickOutputName,
            previousClickOutputChannel: previousSnapshot.clickOutputChannel,
            message: "Audio output change detected. Keep your current Sustain routing, or switch pad and click to \(detectedOutput.name)."
        )
    }

    private func validate(entry: SetlistEntry, song: Song) -> SystemCheckResult {
        SetlistReadinessEvaluator(
            padReadiness: { [padTracks, padAssetStates, audioEngine] song in
                guard let padID = song.padTrackID else { return .noPad }
                guard let pad = padTracks.first(where: { $0.id == padID }) else {
                    return .blocked("The assigned pad is missing from the Pad Library.")
                }
                switch padAssetStates[padID] ?? audioEngine.padAssetState(for: pad) {
                case .available: return .ready
                case .preparing: return .blocked("\(pad.label) is still preparing.")
                case .externalVolumeUnavailable: return .blocked("Reconnect the volume containing \(pad.label).")
                case .permissionDenied: return .blocked("Locate \(pad.label) to grant file access.")
                case .missing: return .blocked("Locate the missing file for \(pad.label).")
                case .changed: return .blocked("Confirm the changed file for \(pad.label) with Locate File.")
                case .unsupportedOrProtected: return .blocked("\(pad.label) is unsupported or protected audio.")
                case .unreadable: return .blocked("\(pad.label) could not be read.")
                }
            },
            routingSnapshot: routingSnapshot,
            routingFailureMessage: audioRoutingFailureMessage,
            entries: activeSetlist.entries,
            song: { [songs] entry in songs.first { $0.id == entry.songID } }
        ).validate(entry: entry, song: song)
    }

}

extension AppStore {
    static func live(
        libraryStore: LocalLibraryStore = LocalLibraryStore(),
        audioEngineOverride: AudioControlling? = nil,
        audioHardwareMonitorOverride: AudioHardwareMonitoring? = nil,
        powerStateMonitorOverride: PowerStateMonitoring? = nil,
        midiControllerOverride: MIDIControlling? = nil
    ) -> AppStore {
        let audioEngine = audioEngineOverride ?? liveAudioEngine(libraryStore: libraryStore)
        let audioHardwareMonitor = audioHardwareMonitorOverride ?? CoreAudioHardwareMonitor()
        let powerStateMonitor = powerStateMonitorOverride ?? MacPowerStateMonitor()
        let midiController = midiControllerOverride ?? CoreMIDIController()

        do {
            if let snapshot = try libraryStore.loadLibrary() {
                guard !snapshot.songs.isEmpty else {
                    throw LibraryValidationError.unusableSetlist
                }

                return AppStore(
                    songs: snapshot.songs,
                    padPacks: snapshot.padPacks,
                    padTracks: snapshot.padTracks,
                    activeSetlist: snapshot.activeSetlist,
                    audioEngine: audioEngine,
                    libraryStore: libraryStore,
                    audioHardwareMonitor: audioHardwareMonitor,
                    powerStateMonitor: powerStateMonitor,
                    routingSettings: snapshot.routingSettings,
                    padVolume: snapshot.padVolume,
                    clickVolume: snapshot.clickVolume,
                    clickSettings: snapshot.clickSettings,
                    midiControllerSettings: snapshot.midiControllerSettings,
                    midiController: midiController,
                    persistenceStatus: "Library loaded"
                )
            }

            let snapshot = seedSnapshot()
            try libraryStore.saveLibrary(snapshot)
            return AppStore(
                songs: snapshot.songs,
                padPacks: snapshot.padPacks,
                padTracks: snapshot.padTracks,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: audioEngine,
                libraryStore: libraryStore,
                audioHardwareMonitor: audioHardwareMonitor,
                powerStateMonitor: powerStateMonitor,
                routingSettings: snapshot.routingSettings,
                padVolume: snapshot.padVolume,
                clickVolume: snapshot.clickVolume,
                clickSettings: snapshot.clickSettings,
                midiControllerSettings: snapshot.midiControllerSettings,
                midiController: midiController,
                persistenceStatus: "Seed library saved"
            )
        } catch let error as LibraryLoadError {
            let snapshot = seedSnapshot()
            let message = "\(error.localizedDescription) Your saved library is protected; this session is read-only."
            let store = AppStore(
                songs: snapshot.songs,
                padPacks: snapshot.padPacks,
                padTracks: snapshot.padTracks,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: audioEngine,
                libraryStore: nil,
                audioHardwareMonitor: audioHardwareMonitor,
                powerStateMonitor: powerStateMonitor,
                routingSettings: snapshot.routingSettings,
                padVolume: snapshot.padVolume,
                clickVolume: snapshot.clickVolume,
                clickSettings: snapshot.clickSettings,
                midiControllerSettings: snapshot.midiControllerSettings,
                midiController: midiController,
                persistenceStatus: message,
                persistenceWriteBlockReason: message
            )
            store.saveErrorPrompt = SaveErrorPrompt(message: message)
            return store
        } catch {
            let snapshot = seedSnapshot()
            let message = "Saved library could not be recovered: \(error.localizedDescription) This session is read-only so the library files remain available for recovery."
            let store = AppStore(
                songs: snapshot.songs,
                padPacks: snapshot.padPacks,
                padTracks: snapshot.padTracks,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: audioEngine,
                libraryStore: nil,
                audioHardwareMonitor: audioHardwareMonitor,
                powerStateMonitor: powerStateMonitor,
                routingSettings: snapshot.routingSettings,
                padVolume: snapshot.padVolume,
                clickVolume: snapshot.clickVolume,
                clickSettings: snapshot.clickSettings,
                midiControllerSettings: snapshot.midiControllerSettings,
                midiController: midiController,
                persistenceStatus: message,
                persistenceWriteBlockReason: message
            )
            store.saveErrorPrompt = SaveErrorPrompt(message: message)
            return store
        }
    }

    private static func liveAudioEngine(libraryStore: LocalLibraryStore) -> SustainAudioEngine {
        SustainAudioEngine()
    }

    static func preview(
        audioEngine: AudioControlling = SilentAudioEngine(),
        libraryStore: LocalLibraryStore? = nil,
        audioRoutingProvider: AudioRoutingProviding = StaticAudioRoutingProvider(snapshotValue: .previewDefault),
        audioHardwareMonitor: AudioHardwareMonitoring = NoopAudioHardwareMonitor(),
        powerStateMonitor: PowerStateMonitoring = NoopPowerStateMonitor(),
        midiController: MIDIControlling = NoopMIDIController(),
        externalAudioReferencer: any ExternalAudioReferencing = ExternalAudioReferenceService(),
        countoffDurationMultiplier: Double = 0
    ) -> AppStore {
        let snapshot = seedSnapshot()
        return AppStore(
            songs: snapshot.songs,
            padPacks: snapshot.padPacks,
            padTracks: snapshot.padTracks,
            activeSetlist: snapshot.activeSetlist,
            audioEngine: audioEngine,
            libraryStore: libraryStore,
            audioRoutingProvider: audioRoutingProvider,
            audioHardwareMonitor: audioHardwareMonitor,
            powerStateMonitor: powerStateMonitor,
            routingSettings: snapshot.routingSettings,
            padVolume: snapshot.padVolume,
            clickVolume: snapshot.clickVolume,
            clickSettings: snapshot.clickSettings,
            midiControllerSettings: snapshot.midiControllerSettings,
            midiController: midiController,
            externalAudioReferencer: externalAudioReferencer,
            countoffDurationMultiplier: countoffDurationMultiplier
        )
    }

    static func seedSnapshot() -> LibrarySnapshot {
        let bundledPads = PadPack.bundled

        let songs = [
            Song(title: "Goodness of God", defaultKey: .g, defaultBPM: 72, timeSignature: .fourFour, padPack: bundledPads),
            Song(title: "King of Kings", defaultKey: .d, defaultBPM: 68, timeSignature: .fourFour, padPack: bundledPads),
            Song(title: "Holy Forever", defaultKey: .a, defaultBPM: 76, timeSignature: .fourFour, padPack: bundledPads)
        ]

        let entries = [
            SetlistEntry(songID: songs[0].id),
            SetlistEntry(songID: songs[1].id),
            SetlistEntry(songID: songs[2].id)
        ]

        return LibrarySnapshot(
            songs: songs,
            padPacks: [bundledPads],
            activeSetlist: Setlist(title: "Sunday Morning", entries: entries)
        )
    }

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func normalizedIncludedBundleSongs(_ songs: [Song]) -> [Song] {
    songs.map { song in
        Song(
            id: song.id,
            title: song.title,
            defaultKey: song.defaultKey,
            defaultBPM: song.defaultBPM,
            timeSignature: song.timeSignature,
            clickSubdivision: song.clickSubdivision,
            padPack: .bundled,
            padTrackID: song.padTrackID
        )
    }
}
