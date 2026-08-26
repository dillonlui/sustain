# Slice 01 — Model and Migration

## Goal

Introduce stable pad-track identity, ordered catalog persistence, optional song
assignment, external-source fingerprints, and a lossless migration from the
current schema without changing playback yet.

## Work

1. Add `PadTrack`, `PadSource`, `ExternalAudioReference`, and a Codable
   resource-identity/size/modification fingerprint model.
2. Define deterministic UUIDs for all twelve included pads and test uniqueness
   and stability. Keep bundled attribution intact.
3. Replace `Song.padPack` as runtime audio authority with optional
   `padTrackID`. Retain legacy decode fields only as needed for migration.
4. Add ordered `padTracks` to `LibrarySnapshot`. Store Show Included Pads in
   `@AppStorage`/UserDefaults, not the content schema.
5. At implementation time, inspect the schema version and MIDI work. Claim the
   next unused schema; never assume v3 is still available.
6. Migrate every legacy song to the included pad matching `defaultKey` and
   preserve all other song/setlist/routing/level/click data.
7. Normalize included records without discarding the user's unified order.
8. Update seed/preview/test fixtures and snapshot equality/coding tests.
9. Decode assignment with schema-aware key presence: old missing field maps to
   the included key pad, current explicit null remains No Pad, and an invalid
   current missing field fails validation.

## Acceptance

- Current v2 and legacy v1 fixtures decode and save to the new version.
- Every migrated song selects the same audible bundled file as before.
- No Pad round-trips as `nil` without being defaulted back during normalization.
- Tests separately cover old missing, current null, current UUID, and invalid
  current missing-key JSON; no unconditional `decodeIfPresent` conflates them.
- Included IDs remain stable in an explicit regression test.
- Included IDs are fixed literal UUID constants and future included-pad merge
  does not reorder the existing user catalog.
- Future schemas are still rejected without quarantine/overwrite.
- `swift test` passes before audio APIs are generalized.

## Do not include

File pickers, bookmark resolution, management UI, or transport behavior.
