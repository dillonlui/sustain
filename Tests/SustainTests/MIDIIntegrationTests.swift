import Foundation
import Testing
@testable import Sustain

@Suite("MIDI AppStore integration")
@MainActor
struct MIDIIntegrationTests {
    private let source = MIDIControllerSource(uniqueID: 501, name: "Test Pedal", manufacturer: nil, model: nil)

    private func mapping(_ action: MIDIAction, kind: MIDIMessageKind = .noteOn, channel: UInt8 = 0, number: UInt8) -> MIDIMapping {
        MIDIMapping(
            action: action,
            source: .source(uniqueID: source.uniqueID),
            message: MIDIMessageIdentity(kind: kind, channel: channel, number: number)
        )
    }

    @Test func everyMappedActionDispatchesThroughExistingStoreTransport() throws {
        let midi = RecordingMIDIController(sources: [source])
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio, midiController: midi)
        store.setMIDIEnabled(true)
        store.midiControllerSettings.mappings = [
            mapping(.startTransition, number: 60),
            mapping(.nextCue, number: 61),
            mapping(.previousCue, number: 62),
            mapping(.toggleClick, number: 63),
            mapping(.stopAll, number: 64)
        ]

        let first = try #require(store.runtime.cuedEntryID)
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 61, value: 127))
        #expect(store.runtime.cuedEntryID != first)
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 62, value: 127))
        #expect(store.runtime.cuedEntryID == first)
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 60, value: 127))
        #expect(store.runtime.playingEntryID == first)

        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 63, value: 127))
        #expect(store.runtime.clickState == .off)
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 63, value: 127))
        #expect(store.runtime.clickState != .off)
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 64, value: 127))
        #expect(store.runtime.playingEntryID == nil)
    }

    @Test func togglePadUsesSameIdlePrerollContextAction() {
        let midi = RecordingMIDIController(sources: [source])
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio, midiController: midi)
        store.setMIDIEnabled(true)
        store.midiControllerSettings.mappings = [mapping(.togglePad, number: 70)]

        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 70, value: 127))
        #expect(store.runtime.playingEntryID == nil)
        #expect(store.runtime.audiblePadEntryID == store.runtime.cuedEntryID)
        #expect(audio.padActivateCount == 1)
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 70, value: 127))
        #expect(store.runtime.padState == .fadingOut)
    }

    @Test func disabledSelectedSourceAndChannelGuardsAreNoOps() {
        let midi = RecordingMIDIController(sources: [source])
        let store = AppStore.preview(midiController: midi)
        store.midiControllerSettings.mappings = [mapping(.nextCue, channel: 4, number: 9)]
        let initial = store.runtime.cuedEntryID
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 4, number: 9, value: 127))
        #expect(store.runtime.cuedEntryID == initial)

        store.setMIDIEnabled(true)
        store.setMIDISelectedSource(.source(uniqueID: 999))
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 4, number: 9, value: 127))
        #expect(store.runtime.cuedEntryID == initial)
        store.setMIDISelectedSource(.any)
        midi.send(.init(sourceUniqueID: 501, kind: .noteOn, channel: 3, number: 9, value: 127))
        #expect(store.runtime.cuedEntryID == initial)
    }

    @Test func ccEdgesSuppressRepeatsAndResetOnSourceLifecycle() {
        let midi = RecordingMIDIController(sources: [source])
        let store = AppStore.preview(midiController: midi)
        store.setMIDIEnabled(true)
        store.midiControllerSettings.mappings = [mapping(.nextCue, kind: .controlChange, number: 11)]
        let down = MIDIMessage(sourceUniqueID: 501, kind: .controlChange, channel: 0, number: 11, value: 127)

        midi.send(down)
        let second = store.runtime.cuedEntryID
        midi.send(down)
        #expect(store.runtime.cuedEntryID == second)
        midi.disconnect(501)
        midi.send(down)
        #expect(store.runtime.cuedEntryID != second)
    }

    @Test func relayOverflowStillDispatchesAtMostItsBoundedBatch() {
        let midi = RecordingMIDIController(sources: [source])
        let store = AppStore.preview(midiController: midi)
        store.setMIDIEnabled(true)
        store.midiControllerSettings.mappings = [mapping(.nextCue, number: 1)]
        let relay = BoundedMIDIEventRelay(capacity: 1) { events in
            MainActor.assumeIsolated { events.forEach(midi.send) }
        }
        relay.offer(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 1, value: 127))
        relay.offer(.init(sourceUniqueID: 501, kind: .noteOn, channel: 0, number: 1, value: 127))
        relay.drainNowForTesting()

        #expect(store.runtime.cuedEntryID == store.activeSetlist.entries[1].id)
        #expect(relay.droppedEventCount == 1)
    }
}
