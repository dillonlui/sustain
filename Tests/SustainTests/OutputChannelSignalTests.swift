import AudioToolbox
import AVFoundation
import Testing
@testable import Sustain

/// Render real PCM through Apple's converter using the same channel-map code as
/// the hardware output. This measures samples, independently of property readback.
struct OutputChannelSignalTests {
    @Test func selectedOutputContainsSignalAndEveryOtherOutputIsSilent() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            for outputs in [2, 4] {
                for selection in [AudioOutputChannelSelection.output2, .output1, .stereo, .output2] {
                    try renderAndCheck(selection: selection, sampleRate: sampleRate, outputs: outputs)
                }
            }
        }
    }

    private func renderAndCheck(selection: AudioOutputChannelSelection,
                                sampleRate: Double, outputs: Int) throws {
        var description = AudioComponentDescription(componentType: kAudioUnitType_FormatConverter,
            componentSubType: kAudioUnitSubType_AUConverter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        let component = try #require(AudioComponentFindNext(nil, &description))
        var instance: AudioUnit?
        #expect(AudioComponentInstanceNew(component, &instance) == noErr)
        let unit = try #require(instance)
        defer { AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                              channels: selection.isExclusiveMono ? 1 : 2))
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(outputs)))
        let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   interleaved: false, channelLayout: layout)
        var inputFormat = input.streamDescription.pointee
        var outputFormat = output.streamDescription.pointee
        #expect(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                    0, &inputFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr)
        #expect(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
                                    0, &outputFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr)
        var callback = AURenderCallbackStruct(inputProc: { _, _, _, _, frames, data in
            guard let data else { return kAudio_ParamError }
            for (channel, buffer) in UnsafeMutableAudioBufferListPointer(data).enumerated() {
                guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    return kAudio_ParamError
                }
                samples.update(repeating: channel == 0 ? 0.25 : 0.75, count: Int(frames))
            }
            return noErr
        }, inputProcRefCon: nil)
        #expect(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
                                    0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr)
        #expect(AudioUnitInitialize(unit) == noErr)
        // Exercise repeated route changes and converter resets on the same instance.
        for cycle in 0..<3 {
            let route: AudioOutputChannelSelection = selection.isExclusiveMono && cycle == 1
                ? (selection == .output1 ? .output2 : .output1) : selection
            let map = try #require(route.channelMap(outputChannelCount: outputs))
            try OutputChannelMap.apply(map, to: unit)
            #expect(AudioUnitReset(unit, kAudioUnitScope_Global, 0) == noErr)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 128))
            buffer.frameLength = 128
            var flags: AudioUnitRenderActionFlags = []
            var timestamp = AudioTimeStamp()
            timestamp.mFlags = .sampleTimeValid
            #expect(AudioUnitRender(unit, &flags, &timestamp, 0, 128, buffer.mutableAudioBufferList) == noErr)
            let samples = try #require(buffer.floatChannelData)
            for channel in 0..<outputs {
                let expected: Float = map[channel] < 0 ? 0 : (map[channel] == 0 ? 0.25 : 0.75)
                for frame in 0..<128 {
                    #expect(abs(samples[channel][frame] - expected) < 0.00001)
                }
            }
        }
    }
}
