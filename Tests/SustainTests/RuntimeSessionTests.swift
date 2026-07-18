import Foundation
import CoreAudio
import Testing
@testable import Sustain

@MainActor
struct RuntimeSessionTests {
    @Test func refreshReadinessReportsReadyWithoutTouchingEngine() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let routingCallsBefore = audio.configureRoutingCount

        store.refreshReadiness()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.messages.contains("Ready for Goodness of God in G at 72 BPM."))
        // The safety-net must NOT reconfigure audio (that is runSystemCheck's job).
        #expect(audio.configureRoutingCount == routingCallsBefore)
    }

    @Test func refreshReadinessBlocksWhenPadOutputUnavailable() {
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [AudioOutputDevice(id: 2, name: "Click Bus", isDefault: true)],
                padOutputID: 2,
                padOutputName: "Click Bus",
                clickOutputID: 2,
                clickOutputName: "Click Bus",
                independentRoutingEnabled: false,
                padOutputUnavailable: true
            )
        )
        let store = AppStore.preview(audioRoutingProvider: provider)

        store.refreshReadiness()

        #expect(!store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.messages.contains("Selected pad output is unavailable."))
    }

    @Test func refreshReadinessIsNeutralWhenNothingCued() {
        let store = AppStore.preview()
        for entry in store.activeSetlist.entries { store.removeSetlistEntry(entry.id) }

        store.refreshReadiness()

        #expect(store.systemCheck == .notRun)
    }

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

    @Test func clickSettingsDefaultToCountedUnaccentedClick() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        store.startCuedSong()

        #expect(audio.clickSettingsHistory.last == .default)
        #expect(audio.clickSettingsHistory.last?.accentMode == ClickAccentMode.none)
        #expect(audio.clickSettingsHistory.last?.countoffSound == .counted)
    }

    @Test func updatingRehearseClickAccentRestartsActiveClick() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        store.startRehearseClick()
        store.setClickAccentMode(.downbeat)

        #expect(audio.clickStartCount == 2)
        #expect(audio.clickSettingsHistory.last?.accentMode == .downbeat)
        #expect(audio.clickIncludesCountoffHistory.last == false)
    }

    @Test func invalidTransitionDoesNotDestroyPlayingState() {
        // Cueing forward lands on Holy Forever (default key A); make its pad missing.
        let audio = RecordingAudioEngine(missingPadKeys: [.a])
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

    @Test func restartingTheAlreadyPlayingSongIsIgnored() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let playing = store.runtime.playingEntryID
        let padStarts = audio.padStartCount
        let clickStarts = audio.clickStartCount

        // After Start, the cued entry is still the playing entry (cueing does not
        // auto-advance). Pressing Start again (button / Return / ⌘Return) must not
        // interrupt the live song with a fresh countoff + pad self-crossfade.
        #expect(store.runtime.cuedEntryID == playing)
        store.startCuedSong()

        #expect(store.runtime.playingEntryID == playing)
        #expect(audio.padStartCount == padStarts)
        #expect(audio.clickStartCount == clickStarts)
    }

    @Test func failedTransitionClearsStaleCountoffBadge() async {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio, countoffDurationMultiplier: 1.0)
        store.startCuedSong()

        // Let the visual countoff for the first song advance to a beat.
        for _ in 0..<200 where store.runtime.countoffBeat == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(store.runtime.countoffBeat != nil)
        let playing = store.runtime.playingEntryID

        // Cue a different song and attempt a transition whose click start fails.
        audio.shouldFailClickStart = true
        store.cueNextSong()
        store.startCuedSong()

        // The previous song keeps playing, and the stale countoff badge is cleared
        // rather than left frozen on screen after the failure.
        #expect(store.runtime.playingEntryID == playing)
        #expect(store.runtime.countoffBeat == nil)
        #expect(store.runtime.padState == .playing)
    }

    @Test func systemCheckWarnsAboutMissingPadAssetsLaterInSetlist() {
        // Holy Forever is later in the seed setlist and resolves to its default key A.
        let audio = RecordingAudioEngine(missingPadKeys: [.a])
        let store = AppStore.preview(audioEngine: audio)

        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings.contains("Holy Forever: Missing included pad A.mp3"))
        #expect(store.systemCheck.messages.contains("Warning: Holy Forever: Missing included pad A.mp3"))
    }

    @Test func systemCheckWarnsAboutInvalidBPMLaterInSetlist() throws {
        let store = AppStore.preview()
        let laterEntry = store.activeSetlist.entries[1]

        let songIndex = try #require(store.songs.firstIndex { $0.id == laterEntry.songID })
        store.songs[songIndex].defaultBPM = 0
        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings.contains("King of Kings: needs a valid BPM."))
        #expect(store.systemCheck.messages.contains("Warning: King of Kings: needs a valid BPM."))
    }

    @Test func systemCheckWarnsAboutMissingSongReferencesLaterInSetlist() {
        let snapshot = AppStore.seedSnapshot()
        var activeSetlist = snapshot.activeSetlist
        activeSetlist.entries.append(SetlistEntry(songID: UUID()))
        let store = AppStore(
            songs: snapshot.songs,
            activeSetlist: activeSetlist,
            audioRoutingProvider: StaticAudioRoutingProvider(snapshotValue: .previewDefault)
        )

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

    @Test func channelRoutingSelectionPersistsToJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainChannelRoutingTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let provider = StaticAudioRoutingProvider(
            snapshotValue: AudioRoutingSnapshot(
                outputs: [
                    AudioOutputDevice(
                        id: 11,
                        name: "Scarlett 2i2",
                        isDefault: true,
                        outputChannelCount: 2
                    )
                ],
                padOutputID: 11,
                padOutputName: "Scarlett 2i2",
                clickOutputID: 11,
                clickOutputName: "Scarlett 2i2",
                independentRoutingEnabled: true,
                padOutputChannel: .output1,
                clickOutputChannel: .output2
            )
        )
        let store = AppStore.preview(libraryStore: libraryStore, audioRoutingProvider: provider)

        store.updateRouting(
            padOutputID: 11,
            clickOutputID: 11,
            padOutputChannel: .output1,
            clickOutputChannel: .output2
        )

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(loaded.routingSettings.padOutputID == 11)
        #expect(loaded.routingSettings.padOutputChannel == .output1)
        #expect(loaded.routingSettings.clickOutputID == 11)
        #expect(loaded.routingSettings.clickOutputChannel == .output2)
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

    @Test func audioChannelVolumesApplyAndPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainVolumeTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio, libraryStore: libraryStore)

        store.setPadVolume(0.64)
        store.setClickVolume(0.28)

        #expect(store.padVolume == 0.64)
        #expect(store.clickVolume == 0.28)
        #expect(audio.lastPadVolume == 0.64)
        #expect(audio.lastClickVolume == 0.28)

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(loaded.padVolume == 0.64)
        #expect(loaded.clickVolume == 0.28)
    }

    @Test func liveVolumeChangesDeferPersistenceUntilCommit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainLevelTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)

        store.setPadVolumeLive(0.9)
        store.setClickVolumeLive(0.1)

        #expect(store.padVolume == 0.9)
        #expect(store.clickVolume == 0.1)
        // Nothing has been persisted yet during the "drag".
        #expect(try libraryStore.loadLibrary() == nil)

        store.commitAudioLevels()

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(loaded.padVolume == 0.9)
        #expect(loaded.clickVolume == 0.1)
    }

    @Test func rehearsePadSelectionStartsIncludedPad() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        store.startRehearsePad(key: .e)

        #expect(store.rehearse.selectedKey == .e)
        #expect(store.rehearse.padState == .playing)
        #expect(audio.padStartCount == 1)
    }

    @Test func countoffWordsCoverEverySupportedBeat() {
        #expect(SpeechCountoffVoiceRenderer.word(for: 1) == "one")
        #expect(SpeechCountoffVoiceRenderer.word(for: 4) == "four")
        #expect(SpeechCountoffVoiceRenderer.word(for: 6) == "six")
        #expect(SpeechCountoffVoiceRenderer.word(for: 12) == "twelve")
        #expect(SpeechCountoffVoiceRenderer.word(for: 0) == nil)
        #expect(SpeechCountoffVoiceRenderer.word(for: 13) == nil)
    }

    @Test func supportedTimeSignaturesAllMapToCountoffWords() {
        for timeSignature in TimeSignature.common {
            for beat in 1...timeSignature.beatsPerMeasure {
                #expect(SpeechCountoffVoiceRenderer.word(for: beat) != nil)
            }
        }
    }

    @Test func startingSongImmediatelyEntersCountoffWithBeatCount() {
        let store = AppStore.preview(countoffDurationMultiplier: 100)
        store.startCuedSong()

        // First cued song is "Goodness of God" in 4/4 → four count-in beats.
        #expect(store.runtime.clickState == .countoff)
        #expect(store.runtime.countoffBeat == 1)
        #expect(store.runtime.countoffTotal == 4)
    }

    @Test func stoppingDuringCountoffClearsCountoffState() async {
        let store = AppStore.preview(countoffDurationMultiplier: 100)
        store.startCuedSong()

        for _ in 0..<400 where store.runtime.countoffBeat == nil {
            try? await Task.sleep(nanoseconds: 500_000)
        }
        store.stop()

        #expect(store.runtime.countoffBeat == nil)
        #expect(store.runtime.countoffTotal == nil)
        #expect(store.runtime.clickState == .off)
    }

    @Test func stoppingLiveClickLeavesPadAndPlayingSongActive() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let playingID = store.runtime.playingEntryID

        store.stopClick()

        #expect(store.runtime.clickState == .off)
        #expect(store.runtime.padState == .playing)
        #expect(store.runtime.playbackPhase == .songPlaying)
        #expect(store.runtime.playingEntryID == playingID)
        #expect(!audio.isClickActive)
        #expect(audio.isPadActive)
    }

    @Test func canonicalLiveSongEditRetimesClickAndCrossfadesPadWithoutCountoff() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let entry = try #require(store.playingEntry)
        let song = try #require(store.song(for: entry))

        let updated = store.updateSong(
            song.id,
            title: song.title,
            defaultKey: .bb,
            defaultBPM: 96,
            timeSignature: .sixEight,
            padPackID: PadPack.bundled.id
        )

        let canonical = try #require(store.songs.first { $0.id == song.id })
        #expect(updated)
        #expect(canonical.defaultKey == .bb)
        #expect(canonical.defaultBPM == 96)
        #expect(canonical.timeSignature == .sixEight)
        #expect(audio.startedPadKeys.last == .bb)
        #expect(audio.clickBPMHistory.last == 96)
        #expect(audio.clickTimeSignatureHistory.last == .sixEight)
        #expect(audio.clickIncludesCountoffHistory.last == false)
        #expect(store.runtime.clickState == .playing)
        #expect(store.runtime.padState == .playing)
    }

    @Test func canonicalSongEditUpdatesEveryDuplicateSetlistOccurrence() throws {
        let store = AppStore.preview()
        let song = try #require(store.songs.first)
        _ = store.addSongToSetlist(song.id)

        store.updateSong(
            song.id,
            title: song.title,
            defaultKey: .a,
            defaultBPM: 84,
            timeSignature: song.timeSignature,
            padPackID: PadPack.bundled.id
        )

        let matchingEntries = store.activeSetlist.entries.filter { $0.songID == song.id }
        let canonical = try #require(store.songs.first { $0.id == song.id })
        #expect(matchingEntries.count == 2)
        #expect(canonical.defaultKey == .a)
        #expect(canonical.defaultBPM == 84)
    }

    @Test func cuingASongRefreshesReadiness() {
        let store = AppStore.preview()
        // Move the cue to the second entry and confirm systemCheck reflects it.
        let second = store.activeSetlist.entries[1].id
        store.cue(entryID: second)

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.messages.contains { $0.hasPrefix("Ready for ") })
    }

    // NOTE: The AVSpeechSynthesizer render path (SpeechCountoffVoiceRenderer) cannot be
    // reliably unit-tested here — `write` delivers its buffers on the true main run loop,
    // which the swift-testing @MainActor executor does not pump. It is verified out-of-band
    // (scripts/ probe) and audibly in the running app. Only the pure mapping logic is tested.
}
