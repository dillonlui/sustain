import Foundation

enum MusicalKey: String, CaseIterable, Codable, Identifiable {
    case c = "C"
    case db = "Db"
    case d = "D"
    case eb = "Eb"
    case e = "E"
    case f = "F"
    case gb = "Gb"
    case g = "G"
    case ab = "Ab"
    case a = "A"
    case bb = "Bb"
    case b = "B"

    var id: String { rawValue }
}

struct TimeSignature: Codable, Equatable, Hashable, CustomStringConvertible {
    var beatsPerMeasure: Int
    var beatUnit: Int

    var description: String {
        "\(beatsPerMeasure)/\(beatUnit)"
    }

    static let common = [fourFour, sixEight]
    static let fourFour = TimeSignature(beatsPerMeasure: 4, beatUnit: 4)
    static let sixEight = TimeSignature(beatsPerMeasure: 6, beatUnit: 8)
}

struct PadPack: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var folderName: String
    var availableKeys: Set<MusicalKey>

    func supports(_ key: MusicalKey) -> Bool {
        availableKeys.contains(key)
    }

    var isBundled: Bool {
        folderName == Self.bundled.folderName
    }

    static let bundled = PadPack(
        name: "Included Pads",
        folderName: "Pads",
        availableKeys: Set(MusicalKey.allCases)
    )
}

struct Song: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var defaultKey: MusicalKey
    var defaultBPM: Int
    var timeSignature: TimeSignature
    var padPack: PadPack
}

struct SetlistEntry: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var songID: Song.ID
    var keyOverride: MusicalKey?
    var bpmOverride: Int?

    func resolvedKey(for song: Song) -> MusicalKey {
        keyOverride ?? song.defaultKey
    }

    func resolvedBPM(for song: Song) -> Int {
        bpmOverride ?? song.defaultBPM
    }
}

struct Setlist: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var entries: [SetlistEntry]
}
