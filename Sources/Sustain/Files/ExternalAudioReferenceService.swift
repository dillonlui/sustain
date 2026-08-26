import AVFoundation
import Foundation

enum PadAssetState: Equatable {
    case available(PadAudioMetadata)
    case preparing
    case externalVolumeUnavailable
    case permissionDenied
    case missing
    case changed
    case unsupportedOrProtected
    case unreadable

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

enum ExternalAudioReferenceError: LocalizedError, Equatable {
    case notAFile
    case directory
    case permissionDenied
    case fileMissing
    case externalVolumeUnavailable
    case unsupportedOrProtected
    case unsupportedChannelCount(UInt32)
    case invalidAudioDescription
    case decodedSizeOverflow
    case decodedAudioTooLarge(bytes: UInt64, limit: UInt64)
    case changed
    case unreadable
    case bookmarkCreationFailed
    case bookmarkResolutionFailed

    var errorDescription: String? {
        switch self {
        case .notAFile: "Choose a local audio file."
        case .directory: "Folders cannot be added as pads."
        case .permissionDenied: "Permission is required to read this audio file."
        case .fileMissing: "The audio file could not be found."
        case .externalVolumeUnavailable: "The external volume or file provider is unavailable."
        case .unsupportedOrProtected: "The file is unsupported or protected audio."
        case let .unsupportedChannelCount(count): "Only mono or stereo audio is supported (found \(count) channels)."
        case .invalidAudioDescription: "The audio file has no usable frames or sample rate."
        case .decodedSizeOverflow: "The decoded audio size is invalid."
        case let .decodedAudioTooLarge(bytes, limit):
            "The decoded audio would use \(bytes) bytes; the per-pad limit is \(limit) bytes."
        case .changed: "The file changed since it was added. Locate or replace it to confirm the new audio."
        case .unreadable: "The audio file could not be read."
        case .bookmarkCreationFailed: "Sustain could not save durable read access to this file."
        case .bookmarkResolutionFailed: "Sustain could not restore access to this file."
        }
    }
}

protocol SecurityScopeAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

struct SystemSecurityScopeAccessor: SecurityScopeAccessing {
    func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

struct ResolvedBookmark: Sendable {
    var url: URL
    var isStale: Bool
}

protocol SecurityScopedBookmarking: Sendable {
    func createReadOnlyBookmark(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedBookmark
}

struct SystemSecurityScopedBookmarkStore: SecurityScopedBookmarking {
    func createReadOnlyBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: [
                    .fileResourceIdentifierKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                relativeTo: nil
            )
        } catch {
            throw ExternalAudioReferenceError.bookmarkCreationFailed
        }
    }

    func resolve(_ data: Data) throws -> ResolvedBookmark {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return ResolvedBookmark(url: url, isStale: stale)
        } catch {
            throw ExternalAudioReferenceError.bookmarkResolutionFailed
        }
    }
}

protocol CoordinatedFileReading: Sendable {
    func coordinate<T>(at url: URL, operation: (URL) throws -> T) throws -> T
}

struct SystemCoordinatedFileReader: CoordinatedFileReading {
    func coordinate<T>(at url: URL, operation: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result { try operation(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ExternalAudioReferenceError.unreadable }
        return try result.get()
    }
}

struct ValidatedExternalAudio: Sendable, Equatable {
    var fingerprint: ExternalFileFingerprint
    var metadata: PadAudioMetadata
}

protocol ExternalAudioValidating: Sendable {
    func validate(_ url: URL) throws -> ValidatedExternalAudio
}

struct AVFoundationExternalAudioValidator: ExternalAudioValidating {
    static let perPadDecodedByteLimit: UInt64 = 256 * 1024 * 1024

