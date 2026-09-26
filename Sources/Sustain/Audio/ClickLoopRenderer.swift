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
        var stopsAfterCountoff = false

        init(channels: Int, maxLoopFrames: Int, maxCountoffFrames: Int) {
            loop = (0..<channels).map { _ in .allocate(capacity: maxLoopFrames) }
            countoff = (0..<channels).map { _ in .allocate(capacity: maxCountoffFrames) }
        }

        deinit {
            for pointer in loop { pointer.deallocate() }
            for pointer in countoff { pointer.deallocate() }
        }
    }

    private let slots: [Slot]
    private let maxLoopFrames: Int
    private let maxCountoffFrames: Int
    private let channels: Int
    private let activeState = ClickAtomicInt(-1)
    private let pending = ClickAtomicInt(-1)
    private let requestedSerial = ClickAtomicInt(0)
    private let appliedSerial = ClickAtomicInt(0)
    private let completedCountoffGeneration = ClickAtomicInt(0)
    private var startGeneration = 0 // control thread only

    // The following fields are accessed only by the single AVAudioSourceNode render thread.
    private var renderSlot = -1
    private var renderState = -1
    private var cursor = 0
    private var inCountoff = false
    private var finishedCountoffOnly = false

    init(format: AVAudioFormat) {
        let channelCount = Int(format.channelCount)
        let loopCapacity = Int(ceil(format.sampleRate * 18.0)) + 1 // 12 pulses at 40 BPM
        let countoffCapacity = Int(ceil(format.sampleRate * 36.0)) + 1 // two legacy 12/8 bars at 40 BPM
        channels = channelCount
        maxLoopFrames = loopCapacity
        maxCountoffFrames = countoffCapacity
        slots = (0..<2).map {
            _ in Slot(channels: channelCount, maxLoopFrames: loopCapacity, maxCountoffFrames: countoffCapacity)
        }
    }

    var lastAppliedSerial: Int { appliedSerial.load() }
    /// The generation whose count-off reached its final frame on the audio render thread.
    var lastCompletedCountoffGeneration: Int { completedCountoffGeneration.load() }

    func cancelPending() {
        pending.store(-1)
    }

    func stop() {
        pending.store(-1)
        activeState.store(-1)
    }

    /// Returns a generation that can be compared with `lastCompletedCountoffGeneration`.
    @discardableResult
    func start(_ prepared: PreparedClick, stopsAfterCountoff: Bool = false) throws -> Int {
        let current = activeState.load()
        let slot = current >= 0 && current % 2 == 0 ? 1 : 0
        guard !stopsAfterCountoff || (prepared.countoff?.buffer.frameLength ?? 0) > 0 else {
            throw AudioEngineError.invalidOutputFormat
        }
        try upload(prepared, to: slot, stopsAfterCountoff: stopsAfterCountoff)
        pending.store(-1)
        startGeneration &+= 1
        activeState.store(startGeneration * 2 + slot)
        return startGeneration
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
        guard !slots[current].stopsAfterCountoff else {
            throw AudioEngineError.invalidOutputFormat
        }
        let slot = current == 0 ? 1 : 0
        try upload(prepared, to: slot, stopsAfterCountoff: false)
        requestedSerial.store(serial)
        pending.store(slot)
    }

    private func upload(_ prepared: PreparedClick, to index: Int, stopsAfterCountoff: Bool) throws {
        let loop = prepared.loop.buffer
        let countoff = prepared.countoff?.buffer
        guard loop.format.channelCount == channels,
              Int(loop.frameLength) <= maxLoopFrames,
              let loopChannels = loop.floatChannelData,
              countoff == nil || (countoff!.format.channelCount == channels && Int(countoff!.frameLength) <= maxCountoffFrames && countoff!.floatChannelData != nil) else {
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
        slot.stopsAfterCountoff = stopsAfterCountoff
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
                finishedCountoffOnly = false
            }
            if finishedCountoffOnly {
                for channel in 0..<min(channels, buffers.count) {
                    if let data = buffers[channel].mData {
                        memset(data.advanced(by: outputOffset * MemoryLayout<Float>.size), 0,
                               (count - outputOffset) * MemoryLayout<Float>.size)
                    }
                }
                return noErr
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
                    completedCountoffGeneration.store(selectedState / 2)
                    if slot.stopsAfterCountoff {
                        finishedCountoffOnly = true
                    }
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
