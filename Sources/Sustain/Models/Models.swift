import Foundation

enum MusicalKey: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
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

    /// Keep the raw values stable because they are persisted in Library.json, while making
    /// the current counted behavior explicit in the UI.
    var label: String {
        switch self {
        case .counted: "Count + Click"
        case .click: "Click Only"
        }
    }
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

struct ExternalFileFingerprint: Codable, Equatable, Hashable, Sendable {
    var resourceIdentifierData: Data?
    var fileSize: Int64?
    var modificationDate: Date?
}

struct PadAudioMetadata: Codable, Equatable, Hashable, Sendable {
    var duration: TimeInterval
    var channelCount: UInt32
    var sampleRate: Double
    var decodedByteCount: UInt64
}

struct ExternalAudioReference: Codable, Equatable, Hashable, Sendable {
    var bookmarkData: Data
    var lastKnownPath: String
    var originalFilename: String
    var fingerprint: ExternalFileFingerprint
    var audioMetadata: PadAudioMetadata
}

enum PadSource: Codable, Equatable, Hashable, Sendable {
    case bundled(key: MusicalKey)
    case external(ExternalAudioReference)

    var bundledKey: MusicalKey? {
        guard case let .bundled(key) = self else { return nil }
        return key
    }

    var originalFilename: String? {
        guard case let .external(reference) = self else { return nil }
        return reference.originalFilename
    }
}

struct PadTrack: Codable, Identifiable, Equatable, Hashable, Sendable {
    typealias ID = UUID

    var id: ID
    var label: String
    var source: PadSource

    var isIncluded: Bool { source.bundledKey != nil }

    static let includedByKey: [MusicalKey: PadTrack] = [
        .c: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000001")!, label: "C", source: .bundled(key: .c)),
        .db: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000002")!, label: "Db", source: .bundled(key: .db)),
        .d: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000003")!, label: "D", source: .bundled(key: .d)),
        .eb: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000004")!, label: "Eb", source: .bundled(key: .eb)),
        .e: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000005")!, label: "E", source: .bundled(key: .e)),
        .f: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000006")!, label: "F", source: .bundled(key: .f)),
        .gb: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000007")!, label: "Gb", source: .bundled(key: .gb)),
        .g: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000008")!, label: "G", source: .bundled(key: .g)),
        .ab: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-000000000009")!, label: "Ab", source: .bundled(key: .ab)),
        .a: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-00000000000A")!, label: "A", source: .bundled(key: .a)),
        .bb: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-00000000000B")!, label: "Bb", source: .bundled(key: .bb)),
        .b: PadTrack(id: UUID(uuidString: "7B14A9F0-0A01-4B75-9000-00000000000C")!, label: "B", source: .bundled(key: .b))
    ]

    static var included: [PadTrack] {
        MusicalKey.allCases.compactMap { includedByKey[$0] }
    }

    static func includedID(for key: MusicalKey) -> ID {
        // The table is exhaustively defined for MusicalKey.allCases and guarded by tests.
        includedByKey[key]!.id
    }
}

struct Song: Codable, Identifiable, Equatable, Hashable {
    enum PadTrackIDDecodingState: Equatable, Hashable {
        case missing
        case null
        case value
    }

    var id: UUID
    var title: String
    var defaultKey: MusicalKey
    var defaultBPM: Int
    var timeSignature: TimeSignature
    var padPack: PadPack
    var padTrackID: PadTrack.ID?
    var padTrackIDDecodingState: PadTrackIDDecodingState = .value

    init(
        id: UUID = UUID(),
        title: String,
        defaultKey: MusicalKey,
        defaultBPM: Int,
        timeSignature: TimeSignature,
        padPack: PadPack
    ) {
        self.id = id
        self.title = title
        self.defaultKey = defaultKey
        self.defaultBPM = defaultBPM
        self.timeSignature = timeSignature
        self.padPack = padPack
        self.padTrackID = PadTrack.includedID(for: defaultKey)
    }

    init(
        id: UUID = UUID(),
        title: String,
        defaultKey: MusicalKey,
        defaultBPM: Int,
        timeSignature: TimeSignature,
        padPack: PadPack,
        padTrackID: PadTrack.ID?
    ) {
        self.init(
            id: id,
            title: title,
            defaultKey: defaultKey,
            defaultBPM: defaultBPM,
            timeSignature: timeSignature,
            padPack: padPack
        )
        self.padTrackID = padTrackID
    }

    enum CodingKeys: String, CodingKey {
        case id, title, defaultKey, defaultBPM, timeSignature, padPack, padTrackID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        defaultKey = try container.decode(MusicalKey.self, forKey: .defaultKey)
        defaultBPM = try container.decode(Int.self, forKey: .defaultBPM)
        timeSignature = try container.decode(TimeSignature.self, forKey: .timeSignature)
        padPack = try container.decodeIfPresent(PadPack.self, forKey: .padPack) ?? .bundled

        if !container.contains(.padTrackID) {
            padTrackID = nil
            padTrackIDDecodingState = .missing
        } else if try container.decodeNil(forKey: .padTrackID) {
            padTrackID = nil
            padTrackIDDecodingState = .null
        } else {
            padTrackID = try container.decode(PadTrack.ID.self, forKey: .padTrackID)
            padTrackIDDecodingState = .value
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(defaultKey, forKey: .defaultKey)
        try container.encode(defaultBPM, forKey: .defaultBPM)
        try container.encode(timeSignature, forKey: .timeSignature)
        try container.encode(padPack, forKey: .padPack)
        try container.encode(padTrackID, forKey: .padTrackID)
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.defaultKey == rhs.defaultKey &&
            lhs.defaultBPM == rhs.defaultBPM && lhs.timeSignature == rhs.timeSignature &&
            lhs.padPack == rhs.padPack && lhs.padTrackID == rhs.padTrackID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(defaultKey)
        hasher.combine(defaultBPM)
        hasher.combine(timeSignature)
        hasher.combine(padPack)
        hasher.combine(padTrackID)
    }
}

struct SetlistEntry: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var songID: Song.ID

    /// Read only while migrating schema-v1 libraries. Runtime code never consults these;
    /// Song is the sole source of truth for key and BPM in schema v2 and later.
    var legacyKeyOverride: MusicalKey?
    var legacyBPMOverride: Int?

    init(id: UUID = UUID(), songID: Song.ID) {
        self.id = id
        self.songID = songID
        legacyKeyOverride = nil
        legacyBPMOverride = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case songID
        case keyOverride
        case bpmOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        songID = try container.decode(Song.ID.self, forKey: .songID)
        legacyKeyOverride = try container.decodeIfPresent(MusicalKey.self, forKey: .keyOverride)
        legacyBPMOverride = try container.decodeIfPresent(Int.self, forKey: .bpmOverride)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(songID, forKey: .songID)
        // v2 intentionally omits the legacy override fields. They are promoted to Song values
        // during decode, leaving one canonical value everywhere in the app.
    }
}

struct Setlist: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var entries: [SetlistEntry]
}
