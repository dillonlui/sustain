# Slice 03 — Settings and Learn UX

**Status:** Not started

**Depends on:** Slices 01 and 02 complete

**Goal:** Give users a clear, accessible way to enable MIDI, select a source,
and create/remove mappings.

## Work

- Add a **MIDI Controller** Settings tab alongside General and Audio.
- Show enabled state, connection/source state, source selection, recoverable
  service errors, and a concise unsupported-device troubleshooting hint.
- Build a Learn interaction: selecting Learn for an action waits for the next
  supported event from the service, ignores CC value zero, previews its readable
  name/source/channel, validates it, then commits the mapping locked to its
  source. Include explicit Cancel and timeout states; Any controller is a
  deliberate post-learn choice.
- Show every action and its current mapping; provide Clear per action.
- Reject/communicate duplicates. Clearly label Stop all as a destructive action.
- Follow existing native SwiftUI form, accessibility, and design-system
  conventions. Every Learn/Cancel/Clear control must be keyboard-operable and
  have VoiceOver labels/value summaries; status changes must be perceivable.
  Do not put controller configuration on the Live screen.
- Add UI-independent tests for learn-session transitions and mapping validation;
  manually inspect the Settings layout at its normal and narrow dimensions.

## Done when

- A user can enable MIDI, learn a mapping, see it, and clear it.
- Settings remain usable when no controller is connected.
- Learn can be cancelled or time out without changing a mapping, and a selected
  controller's disconnect is visibly explained.
- Existing tests remain green.

## Kickoff prompt

```text
Implement Slice 03, MIDI Settings and Learn UX, in docs/midi-controller/03_settings_learn_ux.md. Read the PRD, execution tracker, and Slice 01/02 outputs first. Update the tracker as you work. Keep the UX native and compact; do not add live-screen controls or expand into HID keyboard-pedal support. Run tests, visually inspect the settings view, and record completion evidence.
```
