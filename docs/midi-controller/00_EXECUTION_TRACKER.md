# MIDI Controller Execution Tracker

This file is the durable handoff and progress record for the MIDI Controller
feature. Every Codex task must read this file and the linked slice before
editing. Update this file in the same change set as implementation work so it
remains correct after context is cleared.

PRD: [`../16_MIDI_Controller_PRD.md`](../16_MIDI_Controller_PRD.md)

## Operating protocol for autonomous tasks

1. Confirm the current branch/worktree and preserve unrelated changes.
2. Read the PRD, this tracker, and the assigned slice in full.
3. Mark only your slice **In progress** before implementation. Do not start a
   slice whose dependencies are not complete.
4. Keep work within the assigned slice. If a blocking decision is required,
   document it below and stop rather than broadening scope.
5. Run the slice's required tests plus the relevant full suite.
6. On completion, update the slice status, add the commit/test evidence below,
   and record any manual QA still needed. Then mark it **Complete**.

## Current status

| Slice | Status | Dependency | Completion evidence |
| --- | --- | --- | --- |
| [01 — Foundations](01_foundations.md) | Complete | — | Stable Codable domain, source-specific mapping resolver, channel-sensitive duplicate checks, CC edge/reset behavior, and injectable no-op service; full suite passes. |
| [02 — Core MIDI input](02_core_midi_input.md) | Complete (physical/virtual-source manual QA pending) | 01 | Current MIDI 1.0 protocol port; UMP parsing; bounded CC-coalescing relay; unique-ID topology reconciliation; idempotent lifecycle; source metadata and failures surfaced. |
| [03 — Settings and Learn UX](03_settings_learn_ux.md) | Complete (manual settings accessibility/layout QA pending) | 01, 02 | Native Settings tab with enable/source/status/error/disconnect state, all actions, learn preview, source lock/Any opt-in, duplicate rejection, cancel/timeout, clear, announcements, and troubleshooting. |
| [04 — Persistence and migration](04_persistence_migration.md) | Complete | 01 | Coordinated schema v3 landed with custom pads: prior schemas default MIDI disabled; live/preview/save paths preserve mappings and all pad/song/routing/audio fields; round trips tested. |
| [05 — Integration hardening and release QA](05_integration_release_qa.md) | Complete (physical/signed hardware QA pending) | 02, 03, 04 | Live composition routes every resolved action exclusively through existing AppStore transport methods, including context-aware Toggle Pad; source/channel/disable filters, CC edge and reconnect resets, bounded relay delivery, and wake refresh are covered. |

## Decisions and blockers

| Date | Item | Owner | Resolution / next action |
| --- | --- | --- | --- |
| 2026-08-17 | Device source default | Product | Learn locks mappings to their source; Any controller is an explicit opt-in. |
| 2026-08-17 | Stop behavior | Product | Single press; named clearly and mapped explicitly. |
| 2026-08-17 | Physical pedal for QA | Product | Pending: identify a pedal before Slice 05 release sign-off. |
| 2026-08-25 | Final roadmap reconciliation | Engineering | Schema v3, AppStore action routing, wake/source resets, capability model, and updater/live-audio integration are reconciled. Final full suite passes 135 tests. Physical USB/Bluetooth delivery in the Developer-ID/notarized app remains an external release gate. |

## Completion log

Add an entry only when a slice is complete.

| Date | Slice | Commit(s) | Tests / QA | Notes |
| --- | --- | --- | --- | --- |
| 2026-08-25 | 01 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 88 passed; focused pad/MIDI domain suite included 7 tests. | No Core MIDI client or real input created. Source identity is persisted `Int32` unique ID; display metadata is non-authoritative. |
| 2026-08-25 | 02 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 112 passed; 4 Core MIDI boundary tests cover supported/ignored multiword UMP, bounded/coalesced overflow, unique-ID topology delta, and idempotent service lifecycle. | Uses `MIDIInputPortCreateWithProtocol(..., ._1_0)`; callback copies scalar words only, queues no unbounded work, and never touches AppStore/UI/persistence. Real virtual/physical delivery, sleep/wake, and signed USB/Bluetooth remain manual QA. |
| 2026-08-25 | 04 | Working tree (no commit requested) | Full suite 112 passed; migration/round-trip coverage in Pad and MIDI domain plus persistence suites. | Tracker reconciliation: Slice 04 was already fully implemented during coordinated custom-pad/MIDI schema v3 landing, avoiding incompatible migration landing orders. No additional schema bump is required. |
| 2026-08-25 | 03 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 115 passed; learn zero-value ignore, preview/source lock, commit, duplicate, cancel, timeout, and injected AppStore service tests added. | MIDI Controller Settings remains usable with no sources, explains missing selected unique IDs and Audio MIDI Setup/HID scope, labels Stop all destructively, and announces learn state changes. Normal/narrow Settings, Full Keyboard Access, and VoiceOver remain final manual QA. |
| 2026-08-25 | 05 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 120 passed. Integration coverage exercises all six actions, Live-context pad ownership, disabled/source/channel rejection, CC repeat and reconnect reset, and bounded relay dispatch. | No physical pedal was available. Developer-ID/notarized USB/Bluetooth delivery, sleep/wake on real hardware, and service-length pedal use remain explicit release gates and are not claimed complete. |

## Cross-slice invariants

- `AppStore` remains the only place that invokes transport behavior.
- Core MIDI callback code never mutates UI, `AppStore`, or persistence directly.
- MIDI is disabled by default and a learned mapping is never implicit.
- Existing library data must remain loadable.
- Persistence work must inspect the custom-pad tracker and claim the next unused
  schema version; neither proposed feature owns v3 in advance.
- No third-party dependencies.
- MIDI implementation and release QA must use the entitlement/security model
  recorded by [the signed capability spike](../custom-pads-live/00A_signed_capability_spike.md);
  USB/Bluetooth behavior requires evidence from the actual signed artifact.
- Use the current Core MIDI protocol input API; do not introduce deprecated
  packet-list input APIs.
- A persisted source is identified by Core MIDI unique ID, never display name.
- MIDI service errors, source topology changes, and sleep/wake recovery are
  user-visible and idempotent.
- Do not claim physical hardware support until it is manually verified.
