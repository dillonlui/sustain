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
        let audio = RecordingAudioEngine(missingPadKeys: [.bb])
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

    @Test func stopClearsAudioStatus() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        store.startCuedSong()
        store.stop()

        #expect(store.audioStatus == "Stopped")
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

    @Test func bundledPadResolverFindsBundledPadFiles() throws {
        let resolver = BundlePadAssetResolver()

        let asset = try #require(resolver.asset(for: .bundled, key: .g))
        #expect(asset.url.lastPathComponent == "G Major.mp3")
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

    @Test func unavailablePadOutputBlocksPlayback() {
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 2, name: "Click Bus", isDefault: true)
                ],
                padOutputID: 2,
                padOutputName: "Click Bus",
                clickOutputID: 2,
                clickOutputName: "Click Bus",
                independentRoutingEnabled: false,
                missingSelectionMessages: ["Selected pad output is unavailable."]
            )
        )
        let store = AppStore.preview(audioRoutingProvider: provider)

        store.runSystemCheck()

        #expect(!store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.messages.contains("Selected pad output is unavailable."))
    }

    @Test func unavailableClickOutputBlocksPlayback() {
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 1, name: "Main", isDefault: true)
                ],
                padOutputID: 1,
                padOutputName: "Main",
                clickOutputID: 1,
                clickOutputName: "Main",
                independentRoutingEnabled: false,
                missingSelectionMessages: ["Selected click output is unavailable."]
            )
        )
        let store = AppStore.preview(audioRoutingProvider: provider)

        store.runSystemCheck()

        #expect(!store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.messages.contains("Selected click output is unavailable."))
    }

    @Test func startSongRefreshesRoutingBeforeValidation() {
        let audio = RecordingAudioEngine()
        let provider = MutableAudioRoutingProvider(snapshotValue: .previewDefault)
        let store = AppStore.preview(audioEngine: audio, audioRoutingProvider: provider)

        provider.snapshotValue = AudioRoutingSnapshot(
            outputs: [
                AudioOutputDevice(id: 1, name: "Preview Output", isDefault: true)
            ],
            padOutputID: 1,
            padOutputName: "Preview Output",
            clickOutputID: 1,
            clickOutputName: "Preview Output",
            independentRoutingEnabled: false,
            missingSelectionMessages: ["Selected click output is unavailable."]
        )

        store.startCuedSong()

        #expect(store.runtime.lastMessage == "Playback blocked by system check")
        #expect(!store.systemCheck.canStartPlayback)
        #expect(audio.padStartCount == 0)
        #expect(audio.clickStartCount == 0)
    }

    @Test func hardwareChangeStopsPlaybackWhenSelectedOutputDisappears() {
        let audio = RecordingAudioEngine()
        let provider = MutableAudioRoutingProvider(snapshotValue: .previewDefault)
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioEngine: audio,
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        store.startCuedSong()

        provider.snapshotValue = AudioRoutingSnapshot(
            outputs: [
                AudioOutputDevice(id: 1, name: "Preview Output", isDefault: true)
            ],
            padOutputID: 1,
            padOutputName: "Preview Output",
            clickOutputID: 1,
            clickOutputName: "Preview Output",
            independentRoutingEnabled: false,
            missingSelectionMessages: ["Selected click output is unavailable."]
        )
        monitor.simulateChange()

        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.padState == .off)
        #expect(store.runtime.clickState == .off)
        #expect(store.runtime.lastMessage == "Selected click output is unavailable.")
        #expect(audio.stopAllCount == 1)
    }

    @Test func unchangedHardwarePollDoesNotOverwriteRuntimeMessage() {
        let audio = RecordingAudioEngine()
        let provider = MutableAudioRoutingProvider(snapshotValue: .previewDefault)
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioEngine: audio,
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        store.startCuedSong()
        let message = store.runtime.lastMessage

        monitor.simulateChange()

        #expect(store.runtime.lastMessage == message)
        #expect(store.runtime.playbackPhase == .songPlaying)
        #expect(audio.stopAllCount == 0)
    }

    @Test func hardwareChangeStopsRehearsalWhenSelectedOutputDisappears() {
        let audio = RecordingAudioEngine()
        let provider = MutableAudioRoutingProvider(snapshotValue: .previewDefault)
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioEngine: audio,
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        store.startRehearsePad(key: .g)
        store.startRehearseClick()

        provider.snapshotValue = AudioRoutingSnapshot(
            outputs: [
                AudioOutputDevice(id: 1, name: "Preview Output", isDefault: true)
            ],
            padOutputID: 1,
            padOutputName: "Preview Output",
            clickOutputID: 1,
            clickOutputName: "Preview Output",
            independentRoutingEnabled: false,
            missingSelectionMessages: ["Selected pad output is unavailable."]
        )
        monitor.simulateChange()

        #expect(store.rehearse.padState == .off)
        #expect(store.rehearse.clickState == .off)
        #expect(store.rehearse.lastMessage == "Selected pad output is unavailable.")
        #expect(audio.stopAllCount == 1)
    }

    @Test func hardwareReconnectRefreshesSystemCheck() {
        let provider = MutableAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 1, name: "Preview Output", isDefault: true)
                ],
                padOutputID: 1,
                padOutputName: "Preview Output",
                clickOutputID: 1,
                clickOutputName: "Preview Output",
                independentRoutingEnabled: false,
                missingSelectionMessages: ["Selected click output is unavailable."]
            )
        )
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        store.runSystemCheck()
        #expect(!store.systemCheck.canStartPlayback)

        provider.snapshotValue = .previewDefault
        monitor.simulateChange()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.messages.contains("Ready for Goodness of God in G at 72 BPM."))
        #expect(store.runtime.lastMessage == "Audio devices updated")
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

    @Test func rehearseBPMUpdatesClickWithoutAnotherCountoff() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        store.startRehearseClick()
        store.setRehearseBPM(96)

        #expect(store.rehearse.bpm == 96)
        #expect(store.rehearse.clickState == .playing)
        #expect(audio.clickStartCount == 2)
        #expect(audio.clickIncludesCountoffHistory == [true, false])
    }

    @Test func rehearsePadSelectionStartsBundledPad() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        store.startRehearsePad(key: .e)

        #expect(store.rehearse.selectedKey == .e)
        #expect(store.rehearse.padState == .playing)
        #expect(audio.padStartCount == 1)
    }
}

