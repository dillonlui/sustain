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

    init(songs: [Song], activeSetlist: Setlist) {
        self.songs = songs
        self.activeSetlist = activeSetlist
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

        runtime.playbackPhase = .songStarting

        if runtime.playingEntryID != nil {
            runtime.clickState = .off
            runtime.padState = .fadingOut
        }

        runtime.padState = .fadingIn
        runtime.clickState = .countoff
        runtime.playingEntryID = cuedEntry.id
        runtime.padState = .playing
        runtime.clickState = .playing
        runtime.playbackPhase = .songPlaying
        runtime.lastMessage = "Started \(cuedSong.title)"
    }

    func stop() {
        runtime.clickState = .off
        runtime.padState = .fadingOut
        runtime.playingEntryID = nil
        runtime.padState = .off
        runtime.playbackPhase = .noSongPlaying
        runtime.lastMessage = "Stopped"
    }

    func startClick() {
        guard runtime.playingEntryID != nil else {
            runtime.lastMessage = "Start a song before starting click"
            return
        }

        guard runtime.clickState == .off else {
            runtime.lastMessage = "Click is already active"
            return
        }

        runtime.clickState = .countoff
        runtime.clickState = .playing
        runtime.lastMessage = "Click started after countoff"
    }

    func stopClick() {
        runtime.clickState = .off
        runtime.lastMessage = "Click stopped"
    }

    func startPad() {
        guard runtime.playingEntryID != nil else {
            runtime.lastMessage = "Start a song before starting pad"
            return
        }

        runtime.padState = .fadingIn
        runtime.padState = .playing
        runtime.lastMessage = "Pad started"
    }

    func stopPad() {
        runtime.padState = .fadingOut
        runtime.padState = .off
        runtime.lastMessage = "Pad stopped"
    }

    func runSystemCheck() {
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

    private func validate(entry: SetlistEntry, song: Song) -> SystemCheckResult {
        var messages: [String] = []
        let key = entry.resolvedKey(for: song)

        if song.defaultBPM <= 0 {
            messages.append("\(song.title) needs a valid BPM.")
        }

        if !song.padPack.supports(key) {
            messages.append("\(song.padPack.name) does not include a pad for \(key.rawValue).")
        }

        if messages.isEmpty {
            messages.append("Ready for \(song.title) in \(key.rawValue).")
        }

        return SystemCheckResult(canStartPlayback: messages.count == 1 && messages[0].hasPrefix("Ready"), messages: messages)
    }
}

extension AppStore {
    static func preview() -> AppStore {
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

        return AppStore(
            songs: songs,
            activeSetlist: Setlist(title: "Sunday Morning", entries: entries)
        )
    }
}
