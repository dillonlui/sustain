import AVFoundation
import Dispatch
import Testing
@testable import Sustain

private final class OfflineRenderProbe: @unchecked Sendable {
    let engine = AVAudioEngine()
    let format: AVAudioFormat
    let buffer: AVAudioPCMBuffer
    var status: AVAudioEngineManualRenderingStatus?
    var error: Error?

    init(format: AVAudioFormat) throws {
        self.format = format
        buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        let renderer = ClickLoopRenderer(format: format)
        let source = SustainAudioEngine.makeClickSourceNode(format: format, renderer: renderer)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 128)
    }

    func renderOnBackgroundQueue() {
        do {
            try engine.start()
            status = try engine.renderOffline(128, to: buffer)
            engine.stop()
        } catch {
            self.error = error
        }
    }
}

/// Returns a deterministic voice buffer with a marker after the 45ms click transient. The old
/// voice-or-click implementation is silent near the beat boundary with this renderer; the new
/// click-plus-voice composition has energy in both regions.
private final class MarkerVoiceRenderer: CountoffVoiceRendering {
    func prewarm(numbers: [Int], format: AVAudioFormat) {}

    func renderedWord(for number: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * 0.2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frameCount) {
                channels[channel][frame] = 0
            }
            channels[channel][Int(format.sampleRate * 0.1)] = 0.25
        }
        return buffer
    }
}

@MainActor
struct CountoffAudioTests {
    @Test func clickSourceRenderCallbackDoesNotRequireMainActor() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let probe = try OfflineRenderProbe(format: format)
        let complete = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            probe.renderOnBackgroundQueue()
            complete.signal()
        }
        #expect(complete.wait(timeout: .now() + 5) == .success)
        #expect(probe.error == nil)
        #expect(probe.status == .success)
    }

    @Test func countedCountoffMixesClickAndExistingVoiceOnEveryBeat() throws {
        let bpm = 72
        let signature = TimeSignature.fourFour
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try SustainAudioEngine.makeCountoffBuffer(
            format: format,
            voiceRenderer: MarkerVoiceRenderer(),
            bpm: bpm,
            timeSignature: signature,
            settings: .default
        )
        let samples = try #require(buffer.floatChannelData?[0])
        let sampleRate = buffer.format.sampleRate
        let framesPerBeat = Int((60.0 / Double(bpm)) * sampleRate)

        for beat in 0..<signature.beatsPerMeasure {
            let beatStart = beat * framesPerBeat
            let clickEnd = min(Int(buffer.frameLength), beatStart + Int(sampleRate * 0.045))
            let clickPeak = (beatStart..<clickEnd).reduce(Float(0)) {
                max($0, abs(samples[$1]))
            }
            let voiceMarker = beatStart + Int(sampleRate * 0.1)

            #expect(clickPeak > 0.02)
            #expect(abs(samples[voiceMarker]) > 0.15)
        }

        let expectedFrames = AVAudioFrameCount(
            sampleRate * (60.0 / Double(bpm)) * Double(signature.beatsPerMeasure)
        )
        #expect(buffer.frameLength == expectedFrames)
    }

    @Test func countedCountoffStillFallsBackToOneClickPerBeatWithoutVoice() throws {
        let bpm = 72
        let signature = TimeSignature.sixEight
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try SustainAudioEngine.makeCountoffBuffer(
            format: format,
            voiceRenderer: nil,
            bpm: bpm,
            timeSignature: signature,
            settings: .default
        )
        let samples = try #require(buffer.floatChannelData?[0])
        let sampleRate = buffer.format.sampleRate
        let framesPerBeat = Int((60.0 / Double(bpm)) * sampleRate)

        for beat in 0..<signature.beatsPerMeasure {
            let beatStart = beat * framesPerBeat
            let clickEnd = min(Int(buffer.frameLength), beatStart + Int(sampleRate * 0.045))
            let clickPeak = (beatStart..<clickEnd).reduce(Float(0)) {
                max($0, abs(samples[$1]))
            }
            #expect(clickPeak > 0.02)
        }
    }
}
