import AVFoundation
import Foundation
import Testing
@testable import Sustain

private final class RecordingScopeAccessor: SecurityScopeAccessing, @unchecked Sendable {
    private let lock = NSLock()
    var shouldGrant = true
    private(set) var starts = 0
    private(set) var stops = 0

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock { starts += 1 }
        return shouldGrant
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { stops += 1 }
    }
}

private final class TestBookmarkStore: SecurityScopedBookmarking, @unchecked Sendable {
    private let lock = NSLock()
    var staleOnResolve = false
    private(set) var createCount = 0

    func createReadOnlyBookmark(for url: URL) throws -> Data {
        lock.withLock { createCount += 1 }
        return Data(url.path.utf8)
    }

    func resolve(_ data: Data) throws -> ResolvedBookmark {
        guard let path = String(data: data, encoding: .utf8) else {
            throw ExternalAudioReferenceError.bookmarkResolutionFailed
        }
        return ResolvedBookmark(url: URL(fileURLWithPath: path), isStale: staleOnResolve)
    }
}

private final class TestCoordinator: CoordinatedFileReading, @unchecked Sendable {
    private let lock = NSLock()
    var error: ExternalAudioReferenceError?
    private(set) var readCount = 0

    func coordinate<T>(at url: URL, operation: (URL) throws -> T) throws -> T {
        lock.withLock { readCount += 1 }
        if let error { throw error }
        return try operation(url)
    }
}

private final class TestAudioValidator: ExternalAudioValidating, @unchecked Sendable {
    var failuresByFilename: [String: ExternalAudioReferenceError] = [:]
    var revisionByFilename: [String: UInt8] = [:]

    func validate(_ url: URL) throws -> ValidatedExternalAudio {
        if let failure = failuresByFilename[url.lastPathComponent] { throw failure }
        let revision = revisionByFilename[url.lastPathComponent] ?? 1
        return ValidatedExternalAudio(
            fingerprint: ExternalFileFingerprint(
                resourceIdentifierData: Data([revision]),
                fileSize: 64,
                modificationDate: Date(timeIntervalSince1970: TimeInterval(revision))
            ),
            metadata: PadAudioMetadata(
                duration: 1,
                channelCount: 2,
                sampleRate: 48_000,
                decodedByteCount: 384_000
            )
        )
    }
}

private actor SuspendedInspectionReferencer: ExternalAudioReferencing {
    private var inspectionStarted = false
    private var inspectionContinuation: CheckedContinuation<Void, Never>?

    func createReference(for url: URL) async throws -> ExternalAudioReference {
        throw ExternalAudioReferenceError.unreadable
    }

    func inspect(_ reference: ExternalAudioReference) async -> PadAssetState {
        inspectionStarted = true
        await withCheckedContinuation { continuation in
            inspectionContinuation = continuation
        }
        return .missing
    }

    func refreshedReference(_ reference: ExternalAudioReference) async throws -> ExternalAudioReference {
        reference
    }

    func importReferences(
        from urls: [URL],
        existing: [ExternalAudioReference]
    ) async -> ExternalAudioImportResult {
        ExternalAudioImportResult(
            imported: [],
            failures: [],
            skippedDuplicateFilenames: [],
            wasCancelled: false
        )
    }

    func withCoordinatedRead<T: Sendable>(
        of reference: ExternalAudioReference,
        operation: @Sendable (URL) throws -> T
    ) async throws -> T {
        throw ExternalAudioReferenceError.unreadable
    }

    func waitUntilInspectionStarts() async {
        while !inspectionStarted { await Task.yield() }
    }

    func finishInspection() {
        inspectionContinuation?.resume()
        inspectionContinuation = nil
    }
}

