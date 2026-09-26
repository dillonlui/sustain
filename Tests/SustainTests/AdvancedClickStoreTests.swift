import Foundation
import Testing
@testable import Sustain

@MainActor
@Suite struct AdvancedClickStoreTests {
    @Test func rapidRehearseAccentEditsReachTheLastPattern() {
        let audio = RecordingAudioEngine()
        audio.defersClickSwitch = true
        let store = AppStore.preview(audioEngine: audio)
        store.setRehearseCountoffEnabled(false)
        store.startRehearseClick()

        let first: [ClickAccentLevel] = [.strong, .normal, .normal, .normal]
        let last: [ClickAccentLevel] = [.normal, .mute, .normal, .normal]
        store.setRehearseAccentPattern(first)
        store.setRehearseAccentPattern(last)
        audio.completePendingClickSwitch()
        #expect(store.audibleClickAccentPattern == first)
        #expect(store.pendingRehearseClickSubdivision != nil)
        audio.completePendingClickSwitch()
        #expect(store.audibleClickAccentPattern == last)
        #expect(store.pendingRehearseClickSubdivision == nil)
    }

    @Test func rapidLiveAccentEditsReachTheLastPattern() throws {
        let audio = RecordingAudioEngine()
        audio.defersClickSwitch = true
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        store.runtime.clickState = .playing
        let song = try #require(store.song(for: store.playingEntry))
        let first: [ClickAccentLevel] = [.strong, .normal, .normal, .normal]
        let last: [ClickAccentLevel] = [.normal, .mute, .normal, .normal]

        var firstDraft = SongDraft(song: song)
        firstDraft.clickAccentPattern = first
        #expect(store.saveSongDraft(firstDraft) == song.id)
        var lastDraft = SongDraft(song: try #require(store.songs.first { $0.id == song.id }))
        lastDraft.clickAccentPattern = last
        #expect(store.saveSongDraft(lastDraft) == song.id)
        audio.completePendingClickSwitch()
        #expect(store.audibleClickAccentPattern == first)
        #expect(store.pendingClickSubdivision(for: song.id) != nil)
        audio.completePendingClickSwitch()
        #expect(store.audibleClickAccentPattern == last)
        #expect(store.pendingClickSubdivision(for: song.id) == nil)
    }

    @Test func countoffOnlyStopsClickAndKeepsSongPlaying() async throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let songID = try #require(store.songs.first?.id)
        let index = try #require(store.songs.firstIndex { $0.id == songID })
        store.songs[index].countoffPolicy = CountoffPolicy(bars: 2, after: .countoffOnly)
        store.startCuedSong()
        #expect(store.runtime.countoffTotal == 8)
        for _ in 0..<100 {
            if store.runtime.clickState == .off { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.runtime.clickState == .off)
        #expect(store.runtime.playingEntryID != nil)
        #expect(store.runtime.padState != .off)
    }

    @Test func editedSongDefaultDoesNotRetempoAnOverriddenLiveClick() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.selectedScreen = .live
        let entry = try #require(store.cuedEntry)
        for time in [0.0, 0.5, 1.0] { store.tapTempo(at: time) }
        #expect(store.useTappedTempo(at: 1.1))
        store.startCuedSong()
        let initialStarts = audio.clickBPMHistory.count
        let song = try #require(store.song(for: entry))

        var draft = SongDraft(song: song)
        draft.defaultBPM = 80
        #expect(store.saveSongDraft(draft) == song.id)
        #expect(audio.clickBPMHistory.count == initialStarts)
        #expect(store.effectiveBPM(for: entry) == 120)

        var meterDraft = SongDraft(song: try #require(store.song(for: entry)))
        meterDraft.timeSignature = .threeFour
        #expect(store.saveSongDraft(meterDraft) == song.id)
        #expect(audio.clickBPMHistory.last == 120)
    }

    @Test func legacyUpdateSongUsesPlayingEntryOverride() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.selectedScreen = .live
        let entry = try #require(store.cuedEntry)
        for time in [0.0, 0.5, 1.0] { store.tapTempo(at: time) }
        #expect(store.useTappedTempo(at: 1.1))
        store.startCuedSong()
        let song = try #require(store.song(for: entry))
        let initialStarts = audio.clickBPMHistory.count
        #expect(store.updateSong(song.id, title: song.title, defaultKey: song.defaultKey,
                                 defaultBPM: 80, timeSignature: song.timeSignature,
                                 padPackID: song.padPack.id))
        #expect(audio.clickBPMHistory.count == initialStarts)
        #expect(store.updateSong(song.id, title: song.title, defaultKey: song.defaultKey,
                                 defaultBPM: 80, timeSignature: .threeFour,
                                 padPackID: song.padPack.id))
        #expect(audio.clickBPMHistory.last == 120)
    }

    @Test func countoffOnlyRefreshesAudioStatusOnAutomaticStop() async {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.selectedScreen = .rehearse
        store.setRehearseCountoffPolicy(CountoffPolicy(bars: 1, after: .countoffOnly))
        store.startRehearseClick()
        #expect(store.audioStatus == "Running")
        for _ in 0..<100 {
            if store.rehearse.clickState == .off { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.rehearse.clickState == .off)
        #expect(store.audioStatus == "Stopped")
    }
}