    func validate(_ url: URL) throws -> ValidatedExternalAudio {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileResourceIdentifierKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])
        } catch {
            throw Self.mapFileError(error)
        }
        if values.isDirectory == true { throw ExternalAudioReferenceError.directory }
        guard values.isRegularFile != false else { throw ExternalAudioReferenceError.notAFile }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw Self.mapAudioError(error)
        }

        let format = file.processingFormat
        let channels = format.channelCount
        guard file.length > 0, format.sampleRate.isFinite, format.sampleRate > 0, channels > 0 else {
            throw ExternalAudioReferenceError.invalidAudioDescription
        }
        guard channels <= 2 else { throw ExternalAudioReferenceError.unsupportedChannelCount(channels) }

        let decodedBytes = try Self.decodedByteCount(
            frameCount: file.length,
            channelCount: channels,
            bytesPerFrame: format.streamDescription.pointee.mBytesPerFrame,
            isInterleaved: format.isInterleaved
        )
        guard decodedBytes <= Self.perPadDecodedByteLimit else {
            throw ExternalAudioReferenceError.decodedAudioTooLarge(
                bytes: decodedBytes,
                limit: Self.perPadDecodedByteLimit
            )
        }

        let resourceIdentifierData: Data?
        if let identifier = values.fileResourceIdentifier {
            resourceIdentifierData = try? NSKeyedArchiver.archivedData(
                withRootObject: identifier,
                requiringSecureCoding: true
            )
        } else {
            resourceIdentifierData = nil
        }

        return ValidatedExternalAudio(
            fingerprint: ExternalFileFingerprint(
                resourceIdentifierData: resourceIdentifierData,
                fileSize: values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate
            ),
            metadata: PadAudioMetadata(
                duration: Double(file.length) / format.sampleRate,
                channelCount: channels,
                sampleRate: format.sampleRate,
                decodedByteCount: decodedBytes
            )
        )
    }

    static func decodedByteCount(
        frameCount: AVAudioFramePosition,
        channelCount: AVAudioChannelCount,
        bytesPerFrame: UInt32,
        isInterleaved: Bool
    ) throws -> UInt64 {
        guard frameCount > 0, channelCount > 0, bytesPerFrame > 0 else {
            throw ExternalAudioReferenceError.invalidAudioDescription
        }
        let frames = UInt64(frameCount)
        let bytes = UInt64(bytesPerFrame)
        let channelMultiplier = isInterleaved ? UInt64(1) : UInt64(channelCount)
        let (frameBytes, frameOverflow) = bytes.multipliedReportingOverflow(by: channelMultiplier)
        let (total, totalOverflow) = frames.multipliedReportingOverflow(by: frameBytes)
        guard !frameOverflow, !totalOverflow else { throw ExternalAudioReferenceError.decodedSizeOverflow }
        return total
    }

    private static func mapAudioError(_ error: Error) -> ExternalAudioReferenceError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
            return .permissionDenied
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
            return .fileMissing
        }
        return .unsupportedOrProtected
    }

    private static func mapFileError(_ error: Error) -> ExternalAudioReferenceError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
            return .permissionDenied
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
            return .fileMissing
        }
        return .unreadable
    }
}

struct ImportedExternalAudio: Sendable, Equatable {
    var sourceIndex: Int
    var initialLabel: String
    var reference: ExternalAudioReference
}

struct ExternalAudioImportFailure: Sendable, Equatable {
    var sourceIndex: Int
    var filename: String
    var error: ExternalAudioReferenceError
}

struct ExternalAudioImportResult: Sendable, Equatable {
    var imported: [ImportedExternalAudio]
    var failures: [ExternalAudioImportFailure]
    var skippedDuplicateFilenames: [String]
    var wasCancelled: Bool
    /// Set by the AppStore when validation succeeded but the catalog edit could not be
    /// persisted. In that case `imported` contains only durably committed additions (none).
    var persistenceError: String? = nil
}

protocol ExternalAudioReferencing: Sendable {
    func createReference(for url: URL) async throws -> ExternalAudioReference
    func inspect(_ reference: ExternalAudioReference) async -> PadAssetState
    func refreshedReference(_ reference: ExternalAudioReference) async throws -> ExternalAudioReference
    func importReferences(
        from urls: [URL],
        existing: [ExternalAudioReference]
    ) async -> ExternalAudioImportResult
    func withCoordinatedRead<T: Sendable>(
        of reference: ExternalAudioReference,
        operation: @Sendable (URL) throws -> T
    ) async throws -> T
}

