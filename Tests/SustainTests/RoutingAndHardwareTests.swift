import Foundation
import CoreAudio
import Testing
@testable import Sustain

extension RuntimeSessionTests {
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

    @Test func sameDeviceChannelSplitClearsSharedOutputWarning() {
        let resolver = AudioRoutingResolver()
        let snapshot = resolver.snapshot(
            settings: AudioRoutingSettings(
                padOutputID: 10,
                padOutputName: "Scarlett 2i2",
                padOutputChannel: .output1,
                clickOutputID: 10,
                clickOutputName: "Scarlett 2i2",
                clickOutputChannel: .output2
            ),
            outputs: [
                AudioOutputDevice(
                    id: 10,
                    name: "Scarlett 2i2",
                    isDefault: true,
                    outputChannelCount: 2,
                    nominalSampleRate: 48_000
                )
            ]
        )

        #expect(snapshot.independentRoutingEnabled)
        #expect(snapshot.warning == nil)
        #expect(snapshot.padRouteName == "Scarlett 2i2 Output 1 / Left")
        #expect(snapshot.clickRouteName == "Scarlett 2i2 Output 2 / Right")
    }

    @Test func unavailableChannelSelectionBlocksPlayback() {
        let resolver = AudioRoutingResolver()
        let snapshot = resolver.snapshot(
            settings: AudioRoutingSettings(
                padOutputID: 10,
                padOutputName: "Mono Output",
                padOutputChannel: .output2,
                clickOutputID: 10,
                clickOutputName: "Mono Output"
            ),
            outputs: [
                AudioOutputDevice(id: 10, name: "Mono Output", isDefault: true, outputChannelCount: 1)
            ]
        )

        #expect(!snapshot.independentRoutingEnabled)
        #expect(snapshot.missingSelectionMessages == ["Selected pad output channel is unavailable."])
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

    @Test func audioOutputDiagnosticSummaryIncludesChannelsAndSampleRate() {
        let output = AudioOutputDevice(
            id: 10,
            name: "Scarlett 4i4",
            isDefault: false,
            outputChannelCount: 4,
            nominalSampleRate: 48_000
        )

        #expect(output.diagnosticSummary == "4 output channels @ 48000 Hz")
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
                padOutputUnavailable: true
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
                clickOutputUnavailable: true
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
            clickOutputUnavailable: true
        )

        store.startCuedSong()

        #expect(store.runtime.lastMessage == "Playback blocked by system check")
        #expect(!store.systemCheck.canStartPlayback)
        #expect(audio.padStartCount == 0)
        #expect(audio.clickStartCount == 0)
    }

    @Test func startSongConfiguresRefreshedRoutingBeforePlayback() {
        let audio = RecordingAudioEngine()
        let provider = MutableAudioRoutingProvider(snapshotValue: .previewDefault)
        let store = AppStore.preview(audioEngine: audio, audioRoutingProvider: provider)
        let startupConfigureCount = audio.configureRoutingCount

        provider.snapshotValue = AudioRoutingSnapshot(
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

        store.startCuedSong()

        #expect(audio.configureRoutingCount == startupConfigureCount + 1)
        #expect(audio.lastConfiguredSnapshot?.padOutputID == 11)
        #expect(audio.lastConfiguredSnapshot?.clickOutputID == 12)
        #expect(audio.padStartCount == 1)
        #expect(audio.clickStartCount == 1)
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
            clickOutputUnavailable: true
        )
        monitor.simulateChange()

        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.padState == .off)
        #expect(store.runtime.clickState == .off)
        #expect(store.runtime.lastMessage == "Selected click output is unavailable.")
        #expect(audio.stopAllCount == 1)
    }

    @Test func hardwareChangeKeepsPlayingWhenUsedOutputsUnchanged() {
        // Pad (AirPods=1) and click (MacBook=2) are explicitly selected. Only the unrelated
        // system default moves (1 -> 3); our two devices are untouched, so the engine is
        // unaffected and playback should CONTINUE mid-service — while still surfacing the prompt
        // so the operator can switch to the new default on purpose.
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

        #expect(store.runtime.playbackPhase == .songPlaying)
        #expect(store.runtime.padState == .playing)
        #expect(store.audioRouteChangePrompt?.detectedOutputID == 3)
        #expect(audio.stopAllCount == 0)
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
                padOutputUnavailable: true
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
            padOutputUnavailable: true
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
                clickOutputUnavailable: true
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
            padOutputUnavailable: true
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

}
