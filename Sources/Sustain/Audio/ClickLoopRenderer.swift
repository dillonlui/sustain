import AVFoundation
import Foundation

/// Owns two preallocated PCM slots. The render callback only copies samples and atomically
/// changes slots at a loop boundary; generation and buffer preparation stay off the audio thread.
final class ClickLoopRenderer: @unchecked Sendable {
    private final class Slot {
        let loop: [UnsafeMutablePointer<Float>]
        let countoff: [UnsafeMutablePointer<Float>]
        var loopFrames = 0
        var countoffFrames = 0

        init(channels: Int, maxFrames: Int) {
            loop = (0..<channels).map { _ in .allocate(capacity: maxFrames) }
            countoff = (0..<channels).map { _ in .allocate(capacity: maxFrames) }
        }

        deinit {
            for pointer in loop { pointer.deallocate() }
            for pointer in countoff { pointer.deallocate() }
        }
    }

    private let slots: [Slot]
    private let maxFrames: Int
    private let channels: Int
    private let activeState = ClickAtomicInt(-1)
    private let pending = ClickAtomicInt(-1)
    private let requestedSerial = ClickAtomicInt(0)
    private let appliedSerial = ClickAtomicInt(0)
    private var startGeneration = 0 // control thread only

    // The following fields are accessed only by the single AVAudioSourceNode render thread.
    private var renderSlot = -1
    private var renderState = -1
    private var cursor = 0
    private var inCountoff = false

    init(format: AVAudioFormat) {
        let channelCount = Int(format.channelCount)
        let capacity = Int(ceil(format.sampleRate * 18.0)) + 1 // 12 beats at 40 BPM
        channels = channelCount
        maxFrames = capacity
        slots = (0..<2).map { _ in Slot(channels: channelCount, maxFrames: capacity) }
    }

    var lastAppliedSerial: Int { appliedSerial.load() }

    func cancelPending() {
        pending.store(-1)
    }

    func stop() {
        pending.store(-1)
        activeState.store(-1)
    }

    func start(_ prepared: PreparedClick) throws {
        let current = activeState.load()
        let slot = current >= 0 && current % 2 == 0 ? 1 : 0
        try upload(prepared, to: slot)
        pending.store(-1)
        startGeneration &+= 1
        activeState.store(startGeneration * 2 + slot)
    }

    /// One pending buffer at a time. A later request is held by the store until this boundary.
    func queue(_ prepared: PreparedClick, serial: Int) throws {
        guard pending.load() == -1 else {
            throw AudioEngineError.invalidOutputFormat
        }
        let currentState = activeState.load()
        let current = currentState < 0 ? -1 : currentState % 2
        guard current >= 0 else {
            try start(prepared)
            appliedSerial.store(serial)
            return
        }
        let slot = current == 0 ? 1 : 0
        try upload(prepared, to: slot)
        requestedSerial.store(serial)
        pending.store(slot)
    }

    private func upload(_ prepared: PreparedClick, to index: Int) throws {
        let loop = prepared.loop.buffer
        let countoff = prepared.countoff?.buffer
        guard loop.format.channelCount == channels,
              Int(loop.frameLength) <= maxFrames,
              let loopChannels = loop.floatChannelData,
              countoff == nil || (countoff!.format.channelCount == channels && Int(countoff!.frameLength) <= maxFrames && countoff!.floatChannelData != nil) else {
            throw AudioEngineError.invalidOutputFormat
        }
        let slot = slots[index]
        for channel in 0..<channels {
            slot.loop[channel].update(from: loopChannels[channel], count: Int(loop.frameLength))
            if let countoff, let data = countoff.floatChannelData {
                slot.countoff[channel].update(from: data[channel], count: Int(countoff.frameLength))
            }
        }
        slot.loopFrames = Int(loop.frameLength)
        slot.countoffFrames = Int(countoff?.frameLength ?? 0)
    }

    func render(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let count = Int(frameCount)
        var outputOffset = 0
        while outputOffset < count {
            let selectedState = activeState.load()
            if selectedState < 0 {
                for channel in 0..<min(channels, buffers.count) {
                    if let data = buffers[channel].mData {
                        memset(data.advanced(by: outputOffset * MemoryLayout<Float>.size), 0,
                               (count - outputOffset) * MemoryLayout<Float>.size)
                    }
                }
                return noErr
            }
            if selectedState != renderState {
                renderState = selectedState
                renderSlot = selectedState % 2
                cursor = 0
                inCountoff = slots[renderSlot].countoffFrames > 0
            }

            let slot = slots[renderSlot]
            let length = inCountoff ? slot.countoffFrames : slot.loopFrames
            guard length > 0 else { return kAudio_ParamError }
            let copied = min(count - outputOffset, length - cursor)
            for channel in 0..<min(channels, buffers.count) {
                guard let data = buffers[channel].mData else { continue }
                let destination = data.assumingMemoryBound(to: Float.self).advanced(by: outputOffset)
                let source = (inCountoff ? slot.countoff[channel] : slot.loop[channel]).advanced(by: cursor)
                destination.update(from: source, count: copied)
            }
            outputOffset += copied
            cursor += copied
            if cursor == length {
                cursor = 0
                if inCountoff {
                    inCountoff = false
                } else {
                    let next = pending.exchange(-1)
                    if next >= 0 {
                        renderSlot = next
                        renderState = (selectedState & ~1) | next
                        activeState.store(renderState)
                        appliedSerial.store(requestedSerial.load())
                    }
                }
            }
        }
        return noErr
    }
}
