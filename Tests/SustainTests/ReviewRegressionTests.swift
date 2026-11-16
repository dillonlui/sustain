import Foundation
import Testing
@testable import Sustain

@MainActor
struct ReviewRegressionTests {
    @Test func corruptionProtectionSurvivesSecondLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LocalLibraryStore(directoryOverride: directory)
        let primary = try library.applicationSupportDirectory().appendingPathComponent("Library.json")
        try Data("broken primary".utf8).write(to: primary)
        try Data("broken backup".utf8).write(to: directory.appendingPathComponent("Library.bak"))
        func launch() -> AppStore {
            AppStore.live(libraryStore: library, audioEngineOverride: RecordingAudioEngine(),
                          audioHardwareMonitorOverride: NoopAudioHardwareMonitor(),
                          powerStateMonitorOverride: NoopPowerStateMonitor(), midiControllerOverride: NoopMIDIController())
        }
        #expect(launch().persistenceStatus.contains("read-only"))
        let second = launch()
        #expect(second.persistenceStatus.contains("read-only"))
        #expect(!FileManager.default.fileExists(atPath: primary.path))
    }

    @Test func failedSongSaveDoesNotReturnSuccessfulID() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let store = AppStore.preview(libraryStore: LocalLibraryStore(directoryOverride: directory))
        var draft = SongDraft.newSong()
        draft.title = "Unsaved review song"
        #expect(store.saveSongDraft(&draft) == nil)
        #expect(store.saveErrorPrompt != nil)
    }

    @Test func restartingClickRejectsActualRouteMismatchBeforeMonitorRuns() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        store.stopClick()
        let starts = audio.clickStartCount
        audio.routingIsValid = false
        store.startClick()
        #expect(audio.clickStartCount == starts)
        #expect(store.runtime.clickState == .off)
    }

    @Test func failedRehearsalEditDoesNotFreezeCountoffProgress() async throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio, countoffDurationMultiplier: 0.02)
        store.startRehearseClick()
        #expect(store.rehearse.clickState == .countoff)
        audio.shouldFailClickStart = true
        store.setRehearseBPM(80)
        try await waitForClickState(.playing, in: store)
        #expect(store.rehearse.clickState == .playing)
    }
    @Test func retryFailedTempoSaveKeepsTheRequestedTempo() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let blocked = parent.appendingPathComponent("library")
        try Data("blocks directory creation".utf8).write(to: blocked)
        let library = LocalLibraryStore(directoryOverride: blocked)
        let store = AppStore.preview(libraryStore: library)
        let entry = try #require(store.cuedEntry)
        store.liveTempoOverrides[entry.id] = 123
        #expect(store.saveCuedTempoAsSongDefault() == false)
        #expect(store.saveErrorPrompt != nil)
        try FileManager.default.removeItem(at: blocked)
        store.retryFailedSave()
        let loaded = try #require(try library.loadLibrary())
        #expect(loaded.songs.first(where: { $0.id == entry.songID })?.defaultBPM == 123)
    }

    @Test func failedNewSongSaveCanBeRetriedWithoutCreatingDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let library = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: library)
        let count = store.songs.count
        var draft = SongDraft.newSong()
        draft.title = "Retry this song"
        #expect(store.saveSongDraft(&draft) == nil)
        let id = try #require(draft.id)
        #expect(store.saveSongDraft(&draft) == nil)
        #expect(store.songs.count == count + 1)
        #expect(draft.id == id)
        try FileManager.default.removeItem(at: directory)
        store.retryFailedSave()
        #expect(store.saveErrorPrompt == nil)
        #expect(store.saveSongDraft(&draft) == id)
        let loaded = try #require(try library.loadLibrary())
        #expect(loaded.songs.filter { $0.id == id }.count == 1)
        #expect(store.songs.count == count + 1)
    }

    @Test func corruptLibraryWithoutBackupRemainsProtectedUntilRepaired() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LocalLibraryStore(directoryOverride: directory)
        let primary = try library.applicationSupportDirectory().appendingPathComponent("Library.json")
        try Data("broken primary".utf8).write(to: primary)
        #expect(throws: (any Error).self) { try library.loadLibrary() }
        #expect(throws: (any Error).self) { try library.loadLibrary() }
        #expect(!FileManager.default.fileExists(atPath: primary.path))
        var repaired = AppStore.seedSnapshot()
        repaired.songs[0].title = "Recovered song"
        try JSONEncoder().encode(repaired).write(to: primary)
        #expect(try library.loadLibrary()?.songs[0].title == "Recovered song")
    }

    @Test func deviceDriftDuringClickPreparationBlocksActivation() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        audio.defersClickPreparation = true
        store.startRehearseClick()
        audio.routingIsValid = false
        audio.completePendingClickPreparation()
        #expect(audio.clickStartCount == 0)
        #expect(store.rehearse.clickState == .off)
        #expect(!store.systemCheck.canStartPlayback)
    }

    @Test func failedCountoffOnlyEditStillFinishesTheOriginalCountoff() async throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio, countoffDurationMultiplier: 0.02)
        store.setRehearseCountoffPolicy(CountoffPolicy(bars: 1, after: .countoffOnly))
        store.startRehearseClick()
        audio.shouldFailClickStart = true
        store.setRehearseBPM(80)
        try await waitForClickState(.off, in: store)
        #expect(store.rehearse.clickState == .off)
        #expect(store.rehearse.countoffBeat == nil)
        #expect(!audio.isClickActive)
    }

    @Test func failedReplacementActivationClearsRehearsalPlayingState() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.setRehearseCountoffEnabled(false)
        store.startRehearseClick()
        audio.shouldFailClickActivation = true
        store.setRehearseBPM(80)
        #expect(store.rehearse.clickState == .off)
        #expect(store.rehearse.countoffBeat == nil)
        #expect(!audio.isClickActive)
    }

    private func waitForClickState(_ state: ClickPlaybackState, in store: AppStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while store.rehearse.clickState != state && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

}
