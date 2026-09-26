import Foundation

enum ClickAfterCountoff: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case continueClick
    case countoffOnly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .continueClick: "Continue Click"
        case .countoffOnly: "Countoff Only"
        }
    }
}

/// A song's start behavior. The persisted default exactly matches the existing live behavior.
struct CountoffPolicy: Codable, Equatable, Hashable, Sendable {
    var bars: Int
    var after: ClickAfterCountoff

    init(bars: Int, after: ClickAfterCountoff) {
        self.bars = bars
        self.after = after
    }

    static let liveDefault = CountoffPolicy(bars: 1, after: .continueClick)
    static let rehearseDefault = CountoffPolicy(bars: 1, after: .continueClick)

    var isValid: Bool { (0...2).contains(bars) && !(bars == 0 && after == .countoffOnly) }
    var hasCountoff: Bool { bars > 0 }

    private enum CodingKeys: String, CodingKey { case bars, after }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bars = try container.decode(Int.self, forKey: .bars)
        after = try container.decode(ClickAfterCountoff.self, forKey: .after)
        guard isValid else {
            throw DecodingError.dataCorruptedError(
                forKey: .bars,
                in: container,
                debugDescription: "Countoff policy must have 0–2 bars and cannot be Countoff Only with zero bars."
            )
        }
    }
}
