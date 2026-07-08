import CoreAudio
import Foundation
import Observation

enum AppScreen: String, CaseIterable, Identifiable {
    case live = "Live Service"
    case rehearse = "Rehearse"
    case songs = "Song Library"

    var id: String { rawValue }
}

enum PlaybackPhase: String {
    case noSongPlaying = "No Song Playing"
    case songStarting = "Song Starting"
    case songPlaying = "Song Playing"
}

enum PadPlaybackState: String {
    case off = "Off"
    case fadingIn = "Fading In"
    case playing = "Playing"
    case fadingOut = "Fading Out"
}

enum ClickPlaybackState: String {
    case off = "Off"
    case countoff = "Countoff"
    case playing = "Playing"
}

struct RuntimeSession: Equatable {
    var playingEntryID: SetlistEntry.ID?
    var cuedEntryID: SetlistEntry.ID?
    var playbackPhase: PlaybackPhase = .noSongPlaying
    var padState: PadPlaybackState = .off
    var clickState: ClickPlaybackState = .off
    var countoffBeat: Int?
    var countoffTotal: Int?
    var lastMessage = "Ready"
}

struct RehearseSession: Equatable {
    var selectedKey: MusicalKey = .c
    var padState: PadPlaybackState = .off
    var clickState: ClickPlaybackState = .off
    var bpm: Int = 72
    var timeSignature: TimeSignature = .fourFour
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

@MainActor
@Observable
final class AppStore {
    // UI state — observed with property-level granularity, so a view re-renders only for the
    // exact fields it reads. (Migrated off ObservableObject/@Published, whose object-level
    // invalidation re-rendered every view on any change — the root of the Live layout flip and
    // a latent re-render storm; see docs/13, docs/14.)
    var selectedScreen: AppScreen = .live
    var songs: [Song]
    var padPacks: [PadPack]
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
    @ObservationIgnored private var clickStateTask: Task<Void, Never>?
    @ObservationIgnored private var audioRoutingFailureMessage: String?

    init(
        songs: [Song],
        padPacks: [PadPack]? = nil,
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
        persistenceStatus: String = "Using seed library",
        countoffDurationMultiplier: Double = 1.0
    ) {
        self.songs = normalizedIncludedBundleSongs(songs)
        self.padPacks = [PadPack.bundled]
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
    }

    var playingEntry: SetlistEntry? {
        entry(id: runtime.playingEntryID)
    }

    var cuedEntry: SetlistEntry? {
        entry(id: runtime.cuedEntryID)
    }

    func song(for entry: SetlistEntry?) -> Song? {
        guard let entry else { return nil }
        return songs.first { $0.id == entry.songID }
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
        runtime.lastMessage = "Cued previous song"
        preloadCuedPad()
    }

    func cue(entryID: SetlistEntry.ID) {
        guard let entry = entry(id: entryID), let song = song(for: entry) else {
            runtime.lastMessage = "Could not cue song"
            return
        }

        runtime.cuedEntryID = entryID
        runtime.lastMessage = "Cued \(song.title)"
        preloadCuedPad()
        refreshReadiness()
    }

