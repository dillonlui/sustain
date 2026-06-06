import Foundation

struct LibrarySnapshot: Codable, Equatable {
    var songs: [Song]
    var activeSetlist: Setlist
    var routingSettings: AudioRoutingSettings

    init(
        songs: [Song],
        activeSetlist: Setlist,
        routingSettings: AudioRoutingSettings = .default
    ) {
        self.songs = songs
        self.activeSetlist = activeSetlist
        self.routingSettings = routingSettings
    }

    private enum CodingKeys: String, CodingKey {
        case songs
        case activeSetlist
        case routingSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songs = try container.decode([Song].self, forKey: .songs)
        activeSetlist = try container.decode(Setlist.self, forKey: .activeSetlist)
        routingSettings = try container.decodeIfPresent(AudioRoutingSettings.self, forKey: .routingSettings) ?? .default
    }

    var hasUsableSetlist: Bool {
        let songIDs = Set(songs.map(\.id))
        return !songs.isEmpty && activeSetlist.entries.contains { songIDs.contains($0.songID) }
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

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
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
}
