import AVFoundation
import Foundation
import Testing
@testable import Sustain

private final class NumberProbeVoice: CountoffVoiceRendering {
    var requestedNumbers: [Int] = []
    func prewarm(numbers: [Int], format: AVAudioFormat) {}
    func renderedWord(for number: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        requestedNumbers.append(number)
        return nil
    }
}

private final class ConstantProbeVoice: CountoffVoiceRendering {
    func prewarm(numbers: [Int], format: AVAudioFormat) {}
    func renderedWord(for number: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 0.1)),
              let samples = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(format.channelCount) {
            samples[channel].update(repeating: 0.25, count: Int(buffer.frameLength))
        }
        return buffer
    }
}

struct AdvancedClickAudioTests {
    private func peak(_ buffer: AVAudioPCMBuffer, at frame: Int, width: Int = 500) throws -> Float {
        let samples = try #require(buffer.floatChannelData?[0])
        return (frame..<min(Int(buffer.frameLength), frame + width)).reduce(Float(0)) {
            max($0, abs(samples[$1]))
        }
    }

    @Test func groupedCompoundMetersUseDottedQuarterPulses() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        for (signature, count) in [(TimeSignature.sixEight, 2), (.nineEight, 3), (.twelveEight, 4)] {
            let grid = ClickPulseGrid(timeSignature: signature, pulseInterpretation: .grouped,
                                      bpm: 72, sampleRate: format.sampleRate)
            #expect(grid.pulseCount == count)
            #expect(grid.pulseUnitLabel == "dotted-quarter BPM")
            let loop = try SustainAudioEngine.makeClickBuffer(
                format: format, bpm: 72, timeSignature: signature, subdivision: .three,
                measures: 1, settings: .default, pulseInterpretation: .grouped)
            #expect(Int(loop.frameLength) == grid.frameCount())
            for pulse in 0..<count {
                for slot in 0..<3 {
                    #expect(try peak(loop, at: grid.frame(forPulse: pulse, subdivision: slot,
                                                           subdivisionsPerPulse: 3)) > 0.05)
                }
            }
            let legacy = ClickPulseGrid(timeSignature: signature, pulseInterpretation: .legacy,
                                        bpm: 72 * 3, sampleRate: format.sampleRate)
            #expect(legacy.frameCount() == grid.frameCount())
            #expect(legacy.equivalentBPM(for: .grouped) == 72)
        }
    }

    @Test func accentsAndMuteApplyToWholePulseIncludingSubdivisions() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let pattern: [ClickAccentLevel] = [.strong, .normal, .soft, .mute]
        let buffer = try SustainAudioEngine.makeClickBuffer(
            format: format, bpm: 72, timeSignature: .fourFour, subdivision: .two,
            measures: 1, settings: .default, accentPattern: pattern)
        let grid = ClickPulseGrid(timeSignature: .fourFour, pulseInterpretation: .legacy,
                                  bpm: 72, sampleRate: format.sampleRate)
        let strong = try peak(buffer, at: grid.frame(forPulse: 0))
        let normal = try peak(buffer, at: grid.frame(forPulse: 1))
        let soft = try peak(buffer, at: grid.frame(forPulse: 2))
        #expect(strong > normal)
        #expect(normal > soft)
        #expect(try peak(buffer, at: grid.frame(forPulse: 3)) == 0)
        #expect(try peak(buffer, at: grid.frame(forPulse: 3, subdivision: 1,
                                                subdivisionsPerPulse: 2)) == 0)
    }

    @Test func accentDynamicsStayDistinctAcrossSubdivisionSlots() throws {
        try exportAccentListeningPreviewWhenRequested()
        for sampleRate in [44_100.0, 48_000.0] {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
            for subdivision in ClickSubdivision.allCases {
                let buffer = try SustainAudioEngine.makeClickBuffer(
                    format: format, bpm: 100, timeSignature: .fourFour, subdivision: subdivision,
                    measures: 1, settings: .default, accentPattern: [.strong, .normal, .soft, .mute])
                let grid = ClickPulseGrid(timeSignature: .fourFour, pulseInterpretation: .legacy,
                                          bpm: 100, sampleRate: sampleRate)
                for slot in 0..<subdivision.rawValue {
                    let levels = try (0..<4).map { pulse in
                        try peak(buffer, at: grid.frame(forPulse: pulse, subdivision: slot,
                                                       subdivisionsPerPulse: subdivision.rawValue))
                    }
                    let strongOverNormalDB = 20 * log10(Double(levels[0] / levels[1]))
                    let softBelowNormalDB = 20 * log10(Double(levels[2] / levels[1]))
                    // Strong is noticeable but restrained; Soft remains audible as a guide.
                    #expect((3.5...5.0).contains(strongOverNormalDB))
                    #expect((-11.0 ... -9.0).contains(softBelowNormalDB))
                    #expect(levels[2] > 0.03)
                    #expect(levels[3] == 0)
                    #expect(levels[0] < 0.8)
                }
            }
        }
    }

    @Test func countoffClickDynamicsMatchLoopWithoutChangingSpeechLevel() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let pattern: [ClickAccentLevel] = [.strong, .normal, .soft, .mute]
        let grid = ClickPulseGrid(timeSignature: .fourFour, pulseInterpretation: .legacy,
                                  bpm: 100, sampleRate: format.sampleRate)
        let loop = try SustainAudioEngine.makeClickBuffer(
            format: format, bpm: 100, timeSignature: .fourFour, subdivision: .two,
            measures: 1, settings: .default, accentPattern: pattern)
        let counted = try SustainAudioEngine.makeCountoffBuffer(
            format: format, voiceRenderer: nil, bpm: 100, timeSignature: .fourFour,
            subdivision: .two, settings: .default, accentPattern: pattern)
        for pulse in 0..<3 {
            let frame = grid.frame(forPulse: pulse)
            #expect(abs(try peak(counted, at: frame) / peak(loop, at: frame) - 0.2) < 0.001)
        }
        let spokenOnly = try SustainAudioEngine.makeCountoffBuffer(
            format: format, voiceRenderer: ConstantProbeVoice(), bpm: 100, timeSignature: .fourFour,
            settings: .default, accentPattern: pattern)
        let samples = try #require(spokenOnly.floatChannelData?[0])
        // After the click transient, speech has the same gain for every accent,
        // including a muted click beat; accents must not obscure the spoken numbers.
        let offset = Int(format.sampleRate * 0.06)
        let reference = samples[grid.frame(forPulse: 0) + offset]
        #expect(reference > 0)
        for pulse in 1..<4 {
            #expect(samples[grid.frame(forPulse: pulse) + offset] == reference)
        }
    }

    private func exportAccentListeningPreviewWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["SUSTAIN_CLICK_PREVIEW_PATH"] else { return }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try SustainAudioEngine.makeClickBuffer(
            format: format, bpm: 100, timeSignature: .fourFour, subdivision: .two,
            measures: 3, settings: .default, accentPattern: [.strong, .normal, .soft, .mute])
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings)
        try file.write(from: buffer)
    }

    @Test func groupedTwoBarCountoffRepeatsPulseNumbers() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let voice = NumberProbeVoice()
        let buffer = try SustainAudioEngine.makeCountoffBuffer(
            format: format, voiceRenderer: voice, bpm: 72, timeSignature: .sixEight,
            settings: .default, pulseInterpretation: .grouped, measures: 2)
        let grid = ClickPulseGrid(timeSignature: .sixEight, pulseInterpretation: .grouped,
                                  bpm: 72, sampleRate: format.sampleRate)
        #expect(Int(buffer.frameLength) == grid.frameCount(measures: 2))
        #expect(voice.requestedNumbers == [1, 2, 1, 2])
    }

    @Test @MainActor func oldSnapshotMigratesToAudiblyCompatibleDefaults() throws {
        let snapshot = AppStore.seedSnapshot()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var songs = try #require(object["songs"] as? [[String: Any]])
        for index in songs.indices {
            songs[index].removeValue(forKey: "pulseInterpretation")
            songs[index].removeValue(forKey: "clickAccentPattern")
            songs[index].removeValue(forKey: "countoffPolicy")
        }
        object["songs"] = songs
        object["schemaVersion"] = 4
        let migrated = try JSONDecoder().decode(LibrarySnapshot.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(migrated.songs.allSatisfy {
            $0.pulseInterpretation == .legacy && $0.clickAccentPattern == nil &&
            $0.countoffPolicy == .liveDefault
        })
    }
}