    func startCuedSong() {
        guard let cuedEntry, let cuedSong = song(for: cuedEntry) else {
            runtime.lastMessage = "No song cued"
            return
        }

        prepareCurrentAudioRoutingForStart()
        let validation = validate(entry: cuedEntry, song: cuedSong)
        guard validation.canStartPlayback else {
            systemCheck = validation
            runtime.lastMessage = "Playback blocked by system check"
            return
        }

        let key = cuedEntry.resolvedKey(for: cuedSong)
        let bpm = cuedEntry.resolvedBPM(for: cuedSong)
        let hadPlayingEntry = runtime.playingEntryID != nil

        do {
            stopRehearsalForLiveSession()
            runtime.playbackPhase = .songStarting

            if hadPlayingEntry {
                clickStateTask?.cancel()
                audioEngine.stopClick()
                runtime.clickState = .off
                runtime.padState = .fadingOut
            }

            try audioEngine.startClick(
                bpm: bpm,
                timeSignature: cuedSong.timeSignature,
                includesCountoff: true,
                settings: clickSettings
            )
            try audioEngine.startPad(for: key, padPack: cuedSong.padPack)
            runtime.padState = .playing
            runtime.playingEntryID = cuedEntry.id
            runtime.playbackPhase = .songPlaying
            beginCountoff(for: cuedEntry.id, songTitle: cuedSong.title, bpm: bpm, timeSignature: cuedSong.timeSignature)
            runtime.lastMessage = "Countoff started for \(cuedSong.title)"
            refreshAudioStatus()
        } catch {
            audioEngine.stopClick()
            if hadPlayingEntry {
                runtime.padState = .playing
                runtime.playbackPhase = .songPlaying
            } else {
                audioEngine.stopPad()
                runtime.padState = .off
                runtime.playbackPhase = .noSongPlaying
            }
            runtime.lastMessage = error.localizedDescription
            refreshAudioStatus()
        }
    }

    func stop() {
        clickStateTask?.cancel()
        clearCountoff()
        audioEngine.stopClick()
        runtime.clickState = .off
        runtime.padState = .fadingOut
        runtime.playingEntryID = nil
        audioEngine.stopPad()
        runtime.padState = .off
        runtime.playbackPhase = .noSongPlaying
        runtime.lastMessage = "Stopped"
        refreshAudioStatus()
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

        let bpm = playingEntry.resolvedBPM(for: song)

        do {
            try audioEngine.startClick(
                bpm: bpm,
                timeSignature: song.timeSignature,
                includesCountoff: true,
                settings: clickSettings
            )
            beginCountoff(for: playingEntry.id, songTitle: song.title, bpm: bpm, timeSignature: song.timeSignature)
            runtime.lastMessage = "Countoff started for \(song.title)"
            refreshAudioStatus()
        } catch {
            runtime.lastMessage = error.localizedDescription
            refreshAudioStatus()
        }
    }

    func stopClick() {
        clickStateTask?.cancel()
        clearCountoff()
        audioEngine.stopClick()
        runtime.clickState = .off
        runtime.lastMessage = "Click stopped"
        refreshAudioStatus()
    }

    func startPad() {
        guard let playingEntry, let song = song(for: playingEntry) else {
            runtime.lastMessage = "Start a song before starting pad"
            return
        }

        do {
            try audioEngine.startPad(for: playingEntry.resolvedKey(for: song), padPack: song.padPack)
            runtime.padState = .playing
            runtime.lastMessage = "Pad started"
            refreshAudioStatus()
        } catch {
            runtime.lastMessage = error.localizedDescription
            refreshAudioStatus()
        }
    }

    func stopPad() {
        audioEngine.stopPad()
        runtime.padState = .off
        runtime.lastMessage = "Pad stopped"
        refreshAudioStatus()
    }

    func startRehearsePad(key: MusicalKey) {
        stopLiveSessionForRehearsal()
        rehearse.selectedKey = key
        prepareCurrentAudioRoutingForStart()

        do {
            try audioEngine.startPad(for: key, padPack: .bundled)
            rehearse.padState = .playing
            rehearse.lastMessage = "Pad playing in \(key.rawValue)"
            refreshAudioStatus()
        } catch {
            rehearse.lastMessage = error.localizedDescription
            refreshAudioStatus()
        }
    }

    func stopRehearsePad() {
        audioEngine.stopPad()
        rehearse.padState = .off
        rehearse.lastMessage = "Pad stopped"
        refreshAudioStatus()
    }

    func startRehearseClick() {
        stopLiveSessionForRehearsal()
        prepareCurrentAudioRoutingForStart()

        do {
            try audioEngine.startClick(
                bpm: rehearse.bpm,
                timeSignature: rehearse.timeSignature,
                includesCountoff: rehearse.countoffEnabled,
                settings: clickSettings
            )

            if rehearse.countoffEnabled {
                beginRehearseCountoff()
                rehearse.lastMessage = "Countoff started at \(rehearse.bpm) BPM"
            } else {
                rehearse.clickState = .playing
                rehearse.lastMessage = "Click playing at \(rehearse.bpm) BPM"
            }
            refreshAudioStatus()
        } catch {
            rehearse.lastMessage = error.localizedDescription
            refreshAudioStatus()
        }
    }

