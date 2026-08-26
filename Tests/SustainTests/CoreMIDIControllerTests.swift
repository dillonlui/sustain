import Foundation
import Testing
@testable import Sustain

private final class LockedMIDIEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MIDIMessage] = []
    func append(_ values: [MIDIMessage]) { lock.withLock { storage.append(contentsOf: values) } }
    var values: [MIDIMessage] { lock.withLock { storage } }
}

@Suite("Core MIDI input boundary")
struct CoreMIDIControllerTests {
    @Test func protocolParserCopiesOnlySupportedMIDI10ChannelVoiceEvents() {
        let words: [UInt32] = [
            0x20903C7F, // Note On, channel 1, note 60, velocity 127
            0x20B20A40, // CC, channel 3, controller 10, value 64
            0x20803C00, // Note Off
            0x20903D00, // zero-velocity Note On
            0x30F00000, // two-word SysEx UMP
            0x20903E7F, // SysEx data that resembles Note On and must be skipped
            0x20F80000  // clock
        ]

        let messages = MIDIProtocolEventParser.messages(words: words, sourceUniqueID: 42)

        #expect(messages == [
            MIDIMessage(sourceUniqueID: 42, kind: .noteOn, channel: 0, number: 60, value: 127),
            MIDIMessage(sourceUniqueID: 42, kind: .controlChange, channel: 2, number: 10, value: 64)
        ])
    }

    @Test func boundedRelayCoalescesCCStateAndDropsOverflowWithoutUnboundedQueue() {
        let received = LockedMIDIEvents()
        let relay = BoundedMIDIEventRelay(capacity: 2, delivery: received.append)
        relay.offer(MIDIMessage(sourceUniqueID: 1, kind: .controlChange, channel: 0, number: 7, value: 1))
        relay.offer(MIDIMessage(sourceUniqueID: 1, kind: .controlChange, channel: 0, number: 7, value: 99))
        relay.offer(MIDIMessage(sourceUniqueID: 1, kind: .noteOn, channel: 0, number: 60, value: 127))
        relay.offer(MIDIMessage(sourceUniqueID: 1, kind: .noteOn, channel: 0, number: 61, value: 127))

        #expect(relay.queuedCount == 2)
        #expect(relay.droppedEventCount == 1)
        relay.drainNowForTesting()
        #expect(received.values.count == 2)
        #expect(received.values.first?.value == 99)
        #expect(received.values.last?.identity.number == 60)
    }

    @Test func topologyDeltaReconnectsByUniqueIDNotDisplayMetadata() {
        let delta = MIDISourceTopologyDelta.compare(
            connected: [10, 20],
            available: [20, 30]
        )
        #expect(delta.removed == [10])
        #expect(delta.added == [30])

        // A display-name change has no topology effect because only persisted unique IDs
        // participate in connection identity.
        #expect(MIDISourceTopologyDelta.compare(connected: [20], available: [20]) == .init(removed: [], added: []))
    }

    @Test @MainActor func serviceStartStopIsIdempotent() {
        let controller = CoreMIDIController()
        controller.start()
        controller.start()
        #expect(controller.state == .running || {
            if case .failed = controller.state { return true }
            return false
        }())
        controller.stop()
        controller.stop()
        #expect(controller.state == .stopped)
        #expect(controller.availableSources.isEmpty)
    }
}
