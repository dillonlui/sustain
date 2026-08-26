import Foundation
import Testing
@testable import Sustain

@Suite("Pad and MIDI domain")
@MainActor
struct PadAndMIDIDomainTests {
    private func customPad(label: String = "Custom") -> PadTrack {
        PadTrack(
            id: UUID(),
            label: label,
            source: .external(ExternalAudioReference(
                bookmarkData: Data([9]),
                lastKnownPath: "/tmp/\(label).wav",
                originalFilename: "\(label).wav",
                fingerprint: ExternalFileFingerprint(resourceIdentifierData: Data([9]), fileSize: 64, modificationDate: nil),
                audioMetadata: PadAudioMetadata(duration: 2, channelCount: 2, sampleRate: 48_000, decodedByteCount: 64)
            ))
        )
    }

    @Test func includedPadIDsAreStableUniqueLiterals() {
        let expected = [
            "7B14A9F0-0A01-4B75-9000-000000000001",
            "7B14A9F0-0A01-4B75-9000-000000000002",
            "7B14A9F0-0A01-4B75-9000-000000000003",
            "7B14A9F0-0A01-4B75-9000-000000000004",
            "7B14A9F0-0A01-4B75-9000-000000000005",
            "7B14A9F0-0A01-4B75-9000-000000000006",
            "7B14A9F0-0A01-4B75-9000-000000000007",
            "7B14A9F0-0A01-4B75-9000-000000000008",
            "7B14A9F0-0A01-4B75-9000-000000000009",
            "7B14A9F0-0A01-4B75-9000-00000000000A",
            "7B14A9F0-0A01-4B75-9000-00000000000B",
            "7B14A9F0-0A01-4B75-9000-00000000000C"
        ]
        let actual = PadTrack.included.map(\.id.uuidString)
        #expect(actual == expected)
        #expect(Set(actual).count == MusicalKey.allCases.count)
    }

    @Test func v2MissingPadAndMIDIFieldsMigrateWithoutDataLoss() throws {
        let seed = AppStore.seedSnapshot()
        let encoder = JSONEncoder()
        let currentData = try encoder.encode(seed)
        var root = try #require(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        root["schemaVersion"] = 2
        root.removeValue(forKey: "padTracks")
        root.removeValue(forKey: "midiControllerSettings")
        var songs = try #require(root["songs"] as? [[String: Any]])
        for index in songs.indices { songs[index].removeValue(forKey: "padTrackID") }
        root["songs"] = songs

        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let migrated = try JSONDecoder().decode(LibrarySnapshot.self, from: legacyData)

        #expect(migrated.schemaVersion == LibrarySnapshot.currentSchemaVersion)
        #expect(migrated.needsMigrationSave)
        #expect(migrated.padTracks == PadTrack.included)
        #expect(migrated.midiControllerSettings == .disabled)
        #expect(migrated.routingSettings == seed.routingSettings)
        #expect(migrated.activeSetlist == seed.activeSetlist)
        for song in migrated.songs {
            #expect(song.padTrackID == PadTrack.includedID(for: song.defaultKey))
        }
    }

