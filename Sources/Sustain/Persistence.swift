import Foundation

struct LibrarySnapshot: Codable, Equatable {
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
        self.songs = Self.normalizedSongs(songs)
        self.padPacks = [Self.includedPadPack(from: padPacks)]
        self.activeSetlist = activeSetlist
        self.routingSettings = routingSettings
        self.padVolume = Self.clampedVolume(padVolume)
        self.clickVolume = Self.clampedVolume(clickVolume)
        self.clickSettings = clickSettings
    }

    private enum CodingKeys: String, CodingKey {
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
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        } catch {
            try? quarantineLibrary(at: url)
            throw error
        }
    }

    func saveLibrary(_ snapshot: LibrarySnapshot) throws {
        let url = try libraryURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    private func libraryURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("Library.json", isDirectory: false)
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