@MainActor
private final class RecordingAudioEngine: AudioControlling {
    private var padIsActive = false
    private var clickIsActive = false
    var isEngineRunning: Bool { padIsActive || clickIsActive }
    var padStartCount = 0
    var clickStartCount = 0
    var stopAllCount = 0
    var clickIncludesCountoffHistory: [Bool] = []
    var missingPadKeys: Set<MusicalKey>
    var statusSummary: String { isEngineRunning ? "Running" : "Stopped" }

    init(missingPadKeys: Set<MusicalKey> = []) {
        self.missingPadKeys = missingPadKeys
    }

    func prepare() {}

    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws {}

    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String {
        missingPadKeys.contains(key) ? "Missing bundled pad \(key.rawValue).mp3" : "Found \(key.rawValue).mp3"
    }

    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool {
        !missingPadKeys.contains(key)
    }

    func startPad(for key: MusicalKey, padPack: PadPack) throws {
        padStartCount += 1
        padIsActive = true
    }

    func stopPad() {
        padIsActive = false
    }

    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool) throws {
        clickStartCount += 1
        clickIncludesCountoffHistory.append(includesCountoff)
        clickIsActive = true
    }

    func stopClick() {
        clickIsActive = false
    }

    func stopAll() {
        stopAllCount += 1
        padIsActive = false
        clickIsActive = false
    }
}

private final class MutableAudioRoutingProvider: AudioRoutingProviding {
    var snapshotValue: AudioRoutingSnapshot

    init(snapshotValue: AudioRoutingSnapshot) {
        self.snapshotValue = snapshotValue
    }

    func snapshot(settings: AudioRoutingSettings = .default) -> AudioRoutingSnapshot {
        snapshotValue
    }
}
