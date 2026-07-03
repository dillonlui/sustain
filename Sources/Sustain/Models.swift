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

    static let common = [twoFour, threeFour, fourFour, fiveFour, sixEight, nineEight, twelveEight]
    static let twoFour = TimeSignature(beatsPerMeasure: 2, beatUnit: 4)
    static let threeFour = TimeSignature(beatsPerMeasure: 3, beatUnit: 4)
    static let fourFour = TimeSignature(beatsPerMeasure: 4, beatUnit: 4)
    static let fiveFour = TimeSignature(beatsPerMeasure: 5, beatUnit: 4)
    static let sixEight = TimeSignature(beatsPerMeasure: 6, beatUnit: 8)
    static let nineEight = TimeSignature(beatsPerMeasure: 9, beatUnit: 8)
    static let twelveEight = TimeSignature(beatsPerMeasure: 12, beatUnit: 8)
}

enum ClickAccentMode: String, CaseIterable, Codable, Identifiable {
    case none = "No Accent"
    case downbeat = "Downbeat"

    var id: String { rawValue }
}

enum CountoffSound: String, CaseIterable, Codable, Identifiable {
    case counted = "Count"
    case click = "Click"

    var id: String { rawValue }
}

struct ClickSettings: Codable, Equatable {
    var accentMode: ClickAccentMode
    var countoffSound: CountoffSound

    static let `default` = ClickSettings(accentMode: .none, countoffSound: .counted)
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
