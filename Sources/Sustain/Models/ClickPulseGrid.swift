import Foundation

enum PulseInterpretation: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case legacy
    case grouped

    var id: String { rawValue }
    var label: String {
        switch self {
        case .legacy: "Eighth-note BPM"
        case .grouped: "Dotted-quarter BPM"
        }
    }
}

enum ClickAccentLevel: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case strong
    case normal
    case soft
    case mute

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var next: Self {
        let levels = Self.allCases
        return levels[(levels.firstIndex(of: self)! + 1) % levels.count]
    }
}

/// One BPM pulse is the unit for subdivisions, accents, and spoken count-off numbers.
struct ClickPulseGrid: Equatable, Sendable {
    let timeSignature: TimeSignature
    let pulseInterpretation: PulseInterpretation
    let bpm: Int
    let sampleRate: Double

    var isGrouped: Bool {
        pulseInterpretation == .grouped && timeSignature.beatUnit == 8 &&
            [6, 9, 12].contains(timeSignature.beatsPerMeasure)
    }

    var pulseCount: Int { max(1, timeSignature.beatsPerMeasure / (isGrouped ? 3 : 1)) }
    var secondsPerPulse: TimeInterval { 60 / Double(bpm) }
    var framesPerPulse: Double { sampleRate * 60 / Double(bpm) }
    func frameCount(measures: Int = 1) -> Int {
        max(1, Int(Double(pulseCount * max(1, measures)) * framesPerPulse))
    }
    func frame(forPulse pulse: Int, subdivision: Int = 0, subdivisionsPerPulse: Int = 1) -> Int {
        Int((Double(pulse) + Double(subdivision) / Double(subdivisionsPerPulse)) * framesPerPulse)
    }
    var pulseUnitLabel: String {
        if isGrouped { return "dotted-quarter BPM" }
        return timeSignature.beatUnit == 8 ? "eighth-note BPM" : "quarter-note BPM"
    }

    /// Returns nil when the duration-preserving tempo falls outside Sustain's BPM range.
    func equivalentBPM(for interpretation: PulseInterpretation) -> Int? {
        let target = ClickPulseGrid(timeSignature: timeSignature, pulseInterpretation: interpretation,
                                    bpm: bpm, sampleRate: sampleRate)
        let equivalent = Double(bpm * target.pulseCount) / Double(pulseCount)
        let rounded = Int(equivalent.rounded())
        return (40...220).contains(rounded) ? rounded : nil
    }
}