actor ExternalAudioReferenceService: ExternalAudioReferencing {
    private let bookmarks: any SecurityScopedBookmarking
    private let scopes: any SecurityScopeAccessing
    private let coordinator: any CoordinatedFileReading
    private let validator: any ExternalAudioValidating
    private let fileManager: FileManager

    init(
        bookmarks: any SecurityScopedBookmarking = SystemSecurityScopedBookmarkStore(),
        scopes: any SecurityScopeAccessing = SystemSecurityScopeAccessor(),
        coordinator: any CoordinatedFileReading = SystemCoordinatedFileReader(),
        validator: any ExternalAudioValidating = AVFoundationExternalAudioValidator(),
        fileManager: FileManager = .default
    ) {
        self.bookmarks = bookmarks
        self.scopes = scopes
        self.coordinator = coordinator
        self.validator = validator
        self.fileManager = fileManager
    }

    func createReference(for url: URL) async throws -> ExternalAudioReference {
        let resolvedURL = try canonicalFileURL(url)
        return try scopedAccess(to: resolvedURL) {
            let validated = try coordinator.coordinate(at: resolvedURL) { coordinatedURL in
                try validator.validate(coordinatedURL)
            }
            let bookmark = try bookmarks.createReadOnlyBookmark(for: resolvedURL)
            return ExternalAudioReference(
                bookmarkData: bookmark,
                lastKnownPath: resolvedURL.path,
                originalFilename: resolvedURL.lastPathComponent,
                fingerprint: validated.fingerprint,
                audioMetadata: validated.metadata
            )
        }
    }

    func inspect(_ reference: ExternalAudioReference) async -> PadAssetState {
        do {
            let validated: ValidatedExternalAudio = try await withCoordinatedRead(of: reference) {
                try self.validator.validate($0)
            }
            return validated.fingerprint == reference.fingerprint
                ? .available(validated.metadata)
                : .changed
        } catch let error as ExternalAudioReferenceError {
            return Self.state(for: error)
        } catch {
            return .unreadable
        }
    }

    func refreshedReference(_ reference: ExternalAudioReference) async throws -> ExternalAudioReference {
        let resolved = try bookmarks.resolve(reference.bookmarkData)
        let validated: ValidatedExternalAudio = try scopedAccess(to: resolved.url) {
            try coordinator.coordinate(at: resolved.url) { try validator.validate($0) }
        }
        var refreshed = reference
        refreshed.lastKnownPath = resolved.url.path
        refreshed.originalFilename = resolved.url.lastPathComponent
        refreshed.fingerprint = validated.fingerprint
        refreshed.audioMetadata = validated.metadata
        if resolved.isStale {
            refreshed.bookmarkData = try scopedAccess(to: resolved.url) {
                try bookmarks.createReadOnlyBookmark(for: resolved.url)
            }
        }
        return refreshed
    }

    func importReferences(
        from urls: [URL],
        existing: [ExternalAudioReference] = []
    ) async -> ExternalAudioImportResult {
        var imported: [ImportedExternalAudio] = []
        var failures: [ExternalAudioImportFailure] = []
        var duplicateNames: [String] = []
        var knownIdentities = Set(existing.compactMap(\.fingerprint.resourceIdentifierData))
        var knownPaths = Set(existing.map { URL(fileURLWithPath: $0.lastKnownPath).standardizedFileURL.path })

        for (index, url) in urls.enumerated() {
            if Task.isCancelled {
                return ExternalAudioImportResult(
                    imported: imported,
                    failures: failures,
                    skippedDuplicateFilenames: duplicateNames,
                    wasCancelled: true
                )
            }
            do {
                let reference = try await createReference(for: url)
                let path = URL(fileURLWithPath: reference.lastKnownPath).standardizedFileURL.path
                let identity = reference.fingerprint.resourceIdentifierData
                let isDuplicate = identity.map(knownIdentities.contains) ?? knownPaths.contains(path)
                if isDuplicate {
                    duplicateNames.append(reference.originalFilename)
                    continue
                }
                if let identity { knownIdentities.insert(identity) }
                knownPaths.insert(path)
                imported.append(
                    ImportedExternalAudio(
                        sourceIndex: index,
                        initialLabel: url.deletingPathExtension().lastPathComponent,
                        reference: reference
                    )
                )
            } catch let error as ExternalAudioReferenceError {
                failures.append(
                    ExternalAudioImportFailure(
                        sourceIndex: index,
                        filename: url.lastPathComponent,
                        error: error
                    )
                )
            } catch {
                failures.append(
                    ExternalAudioImportFailure(
                        sourceIndex: index,
                        filename: url.lastPathComponent,
                        error: .unreadable
                    )
                )
            }
        }
        return ExternalAudioImportResult(
            imported: imported,
            failures: failures,
            skippedDuplicateFilenames: duplicateNames,
            wasCancelled: false
        )
    }

    func withCoordinatedRead<T: Sendable>(
        of reference: ExternalAudioReference,
        operation: @Sendable (URL) throws -> T
    ) async throws -> T {
        let resolved = try bookmarks.resolve(reference.bookmarkData)
        return try scopedAccess(to: resolved.url) {
            try coordinator.coordinate(at: resolved.url, operation: operation)
        }
    }

    private func canonicalFileURL(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw ExternalAudioReferenceError.notAFile }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: canonical.path, isDirectory: &isDirectory) else {
            throw ExternalAudioReferenceError.fileMissing
        }
        guard !isDirectory.boolValue else { throw ExternalAudioReferenceError.directory }
        return canonical
    }

    private func scopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let didStart = scopes.startAccessing(url)
        guard didStart || fileManager.isReadableFile(atPath: url.path) else {
            throw ExternalAudioReferenceError.permissionDenied
        }
        defer { if didStart { scopes.stopAccessing(url) } }
        return try operation()
    }

    private static func state(for error: ExternalAudioReferenceError) -> PadAssetState {
        switch error {
        case .permissionDenied: .permissionDenied
        case .fileMissing, .bookmarkResolutionFailed: .missing
        case .externalVolumeUnavailable: .externalVolumeUnavailable
        case .changed: .changed
        case .unsupportedOrProtected, .unsupportedChannelCount, .invalidAudioDescription,
             .decodedSizeOverflow, .decodedAudioTooLarge, .notAFile, .directory:
            .unsupportedOrProtected
        case .unreadable, .bookmarkCreationFailed: .unreadable
        }
    }
}
