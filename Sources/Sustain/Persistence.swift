import Foundation

struct LibrarySnapshot: Codable, Equatable {
    /// The on-disk format version this build writes and can read. Bump when the persisted shape
    /// changes in a breaking way, and add a migration branch in `LocalLibraryStore` keyed on the
    /// decoded `schemaVersion`. Establishing the field now (while it's trivial) is what lets a
    /// future v2 migrate old files instead of throwing and wiping the user's library.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var songs: [Song]
    var padPacks: [PadPack]
    var activeSetlist: Setlist
    var routingSettings: AudioRoutingSettings
    var padVolume: Double
    var clickVolume: Double
    var clickSettings: ClickSettings

    init(
        songs: [Song],
        padPacks: [PadPack]? = nil,
        activeSetlist: Setlist,
        routingSettings: AudioRoutingSettings = .default,
        padVolume: Double = 0.42,
        clickVolume: Double = 0.75,
        clickSettings: ClickSettings = .default
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.songs = Self.normalizedSongs(songs)
        self.padPacks = [Self.includedPadPack(from: padPacks)]
        self.activeSetlist = activeSetlist
        self.routingSettings = routingSettings
        self.padVolume = Self.clampedVolume(padVolume)
        self.clickVolume = Self.clampedVolume(clickVolume)
        self.clickSettings = clickSettings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case songs
        case padPacks
        case activeSetlist
        case routingSettings
        case padVolume
        case clickVolume
        case clickSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy files (shipped before versioning) have no field → treat as v1.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let decodedSongs = try container.decode([Song].self, forKey: .songs)
        let decodedPadPacks = try container.decodeIfPresent([PadPack].self, forKey: .padPacks)
        songs = Self.normalizedSongs(decodedSongs)
        padPacks = [Self.includedPadPack(from: decodedPadPacks)]
        activeSetlist = try container.decode(Setlist.self, forKey: .activeSetlist)
        routingSettings = try container.decodeIfPresent(AudioRoutingSettings.self, forKey: .routingSettings) ?? .default
        padVolume = Self.clampedVolume(try container.decodeIfPresent(Double.self, forKey: .padVolume) ?? 0.42)
        clickVolume = Self.clampedVolume(try container.decodeIfPresent(Double.self, forKey: .clickVolume) ?? 0.75)
        clickSettings = try container.decodeIfPresent(ClickSettings.self, forKey: .clickSettings) ?? .default
    }

    var hasUsableSetlist: Bool {
        let songIDs = Set(songs.map(\.id))
        return !songs.isEmpty && activeSetlist.entries.contains { songIDs.contains($0.songID) }
    }

    private static func normalizedSongs(_ songs: [Song]) -> [Song] {
        songs.map { song in
            Song(
                id: song.id,
                title: song.title,
                defaultKey: song.defaultKey,
                defaultBPM: song.defaultBPM,
                timeSignature: song.timeSignature,
                padPack: .bundled
            )
        }
    }

    private static func includedPadPack(from padPacks: [PadPack]?) -> PadPack {
        .bundled
    }

    private static func clampedVolume(_ volume: Double) -> Double {
        min(1, max(0, volume))
    }
}

enum LibraryValidationError: LocalizedError {
    case unusableSetlist

    var errorDescription: String? {
        switch self {
        case .unusableSetlist:
            "Saved library does not include a usable setlist."
        }
    }
}

enum LibraryLoadError: LocalizedError {
    /// The file decoded fine but was written by a newer app version than this build supports.
    /// Distinct from corruption: we must NOT quarantine or overwrite it, or we'd destroy data
    /// that a newer install can still read.
    case newerSchema(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case let .newerSchema(found, supported):
            "This library was saved by a newer version of Sustain (format \(found); this app supports \(supported)). Update the app to open it."
        }
    }
}

struct LocalLibraryStore {
    private let fileManager: FileManager
    private let directoryOverride: URL?

    init(fileManager: FileManager = .default, directoryOverride: URL? = nil) {
        self.fileManager = fileManager
        self.directoryOverride = directoryOverride
    }

    func applicationSupportDirectory() throws -> URL {
        if let directoryOverride {
            if !fileManager.fileExists(atPath: directoryOverride.path) {
                try fileManager.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            }
            return directoryOverride
        }

        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("Sustain", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    func loadLibrary() throws -> LibrarySnapshot? {
        let url = try libraryURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            return try decodeSnapshot(at: url)
        } catch let error as LibraryLoadError {
            // Newer-than-supported schema: the file is valid, just from the future. Do NOT
            // quarantine or fall back — surface it so we don't clobber recoverable data.
            throw error
        } catch {
            // Corrupt/unreadable primary: quarantine it, then try the rolling backup (the
            // previous good save) before giving up. This turns the common "file got mangled"
            // case from "library wiped, demo seed shown" into "last save recovered".
            try? quarantineLibrary(at: url)
            if let backup = try? backupURL(), let recovered = try? decodeSnapshot(at: backup) {
                return recovered
            }
            throw error
        }
    }

    func saveLibrary(_ snapshot: LibrarySnapshot) throws {
        let url = try libraryURL()
        // Roll the current good file to a backup before overwriting, so a later corrupt or
        // interrupted write can't leave us with only an unreadable primary.
        if fileManager.fileExists(atPath: url.path) {
            let backup = try backupURL()
            try? fileManager.removeItem(at: backup)
            try? fileManager.copyItem(at: url, to: backup)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    /// Decode a snapshot and reject one written by a newer app version (distinct from corrupt).
    private func decodeSnapshot(at url: URL) throws -> LibrarySnapshot {
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        guard snapshot.schemaVersion <= LibrarySnapshot.currentSchemaVersion else {
            throw LibraryLoadError.newerSchema(
                found: snapshot.schemaVersion,
                supported: LibrarySnapshot.currentSchemaVersion
            )
        }
        return snapshot
    }

    private func libraryURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("Library.json", isDirectory: false)
    }

    private func backupURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("Library.bak", isDirectory: false)
    }

    private func quarantineLibrary(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = url
            .deletingLastPathComponent()
            .appendingPathComponent("Library.invalid-\(timestamp).json", isDirectory: false)

        try fileManager.moveItem(at: url, to: backupURL)
    }
}
