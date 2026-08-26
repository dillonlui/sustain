# MIDI Foot Controller Support — PRD

**Status:** Proposed

**Owner:** Codex implementation tasks

**Source of truth for execution:** [`midi-controller/00_EXECUTION_TRACKER.md`](midi-controller/00_EXECUTION_TRACKER.md)

## Summary

Let a worship leader control Sustain's live transport from a standard MIDI foot
controller. A mapped pedal can cue a song, start/transition it, or stop
playback without reaching for the Mac.

Sustain already exposes these actions through its central `AppStore`; MIDI is
an input adapter, not an audio-engine feature. The feature must remain local,
offline, and dependable under device reconnects and rapid pedal presses.

## User problem

During a service, a guitarist or worship leader may need to change pads and
click while playing an instrument. Reaching for the computer is distracting
and sometimes impractical. Ableton-style foot control is familiar to musicians
who use programmable MIDI pedals.

## Goals

- Support USB and Bluetooth MIDI controllers exposed to macOS Core MIDI.
- Let users map MIDI Note On or Control Change messages to live actions.
- Provide a simple Learn workflow; users should not need to know MIDI numbers.
- Keep mappings persistent, source-specific by default, and safe on reconnect.
- Make the current connection/mapping state visible in Settings.
- Preserve existing transport behavior and all playback safety checks.

## Non-goals for v1

- Keyboard/HID-only foot switches (separate follow-up; they do not emit MIDI).
- Sending MIDI, MIDI clock, timecode, SysEx, program changes, or Ableton
  integration.
- Per-song mappings, MIDI-driven BPM/volume, expression pedals, or MIDI 2-only
  capabilities.
- iOS/iPad support.

## Product behavior

### Actions available to map

| Action | Result |
| --- | --- |
| Start / Transition | Calls `startCuedSong()`. Starts the cued song or transitions to it. |
| Next cue | Calls `cueNextSong()`; does not start audio. |
| Previous cue | Calls `cuePreviousSong()`; does not start audio. |
| Stop all | Calls `stop()`. |
| Toggle click | Starts/stops click only when a live song is playing. |
| Toggle pad | Dispatches the same context-aware pad action as Live Service. When a live song exists, it starts/stops only that current song's pad. With no current song it starts a cued pad only from fully idle state, or stops/cancels an existing pre-roll. It never starts NEXT's pad while another song is current. |

All mapped actions use the same `AppStore` methods as buttons and menu
commands, so their existing validation and no-op protections remain
authoritative.

### Setup flow

1. User opens **Settings → MIDI Controller** and enables MIDI control.
2. Sustain lists connected MIDI input sources. A learned mapping is locked to
   the source that produced it by default; the user may explicitly choose **Any
   connected controller** for a mapping if that is desired.
3. For an action the user clicks **Learn**, then presses a pedal.
4. Sustain records the first supported Note On (velocity > 0) or nonzero
   Control Change event, displays a readable summary, validates it, and saves
   it. Learn has an explicit Cancel control and times out safely.
5. The user can test or clear a mapping. A mapping only fires when MIDI control
   is enabled and its source filter matches; choosing Any is an explicit
   opt-in.

### Safety and reliability rules

- MIDI control is off by default; the app never assigns a mapping implicitly.
- A mapping identity is exactly **source selector + message type + MIDI channel
  + note/CC number**. The app rejects duplicates with the same identity.
- A mapping fires only on a Note On with velocity above zero or a Control Change
  whose value crosses from 0 to nonzero. Note Off and repeated nonzero CC
  values are ignored. CC edge state is keyed by source, channel, and controller
  number, and is cleared when its source disconnects or reconnects.
- One incoming event invokes at most one action. Duplicate mappings are
  rejected in the UI.
- The Core MIDI callback only parses and forwards an immutable event; it must
  not access `AppStore`, audio state, or persistence directly. Action dispatch
  occurs on `MainActor`.
- Source add/remove events refresh the UI. Existing mappings are retained when
  a device is disconnected and activate when its stable identity returns. A
  changed or unavailable identity is shown as unavailable; it is never silently
  matched by a similar device name.
