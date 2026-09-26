import AVFoundation
import Foundation
import Testing
@testable import Sustain

private final class NumberRecordingVoice: CountoffVoiceRendering {
    var numbers: [Int] = []

    func prewarm(numbers: [Int], format: AVAudioFormat) {}

    func renderedWord(for number: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        numbers.append(number)
        return nil
    }
}

@MainActor
struct AdvancedClickIntegrationTests {
    private func format(_ sampleRate: Double = 44_100) throws -> AVAudioFormat {
        try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    }

    private func peak(_ buffer: AVAudioPCMBuffer, at frame: Int, width: Int = 500) throws -> Float {
        let samples = try #require(buffer.floatChannelData?[0])
        let end = min(Int(buffer.frameLength), frame + width)
        return (frame..<end).reduce(Float(0)) { max($0, abs(samples[$1])) }
    }

    @Test func v4ThroughV6MigrationKeepsLegacyRhythmDefaults() throws {
        let original = AppStore.seedSnapshot()
        for version in 4...6 {
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            var songs = try #require(object["songs"] as? [[String: Any]])
            for index in songs.indices {
                if version < 5 { songs[index].removeValue(forKey: "clickAccentPattern") }
                if version < 6 { songs[index].removeValue(forKey: "pulseInterpretation") }
                songs[index].removeValue(forKey: "countoffPolicy")
            }
            object["songs"] = songs
            object["schemaVersion"] = version
            let data = try JSONSerialization.data(withJSONObject: object)
            let migrated = try JSONDecoder().decode(LibrarySnapshot.self, from: data)

            #expect(migrated.schemaVersion == LibrarySnapshot.currentSchemaVersion)
            #expect(migrated.needsMigrationSave)
            #expect(migrated.songs.allSatisfy { song in
                song.clickSubdivision == .beat && song.clickAccentPattern == nil &&
                    song.pulseInterpretation == .legacy && song.countoffPolicy == .liveDefault
            })
        }

        let format = try format()
        let oldSound = try SustainAudioEngine.makeClickBuffer(
            format: format, bpm: 72, timeSignature: .sixEight, subdivision: .beat,
            measures: 1, settings: .default
        )
        let migratedSound = try SustainAudioEngine.makeClickBuffer(
            format: format, bpm: 72, timeSignature: .sixEight, subdivision: .beat,
            measures: 1, settings: .default, pulseInterpretation: .legacy, accentPattern: nil
        )
        #expect(oldSound.frameLength == migratedSound.frameLength)
        let a = try #require(oldSound.floatChannelData?[0])
        let b = try #require(migratedSound.floatChannelData?[0])
        #expect((0..<Int(oldSound.frameLength)).allSatisfy { a[$0] == b[$0] })
    }

    @Test func groupedMetersUsePulseAccentsAndMuteTheirSubdivisions() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            let format = try format(sampleRate)
            for signature in [TimeSignature.sixEight, .nineEight, .twelveEight] {
                let pulses = signature.beatsPerMeasure / 3
                var pattern = Array(repeating: ClickAccentLevel.normal, count: pulses)
                pattern[0] = .strong
                pattern[1] = .mute
                if pulses > 2 { pattern[2] = .soft }
                let grid = ClickPulseGrid(timeSignature: signature, pulseInterpretation: .grouped,
                                          bpm: 72, sampleRate: sampleRate)
                let buffer = try SustainAudioEngine.makeClickBuffer(
                    format: format, bpm: 72, timeSignature: signature, subdivision: .three,
                    measures: 1, settings: .default, pulseInterpretation: .grouped,
                    accentPattern: pattern
                )

                #expect(grid.pulseCount == pulses)
                #expect(Int(buffer.frameLength) == grid.frameCount())
                #expect(try peak(buffer, at: grid.frame(forPulse: 0)) > 0.1)
                #expect(try peak(buffer, at: grid.frame(forPulse: 0, subdivision: 1, subdivisionsPerPulse: 3)) > 0.05)
                for subdivision in 0..<3 {
                    #expect(try peak(buffer, at: grid.frame(forPulse: 1, subdivision: subdivision,
                                                           subdivisionsPerPulse: 3)) == 0)
                }
                if pulses > 2 {
                    #expect(try peak(buffer, at: grid.frame(forPulse: 2)) > 0.05)
                }
            }
        }
    }

    @Test func twoBarCountoffRepeatsGroupedNumbersAndClickPattern() throws {
        let format = try format()
        let voice = NumberRecordingVoice()
        let counted = try SustainAudioEngine.makeCountoffBuffer(
            format: format, voiceRenderer: voice, bpm: 72, timeSignature: .sixEight,
            settings: .default, pulseInterpretation: .grouped, measures: 2
        )
        let grid = ClickPulseGrid(timeSignature: .sixEight, pulseInterpretation: .grouped,
                                  bpm: 72, sampleRate: format.sampleRate)
        #expect(Int(counted.frameLength) == grid.frameCount(measures: 2))
        #expect(voice.numbers == [1, 2, 1, 2])

        let settings = ClickSettings(accentMode: .downbeat, countoffSound: .click)
        let clicks = try SustainAudioEngine.makeCountoffBuffer(
            format: format, voiceRenderer: nil, bpm: 72, timeSignature: .sixEight,
            subdivision: .two, settings: settings, pulseInterpretation: .grouped,
            measures: 2
        )
        let samples = try #require(clicks.floatChannelData?[0])
        let barFrames = grid.frameCount()
        #expect(Int(clicks.frameLength) == barFrames * 2)
        #expect((0..<barFrames).allSatisfy { samples[$0] == samples[$0 + barFrames] })
    }

    @Test func oneAndTwoBarTerminalPoliciesReachAudioOwnedBoundary() throws {
        let format = try format()
        let settings = ClickSettings(accentMode: .downbeat, countoffSound: .click)
        for bars in [1, 2] {
            let policy = CountoffPolicy(bars: bars, after: .countoffOnly)
            #expect(policy.isValid)
            let loop = try SustainAudioEngine.makeClickBuffer(
                format: format, bpm: 120, timeSignature: .fourFour, subdivision: .beat,
                measures: 1, settings: settings
            )
            let countoff = try SustainAudioEngine.makeCountoffBuffer(
                format: format, voiceRenderer: nil, bpm: 120, timeSignature: .fourFour,
                settings: settings, measures: policy.bars
            )
            let prepared = PreparedClick(
                loop: ImmutablePCMBuffer(buffer: loop, byteCount: 0),
                countoff: ImmutablePCMBuffer(buffer: countoff, byteCount: 0),
                stopsAfterCountoff: policy.after == .countoffOnly
            )
            let renderer = ClickLoopRenderer(format: format)
            let generation = try renderer.start(prepared, stopsAfterCountoff: prepared.stopsAfterCountoff)
            let before = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: countoff.frameLength - 1))
            before.frameLength = before.frameCapacity
            #expect(renderer.render(frameCount: before.frameLength, audioBufferList: before.mutableAudioBufferList) == noErr)
            #expect(renderer.lastCompletedCountoffGeneration < generation)

            let boundary = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 101))
            boundary.frameLength = boundary.frameCapacity
            #expect(renderer.render(frameCount: boundary.frameLength, audioBufferList: boundary.mutableAudioBufferList) == noErr)
            #expect(renderer.lastCompletedCountoffGeneration == generation)
            let samples = try #require(boundary.floatChannelData?[0])
            #expect((1..<101).allSatisfy { samples[$0] == 0 })
        }
    }
}
