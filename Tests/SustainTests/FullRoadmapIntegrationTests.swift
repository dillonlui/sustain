import Foundation
import Testing
@testable import Sustain

private actor DeterministicExternalAudioReferencer: ExternalAudioReferencing {
    func createReference(for url: URL) async throws -> ExternalAudioReference {
        reference(for: url)
    }

    private func reference(for url: URL) -> ExternalAudioReference {
        ExternalAudioReference(
            bookmarkData: Data(url.path.utf8),
            lastKnownPath: url.path,
            originalFilename: url.lastPathComponent,
            fingerprint: ExternalFileFingerprint(
                resourceIdentifierData: Data(url.path.utf8),
                fileSize: 1_024,
                modificationDate: Date(timeIntervalSince1970: 1)
            ),
            audioMetadata: PadAudioMetadata(
                duration: 30,
                channelCount: 2,
                sampleRate: 48_000,
                decodedByteCount: 11_520_000
            )
        )
    }

    func inspect(_ reference: ExternalAudioReference) async -> PadAssetState {
        .available(reference.audioMetadata)
    }

    func refreshedReference(_ reference: ExternalAudioReference) async throws -> ExternalAudioReference {
        reference
    }

    func importReferences(
        from urls: [URL],
        existing: [ExternalAudioReference]
    ) async -> ExternalAudioImportResult {
        var imported: [ImportedExternalAudio] = []
        for (index, url) in urls.enumerated() {
            let reference = reference(for: url)
            imported.append(ImportedExternalAudio(
                sourceIndex: index,
                initialLabel: url.deletingPathExtension().lastPathComponent,
                reference: reference
            ))
        }
        return ExternalAudioImportResult(
            imported: imported,
            failures: [],
            skippedDuplicateFilenames: [],
            wasCancelled: false
        )
    }

    func withCoordinatedRead<T: Sendable>(
        of reference: ExternalAudioReference,
        operation: @Sendable (URL) throws -> T
    ) async throws -> T {
        try operation(URL(fileURLWithPath: reference.lastKnownPath))
    }
}

@MainActor
@Suite("Complete roadmap integration")
struct FullRoadmapIntegrationTests {
    private func waitUntil(
        timeout: Duration,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test func importAssignAddPrerollStartStopAndClearIsOneAuthoritativePath() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainRoadmap-\(UUID().uuidString)", isDirectory: true)
        let libraryStore = LocalLibraryStore(directoryOverride: directory)
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(
            audioEngine: audio,
            libraryStore: libraryStore,
            externalAudioReferencer: DeterministicExternalAudioReferencer()
        )
        #expect(store.clearActiveSetlist())

        let sourceURL = URL(fileURLWithPath: "/approved/Service Opener.m4a")
        let importResult = await store.importPadFiles([sourceURL])
        #expect(importResult.imported.count == 1)
        let pad = try #require(store.padTracks.last)
        #expect(pad.label == "Service Opener")
        #expect(!pad.isIncluded)

        let songID = store.addSong()
        #expect(store.setSongPadTrackID(songID, padTrackID: pad.id))
        let entryID = try #require(store.addSongToSetlist(songID))
        #expect(store.runtime.cuedEntryID == entryID)

        store.toggleLivePad()
        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.audiblePadTrackID == pad.id)
        #expect(audio.padActivateCount == 1)

        store.startCuedSong()
        #expect(store.runtime.playingEntryID == entryID)
        #expect(store.runtime.audiblePadTrackID == pad.id)
        #expect(audio.padActivateCount == 1)

        store.stop()
        #expect(await waitUntil(timeout: .seconds(5)) { !store.isAnyAudioActivityActive })
        #expect(store.clearActiveSetlist())
        #expect(store.activeSetlist.entries.isEmpty)

        let reloaded = try #require(try libraryStore.loadLibrary())
        #expect(reloaded.activeSetlist.entries.isEmpty)
        #expect(reloaded.padTracks.contains { $0.id == pad.id })
        #expect(reloaded.songs.contains { $0.id == songID && $0.padTrackID == pad.id })
    }
}
