import Foundation

struct LibrarySnapshot: Codable, Equatable {
    var songs: [Song]
    var activeSetlist: Setlist
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
