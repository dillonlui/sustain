# Slice 01 — MIDI domain foundations

**Status:** Complete

**Depends on:** none

**Goal:** Establish the testable, persistence-ready domain boundary without
opening a real MIDI connection or changing UI.

## Work

- Create MIDI domain models in `Sources/Sustain/MIDI/`:
  - `MIDIMessage` (supported Note On / Control Change identity, including MIDI
    channel and note/CC number).
  - `MIDIControllerSource` (Core MIDI unique ID plus display metadata; a name is
    not an identifier).
  - `MIDIControllerSelection` (`any` or one stable source identifier).
  - `MIDIAction` for the six PRD actions.
  - `MIDIMapping` and `MIDIControllerSettings` (disabled by default).
- Make models Codable, Equatable, and stable for persistence. Avoid storing
  transient Core MIDI object references.
- Add a pure mapping resolver that performs source/channel filtering and
  duplicate prevention. It must define CC edge-state behavior keyed by source,
  channel, and CC number, including a reset API for source lifecycle changes.
  Define the public API so Slice 02 can feed it events and Slice 03 can use it
  for Learn validation.
- Add `MIDIControlling` and a no-op implementation suitable for `AppStore`
  injection. Do not yet add Core MIDI framework code.
- Add focused Swift Testing coverage for defaults, Codable round trips,
  filtering, source identity, channel-sensitive duplicates, CC edge/reset
  behavior, and duplicate handling.

## Done when

- New models compile and have tests.
- No real MIDI input is created.
- Existing tests remain green.

## Kickoff prompt

```text
Implement Slice 01, MIDI domain foundations, in docs/midi-controller/01_foundations.md. Read docs/16_MIDI_Controller_PRD.md and docs/midi-controller/00_EXECUTION_TRACKER.md first. Follow the tracker protocol: mark the slice in progress, keep scope to this slice, run tests, then update the tracker and slice with completion evidence. Do not implement real Core MIDI input, UI, or persistence migration yet.
```
