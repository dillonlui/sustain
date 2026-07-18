import Foundation
import CoreAudio
import Testing
@testable import Sustain

extension RuntimeSessionTests {
    @Test func schemaV1SetlistOverridesMigrateIntoCanonicalSongValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let libraryURL = try libraryStore.applicationSupportDirectory()
            .appendingPathComponent("Library.json", isDirectory: false)

        try libraryStore.saveLibrary(AppStore.seedSnapshot())
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: libraryURL)) as? [String: Any]
        )
        object["schemaVersion"] = 1
        var setlist = try #require(object["activeSetlist"] as? [String: Any])
        var entries = try #require(setlist["entries"] as? [[String: Any]])
        entries[0]["keyOverride"] = MusicalKey.bb.rawValue
        entries[0]["bpmOverride"] = 88
        setlist["entries"] = entries
        object["activeSetlist"] = setlist
        try JSONSerialization.data(withJSONObject: object).write(to: libraryURL)

        let loaded = try #require(try libraryStore.loadLibrary())
        let firstEntry = try #require(loaded.activeSetlist.entries.first)
        let migratedSong = try #require(loaded.songs.first { $0.id == firstEntry.songID })

        #expect(loaded.schemaVersion == LibrarySnapshot.currentSchemaVersion)
        #expect(migratedSong.defaultKey == .bb)
        #expect(migratedSong.defaultBPM == 88)
        #expect(firstEntry.legacyKeyOverride == nil)
        #expect(firstEntry.legacyBPMOverride == nil)

        // Loading performs the migration durably. The v1 primary is retained as the rolling
        // backup, while the current Library.json is immediately rewritten in canonical v2.
        let encodedText = try #require(String(data: Data(contentsOf: libraryURL), encoding: .utf8))
        #expect(encodedText.contains("\"schemaVersion\" : 2"))
        #expect(!encodedText.contains("keyOverride"))
        #expect(!encodedText.contains("bpmOverride"))
        let backupURL = libraryURL.deletingLastPathComponent()
            .appendingPathComponent("Library.bak", isDirectory: false)
        let backupText = try #require(String(data: Data(contentsOf: backupURL), encoding: .utf8))
        #expect(backupText.contains("keyOverride"))
    }

    @Test func conflictingLegacyOverridesPreserveLibraryDefaults() throws {
        let snapshot = AppStore.seedSnapshot()
        let firstEntry = try #require(snapshot.activeSetlist.entries.first)
        let firstSong = try #require(snapshot.songs.first { $0.id == firstEntry.songID })
        let encoder = JSONEncoder()
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any]
        )
        object["schemaVersion"] = 1
        var setlist = try #require(object["activeSetlist"] as? [String: Any])
        var entries = try #require(setlist["entries"] as? [[String: Any]])
        entries[0]["keyOverride"] = MusicalKey.bb.rawValue
        entries[0]["bpmOverride"] = 88
        var duplicate = entries[0]
        duplicate["id"] = UUID().uuidString
        duplicate["keyOverride"] = MusicalKey.a.rawValue
        duplicate["bpmOverride"] = 99
        entries.append(duplicate)
        setlist["entries"] = entries
        object["activeSetlist"] = setlist

        let loaded = try JSONDecoder().decode(
            LibrarySnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let canonical = try #require(loaded.songs.first { $0.id == firstSong.id })

        #expect(canonical.defaultKey == firstSong.defaultKey)
        #expect(canonical.defaultBPM == firstSong.defaultBPM)
    }

    @Test func corruptLibraryIsQuarantinedOnLoadFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let libraryURL = try libraryStore.applicationSupportDirectory()
            .appendingPathComponent("Library.json", isDirectory: false)
        try Data("{not-json".utf8).write(to: libraryURL)

        do {
            _ = try libraryStore.loadLibrary()
            Issue.record("Expected corrupt library load to fail")
        } catch {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            #expect(!FileManager.default.fileExists(atPath: libraryURL.path))
            #expect(files.contains { $0.lastPathComponent.hasPrefix("Library.invalid-") })
        }
    }

    @Test func schemaVersionIsStampedOnSaveAndLegacyFilesDefaultToV1() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let libraryURL = try libraryStore.applicationSupportDirectory()
            .appendingPathComponent("Library.json", isDirectory: false)

        try libraryStore.saveLibrary(AppStore.seedSnapshot())

        // The written file carries the current schema version, and reloads with it.
        let raw = try #require(String(data: Data(contentsOf: libraryURL), encoding: .utf8))
        #expect(raw.contains("\"schemaVersion\""))
        let saved = try #require(try libraryStore.loadLibrary())
        #expect(saved.schemaVersion == LibrarySnapshot.currentSchemaVersion)

        // A legacy file (field absent, i.e. written before versioning existed) still loads
        // and is normalized in memory to the current schema.
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: libraryURL)) as? [String: Any]
        )
        object.removeValue(forKey: "schemaVersion")
        try JSONSerialization.data(withJSONObject: object).write(to: libraryURL)
        let legacy = try #require(try libraryStore.loadLibrary())
        #expect(legacy.schemaVersion == LibrarySnapshot.currentSchemaVersion)
    }

    @Test func loadRecoversFromBackupWhenPrimaryIsCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let appSupport = try libraryStore.applicationSupportDirectory()
        let libraryURL = appSupport.appendingPathComponent("Library.json", isDirectory: false)
        let backupURL = appSupport.appendingPathComponent("Library.bak", isDirectory: false)

        // First save: nothing to back up yet.
        var first = AppStore.seedSnapshot()
        first.activeSetlist.title = "Backup Copy"
        try libraryStore.saveLibrary(first)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))

        // Second save rolls the previous good primary into the backup.
        var second = AppStore.seedSnapshot()
        second.activeSetlist.title = "Latest Save"
        try libraryStore.saveLibrary(second)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        // Corrupt the primary → load recovers the previous good save from the backup and
        // quarantines the corrupt primary (instead of silently seeding the demo library).
        try Data("{not-json".utf8).write(to: libraryURL)
        let recovered = try #require(try libraryStore.loadLibrary())
        #expect(recovered.activeSetlist.title == "Backup Copy")
        #expect(!FileManager.default.fileExists(atPath: libraryURL.path))
    }

    @Test func routingNormalizerAppliesOutputResolutionRules() {
        // Unchosen output stays on the system default (nil), regardless of what resolves.
        #expect(RoutingSettingsNormalizer.normalizedOutputID(currentID: nil, resolvedID: 5) == nil)
        // A chosen device that's momentarily unresolved (unplugged) is kept.
        #expect(RoutingSettingsNormalizer.normalizedOutputID(currentID: 42, resolvedID: nil) == 42)
        // A chosen device that resolves adopts the fresh id.
        #expect(RoutingSettingsNormalizer.normalizedOutputID(currentID: 42, resolvedID: 7) == 7)

        #expect(RoutingSettingsNormalizer.normalizedOutputName(currentID: nil, currentName: "X", resolvedName: "Y") == nil)
        #expect(RoutingSettingsNormalizer.normalizedOutputName(currentID: 1, currentName: "Prev", resolvedName: "Unavailable") == "Prev")
        #expect(RoutingSettingsNormalizer.normalizedOutputName(currentID: 1, currentName: "Prev", resolvedName: "Live") == "Live")
    }

    @Test func readinessEvaluatorBlocksOnMissingPadAndSurfacesSetlistWarnings() {
        let song = Song(title: "Cued", defaultKey: .c, defaultBPM: 72, timeSignature: .fourFour, padPack: .bundled)
        let laterMissingBPM = Song(title: "Bad", defaultKey: .c, defaultBPM: 0, timeSignature: .fourFour, padPack: .bundled)
        let cued = SetlistEntry(songID: song.id)
        let later = SetlistEntry(songID: laterMissingBPM.id)
        let lookup: (SetlistEntry) -> Song? = { entry in
            [song, laterMissingBPM].first { $0.id == entry.songID }
        }

        let ready = SetlistReadinessEvaluator(
            hasPadAsset: { _, _ in true },
            padAssetStatus: { _, _ in "" },
            routingSnapshot: .previewDefault,
            routingFailureMessage: nil,
            entries: [cued, later],
            song: lookup
        ).validate(entry: cued, song: song)
        #expect(ready.canStartPlayback)
        // The other entry's zero BPM surfaces as a non-blocking warning.
        #expect(ready.warnings.contains { $0.contains("Bad") })

        let blocked = SetlistReadinessEvaluator(
            hasPadAsset: { _, _ in false },
            padAssetStatus: { _, _ in "No pad for this key" },
            routingSnapshot: .previewDefault,
            routingFailureMessage: nil,
            entries: [cued],
            song: lookup
        ).validate(entry: cued, song: song)
        #expect(!blocked.canStartPlayback)
    }

    @Test func failedSaveRaisesAlertPrompt() throws {
        // A directory under /dev/null can never be created, so every save write fails.
        let unwritable = LocalLibraryStore(
            directoryOverride: URL(fileURLWithPath: "/dev/null/sustain-nope", isDirectory: true)
        )
        let store = AppStore.preview(libraryStore: unwritable)
        #expect(store.saveErrorPrompt == nil)

        let song = try #require(store.songs.first)
        store.updateSong(
            song.id,
            title: song.title,
            defaultKey: .bb,
            defaultBPM: 88,
            timeSignature: song.timeSignature,
            padPackID: PadPack.bundled.id
        )

        #expect(store.saveErrorPrompt != nil)
        #expect(store.persistenceStatus.hasPrefix("Library save failed"))
    }

    @Test func newerSchemaFileThrowsDistinctErrorAndIsNotQuarantined() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let libraryURL = try libraryStore.applicationSupportDirectory()
            .appendingPathComponent("Library.json", isDirectory: false)

        // Write a valid library, then bump its version beyond what this build supports.
        try libraryStore.saveLibrary(AppStore.seedSnapshot())
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: libraryURL)) as? [String: Any]
        )
        object["schemaVersion"] = LibrarySnapshot.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: libraryURL)

        do {
            _ = try libraryStore.loadLibrary()
            Issue.record("Expected newer-schema load to throw")
        } catch let error as LibraryLoadError {
            guard case .newerSchema = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
            // The valid (future) file must be preserved, not quarantined or overwritten.
            #expect(FileManager.default.fileExists(atPath: libraryURL.path))
        }
    }

    @Test func songAssignmentWorkflowPersistsSongAndSetlistEntry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)

        let songID = store.addSong()
        store.updateSong(
            songID,
            title: "Gratitude",
            defaultKey: .bb,
            defaultBPM: 82,
            timeSignature: .sixEight,
            padPackID: PadPack.bundled.id
        )
        let entryID = try #require(store.addSongToSetlist(songID))

        let loaded = try #require(try libraryStore.loadLibrary())
        let loadedSong = try #require(loaded.songs.first { $0.id == songID })

        #expect(loadedSong.title == "Gratitude")
        #expect(loadedSong.defaultKey == .bb)
        #expect(loadedSong.defaultBPM == 82)
        #expect(loadedSong.timeSignature == .sixEight)
        #expect(loadedSong.padPack == .bundled)
        #expect(loaded.activeSetlist.entries.contains { $0.id == entryID && $0.songID == songID })
    }

    @Test func legacyPadPacksNormalizeToIncludedBundle() throws {
        let legacyPadPack = PadPack(
            name: "Legacy Pad Pack",
            folderName: "Legacy Pad Pack",
            availableKeys: [.g]
        )
        let legacySong = Song(
            title: "Legacy Song",
            defaultKey: .g,
            defaultBPM: 72,
            timeSignature: .fourFour,
            padPack: legacyPadPack
        )
        let snapshot = LibrarySnapshot(
            songs: [legacySong],
            padPacks: [legacyPadPack],
            activeSetlist: Setlist(title: "Legacy", entries: [SetlistEntry(songID: legacySong.id)])
        )

        #expect(snapshot.songs.first?.padPack == .bundled)
        #expect(snapshot.padPacks == [.bundled])
    }

    @Test func addingFirstSetlistEntryCuesIt() throws {
        let snapshot = AppStore.seedSnapshot()
        let store = AppStore(
            songs: snapshot.songs,
            activeSetlist: Setlist(title: "Empty", entries: [])
        )

        let entryID = try #require(store.addSongToSetlist(snapshot.songs[0].id))

        #expect(store.runtime.cuedEntryID == entryID)
    }

    @Test func removingPlayingSetlistEntryIsBlocked() throws {
        let store = AppStore.preview()
        let entry = try #require(store.activeSetlist.entries.first)

        store.startCuedSong()
        store.removeSetlistEntry(entry.id)

        #expect(store.activeSetlist.entries.contains(entry))
        #expect(store.runtime.lastMessage == "Stop playback before removing the playing song")
    }

    @Test func deletingSongRemovesItAndReferencingSetlistEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainDeleteTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)

        let songID = store.addSong()
        let entryID = try #require(store.addSongToSetlist(songID))

        store.deleteSong(songID)

        #expect(!store.songs.contains { $0.id == songID })
        #expect(!store.activeSetlist.entries.contains { $0.id == entryID })

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(!loaded.songs.contains { $0.id == songID })
        #expect(!loaded.activeSetlist.entries.contains { $0.songID == songID })
    }

    @Test func deletingPlayingSongIsBlocked() throws {
        let store = AppStore.preview()
        let entry = try #require(store.activeSetlist.entries.first)
        let songID = entry.songID

        store.startCuedSong()
        store.deleteSong(songID)

        #expect(store.songs.contains { $0.id == songID })
        #expect(store.activeSetlist.entries.contains(entry))
        #expect(store.persistenceStatus == "Stop playback before deleting the playing song")
    }

    @Test func activeSetlistTitlePersistsToJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)

        store.updateActiveSetlistTitle("Sunday Night")

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(loaded.activeSetlist.title == "Sunday Night")
    }

    @Test func cueingPreloadsPadForCuedSong() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)

        let before = audio.preloadedKeys.count
        store.cueNextSong()

        let cued = try #require(store.cuedEntry)
        let song = try #require(store.song(for: cued))
        #expect(audio.preloadedKeys.count > before)
        #expect(audio.preloadedKeys.last == song.defaultKey)
    }

    @Test func movingSetlistEntryReordersAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainReorderTests-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let store = AppStore.preview(libraryStore: libraryStore)
        let original = store.activeSetlist.entries.map(\.id)

        store.moveSetlistEntry(from: IndexSet(integer: 0), to: original.count)

        let reordered = store.activeSetlist.entries.map(\.id)
        #expect(reordered.first == original[1])
        #expect(reordered.last == original[0])

        let loaded = try #require(try libraryStore.loadLibrary())
        #expect(loaded.activeSetlist.entries.map(\.id) == reordered)
    }

    @Test func clearingSetlistRemovesEntriesAndCue() {
        let store = AppStore.preview()

        store.clearSetlist()

        #expect(store.activeSetlist.entries.isEmpty)
        #expect(store.runtime.cuedEntryID == nil)
        #expect(store.runtime.lastMessage == "Cleared setlist")
    }

    @Test func clearingSetlistDuringPlaybackIsBlocked() {
        let store = AppStore.preview()

        store.startCuedSong()
        store.clearSetlist()

        #expect(!store.activeSetlist.entries.isEmpty)
        #expect(store.runtime.lastMessage == "Stop playback before clearing the setlist")
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

    @Test func includedPadResolverFindsIncludedPadFiles() throws {
        let resolver = BundlePadAssetResolver()

        let asset = try #require(resolver.asset(for: .bundled, key: .g))
        #expect(asset.url.lastPathComponent == "G Major.mp3")
        #expect(asset.displayName == "G Major.mp3")
    }

}