@Suite("External audio references")
struct ExternalAudioReferenceServiceTests {
    private func temporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SustainExternalAudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data([0]).write(to: url)
        return url
    }

    @Test func createResolveAndStaleRefreshBalanceScopes() async throws {
        let scope = RecordingScopeAccessor()
        let bookmarks = TestBookmarkStore()
        let coordinator = TestCoordinator()
        let validator = TestAudioValidator()
        let service = ExternalAudioReferenceService(
            bookmarks: bookmarks,
            scopes: scope,
            coordinator: coordinator,
            validator: validator
        )
        let file = try temporaryFile(named: "Atmosphere.wav")

        let reference = try await service.createReference(for: file)
        #expect(reference.originalFilename == "Atmosphere.wav")
        #expect(reference.audioMetadata.channelCount == 2)
        #expect(scope.starts == 1)
        #expect(scope.stops == 1)
        #expect(await service.inspect(reference).isAvailable)
        #expect(scope.starts == 2)
        #expect(scope.stops == 2)

        bookmarks.staleOnResolve = true
        let refreshed = try await service.refreshedReference(reference)
        #expect(refreshed.bookmarkData == reference.bookmarkData)
        #expect(bookmarks.createCount == 2)
        #expect(scope.starts == scope.stops)
        #expect(coordinator.readCount == 3)
    }

    @Test func scopeClosesWhenValidationOrReadFails() async throws {
        let scope = RecordingScopeAccessor()
        let validator = TestAudioValidator()
        validator.failuresByFilename["bad.wav"] = .unsupportedOrProtected
        let service = ExternalAudioReferenceService(
            scopes: scope,
            coordinator: TestCoordinator(),
            validator: validator
        )
        let file = try temporaryFile(named: "bad.wav")

        await #expect(throws: ExternalAudioReferenceError.unsupportedOrProtected) {
            try await service.createReference(for: file)
        }
        #expect(scope.starts == 1)
        #expect(scope.stops == 1)

        let bookmarks = TestBookmarkStore()
        let coordinator = TestCoordinator()
        coordinator.error = .externalVolumeUnavailable
        let failingReadService = ExternalAudioReferenceService(
            bookmarks: bookmarks,
            scopes: scope,
            coordinator: coordinator,
            validator: TestAudioValidator()
        )
        let reference = ExternalAudioReference(
            bookmarkData: Data(file.path.utf8),
            lastKnownPath: file.path,
            originalFilename: file.lastPathComponent,
            fingerprint: ExternalFileFingerprint(resourceIdentifierData: Data([1]), fileSize: 64, modificationDate: nil),
            audioMetadata: PadAudioMetadata(duration: 1, channelCount: 2, sampleRate: 48_000, decodedByteCount: 1)
        )
        #expect(await failingReadService.inspect(reference) == .externalVolumeUnavailable)
        #expect(scope.starts == scope.stops)
    }

    @Test func batchImportPreservesOrderSkipsDuplicatesAndKeepsPartialSuccess() async throws {
        let validator = TestAudioValidator()
        validator.failuresByFilename["broken.wav"] = .unreadable
        let service = ExternalAudioReferenceService(
            bookmarks: TestBookmarkStore(),
            scopes: RecordingScopeAccessor(),
            coordinator: TestCoordinator(),
            validator: validator
        )
        let first = try temporaryFile(named: "First.wav")
        let broken = try temporaryFile(named: "broken.wav")
        let duplicate = try temporaryFile(named: "Duplicate.wav")
        validator.revisionByFilename["First.wav"] = 9
        validator.revisionByFilename["Duplicate.wav"] = 9

        let result = await service.importReferences(from: [first, broken, duplicate], existing: [])
        #expect(result.imported.map(\.initialLabel) == ["First"])
        #expect(result.failures.map(\.filename) == ["broken.wav"])
        #expect(result.skippedDuplicateFilenames == ["Duplicate.wav"])
        #expect(!result.wasCancelled)
    }

    @Test func symlinkResolvesToApprovedTargetAndChangedContentIsTyped() async throws {
        let validator = TestAudioValidator()
        let bookmarks = TestBookmarkStore()
        let service = ExternalAudioReferenceService(
            bookmarks: bookmarks,
            scopes: RecordingScopeAccessor(),
            coordinator: TestCoordinator(),
            validator: validator
        )
        let target = try temporaryFile(named: "Target.wav")
        let symlink = target.deletingLastPathComponent().appendingPathComponent("Alias.wav")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        let reference = try await service.createReference(for: symlink)
        #expect(reference.lastKnownPath == target.path)
        validator.revisionByFilename["Target.wav"] = 2
        #expect(await service.inspect(reference) == .changed)
    }

    @Test func decodedSizeMathRejectsOverflowAndMultichannel() throws {
        #expect(throws: ExternalAudioReferenceError.decodedSizeOverflow) {
            try AVFoundationExternalAudioValidator.decodedByteCount(
                frameCount: .max,
                channelCount: .max,
                bytesPerFrame: .max,
                isInterleaved: false
            )
        }
        #expect(try AVFoundationExternalAudioValidator.decodedByteCount(
            frameCount: 100,
            channelCount: 2,
            bytesPerFrame: 4,
            isInterleaved: false
        ) == 800)
    }

    @Test @MainActor func appStoreImportAndLocatePreserveIdentityAndAssignments() async throws {
        let validator = TestAudioValidator()
        let service = ExternalAudioReferenceService(
            bookmarks: TestBookmarkStore(),
            scopes: RecordingScopeAccessor(),
            coordinator: TestCoordinator(),
            validator: validator
        )
        let store = AppStore.preview(externalAudioReferencer: service)
        let originalIncludedCount = store.padTracks.count
        let first = try temporaryFile(named: "Original.wav")
        let replacement = try temporaryFile(named: "Replacement.wav")

        let result = await store.importPadFiles([first])
        #expect(result.imported.count == 1)
        #expect(store.padTracks.count == originalIncludedCount + 1)
        let custom = try #require(store.padTracks.last)
        store.songs[0].padTrackID = custom.id

        #expect(await store.locateExternalPad(custom.id, at: replacement))
        let repaired = try #require(store.padTracks.first { $0.id == custom.id })
        #expect(repaired.id == custom.id)
        #expect(repaired.label == custom.label)
        #expect(store.songs[0].padTrackID == custom.id)
        guard case let .external(reference) = repaired.source else {
            Issue.record("Expected an external replacement")
            return
        }
        #expect(reference.originalFilename == "Replacement.wav")
    }

    @Test @MainActor func failedImportPersistenceReportsNoCommittedPads() async throws {
        let service = ExternalAudioReferenceService(
            bookmarks: TestBookmarkStore(),
            scopes: RecordingScopeAccessor(),
            coordinator: TestCoordinator(),
            validator: TestAudioValidator()
        )
        let unwritable = LocalLibraryStore(
            directoryOverride: URL(fileURLWithPath: "/dev/null/sustain-import-nope", isDirectory: true)
        )
        let store = AppStore.preview(libraryStore: unwritable, externalAudioReferencer: service)
        let originalCount = store.padTracks.count
        let file = try temporaryFile(named: "Validated.wav")

        let result = await store.importPadFiles([file])

        #expect(result.imported.isEmpty)
        #expect(result.persistenceError != nil)
        #expect(store.padTracks.count == originalCount)
        #expect(store.runtime.lastMessage == result.persistenceError)
    }

    @Test @MainActor func staleInspectionCannotOverwriteRelinkedPadState() async throws {
        func reference(_ marker: UInt8, filename: String) -> ExternalAudioReference {
            ExternalAudioReference(
                bookmarkData: Data([marker]),
                lastKnownPath: "/tmp/\(filename)",
                originalFilename: filename,
                fingerprint: ExternalFileFingerprint(
                    resourceIdentifierData: Data([marker]),
                    fileSize: 64,
                    modificationDate: nil
                ),
                audioMetadata: PadAudioMetadata(
                    duration: 1,
                    channelCount: 2,
                    sampleRate: 48_000,
                    decodedByteCount: 64
                )
            )
        }

        let referencer = SuspendedInspectionReferencer()
        let store = AppStore.preview(externalAudioReferencer: referencer)
        let padID = UUID()
        let oldReference = reference(1, filename: "Old.wav")
        let newReference = reference(2, filename: "New.wav")
        store.padTracks.append(PadTrack(id: padID, label: "Custom", source: .external(oldReference)))

        let refresh = Task { await store.refreshExternalPadState(padID) }
        await referencer.waitUntilInspectionStarts()
        let index = try #require(store.padTracks.firstIndex { $0.id == padID })
        store.padTracks[index].source = .external(newReference)
        store.padAssetStates[padID] = .available(newReference.audioMetadata)
        await referencer.finishInspection()
        await refresh.value

        #expect(store.padAssetStates[padID] == .available(newReference.audioMetadata))
    }
}
