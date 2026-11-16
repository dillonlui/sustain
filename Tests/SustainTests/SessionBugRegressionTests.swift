import AVFoundation
import Foundation
import Testing
@testable import Sustain

@MainActor
struct SessionBugRegressionTests {
    @Test func rehearsalControlsSurviveDiskReloadWithoutRestoringTransport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: library)
        store.setRehearseTimeSignature(.sixEight)
        store.setRehearsePulseInterpretation(.grouped)
        store.setRehearseAccentPattern([.strong, .mute])
        store.setRehearseCountoffPolicy(CountoffPolicy(bars: 2, after: .countoffOnly))
        store.setRehearseAccentMode(.downbeat)
        store.setRehearseCountoffSound(.click)
        let snapshot = try #require(try library.loadLibrary())
        let restored = AppStore(songs: snapshot.songs, activeSetlist: snapshot.activeSetlist,
                                audioRoutingProvider: StaticAudioRoutingProvider(snapshotValue: .previewDefault),
                                rehearsePreferences: snapshot.rehearsePreferences)
        #expect(restored.rehearse.timeSignature == .sixEight)
        #expect(restored.rehearse.pulseInterpretation == .grouped)
        #expect(restored.rehearse.clickAccentPattern == [.strong, .mute])
        #expect(restored.rehearse.countoffPolicy == CountoffPolicy(bars: 2, after: .countoffOnly))
        #expect(restored.rehearseClickSettings == store.rehearseClickSettings)
        #expect(restored.rehearse.clickState == .off)
        #expect(restored.rehearse.padState == .off)
        store.setRehearseCountoffEnabled(false)
        let disabled = try #require(try library.loadLibrary())
        #expect(disabled.rehearsePreferences?.session.countoffEnabled == false)
        let disabledStore = AppStore(songs: disabled.songs, activeSetlist: disabled.activeSetlist,
                                    audioRoutingProvider: StaticAudioRoutingProvider(snapshotValue: .previewDefault),
                                    rehearsePreferences: disabled.rehearsePreferences)
        disabledStore.setRehearseCountoffEnabled(true)
        #expect(disabledStore.rehearse.countoffPolicy == CountoffPolicy(bars: 2, after: .countoffOnly))
    }

    @Test func olderLibrariesUseRehearsalDefaults() throws {
        let snapshot = AppStore.seedSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        #expect(decoded.rehearsePreferences == nil)
    }

    @Test func channelMapsSilenceEveryUnselectedHardwareOutput() {
        #expect(AudioOutputChannelSelection.output1.channelMap(outputChannelCount: 2) == [0, -1])
        #expect(AudioOutputChannelSelection.output2.channelMap(outputChannelCount: 2) == [-1, 0])
        #expect(AudioOutputChannelSelection.output2.channelMap(outputChannelCount: 8) == [-1, 0, -1, -1, -1, -1, -1, -1])
        #expect(AudioOutputChannelSelection.stereo.channelMap(outputChannelCount: 4) == [0, 1, -1, -1])
        #expect(AudioOutputChannelSelection.output2.channelMap(outputChannelCount: 1) == nil)
        #expect(AudioOutputChannelSelection.output1.channelMap(outputChannelCount: 0) == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUSTAIN_TEST_HARDWARE"] == "1"))
    func realOutputRetainsIsolationThroughRouteChangesAndPreparation() throws {
        let provider = CoreAudioRoutingProvider()
        let available = provider.snapshot().outputs
        guard let output = available.first(where: { $0.outputChannelCount >= 2 }) else {
            throw SkipHardwareTest.noStereoOutput
        }
        let engine = SustainAudioEngine(voiceRenderer: nil)
        for (pad, click) in [(AudioOutputChannelSelection.output1, AudioOutputChannelSelection.output2),
                             (.output2, .output1), (.stereo, .stereo), (.output1, .output2)] {
            let settings = AudioRoutingSettings(padOutputID: output.id, padOutputChannel: pad,
                                                clickOutputID: output.id, clickOutputChannel: click)
            let snapshot = provider.snapshot(settings: settings)
            engine.resetAudioConnection()
            try engine.configureRouting(snapshot)
            engine.prepare()
            #expect(engine.routingMatches(snapshot))
            engine.setClickVolume(0)
            try engine.startClick(bpm: 72, timeSignature: .fourFour,
                                  includesCountoff: false, settings: .default)
            #expect(engine.routingMatches(snapshot))
            engine.stopAll()
        }
    }
}

private enum SkipHardwareTest: Error {
    case noStereoOutput
}