    @Test func currentSchemaDistinguishesNullValueAndMissingPadAssignment() throws {
        let seed = AppStore.seedSnapshot()
        var noPadSongs = seed.songs
        noPadSongs[0].padTrackID = nil
        let noPad = LibrarySnapshot(
            songs: noPadSongs,
            padTracks: seed.padTracks,
            activeSetlist: seed.activeSetlist
        )
        let encoder = JSONEncoder()
        let noPadData = try encoder.encode(noPad)
        let decodedNoPad = try JSONDecoder().decode(LibrarySnapshot.self, from: noPadData)
        #expect(decodedNoPad.songs[0].padTrackID == nil)

        var valuedSongs = seed.songs
        valuedSongs[0].padTrackID = PadTrack.includedID(for: .bb)
        let valued = LibrarySnapshot(
            songs: valuedSongs,
            padTracks: seed.padTracks,
            activeSetlist: seed.activeSetlist
        )
        let decodedValue = try JSONDecoder().decode(
            LibrarySnapshot.self,
            from: encoder.encode(valued)
        )
        #expect(decodedValue.songs[0].padTrackID == PadTrack.includedID(for: .bb))

        var root = try #require(JSONSerialization.jsonObject(with: noPadData) as? [String: Any])
        var songs = try #require(root["songs"] as? [[String: Any]])
        songs[0].removeValue(forKey: "padTrackID")
        root["songs"] = songs
        let invalid = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LibrarySnapshot.self, from: invalid)
        }
    }

    @Test func includedNormalizationPreservesUnifiedUserOrder() {
        let custom = PadTrack(
            id: UUID(),
            label: "Prayer Room",
            source: .external(
                ExternalAudioReference(
                    bookmarkData: Data([1, 2, 3]),
                    lastKnownPath: "/redacted/Prayer Room.wav",
                    originalFilename: "Prayer Room.wav",
                    fingerprint: ExternalFileFingerprint(resourceIdentifierData: nil, fileSize: 42, modificationDate: nil),
                    audioMetadata: PadAudioMetadata(duration: 4, channelCount: 2, sampleRate: 48_000, decodedByteCount: 128)
                )
            )
        )
        var supplied = [PadTrack.included[0], custom, PadTrack.included[1]]
        supplied[0].label = "Attempted bundled rename"
        let song = Song(title: "Song", defaultKey: .c, defaultBPM: 72, timeSignature: .fourFour, padPack: .bundled)
        let snapshot = LibrarySnapshot(
            songs: [song],
            padTracks: supplied,
            activeSetlist: Setlist(title: "Set", entries: [SetlistEntry(songID: song.id)])
        )

        #expect(snapshot.padTracks[0] == PadTrack.included[0])
        #expect(snapshot.padTracks[1] == custom)
        #expect(snapshot.padTracks[2] == PadTrack.included[1])
        #expect(Set(snapshot.padTracks.filter(\.isIncluded).map(\.id)).count == 12)
    }

    @Test func midiDefaultsAndCodableRoundTrip() throws {
        let mapping = MIDIMapping(
            action: .togglePad,
            source: .source(uniqueID: 4242),
            message: MIDIMessageIdentity(kind: .controlChange, channel: 9, number: 64)
        )
        let settings = MIDIControllerSettings(isEnabled: true, selectedSource: .source(uniqueID: 4242), mappings: [mapping])
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(MIDIControllerSettings.self, from: data) == settings)
        #expect(MIDIControllerSettings.disabled.mappings.isEmpty)
        #expect(!MIDIControllerSettings.disabled.isEnabled)
    }

    @Test func midiResolverFiltersSourceAndChannelAndRejectsDuplicates() {
        let mapping = MIDIMapping(
            action: .startTransition,
            source: .source(uniqueID: 11),
            message: MIDIMessageIdentity(kind: .noteOn, channel: 2, number: 60)
        )
        let duplicate = MIDIMapping(action: .stopAll, source: mapping.source, message: mapping.message)
        #expect(MIDIControllerMappingResolver.duplicateIdentity(in: [mapping], candidate: duplicate) == mapping)

        let settings = MIDIControllerSettings(isEnabled: true, selectedSource: .any, mappings: [mapping])
        var resolver = MIDIControllerMappingResolver()
        #expect(resolver.action(for: MIDIMessage(sourceUniqueID: 12, kind: .noteOn, channel: 2, number: 60, value: 127), settings: settings) == nil)
        #expect(resolver.action(for: MIDIMessage(sourceUniqueID: 11, kind: .noteOn, channel: 3, number: 60, value: 127), settings: settings) == nil)
        #expect(resolver.action(for: MIDIMessage(sourceUniqueID: 11, kind: .noteOn, channel: 2, number: 60, value: 0), settings: settings) == nil)
        #expect(resolver.action(for: MIDIMessage(sourceUniqueID: 11, kind: .noteOn, channel: 2, number: 60, value: 127), settings: settings) == .startTransition)
    }

    @Test func ccFiresOnlyOnZeroToNonzeroEdgeAndResetsPerSource() {
        let mapping = MIDIMapping(
            action: .toggleClick,
            source: .source(uniqueID: 7),
            message: MIDIMessageIdentity(kind: .controlChange, channel: 0, number: 12)
        )
        let settings = MIDIControllerSettings(isEnabled: true, selectedSource: .any, mappings: [mapping])
        var resolver = MIDIControllerMappingResolver()
        let zero = MIDIMessage(sourceUniqueID: 7, kind: .controlChange, channel: 0, number: 12, value: 0)
        let down = MIDIMessage(sourceUniqueID: 7, kind: .controlChange, channel: 0, number: 12, value: 127)

        #expect(resolver.action(for: down, settings: settings) == .toggleClick)
        #expect(resolver.action(for: down, settings: settings) == nil)
        #expect(resolver.action(for: zero, settings: settings) == nil)
        #expect(resolver.action(for: down, settings: settings) == .toggleClick)
        resolver.reset(sourceUniqueID: 7)
        #expect(resolver.action(for: down, settings: settings) == .toggleClick)
    }

    @Test func customPadRenameReorderAndRemovalAreAtomicAndUndoable() throws {
        let store = AppStore.preview()
        let custom = customPad(label: "Room")
        store.padTracks.insert(custom, at: 1)
        let songID = try #require(store.songs.first?.id)
        #expect(store.setSongPadTrackID(songID, padTrackID: custom.id))
        let undo = UndoManager()

        #expect(store.renamePad(custom.id, label: "  Room Wide  ", undoManager: undo))
        #expect(store.padTracks.first(where: { $0.id == custom.id })?.label == "Room Wide")
        #expect(store.movePad(custom.id, by: 2, undoManager: undo))
        #expect(store.padTracks.firstIndex(where: { $0.id == custom.id }) == 3)

        #expect(store.removePads([custom.id], replacementPadID: nil, undoManager: undo))
        #expect(!store.padTracks.contains(where: { $0.id == custom.id }))
        #expect(store.songs.first(where: { $0.id == songID })?.padTrackID == nil)
        undo.undo()
        #expect(store.padTracks.contains(where: { $0.id == custom.id }))
        #expect(store.songs.first(where: { $0.id == songID })?.padTrackID == custom.id)
    }

    @Test func includedAndAudiblePadsCannotBeRemoved() {
        let store = AppStore.preview()
        let custom = customPad()
        store.padTracks.append(custom)

        #expect(!store.removePads([PadTrack.included[0].id], replacementPadID: nil))
        store.runtime.audiblePadTrackID = custom.id
        #expect(!store.removePads([custom.id], replacementPadID: nil))
        #expect(store.padTracks.contains(where: { $0.id == custom.id }))

        store.runtime.audiblePadTrackID = nil
        store.rehearse.selectedPadTrackID = custom.id
        store.rehearse.padState = .playing
        #expect(!store.removePads([custom.id], replacementPadID: nil))
        #expect(store.padTracks.contains(where: { $0.id == custom.id }))
    }

    @Test func midiLearnIgnoresReleasePreviewsCommitsAndRejectsDuplicates() {
        let source = MIDIControllerSource(uniqueID: 77, name: "Pedal", manufacturer: nil, model: nil)
        let event = MIDIMessage(sourceUniqueID: 77, kind: .controlChange, channel: 3, number: 12, value: 127)
        var settings = MIDIControllerSettings.disabled
        settings.isEnabled = true
        var learn = MIDILearnCoordinator()
        learn.begin(.togglePad)
        learn.receive(MIDIMessage(sourceUniqueID: 77, kind: .controlChange, channel: 3, number: 12, value: 0), sources: [source], settings: settings)
        #expect(learn.state == .listening(action: .togglePad))

        learn.receive(event, sources: [source], settings: settings)
        guard case let .preview(candidate) = learn.state else {
            Issue.record("Expected a learn preview")
            return
        }
        #expect(candidate.source == source)
        #expect(learn.commit(into: &settings, useAnyController: false))
        #expect(settings.mappings.first?.source == .source(uniqueID: 77))

        learn.begin(.toggleClick)
        learn.receive(event, sources: [source], settings: settings)
        #expect(learn.state == .duplicate(candidate: MIDILearnCandidate(action: .toggleClick, event: event, source: source), existingAction: .togglePad))
    }

    @Test func midiLearnCancelAndTimeoutNeverMutateSettings() {
        var settings = MIDIControllerSettings.disabled
        var learn = MIDILearnCoordinator()
        learn.begin(.stopAll)
        learn.timeOut()
        #expect(learn.state == .timedOut(action: .stopAll))
        #expect(!learn.commit(into: &settings, useAnyController: false))
        learn.cancel()
        #expect(learn.state == .idle)
        #expect(settings == .disabled)
    }

    @Test func appStoreMIDISettingsLearnAndClearUseInjectedService() {
        let source = MIDIControllerSource(uniqueID: 91, name: "Foot Controller", manufacturer: "Test", model: "One")
        let midi = RecordingMIDIController(sources: [source])
        let store = AppStore.preview(midiController: midi)
        store.setMIDIEnabled(true)
        #expect(midi.startCount == 1)
        #expect(store.midiAvailableSources == [source])

        store.beginMIDILearn(for: .nextCue)
        midi.send(MIDIMessage(sourceUniqueID: 91, kind: .noteOn, channel: 1, number: 64, value: 100))
        #expect(store.commitMIDILearn())
        #expect(store.midiMapping(for: .nextCue)?.message == MIDIMessageIdentity(kind: .noteOn, channel: 1, number: 64))
        store.clearMIDIMapping(for: .nextCue)
        #expect(store.midiMapping(for: .nextCue) == nil)

        store.setMIDIEnabled(false)
        #expect(midi.stopCount == 1)
        store.beginMIDILearn(for: .stopAll)
        #expect(store.midiLearnState == .idle)
    }
}
