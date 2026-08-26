# Slice 02 — Core MIDI input service

**Status:** Not started

**Depends on:** Slice 01 complete

**Goal:** Receive common MIDI pedal events safely and expose source state through
the `MIDIControlling` boundary.

## Work

- Implement `CoreMIDIController` using `CoreMIDI` in `Sources/Sustain/MIDI/`.
  Use `MIDIInputPortCreateWithProtocol` and `kMIDIProtocol_1_0`; do not use
  deprecated packet-list input APIs.
- Enumerate MIDI sources and connect an input port to each usable source.
- Convert only Note On (velocity > 0) and Control Change messages into the
  Slice 01 event model. Ignore Note Off, zero-velocity Note On, SysEx, clock,
  and unsupported status bytes.
- Use a bounded lock/queue relay to hand copied scalar events to `@MainActor`.
  Specify and test its overflow behavior (coalesce repeated controller state;
  never queue unbounded work). The Core MIDI callback must do bounded parsing
  and no UI/store/persistence work.
- Refresh source availability on Core MIDI topology/setup notifications and
  reconnect sources idempotently. Surface client/port/connect/I-O errors through
  service state; preserve mappings outside this service.
- Identify sources with `kMIDIPropertyUniqueID`; retain name/manufacturer/model
  for display only. Do not resolve a missing ID by matching a display name.
- Avoid packet-pointer lifetime bugs: copy only the parsed scalar data before
  leaving the callback.
- Add parser and relay tests with a fake/injectable protocol-event adapter,
  including multi-message input, source connect/disconnect, error state, and
  bounded-queue behavior. Provide a virtual-source test path where practical;
  physical hardware I/O remains manual QA.

## Done when

- The service starts/stops cleanly and reports sources.
- One supported received event reaches the main-actor handler exactly once.
- Unsupported / release events do not reach it.
- Setup changes and a source reconnect do not produce duplicate connections or
  duplicate delivery.
- Failure state is observable to the Settings layer.
- Existing tests remain green.

## Kickoff prompt

```text
Implement Slice 02, Core MIDI input service, in docs/midi-controller/02_core_midi_input.md. Read the PRD, execution tracker, and completed Slice 01 first. Update the tracker status before and after work. Keep Core MIDI callbacks real-time safe and do not implement Settings UI, app-store action dispatch, or persistence migration beyond what is strictly required by the Slice 01 interface. Test thoroughly and record evidence.
```
