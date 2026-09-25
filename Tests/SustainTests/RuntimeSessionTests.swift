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
        #expect(store.systemCheck.messages.contains("Ready for Goodness of God at 72 BPM."))
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

    @Test func rehearseCountoffExposesAndClearsBeatProgress() async {
        let store = AppStore.preview(countoffDurationMultiplier: 0)
        store.startRehearseClick()

        #expect(store.rehearse.clickState == .countoff)
        #expect(store.rehearse.countoffBeat == 1)
        #expect(store.rehearse.countoffTotal == store.rehearse.timeSignature.beatsPerMeasure)

        for _ in 0..<20 where store.rehearse.clickState != .playing {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(store.rehearse.clickState == .playing)
        #expect(store.rehearse.countoffBeat == nil)
        #expect(store.rehearse.countoffTotal == nil)

        store.stopRehearseClick()
        #expect(store.rehearse.countoffBeat == nil)
        #expect(store.rehearse.countoffTotal == nil)
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

        // The previous song and its truthful countoff state remain untouched because target
        // preparation failed before the transition commit.
        #expect(store.runtime.playingEntryID == playing)
        #expect(store.runtime.countoffBeat != nil)
        #expect(store.runtime.padState != .off)
    }

    @Test func systemCheckWarnsAboutMissingPadAssetsLaterInSetlist() {
        // Holy Forever is later in the seed setlist and resolves to its default key A.
        let audio = RecordingAudioEngine(missingPadKeys: [.a])
        let store = AppStore.preview(audioEngine: audio)

        store.runSystemCheck()

        #expect(store.systemCheck.canStartPlayback)
        #expect(store.systemCheck.warnings.contains("Holy Forever: Locate the missing file for A."))
        #expect(store.systemCheck.messages.contains("Warning: Holy Forever: Locate the missing file for A."))
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
        #expect(store.runtime.padState != .off)
        #expect(audio.padStartCount == padStarts)
        #expect(store.runtime.lastMessage == AudioEngineError.invalidOutputFormat.localizedDescription)
    }

    @Test func lateTransitionPreparationDoesNotRestoreStoppedSong() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        store.cueNextSong()

        audio.defersClickPreparation = true
        store.startCuedSong()
        #expect(store.runtime.playbackPhase == .songStarting)

        store.stop()
        audio.completePendingClickPreparation()

        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.playbackPhase == .noSongPlaying)
        #expect(store.runtime.clickState == .off)
        #expect(!audio.isClickActive)
    }

    @Test func rejectedPadActivationDoesNotStartClickOrClaimPad() {
        let audio = RecordingAudioEngine()
        audio.shouldRejectPadActivation = true
        let store = AppStore.preview(audioEngine: audio)

        store.startCuedSong()

        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.padState == .off)
        #expect(store.runtime.clickState == .off)
        #expect(store.runtime.audiblePadTrackID == nil)
        #expect(audio.clickStartCount == 0)
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
        #expect(audio.clickStartCount == 0)
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
        #expect(store.rehearse.padState == .fadingIn)
        #expect(audio.padStartCount == 1)
    }

    @Test func padPlaybackStateStaysConsistentAcrossScreens() {
        let store = AppStore.preview(audioEngine: RecordingAudioEngine())
        let padID = PadTrack.includedID(for: .e)

        store.startRehearsePad(padID: padID)
        #expect(store.padPlaybackState(for: padID) == .fadingIn)

        store.selectedScreen = .pads
        #expect(store.padPlaybackState(for: padID) == .fadingIn)
        store.togglePadPlayback(for: padID)
        #expect(store.padPlaybackState(for: padID) == .off)
        #expect(store.selectedScreen == .pads)
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
        #expect(store.runtime.padState != .off)
        #expect(store.runtime.playbackPhase == .songPlaying)
        #expect(store.runtime.playingEntryID == playingID)
        #expect(!audio.isClickActive)
        #expect(audio.isPadActive)
    }

    @Test func canonicalLiveSongEditRetimesClickWithoutRestartingAudiblePad() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let entry = try #require(store.playingEntry)
        let song = try #require(store.song(for: entry))
        let padStarts = audio.padStartCount

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
        #expect(audio.padStartCount == padStarts)
        #expect(audio.clickBPMHistory.last == 96)
        #expect(audio.clickTimeSignatureHistory.last == .sixEight)
        #expect(audio.clickIncludesCountoffHistory.last == false)
        #expect(store.runtime.clickState == .playing)
        #expect(store.runtime.padState != .off)
    }

    @Test func songDraftCancelAndValidationLeaveLibraryUntouched() {
        let store = AppStore.preview()
        let original = store.songs

        _ = SongDraft.newSong() // Closing a new draft does not create a placeholder.
        #expect(store.songs == original)

        var draft = SongDraft.newSong()
        #expect(store.saveSongDraft(draft) == nil)
        #expect(store.persistenceStatus == "Enter a song title")
        draft.title = "  New Song  "
        draft.defaultBPM = 221
        #expect(store.saveSongDraft(draft) == nil)
        #expect(store.persistenceStatus == "BPM must be between 40 and 220")
        draft.defaultBPM = 72
        draft.padTrackID = UUID()
        #expect(store.saveSongDraft(draft) == nil)
        #expect(store.persistenceStatus == "The selected pad is unavailable")
        #expect(store.songs == original)
    }

    @Test func songDraftCreatesOnceAndUpdatesExistingSetlistReferences() throws {
        let store = AppStore.preview()
        var draft = SongDraft.newSong()
        draft.title = "  Gratitude  "
        draft.padTrackID = PadTrack.includedID(for: .bb)
        draft.defaultBPM = 82
        draft.timeSignature = .sixEight
        draft.clickSubdivision = .three

        let id = try #require(store.saveSongDraft(draft))
        let created = try #require(store.songs.first { $0.id == id })
        #expect(created.title == "Gratitude")
        #expect(created.defaultKey == .bb)
        #expect(created.padTrackID == PadTrack.includedID(for: .bb))
        #expect(created.defaultBPM == 82)
        #expect(created.timeSignature == .sixEight)
        #expect(created.clickSubdivision == .three)

        let entryID = try #require(store.addSongToSetlist(id))
        var edit = SongDraft(song: created)
        edit.title = "Gratitude (Live)"
        edit.padTrackID = nil
        #expect(store.saveSongDraft(edit) == id)
        #expect(store.songs.filter { $0.id == id }.count == 1)
        #expect(store.activeSetlist.entries.contains { $0.id == entryID && $0.songID == id })
        let edited = try #require(store.songs.first { $0.id == id })
        #expect(edited.padTrackID == nil)
        #expect(edited.defaultKey == .bb)
    }

    @Test func songDraftCustomPadPreservesStoredKey() throws {
        let store = AppStore.preview()
        let original = try #require(store.songs.first)
        let custom = PadTrack(
            id: UUID(),
            label: "Ambient",
            source: .external(ExternalAudioReference(
                bookmarkData: Data([9]),
                lastKnownPath: "/tmp/Ambient.wav",
                originalFilename: "Ambient.wav",
                fingerprint: ExternalFileFingerprint(resourceIdentifierData: nil, fileSize: 64, modificationDate: nil),
                audioMetadata: PadAudioMetadata(duration: 2, channelCount: 2, sampleRate: 48_000, decodedByteCount: 64)
            ))
        )
        store.padTracks.append(custom)
        var draft = SongDraft(song: original)
        draft.padTrackID = custom.id

        #expect(store.saveSongDraft(draft) == original.id)
        let updated = try #require(store.songs.first { $0.id == original.id })
        #expect(updated.padTrackID == custom.id)
        #expect(updated.defaultKey == original.defaultKey)
    }

    @Test func songDraftPersistsAssignmentAndClickFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainDraftTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)
        var draft = SongDraft.newSong()
        draft.title = "No Pad Song"
        draft.padTrackID = nil
        draft.defaultBPM = 104
        draft.timeSignature = .fiveFour
        draft.clickSubdivision = .three

        let id = try #require(store.saveSongDraft(draft))
        let snapshot = try #require(try libraryStore.loadLibrary())
        let saved = try #require(snapshot.songs.first { $0.id == id })
        #expect(saved.title == "No Pad Song")
        #expect(saved.padTrackID == nil)
        #expect(saved.defaultBPM == 104)
        #expect(saved.timeSignature == .fiveFour)
        #expect(saved.clickSubdivision == .three)
    }

    @Test func genericSongUpdateDoesNotReassignPadWhenKeyChanges() throws {
        let store = AppStore.preview()
        let song = try #require(store.songs.first)
        let originalPadID = song.padTrackID

        #expect(store.updateSong(
            song.id,
            title: "Retitled",
            defaultKey: .bb,
            defaultBPM: 88,
            timeSignature: .fourFour,
            padPackID: PadPack.bundled.id
        ))

        let updated = try #require(store.songs.first { $0.id == song.id })
        #expect(updated.defaultKey == .bb)
        #expect(updated.padTrackID == originalPadID)
    }

    @Test func directIncludedPadAssignmentSynchronizesStoredKey() throws {
        let store = AppStore.preview()
        let song = try #require(store.songs.first)

        #expect(store.setSongPadTrackID(song.id, padTrackID: PadTrack.includedID(for: .bb)))
        let updated = try #require(store.songs.first { $0.id == song.id })
        #expect(updated.padTrackID == PadTrack.includedID(for: .bb))
        #expect(updated.defaultKey == .bb)
    }

    @Test func songDraftLiveEditRetimesClickAndDefersPadUntilNextStart() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let entry = try #require(store.playingEntry)
        let song = try #require(store.song(for: entry))
        let audiblePadID = store.runtime.audiblePadTrackID
        let padStarts = audio.padStartCount
        var draft = SongDraft(song: song)
        draft.defaultBPM = 96
        draft.timeSignature = .sixEight
        draft.clickSubdivision = .two
        draft.padTrackID = PadTrack.includedID(for: .bb)

        #expect(store.saveSongDraft(draft) == song.id)
        #expect(audio.clickBPMHistory.last == 96)
        #expect(audio.clickTimeSignatureHistory.last == .sixEight)
        #expect(audio.clickSubdivisionHistory.last == .two)
        #expect(audio.clickIncludesCountoffHistory.last == false)
        #expect(audio.padStartCount == padStarts)
        #expect(store.runtime.audiblePadTrackID == audiblePadID)
        #expect(store.songs.first { $0.id == song.id }?.padTrackID == PadTrack.includedID(for: .bb))
    }

    @Test func failedLiveClickUpdateDoesNotCommitSongDraft() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let entry = try #require(store.playingEntry)
        let song = try #require(store.song(for: entry))
        var draft = SongDraft(song: song)
        draft.title = "Unsaved live edit"
        draft.defaultBPM = 96
        draft.padTrackID = nil
        audio.shouldFailClickStart = true

        #expect(store.saveSongDraft(draft) == nil)
        #expect(store.songs.first { $0.id == song.id } == song)
        #expect(store.runtime.audiblePadTrackID == song.padTrackID)
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

    @Test func idleCuedPadPrerollIsReusedWhenStartingMatchingSong() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let cuedID = try #require(store.runtime.cuedEntryID)

        store.startCuedPad()
        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.audiblePadEntryID == cuedID)
        #expect(audio.padActivateCount == 1)

        store.startCuedSong()
        #expect(store.runtime.playingEntryID == cuedID)
        #expect(store.runtime.audiblePadEntryID == cuedID)
        #expect(audio.padActivateCount == 1)
        #expect(audio.clickStartCount == 1)
    }

    @Test func cueChangeDuringPrerollReplacesOnlyAfterPreparationSucceeds() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedPad()
        let originalPad = try #require(store.runtime.audiblePadTrackID)
        let secondEntry = store.activeSetlist.entries[1]
        store.cue(entryID: secondEntry.id)

        audio.shouldFailClickStart = true
        store.startCuedSong()
        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.cuedEntryID == secondEntry.id)
        #expect(store.runtime.audiblePadTrackID == originalPad)
        #expect(audio.padActivateCount == 1)

        audio.shouldFailClickStart = false
        store.startCuedSong()
        #expect(store.runtime.playingEntryID == secondEntry.id)
        #expect(store.runtime.audiblePadTrackID != originalPad)
        #expect(audio.padActivateCount == 2)
    }

    @Test func samePadPrerollMismatchTransfersOwnershipWithoutRestart() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedPad()
        let padID = try #require(store.runtime.audiblePadTrackID)
        let secondEntry = store.activeSetlist.entries[1]
        let secondSong = try #require(store.song(for: secondEntry))
        #expect(store.setSongPadTrackID(secondSong.id, padTrackID: padID))
        store.cue(entryID: secondEntry.id)

        store.startCuedSong()
        #expect(store.runtime.playingEntryID == secondEntry.id)
        #expect(store.runtime.audiblePadEntryID == secondEntry.id)
        #expect(store.runtime.audiblePadTrackID == padID)
        #expect(audio.padActivateCount == 1)
    }

    @Test func playingEntryOwnsPadControlEvenWhenItsPadWasManuallyStopped() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        let playingEntry = try #require(store.playingEntry)
        let playingPad = try #require(store.song(for: playingEntry)?.padTrackID)
        let secondEntry = store.activeSetlist.entries[1]
        store.cue(entryID: secondEntry.id)

        // Represent the post-fade state after the operator manually stopped the current pad.
        store.runtime.padState = .off
        store.runtime.audiblePadTrackID = nil
        store.runtime.audiblePadEntryID = nil
        store.toggleLivePad()

        #expect(store.runtime.playingEntryID == playingEntry.id)
        #expect(store.runtime.audiblePadTrackID == playingPad)
        #expect(store.runtime.audiblePadEntryID == playingEntry.id)
    }

    @Test func stoppingPrerollRequiresFadeCompletionBeforeIdleRearm() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedPad()
        store.stopPad()

        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.padState == .fadingOut)
        #expect(!store.isFullyIdleForCuedPad)
        let activations = audio.padActivateCount
        store.startCuedPad()
        #expect(audio.padActivateCount == activations)
    }

    @Test func stopDuringCuedPadPreparationMakesLateCompletionHarmless() {
        let audio = RecordingAudioEngine()
        audio.defersPadPreparation = true
        let store = AppStore.preview(audioEngine: audio)

        store.startCuedPad()
        #expect(store.runtime.padState == .preparing)
        store.stop()
        #expect(store.runtime.padState == .off)
        audio.completePendingPadPreparation()

        #expect(store.runtime.padState == .off)
        #expect(store.runtime.audiblePadTrackID == nil)
        #expect(audio.padActivateCount == 0)
    }

    @Test func stopDuringPlayingPadPreparationMakesLateCompletionHarmless() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let song = try #require(store.song(for: store.cuedEntry))
        #expect(store.setSongPadTrackID(song.id, padTrackID: nil))
        store.startCuedSong()
        #expect(store.runtime.playingEntryID != nil)
        #expect(store.runtime.padState == .off)

        #expect(store.setSongPadTrackID(song.id, padTrackID: PadTrack.includedID(for: .c)))
        audio.defersPadPreparation = true
        store.startPad()
        #expect(store.runtime.padState == .preparing)
        store.stopPad()
        #expect(store.runtime.padState == .off)
        audio.completePendingPadPreparation()

        #expect(store.runtime.padState == .off)
        #expect(store.runtime.audiblePadTrackID == nil)
        #expect(audio.padActivateCount == 0)
        #expect(store.runtime.lastMessage == "Pad stopped")
    }

    @Test func startingNoPadLiveSongInvalidatesPendingRehearsePad() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        audio.defersPadPreparation = true

        store.startRehearsePad(padID: PadTrack.includedID(for: .c))
        #expect(store.rehearse.padState == .preparing)
        let cuedSong = try #require(store.song(for: store.cuedEntry))
        #expect(store.setSongPadTrackID(cuedSong.id, padTrackID: nil))

        store.startCuedSong()
        #expect(store.runtime.playingEntryID == store.runtime.cuedEntryID)
        #expect(store.rehearse.padState == .off)
        audio.completePendingPadPreparation()

        #expect(audio.padActivateCount == 0)
        #expect(!audio.isPadActive)
        #expect(store.rehearse.padState == .off)
    }

    @Test func startingLiveSongCancelsRehearseFadeStateTask() async throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        store.startRehearsePad(padID: PadTrack.includedID(for: .c))
        #expect(store.rehearse.padState == .fadingIn)
        let cuedSong = try #require(store.song(for: store.cuedEntry))
        #expect(store.setSongPadTrackID(cuedSong.id, padTrackID: nil))
        store.startCuedSong()

        try await Task.sleep(for: .seconds(1.3))
        #expect(store.rehearse.padState == .off)
        #expect(store.runtime.playingEntryID == store.runtime.cuedEntryID)
    }

    @Test func cueChangeBeforeCommitCannotReplaceExistingPreroll() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedPad()
        let originalPad = try #require(store.runtime.audiblePadTrackID)
        let second = store.activeSetlist.entries[1]
        store.cue(entryID: second.id)
        audio.defersClickPreparation = true
        store.startCuedSong()
        let third = store.activeSetlist.entries[2]
        store.cue(entryID: third.id)

        audio.completePendingClickPreparation()

        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.cuedEntryID == third.id)
        #expect(store.runtime.audiblePadTrackID == originalPad)
        #expect(audio.padActivateCount == 1)
        #expect(audio.clickStartCount == 0)
    }

    @Test func rehearseUsesStablePadIDsAndDoesNotRestartAudibleSelection() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let first = PadTrack.includedID(for: .c)
        let second = PadTrack.includedID(for: .db)

        store.startRehearsePad(padID: first)
        store.startRehearsePad(padID: first)
        #expect(audio.padActivateCount == 1)
        #expect(store.rehearse.selectedPadTrackID == first)

        store.startRehearsePad(padID: second)
        #expect(audio.padActivateCount == 2)
        #expect(store.rehearse.selectedPadTrackID == second)
        #expect(store.rehearse.selectedPadLabel == "Db")
    }

    @Test func typedUnavailablePadCannotLaunchAndPlayRoutingOpensRehearse() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let padID = PadTrack.includedID(for: .gb)
        store.padAssetStates[padID] = .permissionDenied

        store.playPadInRehearse(padID)

        #expect(store.selectedScreen == .rehearse)
        #expect(audio.padActivateCount == 0)
        #expect(store.rehearse.lastMessage.contains("grant file access"))
    }

    @Test func rehearseClickPreparationCountsAsAudioAndStopInvalidatesLateCompletion() {
        let audio = RecordingAudioEngine()
        audio.defersClickPreparation = true
        let store = AppStore.preview(audioEngine: audio)

        store.startRehearseClick()
        #expect(store.rehearse.clickState == .preparing)
        #expect(store.isAnyAudioActivityActive)
        store.stopRehearseClick()
        audio.completePendingClickPreparation()

        #expect(store.rehearse.clickState == .off)
        #expect(!store.isAnyAudioActivityActive)
        #expect(audio.clickStartCount == 0)
    }

    @Test func liveClickStopInvalidatesLatePreparation() {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        store.stopClick()
        audio.defersClickPreparation = true

        store.startClick()
        #expect(store.runtime.clickState == .preparing)
        store.stopClick()
        audio.completePendingClickPreparation()

        #expect(store.runtime.clickState == .off)
        #expect(audio.clickStartCount == 1)
    }

    // NOTE: The AVSpeechSynthesizer render path (SpeechCountoffVoiceRenderer) cannot be
    // reliably unit-tested here — `write` delivers its buffers on the true main run loop,
    // which the swift-testing @MainActor executor does not pump. It is verified out-of-band
    // (scripts/ probe) and audibly in the running app. Only the pure mapping logic is tested.
}
