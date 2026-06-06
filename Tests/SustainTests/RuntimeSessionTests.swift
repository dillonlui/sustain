import Foundation
import CoreAudio
import Testing
@testable import Sustain

@MainActor
struct RuntimeSessionTests {
    @Test func nextSongOnlyChangesCue() {
        let store = AppStore.preview()
        store.startCuedSong()

        let playing = store.runtime.playingEntryID
        store.cueNextSong()

        #expect(store.runtime.playingEntryID == playing)
        #expect(store.runtime.cuedEntryID != playing)
    }

    @Test func startClickUsesCountoffBeforePlaying() async {
        let store = AppStore.preview(countoffDurationMultiplier: 0)
        store.startCuedSong()
        store.stopClick()

        store.startClick()

        #expect(store.runtime.clickState == .countoff)

        for _ in 0..<20 where store.runtime.clickState != .playing {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(store.runtime.clickState == .playing)
        #expect(store.runtime.lastMessage == "Click playing for Goodness of God")
    }

    @Test func invalidTransitionDoesNotDestroyPlayingState() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let playing = store.runtime.playingEntryID
        let padStarts = audio.padStartCount
        let clickStarts = audio.clickStartCount

        store.cueNextSong()
        store.cueNextSong()
        store.startCuedSong()

        #expect(store.runtime.playingEntryID == playing)
        #expect(store.runtime.lastMessage == "Playback blocked by system check")
        #expect(audio.padStartCount == padStarts)
        #expect(audio.clickStartCount == clickStarts)
    }

    @Test func setlistOverridesPersistToJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)

        let entry = try #require(store.activeSetlist.entries.first)
        store.updateEntry(entry.id, keyOverride: .bb, bpmOverride: 88)

        let loaded = try #require(try libraryStore.loadLibrary())
        let loadedEntry = try #require(loaded.activeSetlist.entries.first)

        #expect(loadedEntry.keyOverride == .bb)
        #expect(loadedEntry.bpmOverride == 88)
    }

    @Test func bundledPadResolverFindsExpectedWAVFiles() throws {
        let resolver = BundlePadAssetResolver()
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

        let warmAsset = try #require(resolver.asset(for: warm, key: .g))
        #expect(warmAsset.url.pathExtension == "wav")
        #expect(resolver.asset(for: airy, key: .bb) == nil)
    }

    @Test func sharedOutputRoutingWarnsButDoesNotBlockPlayback() {
        let store = AppStore.preview()

        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings == ["Pad and click are currently sharing the same output."])
    }

    @Test func independentOutputRoutingClearsSharedOutputWarning() {
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 1, name: "Main", isDefault: true),
                    AudioOutputDevice(id: 2, name: "Click Bus", isDefault: false)
                ],
                padOutputID: 1,
                padOutputName: "Main",
                clickOutputID: 2,
                clickOutputName: "Click Bus",
                independentRoutingEnabled: true
            )
        )
        let store = AppStore.preview(audioRoutingProvider: provider)

        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings.isEmpty)
        #expect(store.routingSnapshot.independentRoutingEnabled)
    }

    @Test func routingSelectionPersistsToJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainRoutingTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)

        store.updateRouting(padOutputID: 11, clickOutputID: 12)

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(loaded.routingSettings.padOutputID == 11)
        #expect(loaded.routingSettings.clickOutputID == 12)
    }
}

@MainActor
private final class RecordingAudioEngine: AudioControlling {
    var isEngineRunning = false
    var padStartCount = 0
    var clickStartCount = 0
    var statusSummary: String { isEngineRunning ? "Running" : "Stopped" }

    func prepare() {}

    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws {}

    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String {
        "Found \(padPack.name) \(key.rawValue).wav"
    }

    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool {
        padPack.supports(key)
    }

    func startPad(for key: MusicalKey, padPack: PadPack) throws {
        padStartCount += 1
        isEngineRunning = true
    }

    func stopPad() {}

    func startClick(bpm: Int, timeSignature: TimeSignature) throws {
        clickStartCount += 1
        isEngineRunning = true
    }

    func stopClick() {}

    func stopAll() {
        isEngineRunning = false
    }
}