- `Stop all` remains a single immediate press in v1, but must be clearly named
  and shown as a destructive action. Do not add a confirmation dialog during a
  live performance.

## Technical approach

- Add `Sources/Sustain/MIDI/` using Apple's built-in `CoreMIDI` framework;
  introduce no package dependency. Before finalizing entitlements, read the
  custom-pad signed-capability spike and verify USB/Bluetooth Core MIDI in the
  exact chosen sandbox/signing configuration; add no broad or temporary
  exception merely by assumption.
- Define an event and service boundary that is injectable into `AppStore`:
  `MIDIControlling` (start, stop, available sources, and event handler) and a
  test fake.
- Use a Core MIDI client and `MIDIInputPortCreateWithProtocol` with
  `kMIDIProtocol_1_0`, then connect the port to system MIDI sources and react to
  client notifications. Core MIDI converts common MIDI 1 controller messages
  to the requested protocol; do not use deprecated packet-list input APIs.
- Persist a source's Core MIDI `kMIDIPropertyUniqueID` as its primary identity.
  Retain name, manufacturer, and model only as display metadata. If an endpoint
  has no usable unique ID or it changes, require the user to select it again.
- Marshal inbound events through a thread-safe, bounded relay to `@MainActor`,
  following the existing hardware-monitor pattern. The relay copies scalar data
  inside the callback, has an explicit overflow/coalescing policy, and never
  creates unbounded main-actor work.
- Treat client/port creation, source connection, MIDI-server I/O, setup-change,
  and app wake events as recoverable states. Reconnect idempotently and surface
  the error/state in Settings; do not fail silently.
- Add Codable models for controller selection, messages, mappings, and enabled
  state. Store them in `LibrarySnapshot`. At implementation start, inspect the
  current schema and the custom-pad tracker: claim the next unused version (do
  not assume v3 is still available) and preserve/default fields from either
  feature landing order so existing libraries continue to load.
- Add the Settings tab in `SustainApp.swift`. Keep performance screens unchanged
  for the initial release.
- The Settings UI must work with VoiceOver and keyboard alone: labeled controls,
  mapping summaries, clear listening/cancel/timeout states, and visible selected
  device disconnect errors.
- Own one Core MIDI service for the application lifetime, stop/dispose ports
  deterministically, and register handlers weakly so no retain cycle can keep a
  service or store alive.

## Acceptance criteria

- On macOS 14+, a connected common MIDI pedal appears as a selectable source.
- A learned Note On or CC pedal triggers exactly its mapped action once.
- Mappings distinguish channel and device identity; a matching event from a
  different source or channel cannot fire an action.
- Next/previous only changes the cue; Start/Transition and Stop retain current
  runtime behavior.
- Disabling MIDI makes all incoming events harmless.
- Mappings persist after relaunch and survive a temporary device disconnect.
- Existing supported library files load with MIDI defaults and save to the next
  coordinated schema without data loss.
- Unit tests cover parsing/normalization, routing, duplicate suppression,
  mapping dispatch, persistence migration, disabled/device-filter cases, CC
  reset/debounce behavior, and bounded relay behavior.
- An automated virtual-source or protocol-adapter integration test covers
  multi-message input and lifecycle/reconnect paths without physical hardware.
- Manual QA covers at least one physical MIDI foot controller and an unplug /
  replug cycle while audio is playing, plus sleep/wake and the signed/notarized
  release build.

## Release and support notes

Document that users need a MIDI-capable pedal and, if it is not visible, should
check macOS **Audio MIDI Setup**. List tested controller models only after they
are physically verified. Keyboard-emulating pedals are explicitly unsupported
in this release.

## Open decisions (resolve before Slice 3)

1. Is a single-press Stop acceptable for the intended team? Recommendation: yes
   for parity with the existing keyboard shortcut, with clear mapping labels.
2. Which physical pedal(s) are available for final QA? This blocks release
   verification, not the implementation slices.
