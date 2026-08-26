# Slice 05 — App integration, hardening, and release QA

**Status:** Not started

**Depends on:** Slices 02, 03, and 04 complete

**Goal:** Connect persisted MIDI events to `AppStore` transport actions, prove
safety, and prepare the feature for release.

## Work

- Create and start the live `CoreMIDIController` from app composition; inject it
  into `AppStore` without creating retain cycles.
- Route events through the mapping resolver and invoke only the corresponding
  existing `AppStore` methods. Do not duplicate transport logic.
- Enforce the PRD safety rules in the integration layer: disabled guard,
  selected-source/channel filtering, one-action dispatch, CC duplicate
  suppression, and source-state reset on disconnect/reconnect.
- Add `AppStore` tests for each action and no-op states, including disabled,
  mismatched-device/channel, repeated-event, relay-overflow, and reconnection
  cases. Exercise the full dispatch path with a virtual source or protocol
  adapter, not only unit-level parser fakes.
- Perform manual QA with at least one physical MIDI foot controller: discovery,
  learn, every mapped action, restart persistence, disconnect/reconnect, and a
  live audio transition. Also test sleep/wake and the signed/notarized release
  build. Record model, macOS version, build type, and results in the tracker
  completion log.
- Update README/release notes with supported scope and Audio MIDI Setup
  troubleshooting. Do not list a device as supported without completed QA.

## Release gate

All automated tests pass and the tracker contains a physical-controller QA
entry. If hardware is unavailable, implementation can be complete but release
sign-off stays blocked.

## Kickoff prompt

```text
Implement Slice 05, MIDI integration, hardening, and release QA, in docs/midi-controller/05_integration_release_qa.md. Read the PRD, tracker, and all completed dependency slices first. Update the tracker throughout. Use only existing AppStore transport methods, enforce the documented safety rules, and run the full suite. Complete and record physical pedal QA if hardware is available; otherwise explicitly leave the release gate blocked rather than claiming support.
```
