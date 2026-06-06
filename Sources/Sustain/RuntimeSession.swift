import Combine
import CoreAudio
import Foundation

enum AppScreen: String, CaseIterable, Identifiable {
    case live = "Live Service"
    case rehearse = "Rehearse"
    case songs = "Song Library"
    case setlist = "Setlist"
    case audio = "Audio Setup"
    case check = "System Check"

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

@MainActor
final class AppStore: ObservableObject {
    @Published var selectedScreen: AppScreen = .live
    @Published var songs: [Song]
    @Published var activeSetlist: Setlist
    @Published var runtime = RuntimeSession()
    @Published var rehearse = RehearseSession()
    @Published var systemCheck = SystemCheckResult.notRun
    @Published var audioStatus: String
    @Published var persistenceStatus: String
    @Published var routingSettings: AudioRoutingSettings
    @Published var routingSnapshot: AudioRoutingSnapshot

    private let audioEngine: AudioControlling
    private let libraryStore: LocalLibraryStore?
    private let audioRoutingProvider: AudioRoutingProviding
    private let audioHardwareMonitor: AudioHardwareMonitoring
    private let countoffDurationMultiplier: Double
    private var clickStateTask: Task<Void, Never>?
    private var audioRoutingFailureMessage: String?

    init(
        songs: [Song],
        activeSetlist: Setlist,
        audioEngine: AudioControlling = SilentAudioEngine(),
        libraryStore: LocalLibraryStore? = nil,
        audioRoutingProvider: AudioRoutingProviding = CoreAudioRoutingProvider(),
        audioHardwareMonitor: AudioHardwareMonitoring = NoopAudioHardwareMonitor(),
        routingSettings: AudioRoutingSettings = .default,
        persistenceStatus: String = "Using seed library",
        countoffDurationMultiplier: Double = 1.0
    ) {
        self.songs = songs
        self.activeSetlist = activeSetlist
        self.audioEngine = audioEngine
        self.libraryStore = libraryStore
        self.audioRoutingProvider = audioRoutingProvider
        self.audioHardwareMonitor = audioHardwareMonitor
        self.routingSettings = routingSettings
        self.audioStatus = audioEngine.statusSummary
        self.persistenceStatus = persistenceStatus
        self.routingSnapshot = audioRoutingProvider.snapshot(settings: routingSettings)
        self.countoffDurationMultiplier = countoffDurationMultiplier
        runtime.cuedEntryID = activeSetlist.entries.first?.id
        configureAudioRouting()
        audioHardwareMonitor.start { [weak self] in
            self?.handleAudioHardwareChanged()
        }
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
    }

    func cue(entryID: SetlistEntry.ID) {
        guard let entry = entry(id: entryID), let song = song(for: entry) else {
            runtime.lastMessage = "Could not cue song"
            return
        }

        runtime.cuedEntryID = entryID
        runtime.lastMessage = "Cued \(song.title)"
    }

