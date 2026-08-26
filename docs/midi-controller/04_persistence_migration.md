# Slice 04 — Persistence and migration

**Status:** Not started

**Depends on:** Slice 01 complete

**Goal:** Persist MIDI settings safely without breaking existing user libraries.
Coordinate with the custom-pad tracker before selecting a schema number; v3 is
not reserved for either feature.

## Work

- Add `midiControllerSettings` to `LibrarySnapshot` and all `AppStore` live /
  preview loading and saving paths.
- Inspect `LibrarySnapshot.currentSchemaVersion` at implementation start and
  claim the next unused integer; do not assume the repository is still on v2.
- Decode absent MIDI data from every supported prior schema as disabled
  defaults; ensure normal saves rewrite those files to the selected new version
  while retaining existing songs, setlist, pad catalog/assignments (if landed),
  routing, volumes, and click settings.
- Inject settings into `AppStore` so later Slice 05 can bind action dispatch.
- Add migration and round-trip tests, including a representative v2 JSON file
  and a default-settings assertion.

## Done when

- A snapshot from the immediately prior schema loads with MIDI disabled, then
  saves to the selected new schema.
- A current-schema MIDI mapping—including source unique ID, channel, and message
  number—round-trips exactly.
- Existing persistence tests remain green.

## Kickoff prompt

```text
Implement Slice 04, MIDI persistence and schema migration, in docs/midi-controller/04_persistence_migration.md. Read the PRD, tracker, and Slice 01 models before editing. Mark the tracker in progress and update it with commit/test evidence when finished. Preserve all existing snapshot migration guarantees; do not implement UI or real MIDI input behavior.
```
