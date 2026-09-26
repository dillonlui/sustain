import Testing
@testable import Sustain

struct TapTempoTests {
    @Test func threeTapsProduceEstimateAndIgnoreJitter() {
        var estimator = TapTempoEstimator()
        for time in [0.0, 0.50, 1.02, 1.51] { estimator.tap(at: time) }
        #expect(estimator.bpm == 120)
    }

    @Test func pauseAndOutlierResetSequence() {
        var estimator = TapTempoEstimator()
        for time in [0.0, 0.5, 1.0, 3.1] { estimator.tap(at: time) }
        #expect(estimator.didResetOnLastTap)
        #expect(estimator.bpm == nil)
        for time in [3.6, 4.1, 5.5] { estimator.tap(at: time) }
        #expect(estimator.didResetOnLastTap)
        #expect(estimator.bpm == nil)
    }

    @Test func estimateStaysInSupportedRange() {
        var fast = TapTempoEstimator()
        for time in [0.0, 0.2, 0.4] { fast.tap(at: time) }
        #expect(fast.bpm == 220)
        var slow = TapTempoEstimator()
        for time in [0.0, 1.7, 3.4] { slow.tap(at: time) }
        #expect(slow.bpm == 40)
    }

    @Test func estimateExpiresAfterPauseEvenWithoutAnotherTap() {
        var estimator = TapTempoEstimator()
        for time in [0.0, 0.5, 1.0] { estimator.tap(at: time) }
        #expect(estimator.bpm(at: 2.99) == 120)
        #expect(estimator.bpm(at: 3.0) == nil)
    }
}

@MainActor
struct TapTempoStoreTests {
    @Test func liveTapAppliesOnlyToCuedEntryUntilExplicitSave() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.selectedScreen = .live
        let entry = try #require(store.cuedEntry)
        let original = try #require(store.song(for: entry)?.defaultBPM)
        for time in [0.0, 0.5, 1.0] { store.tapTempo(at: time) }
        #expect(store.useTappedTempo(at: 1.1))
        #expect(store.effectiveBPM(for: entry) == 120)
        #expect(store.song(for: entry)?.defaultBPM == original)
        store.startCuedSong()
        #expect(audio.clickBPMHistory.last == 120)
    }

    @Test func cueChangeDropsProvisionalTaps() throws {
        let store = AppStore.preview()
        store.selectedScreen = .live
        store.tapTempo(at: 0)
        store.tapTempo(at: 0.5)
        store.cueNextSong()
        #expect(store.liveTapTempo.tapCount == 0)
        #expect(!store.useTappedTempo(at: 1.1))
    }

    @Test func rehearseTapRequiresClickStopped() {
        let store = AppStore.preview()
        store.selectedScreen = .rehearse
        for time in [0.0, 0.6, 1.2] { store.tapTempo(at: time) }
        #expect(store.useTappedTempo(at: 1.3))
        #expect(store.rehearse.bpm == 100)
        store.startRehearseClick()
        for time in [2.0, 2.5, 3.0] { store.tapTempo(at: time) }
        #expect(!store.useTappedTempo(at: 3.1))
    }

    @Test func useTempoRejectsExpiredSequence() {
        let store = AppStore.preview()
        store.selectedScreen = .rehearse
        for time in [0.0, 0.5, 1.0] { store.tapTempo(at: time) }
        #expect(!store.useTappedTempo(at: 3.0))
        #expect(store.rehearse.bpm == 72)
    }

    @Test func keyboardAndMIDITapsAreIgnoredDuringPlayback() throws {
        let store = AppStore.preview(audioEngine: RecordingAudioEngine())
        store.selectedScreen = .rehearse
        store.setRehearseCountoffEnabled(false)
        store.startRehearseClick()
        store.tapTempo(at: 1.0)
        #expect(store.rehearseTapTempo.tapCount == 0)
        store.stopRehearseClick()

        store.selectedScreen = .live
        store.startCuedSong()
        store.tapTempo(at: 2.0)
        #expect(store.liveTapTempo.tapCount == 0)
    }

    @Test func mappedMIDINoteNeedsReleaseBeforeAnotherTap() {
        var resolver = MIDIControllerMappingResolver()
        let identity = MIDIMessageIdentity(kind: .noteOn, channel: 0, number: 70)
        let settings = MIDIControllerSettings(isEnabled: true, selectedSource: .any,
            mappings: [MIDIMapping(action: .tapTempo, source: .any, message: identity)])
        let down = MIDIMessage(sourceUniqueID: 1, kind: .noteOn, channel: 0, number: 70, value: 127)
        let up = MIDIMessage(sourceUniqueID: 1, kind: .noteOn, channel: 0, number: 70, value: 0)
        #expect(resolver.action(for: down, settings: settings) == .tapTempo)
        #expect(resolver.action(for: down, settings: settings) == nil)
        #expect(resolver.action(for: up, settings: settings) == nil)
        #expect(resolver.action(for: down, settings: settings) == .tapTempo)
    }
}
