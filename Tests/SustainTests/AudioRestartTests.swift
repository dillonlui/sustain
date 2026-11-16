import Foundation
import Testing
@testable import Sustain

@MainActor
struct AudioRestartTests {
    private func makeStore(_ audio: RecordingAudioEngine) -> (AppStore, MutableAudioRoutingProvider) {
        var snapshot = AudioRoutingSnapshot.previewDefault
        snapshot.outputs[0].name = "Scarlett"
        snapshot.outputs[0].outputChannelCount = 2
        snapshot.padOutputName = "Scarlett"
        snapshot.clickOutputName = "Scarlett"
        snapshot.padOutputChannel = .output2
        snapshot.clickOutputChannel = .output1
        snapshot.independentRoutingEnabled = true
        let provider = MutableAudioRoutingProvider(snapshotValue: snapshot)
        let store = AppStore.preview(audioEngine: audio, audioRoutingProvider: provider)
        store.updateRouting(padOutputID: 1, clickOutputID: 1,
                            padOutputChannel: .output2, clickOutputChannel: .output1)
        return (store, provider)
    }

    @Test func restartStopsPlaybackAndKeepsOutputAssignmentsAndLibrary() {
        let audio = RecordingAudioEngine()
        let (store, _) = makeStore(audio)
        store.startCuedSong()
        let settings = store.routingSettings
        let songs = store.songs
        let cued = store.runtime.cuedEntryID
        let starts = audio.clickStartCount
        let configurations = audio.configureRoutingCount
        store.restartAudio()
        #expect(audio.resetAudioConnectionCount == 1)
        #expect(audio.configureRoutingCount == configurations + 1)
        #expect(audio.clickStartCount == starts)
        #expect(!audio.isPadActive && !audio.isClickActive)
        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.padState == .off && store.runtime.clickState == .off)
        #expect(store.rehearse.padState == .off && store.rehearse.clickState == .off)
        #expect(store.routingSettings == settings)
        #expect(store.songs == songs)
        #expect(store.runtime.cuedEntryID == cued)
        #expect(store.audioRestartResult?.succeeded == true)
        #expect(audio.lastConfiguredSnapshot?.padOutputChannel == .output2)
        #expect(audio.lastConfiguredSnapshot?.clickOutputChannel == .output1)
    }

    @Test func lateRehearsalPreparationCannotResumeAfterRestart() {
        let audio = RecordingAudioEngine()
        let (store, _) = makeStore(audio)
        audio.defersPadPreparation = true
        audio.defersClickPreparation = true
        store.startRehearsePad(padID: store.padTracks[0].id)
        store.startRehearseClick()
        store.restartAudio()
        audio.completePendingPadPreparation()
        audio.completePendingClickPreparation()
        #expect(audio.padActivateCount == 0)
        #expect(audio.clickStartCount == 0)
        #expect(store.rehearse.padState == .off && store.rehearse.clickState == .off)
    }

    @Test func missingInterfacePreservesSelectionsAndNeverConfiguresFallback() {
        let audio = RecordingAudioEngine()
        let (store, provider) = makeStore(audio)
        let settings = store.routingSettings
        let configurations = audio.configureRoutingCount
        provider.snapshotValue = .unavailable
        store.restartAudio()
        #expect(store.audioRestartResult?.succeeded == false)
        #expect(audio.configureRoutingCount == configurations)
        #expect(store.routingSettings == settings)
        #expect(!audio.isPadActive && !audio.isClickActive)
    }

    @Test func failedRestartBlocksPlaybackAndCanBeRetried() {
        let audio = RecordingAudioEngine()
        let (store, _) = makeStore(audio)
        audio.shouldFailConfigureRouting = true
        store.restartAudio()
        #expect(store.audioRestartResult?.succeeded == false)
        #expect(!store.systemCheck.canStartPlayback)
        store.startRehearseClick()
        #expect(audio.clickStartCount == 0)
        audio.shouldFailConfigureRouting = false
        store.restartAudio()
        #expect(store.audioRestartResult?.succeeded == true)
        #expect(store.systemCheck.canStartPlayback)
        #expect(audio.clickStartCount == 0)
    }

    @Test func unacceptedRoutingDoesNotReportSuccessfulRestart() {
        let audio = RecordingAudioEngine()
        let (store, _) = makeStore(audio)
        audio.routingIsValid = false
        store.restartAudio()
        #expect(store.audioRestartResult?.succeeded == false)
        #expect(!store.systemCheck.canStartPlayback)
        #expect(audio.resetAudioConnectionCount == 2)
    }
}