    func stopRehearseClick() {
        clickStateTask?.cancel()
        audioEngine.stopClick()
        rehearse.clickState = .off
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

    func setRehearseTimeSignature(_ timeSignature: TimeSignature) {
        rehearse.timeSignature = timeSignature

        guard rehearse.clickState != .off else { return }
        restartActiveRehearseClickIfNeeded(message: "Click updated to \(timeSignature.description)")
    }

    func setRehearseCountoffEnabled(_ isEnabled: Bool) {
        rehearse.countoffEnabled = isEnabled
        rehearse.lastMessage = isEnabled ? "Countoff enabled" : "Countoff disabled"
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
        rehearse.lastMessage = "\(countoffSound.rawValue) countoff selected"
        runtime.lastMessage = "\(countoffSound.rawValue) countoff selected"
        saveLibrary()
    }

    private func restartActiveRehearseClickIfNeeded(message: String) {
        guard rehearse.clickState != .off else { return }

        do {
            clickStateTask?.cancel()
            try audioEngine.startClick(
                bpm: rehearse.bpm,
                timeSignature: rehearse.timeSignature,
                includesCountoff: false,
                settings: clickSettings
            )
            rehearse.clickState = .playing
            rehearse.lastMessage = message
            refreshAudioStatus()
        } catch {
            rehearse.lastMessage = error.localizedDescription
            refreshAudioStatus()
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

    func updateSong(
        _ songID: Song.ID,
        title: String,
        defaultKey: MusicalKey,
        defaultBPM: Int,
        timeSignature: TimeSignature,
        padPackID: PadPack.ID
    ) {
        guard let songIndex = songs.firstIndex(where: { $0.id == songID }) else {
            persistenceStatus = "Could not update song"
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        songs[songIndex] = Song(
            id: songID,
            title: trimmedTitle.isEmpty ? songs[songIndex].title : trimmedTitle,
            defaultKey: defaultKey,
            defaultBPM: min(220, max(40, defaultBPM)),
            timeSignature: timeSignature,
            padPack: .bundled
        )
        saveLibrary()
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
        if runtime.cuedEntryID == removedEntry.id {
            runtime.cuedEntryID = activeSetlist.entries[safe: index]?.id ?? activeSetlist.entries.last?.id
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

    func clearSetlist() {
        guard runtime.playbackPhase == .noSongPlaying else {
            runtime.lastMessage = "Stop playback before clearing the setlist"
            return
        }

        activeSetlist.entries.removeAll()
        runtime.cuedEntryID = nil
        runtime.lastMessage = "Cleared setlist"
        saveLibrary()
    }

    func updateEntry(
        _ entryID: SetlistEntry.ID,
        keyOverride: MusicalKey?,
        bpmOverride: Int?
    ) {
        guard let index = activeSetlist.entries.firstIndex(where: { $0.id == entryID }) else {
            runtime.lastMessage = "Could not update setlist entry"
            return
        }

        activeSetlist.entries[index].keyOverride = keyOverride
        activeSetlist.entries[index].bpmOverride = bpmOverride
        saveLibrary()
        preloadCuedPad()
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
        guard runtime.playbackPhase != .noSongPlaying || rehearse.padState != .off || rehearse.clickState != .off else {
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
        timeSignature: TimeSignature
    ) {
        clickStateTask?.cancel()
        runtime.clickState = .countoff

        let beats = max(1, timeSignature.beatsPerMeasure)
        let secondsPerBeat = bpm > 0 ? 60.0 / Double(bpm) : 0
        runtime.countoffTotal = beats
        clickStateTask = Task { @MainActor in
            let perBeat = UInt64(max(0, secondsPerBeat * countoffDurationMultiplier) * 1_000_000_000)
            for beat in 1...beats {
                guard !Task.isCancelled,
                      runtime.playingEntryID == entryID,
                      runtime.clickState == .countoff else {
                    return
                }
                runtime.countoffBeat = beat
                try? await Task.sleep(nanoseconds: perBeat)
            }

            guard !Task.isCancelled,
                  runtime.playingEntryID == entryID,
                  runtime.clickState == .countoff else {
                return
            }

            runtime.countoffBeat = nil
            runtime.countoffTotal = nil
            runtime.clickState = .playing
            runtime.lastMessage = "Click playing for \(songTitle)"
        }
    }

    private func beginRehearseCountoff() {
        clickStateTask?.cancel()
        rehearse.clickState = .countoff

        let duration = countoffDuration(bpm: rehearse.bpm, timeSignature: rehearse.timeSignature)
        clickStateTask = Task { @MainActor in
            let nanoseconds = UInt64(max(0, duration * countoffDurationMultiplier) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard !Task.isCancelled,
                  rehearse.clickState == .countoff else {
                return
            }

            rehearse.clickState = .playing
            rehearse.lastMessage = "Click playing at \(rehearse.bpm) BPM"
        }
    }

    private func stopLiveSessionForRehearsal() {
        guard runtime.playbackPhase != .noSongPlaying || runtime.clickState != .off else { return }

        clickStateTask?.cancel()
        clearCountoff()
        if runtime.clickState != .off {
            audioEngine.stopClick()
        }
        if runtime.padState != .off {
            audioEngine.stopPad()
        }
        runtime.clickState = .off
        runtime.padState = .off
        runtime.playingEntryID = nil
        runtime.playbackPhase = .noSongPlaying
        runtime.lastMessage = "Live playback stopped for rehearsal"
    }

    private func stopRehearsalForLiveSession() {
        clickStateTask?.cancel()

        if rehearse.clickState != .off {
            audioEngine.stopClick()
        }
        if rehearse.padState != .off {
            audioEngine.stopPad()
        }

        rehearse.clickState = .off
        rehearse.padState = .off
        rehearse.lastMessage = "Rehearsal stopped"
    }

    private func clearCountoff() {
        runtime.countoffBeat = nil
        runtime.countoffTotal = nil
    }

    private func preloadCuedPad() {
        guard let cuedEntry, let song = song(for: cuedEntry) else { return }
        audioEngine.preloadPad(for: cuedEntry.resolvedKey(for: song), padPack: song.padPack)
    }

    private func countoffDuration(bpm: Int, timeSignature: TimeSignature) -> TimeInterval {
        guard bpm > 0 else { return 0 }
        return (60.0 / Double(bpm)) * Double(max(1, timeSignature.beatsPerMeasure))
    }

    private func saveLibrary() {
        guard let libraryStore else {
            persistenceStatus = "Seed library is not persisted"
            return
        }

        let snapshot = LibrarySnapshot(
            songs: songs,
            padPacks: padPacks,
            activeSetlist: activeSetlist,
            routingSettings: routingSettings,
            padVolume: padVolume,
            clickVolume: clickVolume,
            clickSettings: clickSettings
        )

        // Retry once — most write failures are transient (a brief lock, momentary I/O hiccup).
        for attempt in 1...2 {
            do {
                try libraryStore.saveLibrary(snapshot)
                persistenceStatus = "Library saved"
                hasUnsavedChanges = false
                saveErrorPrompt = nil
                return
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
    }

    /// Re-attempt a save the user asked to retry from the save-failure alert.
    func retryFailedSave() {
        saveErrorPrompt = nil
        saveLibrary()
    }

    /// Flush unsaved work — call on app quit / scene backgrounding as a last-chance backstop.
    func flushPendingSaveIfNeeded() {
        guard hasUnsavedChanges else { return }
        saveLibrary()
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
        handleAudioHardwareChanged(
            forceValidation: true,
            readyMessage: "System woke. Audio routing checked."
        )
    }

    private func stopAudioAfterHardwareChange(message: String) {
        clickStateTask?.cancel()
        clearCountoff()
        audioEngine.stopAll()
        runtime.clickState = .off
        runtime.padState = .off
        runtime.playingEntryID = nil
        runtime.playbackPhase = .noSongPlaying
        rehearse.clickState = .off
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
            hasPadAsset: { [audioEngine] pack, key in audioEngine.hasPadAsset(for: pack, key: key) },
            padAssetStatus: { [audioEngine] pack, key in audioEngine.padAssetStatus(for: pack, key: key) },
            routingSnapshot: routingSnapshot,
            routingFailureMessage: audioRoutingFailureMessage,
            entries: activeSetlist.entries,
            song: { [songs] entry in songs.first { $0.id == entry.songID } }
        ).validate(entry: entry, song: song)
    }

}

extension AppStore {
    static func live() -> AppStore {
        let libraryStore = LocalLibraryStore()

        do {
            if let snapshot = try libraryStore.loadLibrary() {
                guard snapshot.hasUsableSetlist else {
                    throw LibraryValidationError.unusableSetlist
                }

                return AppStore(
                    songs: snapshot.songs,
                    padPacks: snapshot.padPacks,
                    activeSetlist: snapshot.activeSetlist,
                    audioEngine: liveAudioEngine(libraryStore: libraryStore),
                    libraryStore: libraryStore,
                    audioHardwareMonitor: CoreAudioHardwareMonitor(),
                    powerStateMonitor: MacPowerStateMonitor(),
                    routingSettings: snapshot.routingSettings,
                    padVolume: snapshot.padVolume,
                    clickVolume: snapshot.clickVolume,
                    clickSettings: snapshot.clickSettings,
                    persistenceStatus: "Library loaded"
                )
            }

            let snapshot = seedSnapshot()
            try libraryStore.saveLibrary(snapshot)
            return AppStore(
                songs: snapshot.songs,
                padPacks: snapshot.padPacks,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: liveAudioEngine(libraryStore: libraryStore),
                libraryStore: libraryStore,
                audioHardwareMonitor: CoreAudioHardwareMonitor(),
                powerStateMonitor: MacPowerStateMonitor(),
                routingSettings: snapshot.routingSettings,
                padVolume: snapshot.padVolume,
                clickVolume: snapshot.clickVolume,
                clickSettings: snapshot.clickSettings,
                persistenceStatus: "Seed library saved"
            )
        } catch {
            let snapshot = seedSnapshot()
            return AppStore(
                songs: snapshot.songs,
                padPacks: snapshot.padPacks,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: liveAudioEngine(libraryStore: libraryStore),
                libraryStore: libraryStore,
                audioHardwareMonitor: CoreAudioHardwareMonitor(),
                powerStateMonitor: MacPowerStateMonitor(),
                routingSettings: snapshot.routingSettings,
                padVolume: snapshot.padVolume,
                clickVolume: snapshot.clickVolume,
                clickSettings: snapshot.clickSettings,
                persistenceStatus: "Using seed library: \(error.localizedDescription)"
            )
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
        countoffDurationMultiplier: Double = 0
    ) -> AppStore {
        let snapshot = seedSnapshot()
        return AppStore(
            songs: snapshot.songs,
            padPacks: snapshot.padPacks,
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
            countoffDurationMultiplier: countoffDurationMultiplier
        )
    }

    static func seedSnapshot() -> LibrarySnapshot {
        let bundledPads = PadPack.bundled

        let songs = [
            Song(title: "Goodness of God", defaultKey: .g, defaultBPM: 72, timeSignature: .sixEight, padPack: bundledPads),
            Song(title: "King of Kings", defaultKey: .d, defaultBPM: 68, timeSignature: .fourFour, padPack: bundledPads),
            Song(title: "Holy Forever", defaultKey: .a, defaultBPM: 76, timeSignature: .fourFour, padPack: bundledPads)
        ]

        let entries = [
            SetlistEntry(songID: songs[0].id),
            SetlistEntry(songID: songs[1].id, keyOverride: .e),
            SetlistEntry(songID: songs[2].id, keyOverride: .bb, bpmOverride: 74)
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
            padPack: .bundled
        )
    }
}
