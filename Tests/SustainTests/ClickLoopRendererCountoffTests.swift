import AVFoundation
import Testing
@testable import Sustain

@MainActor
struct ClickLoopRendererCountoffTests {
    private func format() throws -> AVAudioFormat {
        try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    }

    private func buffer(_ values: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)))
        buffer.frameLength = buffer.frameCapacity
        let samples = try #require(buffer.floatChannelData?[0])
        for (index, value) in values.enumerated() { samples[index] = value }
        return buffer
    }

    private func prepared(format: AVAudioFormat) throws -> PreparedClick {
        let loop = try buffer([0.5, 0.5], format: format)
        let countoff = try buffer([1, 1, 1, 1], format: format)
        return PreparedClick(
            loop: ImmutablePCMBuffer(buffer: loop, byteCount: 0),
            countoff: ImmutablePCMBuffer(buffer: countoff, byteCount: 0)
        )
    }

    @Test func terminalCountoffEndsAtExactFrameAndReportsGeneration() throws {
        let format = try format()
        let renderer = ClickLoopRenderer(format: format)
        let generation = try renderer.start(prepared(format: format), stopsAfterCountoff: true)
        let output = try buffer(Array(repeating: -1, count: 9), format: format)

        #expect(renderer.lastCompletedCountoffGeneration < generation)
        #expect(renderer.render(frameCount: output.frameLength, audioBufferList: output.mutableAudioBufferList) == noErr)
        let samples = try #require(output.floatChannelData?[0])
        #expect((0..<9).map { samples[$0] } == [1, 1, 1, 1, 0, 0, 0, 0, 0])
        #expect(renderer.lastCompletedCountoffGeneration == generation)

        let later = try buffer(Array(repeating: -1, count: 3), format: format)
        #expect(renderer.render(frameCount: later.frameLength, audioBufferList: later.mutableAudioBufferList) == noErr)
        let laterSamples = try #require(later.floatChannelData?[0])
        #expect((0..<3).allSatisfy { laterSamples[$0] == 0 })
    }

    @Test func normalCountoffContinuesLoopAndRestartClearsTerminalSilence() throws {
        let format = try format()
        let renderer = ClickLoopRenderer(format: format)
        let prepared = try prepared(format: format)
        let first = try renderer.start(prepared, stopsAfterCountoff: true)
        let firstOutput = try buffer(Array(repeating: -1, count: 6), format: format)
        #expect(renderer.render(frameCount: firstOutput.frameLength, audioBufferList: firstOutput.mutableAudioBufferList) == noErr)
        #expect(renderer.lastCompletedCountoffGeneration == first)

        renderer.stop()
        let second = try renderer.start(prepared)
        let secondOutput = try buffer(Array(repeating: -1, count: 8), format: format)
        #expect(renderer.render(frameCount: secondOutput.frameLength, audioBufferList: secondOutput.mutableAudioBufferList) == noErr)
        let samples = try #require(secondOutput.floatChannelData?[0])
        #expect((0..<8).map { samples[$0] } == [1, 1, 1, 1, 0.5, 0.5, 0.5, 0.5])
        #expect(renderer.lastCompletedCountoffGeneration == second)
        #expect(second > first)
    }

    @Test func stoppingDuringCountoffDoesNotReportCompletion() throws {
        let format = try format()
        let renderer = ClickLoopRenderer(format: format)
        let generation = try renderer.start(prepared(format: format), stopsAfterCountoff: true)
        let first = try buffer(Array(repeating: -1, count: 3), format: format)
        #expect(renderer.render(frameCount: first.frameLength, audioBufferList: first.mutableAudioBufferList) == noErr)
        #expect(renderer.lastCompletedCountoffGeneration < generation)

        renderer.stop()
        let stopped = try buffer(Array(repeating: -1, count: 3), format: format)
        #expect(renderer.render(frameCount: stopped.frameLength, audioBufferList: stopped.mutableAudioBufferList) == noErr)
        let samples = try #require(stopped.floatChannelData?[0])
        #expect((0..<3).allSatisfy { samples[$0] == 0 })
        #expect(renderer.lastCompletedCountoffGeneration < generation)
    }

    @Test func terminalModeRequiresCountoffAndCannotQueueLoopChange() throws {
        let format = try format()
        let renderer = ClickLoopRenderer(format: format)
        let loop = try buffer([0.5], format: format)
        let noCountoff = PreparedClick(loop: ImmutablePCMBuffer(buffer: loop, byteCount: 0), countoff: nil)
        #expect(throws: AudioEngineError.self) {
            _ = try renderer.start(noCountoff, stopsAfterCountoff: true)
        }
        _ = try renderer.start(prepared(format: format), stopsAfterCountoff: true)
        #expect(throws: AudioEngineError.self) {
            try renderer.queue(noCountoff, serial: 1)
        }
    }

    @Test func acceptsMaximumTwoBarLegacyCountoff() throws {
        let format = try format()
        let renderer = ClickLoopRenderer(format: format)
        let frames = Int(format.sampleRate * 36)
        let countoff = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        countoff.frameLength = countoff.frameCapacity
        let loop = try buffer([0.5], format: format)
        let prepared = PreparedClick(
            loop: ImmutablePCMBuffer(buffer: loop, byteCount: 0),
            countoff: ImmutablePCMBuffer(buffer: countoff, byteCount: 0)
        )
        _ = try renderer.start(prepared, stopsAfterCountoff: true)
    }
}
