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

    @Test func systemCheckWarnsAboutMissingPadAssetsLaterInSetlist() {
        let audio = RecordingAudioEngine(missingPadKeys: [.bb])
        let store = AppStore.preview(audioEngine: audio)

        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings.contains("Holy Forever: Missing bundled pad Bb.mp3"))
        #expect(store.systemCheck.messages.contains("Warning: Holy Forever: Missing bundled pad Bb.mp3"))
    }

    @Test func systemCheckWarnsAboutInvalidBPMLaterInSetlist() {
        let store = AppStore.preview()
        let laterEntry = store.activeSetlist.entries[1]

        store.updateEntry(laterEntry.id, keyOverride: nil, bpmOverride: 0)
        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings.contains("King of Kings: needs a valid BPM."))
        #expect(store.systemCheck.messages.contains("Warning: King of Kings: needs a valid BPM."))
    }

    @Test func systemCheckWarnsAboutMissingSongReferencesLaterInSetlist() {
        let snapshot = AppStore.seedSnapshot()
        var activeSetlist = snapshot.activeSetlist
        activeSetlist.entries.append(SetlistEntry(songID: UUID()))
        let store = AppStore(songs: snapshot.songs, activeSetlist: activeSetlist)

        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings.contains("Setlist entry 4: references a missing song."))
        #expect(store.systemCheck.messages.contains("Warning: Setlist entry 4: references a missing song."))
    }

    @Test func clickStartupFailureDoesNotStartNewPadDuringTransition() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let playing = store.runtime.playingEntryID
        let padStarts = audio.padStartCount

        audio.shouldFailClickStart = true
        store.cueNextSong()
        store.startCuedSong()

        #expect(store.runtime.playingEntryID == playing)
        #expect(store.runtime.playbackPhase == .songPlaying)
        #expect(store.runtime.padState == .playing)
        #expect(audio.padStartCount == padStarts)
        #expect(store.runtime.lastMessage == AudioEngineError.invalidOutputFormat.localizedDescription)
    }

    @Test func padStartupFailureStopsClickForInitialSong() {
        let audio = RecordingAudioEngine()
        audio.shouldFailPadStart = true
        let store = AppStore.preview(audioEngine: audio)

        store.startCuedSong()

        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.padState == .off)
        #expect(store.runtime.clickState == .off)
        #expect(!audio.isEngineRunning)
        #expect(audio.clickStartCount == 1)
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

    @Test func librarySnapshotRequiresUsableSetlist() {
        let snapshot = AppStore.seedSnapshot()

        let emptySetlist = LibrarySnapshot(
            songs: snapshot.songs,
            activeSetlist: Setlist(title: "Empty", entries: [])
        )
        let missingSongSetlist = LibrarySnapshot(
            songs: snapshot.songs,
            activeSetlist: Setlist(
                title: "Broken",
                entries: [SetlistEntry(songID: UUID())]
            )
        )

        #expect(snapshot.hasUsableSetlist)
        #expect(!emptySetlist.hasUsableSetlist)
        #expect(!missingSongSetlist.hasUsableSetlist)
    }

    @Test func bundledPadResolverFindsBundledPadFiles() throws {
        let resolver = BundlePadAssetResolver()

        let asset = try #require(resolver.asset(for: .bundled, key: .g))
        #expect(asset.url.lastPathComponent == "G Major.mp3")
    }

    @Test func bundledPadResolverIgnoresFolderBackedPadPacks() {
        let resolver = BundlePadAssetResolver()
        let padPack = PadPack(
            name: "Warm",
            folderName: "Warm",
            availableKeys: Set(MusicalKey.allCases)
        )

        #expect(resolver.asset(for: padPack, key: .g) == nil)
    }

    @Test func fileSystemPadResolverFindsFolderBackedPadFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainPadResolverTests-\(UUID().uuidString)", isDirectory: true)
        let packDirectory = root.appendingPathComponent("Warm", isDirectory: true)
        try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)
        let fileURL = packDirectory.appendingPathComponent("Db.wav", isDirectory: false)
        try Data().write(to: fileURL)
        let resolver = FileSystemPadAssetResolver(rootDirectory: root)
        let padPack = PadPack(
            name: "Warm",
            folderName: "Warm",
            availableKeys: Set(MusicalKey.allCases)
        )

        let asset = try #require(resolver.asset(for: padPack, key: .db))

        #expect(asset.url == fileURL)
        #expect(asset.displayName == "Warm/Db.wav")
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

    @Test func routingConfigurationFailureBlocksPlayback() {
        let audio = RecordingAudioEngine()
        audio.shouldFailConfigureRouting = true
        let store = AppStore.preview(audioEngine: audio)

        store.runSystemCheck()

        #expect(!store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.messages.contains("Audio routing failed: \(AudioEngineError.invalidOutputFormat.localizedDescription)"))
    }

    @Test func routingResolverRecoversSelectedOutputByNameWhenDeviceIDChanges() {
        let resolver = AudioRoutingResolver()
        let snapshot = resolver.snapshot(
            settings: AudioRoutingSettings(
                padOutputID: 10,
                padOutputName: "Dillon's AirPods",
                clickOutputID: 20,
                clickOutputName: "MacBook Pro Speakers"
            ),
            outputs: [
                AudioOutputDevice(id: 30, name: "Dillon's AirPods", isDefault: false),
                AudioOutputDevice(id: 20, name: "MacBook Pro Speakers", isDefault: true)
            ]
        )

        #expect(snapshot.padOutputID == 30)
        #expect(snapshot.padOutputName == "Dillon's AirPods")
        #expect(snapshot.clickOutputID == 20)
        #expect(snapshot.missingSelectionMessages.isEmpty)
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

    @Test func hardwareChangeStopsPlaybackWhenDefaultOutputChanges() {
        let audio = RecordingAudioEngine()
        let provider = MutableAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 1, name: "AirPods", isDefault: true),
                    AudioOutputDevice(id: 2, name: "MacBook Speakers", isDefault: false),
                    AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: false)
                ],
                padOutputID: 1,
                padOutputName: "AirPods",
                clickOutputID: 2,
                clickOutputName: "MacBook Speakers",
                independentRoutingEnabled: true
            )
        )
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioEngine: audio,
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        store.startCuedSong()

        provider.snapshotValue = AudioRoutingSnapshot(
            outputs: [
                AudioOutputDevice(id: 1, name: "AirPods", isDefault: false),
                AudioOutputDevice(id: 2, name: "MacBook Speakers", isDefault: false),
                AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: true)
            ],
            padOutputID: 1,
            padOutputName: "AirPods",
            clickOutputID: 2,
            clickOutputName: "MacBook Speakers",
            independentRoutingEnabled: true
        )
        monitor.simulateChange()

        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.padState == .off)
        #expect(store.runtime.clickState == .off)
        #expect(store.runtime.lastMessage == "Audio devices changed. Playback stopped so routing can be rechecked.")
        #expect(store.audioRouteChangePrompt?.detectedOutputID == 3)
        #expect(audio.stopAllCount == 1)
    }

    @Test func keepingCurrentRoutingDismissesRouteChangePrompt() {
        let provider = MutableAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 1, name: "AirPods", isDefault: true),
                    AudioOutputDevice(id: 2, name: "MacBook Speakers", isDefault: false),
                    AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: false)
                ],
                padOutputID: 1,
                padOutputName: "AirPods",
                clickOutputID: 2,
                clickOutputName: "MacBook Speakers",
                independentRoutingEnabled: true
            )
        )
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        provider.snapshotValue = AudioRoutingSnapshot(
            outputs: [
                AudioOutputDevice(id: 1, name: "AirPods", isDefault: false),
                AudioOutputDevice(id: 2, name: "MacBook Speakers", isDefault: false),
                AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: true)
            ],
            padOutputID: 1,
            padOutputName: "AirPods",
            clickOutputID: 2,
            clickOutputName: "MacBook Speakers",
            independentRoutingEnabled: true
        )
        monitor.simulateChange()

        store.keepCurrentAudioRouting()

        #expect(store.audioRouteChangePrompt == nil)
        #expect(store.routingSettings.padOutputID == 1)
        #expect(store.routingSettings.padOutputName == "AirPods")
        #expect(store.routingSettings.clickOutputID == 2)
        #expect(store.routingSettings.clickOutputName == "MacBook Speakers")
        #expect(store.runtime.lastMessage == "Kept current audio output settings")
    }

    @Test func keepingCurrentRoutingPinsPreviousDefaultOutputAfterDefaultChanges() {
        let provider = MutableAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 10, name: "Dillon's AirPods", isDefault: true),
                    AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: false)
                ],
                padOutputID: 10,
                padOutputName: "Dillon's AirPods",
                clickOutputID: 10,
                clickOutputName: "Dillon's AirPods",
                independentRoutingEnabled: false
            )
        )
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        provider.snapshotValue = AudioRoutingSnapshot(
            outputs: [
                AudioOutputDevice(id: 10, name: "Dillon's AirPods", isDefault: false),
                AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: true)
            ],
            padOutputID: 3,
            padOutputName: "Monitor Speakers",
            clickOutputID: 3,
            clickOutputName: "Monitor Speakers",
            independentRoutingEnabled: false
        )
        monitor.simulateChange()

        store.keepCurrentAudioRouting()

        #expect(store.audioRouteChangePrompt == nil)
        #expect(store.routingSettings.padOutputID == 10)
        #expect(store.routingSettings.padOutputName == "Dillon's AirPods")
        #expect(store.routingSettings.clickOutputID == 10)
        #expect(store.routingSettings.clickOutputName == "Dillon's AirPods")
    }

    @Test func keepingCurrentRoutingPreservesExplicitSelectionWhenOutputIsTemporarilyUnavailable() {
        let provider = MutableAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: true)
                ],
                padOutputID: nil,
                padOutputName: "Unavailable",
                clickOutputID: 3,
                clickOutputName: "Monitor Speakers",
                independentRoutingEnabled: false,
                missingSelectionMessages: ["Selected pad output is unavailable."]
            )
        )
        let monitor = NoopAudioHardwareMonitor()
        let snapshot = AppStore.seedSnapshot()
        let store = AppStore(
            songs: snapshot.songs,
            activeSetlist: snapshot.activeSetlist,
            audioEngine: RecordingAudioEngine(),
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor,
            routingSettings: AudioRoutingSettings(
                padOutputID: 10,
                padOutputName: "Dillon's AirPods",
                clickOutputID: 3,
                clickOutputName: "Monitor Speakers"
            )
        )

        monitor.simulateChange()
        store.keepCurrentAudioRouting()

        #expect(store.routingSettings.padOutputID == 10)
        #expect(store.routingSettings.padOutputName == "Dillon's AirPods")
        #expect(store.routingSettings.clickOutputID == 3)
    }

    @Test func switchingToDetectedOutputUpdatesRoutingSettings() {
        let provider = MutableAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 1, name: "AirPods", isDefault: true),
                    AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: false)
                ],
                padOutputID: 1,
                padOutputName: "AirPods",
                clickOutputID: 1,
                clickOutputName: "AirPods",
                independentRoutingEnabled: false
            )
        )
        let monitor = NoopAudioHardwareMonitor()
        let store = AppStore.preview(
            audioRoutingProvider: provider,
            audioHardwareMonitor: monitor
        )

        provider.snapshotValue = AudioRoutingSnapshot(
            outputs: [
                AudioOutputDevice(id: 1, name: "AirPods", isDefault: false),
                AudioOutputDevice(id: 3, name: "Monitor Speakers", isDefault: true)
            ],
            padOutputID: 1,
            padOutputName: "AirPods",
            clickOutputID: 1,
            clickOutputName: "AirPods",
            independentRoutingEnabled: false
        )
        monitor.simulateChange()

        store.switchToDetectedAudioOutput()

        #expect(store.audioRouteChangePrompt == nil)
        #expect(store.routingSettings.padOutputID == 3)
        #expect(store.routingSettings.clickOutputID == 3)
        #expect(store.runtime.lastMessage == "Switched audio outputs to Monitor Speakers")
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

    @Test func systemWakeRechecksRoutingWithoutChange() {
        let powerMonitor = NoopPowerStateMonitor()
        let store = AppStore.preview(powerStateMonitor: powerMonitor)

        powerMonitor.simulateWake()

        #expect(store.runtime.lastMessage == "System woke. Audio routing checked.")
        #expect(store.runtime.playbackPhase == .noSongPlaying)
    }

    @Test func systemWakeStopsPlaybackWhenSelectedOutputIsUnavailable() {
        let audio = RecordingAudioEngine()
        let provider = MutableAudioRoutingProvider(snapshotValue: .previewDefault)
        let powerMonitor = NoopPowerStateMonitor()
        let store = AppStore.preview(
            audioEngine: audio,
            audioRoutingProvider: provider,
            powerStateMonitor: powerMonitor
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
            missingSelectionMessages: ["Selected pad output is unavailable."]
        )

        powerMonitor.simulateWake()

        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.lastMessage == "Selected pad output is unavailable.")
        #expect(store.audioRouteChangePrompt == nil)
        #expect(audio.stopAllCount == 1)
    }

    @Test func systemWakeNormalizesRecoveredOutputDeviceID() {
        let provider = MutableAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 30, name: "Dillon's AirPods", isDefault: false),
                    AudioOutputDevice(id: 20, name: "MacBook Pro Speakers", isDefault: true)
                ],
                padOutputID: 30,
                padOutputName: "Dillon's AirPods",
                clickOutputID: 20,
                clickOutputName: "MacBook Pro Speakers",
                independentRoutingEnabled: true
            )
        )
        let powerMonitor = NoopPowerStateMonitor()
        let snapshot = AppStore.seedSnapshot()
        let store = AppStore(
            songs: snapshot.songs,
            activeSetlist: snapshot.activeSetlist,
            audioEngine: RecordingAudioEngine(),
            audioRoutingProvider: provider,
            powerStateMonitor: powerMonitor,
            routingSettings: AudioRoutingSettings(
                padOutputID: 10,
                padOutputName: "Dillon's AirPods",
                clickOutputID: 20,
                clickOutputName: "MacBook Pro Speakers"
            )
        )

        powerMonitor.simulateWake()

        #expect(store.routingSettings.padOutputID == 30)
        #expect(store.routingSettings.padOutputName == "Dillon's AirPods")
        #expect(store.routingSettings.clickOutputID == 20)
        #expect(store.systemCheck.canStartPlayback)
    }

    @Test func routingSelectionPersistsToJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainRoutingTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 11, name: "Pads Bus", isDefault: true),
                    AudioOutputDevice(id: 12, name: "Click Bus", isDefault: false)
                ],
                padOutputID: 11,
                padOutputName: "Pads Bus",
                clickOutputID: 12,
                clickOutputName: "Click Bus",
                independentRoutingEnabled: true
            )
        )
        let store = AppStore.preview(libraryStore: libraryStore, audioRoutingProvider: provider)

        store.updateRouting(padOutputID: 11, clickOutputID: 12)

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(loaded.routingSettings.padOutputID == 11)
        #expect(loaded.routingSettings.padOutputName == "Pads Bus")
        #expect(loaded.routingSettings.clickOutputID == 12)
        #expect(loaded.routingSettings.clickOutputName == "Click Bus")
    }

    @Test func manualRoutingChangeStopsLivePlayback() {
        let audio = RecordingAudioEngine()
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 11, name: "Pads Bus", isDefault: true),
                    AudioOutputDevice(id: 12, name: "Click Bus", isDefault: false)
                ],
                padOutputID: 11,
                padOutputName: "Pads Bus",
                clickOutputID: 12,
                clickOutputName: "Click Bus",
                independentRoutingEnabled: true
            )
        )
        let store = AppStore.preview(audioEngine: audio, audioRoutingProvider: provider)

        store.startCuedSong()
        store.updateRouting(padOutputID: 11, clickOutputID: 12)

        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.lastMessage == "Audio routing changed. Playback stopped so outputs can be rechecked.")
        #expect(audio.stopAllCount == 1)
    }

    @Test func manualRoutingChangeStopsRehearsalPlayback() {
        let audio = RecordingAudioEngine()
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(id: 11, name: "Pads Bus", isDefault: true)
                ],
                padOutputID: 11,
                padOutputName: "Pads Bus",
                clickOutputID: 11,
                clickOutputName: "Pads Bus",
                independentRoutingEnabled: false
            )
        )
        let store = AppStore.preview(audioEngine: audio, audioRoutingProvider: provider)

        store.startRehearsePad(key: .g)
        store.updateRouting(padOutputID: 11, clickOutputID: 11)

        #expect(store.rehearse.padState == .off)
        #expect(store.rehearse.lastMessage == "Audio routing changed. Playback stopped so outputs can be rechecked.")
        #expect(audio.stopAllCount == 1)
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
    var shouldFailPadStart = false
    var shouldFailClickStart = false
    var shouldFailConfigureRouting = false
    var statusSummary: String { isEngineRunning ? "Running" : "Stopped" }

    init(missingPadKeys: Set<MusicalKey> = []) {
        self.missingPadKeys = missingPadKeys
    }

    func prepare() {}

    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws {
        if shouldFailConfigureRouting {
            throw AudioEngineError.invalidOutputFormat
        }
    }

    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String {
        missingPadKeys.contains(key) ? "Missing bundled pad \(key.rawValue).mp3" : "Found \(key.rawValue).mp3"
    }

    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool {
        !missingPadKeys.contains(key)
    }

    func startPad(for key: MusicalKey, padPack: PadPack) throws {
        padStartCount += 1
        if shouldFailPadStart {
            throw AudioEngineError.unreadablePadFile(URL(fileURLWithPath: "\(key.rawValue).mp3"))
        }
        padIsActive = true
    }

    func stopPad() {
        padIsActive = false
    }

    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool) throws {
        clickStartCount += 1
        clickIncludesCountoffHistory.append(includesCountoff)
        if shouldFailClickStart {
            throw AudioEngineError.invalidOutputFormat
        }
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
