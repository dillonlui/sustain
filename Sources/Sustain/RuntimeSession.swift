import Combine
import Foundation

enum AppScreen: String, CaseIterable, Identifiable {
    case live = "Live Service"
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
    @Published var systemCheck = SystemCheckResult.notRun
    @Published var audioStatus: String
    @Published var persistenceStatus: String
    @Published var routingSnapshot: AudioRoutingSnapshot

    private let audioEngine: AudioControlling
    private let libraryStore: LocalLibraryStore?
    private let audioRoutingProvider: AudioRoutingProviding
    private let countoffDurationMultiplier: Double
    private var clickStateTask: Task<Void, Never>?

    init(
        songs: [Song],
        activeSetlist: Setlist,
        audioEngine: AudioControlling = SilentAudioEngine(),
        libraryStore: LocalLibraryStore? = nil,
        audioRoutingProvider: AudioRoutingProviding = CoreAudioRoutingProvider(),
        persistenceStatus: String = "Using seed library",
        countoffDurationMultiplier: Double = 1.0
    ) {
        self.songs = songs
        self.activeSetlist = activeSetlist
        self.audioEngine = audioEngine
        self.libraryStore = libraryStore
        self.audioRoutingProvider = audioRoutingProvider
        self.audioStatus = audioEngine.statusSummary
        self.persistenceStatus = persistenceStatus
        self.routingSnapshot = audioRoutingProvider.snapshot()
        self.countoffDurationMultiplier = countoffDurationMultiplier
        runtime.cuedEntryID = activeSetlist.entries.first?.id
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

        let validation = validate(entry: cuedEntry, song: cuedSong)
        guard validation.canStartPlayback else {
            systemCheck = validation
            runtime.lastMessage = "Playback blocked by system check"
            return
        }

        let key = cuedEntry.resolvedKey(for: cuedSong)
        let bpm = cuedEntry.resolvedBPM(for: cuedSong)

        do {
            runtime.playbackPhase = .songStarting

            if runtime.playingEntryID != nil {
                clickStateTask?.cancel()
                audioEngine.stopClick()
                runtime.clickState = .off
                runtime.padState = .fadingOut
            }

            try audioEngine.startPad(for: key, padPack: cuedSong.padPack)
            runtime.padState = .playing

            try audioEngine.startClick(bpm: bpm, timeSignature: cuedSong.timeSignature)
            runtime.playingEntryID = cuedEntry.id
            runtime.playbackPhase = .songPlaying
            beginCountoff(for: cuedEntry.id, songTitle: cuedSong.title, bpm: bpm, timeSignature: cuedSong.timeSignature)
            runtime.lastMessage = "Countoff started for \(cuedSong.title)"
            refreshAudioStatus()
        } catch {
            audioEngine.stopClick()
            if runtime.playingEntryID == nil {
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
            try audioEngine.startClick(bpm: bpm, timeSignature: song.timeSignature)
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

    func runSystemCheck() {
        audioEngine.prepare()
        routingSnapshot = audioRoutingProvider.snapshot()
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
            try libraryStore.saveLibrary(LibrarySnapshot(songs: songs, activeSetlist: activeSetlist))
            persistenceStatus = "Library saved"
        } catch {
            persistenceStatus = "Library save failed: \(error.localizedDescription)"
        }
    }

    private func refreshAudioStatus() {
        audioStatus = audioEngine.statusSummary
    }

    private func validate(entry: SetlistEntry, song: Song) -> SystemCheckResult {
        var blockingMessages: [String] = []
        var warnings: [String] = []
        let key = entry.resolvedKey(for: song)
        let bpm = entry.resolvedBPM(for: song)

        if bpm <= 0 {
            blockingMessages.append("\(song.title) needs a valid BPM.")
        }

        if !song.padPack.supports(key) {
            blockingMessages.append("\(song.padPack.name) does not include a pad for \(key.rawValue).")
        }

        if !audioEngine.hasPadAsset(for: song.padPack, key: key) {
            blockingMessages.append(audioEngine.padAssetStatus(for: song.padPack, key: key))
        }

        if routingSnapshot.outputs.isEmpty {
            blockingMessages.append("No output audio device is available.")
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
                persistenceStatus: "Seed library saved"
            )
        } catch {
            let snapshot = seedSnapshot()
            return AppStore(
                songs: snapshot.songs,
                activeSetlist: snapshot.activeSetlist,
                audioEngine: SustainAudioEngine(),
                libraryStore: libraryStore,
                persistenceStatus: "Using seed library: \(error.localizedDescription)"
            )
        }
    }

    static func preview(
        audioEngine: AudioControlling = SilentAudioEngine(),
        libraryStore: LocalLibraryStore? = nil,
        audioRoutingProvider: AudioRoutingProviding = StaticAudioRoutingProvider(snapshotValue: .previewDefault),
        countoffDurationMultiplier: Double = 0
    ) -> AppStore {
        let snapshot = seedSnapshot()
        return AppStore(
            songs: snapshot.songs,
            activeSetlist: snapshot.activeSetlist,
            audioEngine: audioEngine,
            libraryStore: libraryStore,
            audioRoutingProvider: audioRoutingProvider,
            countoffDurationMultiplier: countoffDurationMultiplier
        )
    }

    static func seedSnapshot() -> LibrarySnapshot {
        let warm = PadPack(
            name: "Warm",
            folderName: "Warm",
            availableKeys: Set(MusicalKey.allCases)
        )
        let airy = PadPack(
            name: "Airy",
            folderName: "Airy",
            availableKeys: [.c, .d, .e, .f, .g, .a]
        )

        let songs = [
            Song(title: "Goodness of God", defaultKey: .g, defaultBPM: 72, timeSignature: .sixEight, padPack: warm),
            Song(title: "King of Kings", defaultKey: .d, defaultBPM: 68, timeSignature: .fourFour, padPack: warm),
            Song(title: "Holy Forever", defaultKey: .a, defaultBPM: 76, timeSignature: .fourFour, padPack: airy)
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