    func startCuedSong() {
        guard let cuedEntry, let cuedSong = song(for: cuedEntry) else {
            runtime.lastMessage = "No song cued"
            return
        }

        refreshRoutingSnapshot()
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

            try audioEngine.startClick(bpm: bpm, timeSignature: cuedSong.timeSignature, includesCountoff: true)
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
            try audioEngine.startClick(bpm: bpm, timeSignature: song.timeSignature, includesCountoff: true)
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

        do {
            try audioEngine.startClick(
                bpm: rehearse.bpm,
                timeSignature: rehearse.timeSignature,
                includesCountoff: rehearse.countoffEnabled
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

        do {
            clickStateTask?.cancel()
            try audioEngine.startClick(
                bpm: rehearse.bpm,
                timeSignature: rehearse.timeSignature,
                includesCountoff: false
            )
            rehearse.clickState = .playing
            rehearse.lastMessage = "Click updated to \(rehearse.bpm) BPM"
            refreshAudioStatus()
        } catch {
            rehearse.lastMessage = error.localizedDescription
            refreshAudioStatus()
        }
    }

    func setRehearseTimeSignature(_ timeSignature: TimeSignature) {
        rehearse.timeSignature = timeSignature

        guard rehearse.clickState != .off else { return }
        setRehearseBPM(rehearse.bpm)
    }

    func setRehearseCountoffEnabled(_ isEnabled: Bool) {
        rehearse.countoffEnabled = isEnabled
        rehearse.lastMessage = isEnabled ? "Countoff enabled" : "Countoff disabled"
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
    }

    func updateRouting(padOutputID: AudioDeviceID?, clickOutputID: AudioDeviceID?) {
        routingSettings = AudioRoutingSettings(
            padOutputID: padOutputID,
            clickOutputID: clickOutputID
        )
        routingSnapshot = audioRoutingProvider.snapshot(settings: routingSettings)
        configureAudioRouting()
        saveLibrary()
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

    private func beginCountoff(
        for entryID: SetlistEntry.ID,
        songTitle: String,
        bpm: Int,
        timeSignature: TimeSignature
    ) {
        clickStateTask?.cancel()
        runtime.clickState = .countoff

        let duration = countoffDuration(bpm: bpm, timeSignature: timeSignature)
        clickStateTask = Task { @MainActor in
            let nanoseconds = UInt64(max(0, duration * countoffDurationMultiplier) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard !Task.isCancelled,
                  runtime.playingEntryID == entryID,
                  runtime.clickState == .countoff else {
                return
            }

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

    private func countoffDuration(bpm: Int, timeSignature: TimeSignature) -> TimeInterval {
        guard bpm > 0 else { return 0 }
        return (60.0 / Double(bpm)) * Double(max(1, timeSignature.beatsPerMeasure))
    }

    private func saveLibrary() {
        guard let libraryStore else {
            persistenceStatus = "Seed library is not persisted"
            return
        }

        do {
            try libraryStore.saveLibrary(
                LibrarySnapshot(
                    songs: songs,
                    activeSetlist: activeSetlist,
                    routingSettings: routingSettings
                )
            )
            persistenceStatus = "Library saved"
        } catch {
            persistenceStatus = "Library save failed: \(error.localizedDescription)"
        }
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

    private func refreshAudioStatus() {
        audioStatus = audioEngine.statusSummary
    }

    private func refreshRoutingSnapshot() {
        routingSnapshot = audioRoutingProvider.snapshot(settings: routingSettings)
    }

    private func handleAudioHardwareChanged() {
        let previousSnapshot = routingSnapshot
        refreshRoutingSnapshot()
        guard routingSnapshot != previousSnapshot else { return }

        if let cuedEntry, let cuedSong = song(for: cuedEntry) {
            systemCheck = validate(entry: cuedEntry, song: cuedSong)
        }

        guard !routingSnapshot.missingSelectionMessages.isEmpty else {
            if runtime.playbackPhase == .noSongPlaying {
                configureAudioRouting()
            }
            runtime.lastMessage = "Audio devices updated"
            return
        }

        clickStateTask?.cancel()
        audioEngine.stopAll()
        runtime.clickState = .off
        runtime.padState = .off
        runtime.playingEntryID = nil
        runtime.playbackPhase = .noSongPlaying
        rehearse.clickState = .off
        rehearse.padState = .off
        rehearse.lastMessage = routingSnapshot.missingSelectionMessages.joined(separator: " ")
        runtime.lastMessage = routingSnapshot.missingSelectionMessages.joined(separator: " ")
        refreshAudioStatus()
    }

    private func validate(entry: SetlistEntry, song: Song) -> SystemCheckResult {
        var blockingMessages: [String] = []
        var warnings: [String] = []
        let key = entry.resolvedKey(for: song)
        let bpm = entry.resolvedBPM(for: song)

        if bpm <= 0 {
            blockingMessages.append("\(song.title) needs a valid BPM.")
        }

        if !audioEngine.hasPadAsset(for: song.padPack, key: key) {
            blockingMessages.append(audioEngine.padAssetStatus(for: song.padPack, key: key))
        }

        if routingSnapshot.outputs.isEmpty {
            blockingMessages.append("No output audio device is available.")
        } else if let audioRoutingFailureMessage {
            blockingMessages.append(audioRoutingFailureMessage)
        } else if !routingSnapshot.missingSelectionMessages.isEmpty {
            blockingMessages.append(contentsOf: routingSnapshot.missingSelectionMessages)
        } else if let warning = routingSnapshot.warning {
            warnings.append(warning)
        }

        var messages = blockingMessages
        if messages.isEmpty {
            messages.append("Ready for \(song.title) in \(key.rawValue) at \(bpm) BPM.")
        }
        messages.append(contentsOf: warnings.map { "Warning: \($0)" })

        return SystemCheckResult(
            canStartPlayback: blockingMessages.isEmpty,
            messages: messages,
            warnings: warnings
        )
    }
}

extension AppStore {
    static func live() -> AppStore {
        let libraryStore = LocalLibraryStore()

        do {
            if let snapshot = try libraryStore.loadLibrary() {
                return AppStore(
                    songs: snapshot.songs,
                    activeSetlist: snapshot.activeSetlist,
                    audioEngine: SustainAudioEngine(),
                    libraryStore: libraryStore,
                    audioHardwareMonitor: CoreAudioHardwareMonitor(),
                    routingSettings: snapshot.routingSettings,
                    persistenceStatus: "Library loaded"
                )
            }

            let snapshot = seedSnapshot()
            try libraryStore.saveLibrary(snapshot)
            return AppStore(
                songs: snapshot.songs,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: SustainAudioEngine(),
                libraryStore: libraryStore,
                audioHardwareMonitor: CoreAudioHardwareMonitor(),
                routingSettings: snapshot.routingSettings,
                persistenceStatus: "Seed library saved"
            )
        } catch {
            let snapshot = seedSnapshot()
            return AppStore(
                songs: snapshot.songs,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: SustainAudioEngine(),
                libraryStore: libraryStore,
                audioHardwareMonitor: CoreAudioHardwareMonitor(),
                routingSettings: snapshot.routingSettings,
                persistenceStatus: "Using seed library: \(error.localizedDescription)"
            )
        }
    }

    static func preview(
        audioEngine: AudioControlling = SilentAudioEngine(),
        libraryStore: LocalLibraryStore? = nil,
        audioRoutingProvider: AudioRoutingProviding = StaticAudioRoutingProvider(snapshotValue: .previewDefault),
        audioHardwareMonitor: AudioHardwareMonitoring = NoopAudioHardwareMonitor(),
        countoffDurationMultiplier: Double = 0
    ) -> AppStore {
        let snapshot = seedSnapshot()
        return AppStore(
            songs: snapshot.songs,
            activeSetlist: snapshot.activeSetlist,
            audioEngine: audioEngine,
            libraryStore: libraryStore,
            audioRoutingProvider: audioRoutingProvider,
            audioHardwareMonitor: audioHardwareMonitor,
            routingSettings: snapshot.routingSettings,
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
            activeSetlist: Setlist(title: "Sunday Morning", entries: entries)
        )
    }
}
