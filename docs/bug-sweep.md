# General bug sweep

Reviewed transport/preparation ownership, library loading/saving, song and pad
editing, undo/redo, navigation, MIDI input/mapping, external file access, and update
coordination. This is a code review plus automated regression testing; physical
audio-interface and full interactive UI testing remain separate acceptance work.

## Fixes

- Reject a future library schema before decoding its content. A changed future
  representation previously fell through corruption recovery and could be replaced
  with an older backup.
- Apply pad removal undo/redo to changed catalog membership and pad assignments only.
  Preserve later song edits, added/deleted songs and pads, and explicit reassignment.
  Reorder undo preserves current metadata and does not resurrect removed pads. Redo
  refuses to remove a pad that has become audible.
- Refuse to delete a song or remove its entry while that entry owns an audible
  pre-roll or fade, even without a playing-song identity.
- Treat Any Controller MIDI mappings as overlapping matching source-specific
  mappings, including when the Any Controller option is chosen at commit time.
  Reset held-message edges when mappings are changed.
- Preserve CC press/release edges within one input drain while still coalescing
  repeated values within a pressed or released state. Quick button taps previously
  disappeared when their release replaced the queued press.
- If click activation fails after a pad has activated, stop the click and fade the
  actual audible pad. Do not restore a stale runtime snapshot that hides that pad.
  Preparation failures before audio commit still preserve existing playback.
- Relink external pads by identity after asynchronous file work. Preserve concurrent
  renaming/reordering and reject superseded relink results or changed references.

## Verification

The targeted reproduction tests initially failed for future-schema preservation,
pad-removal undo, pre-roll deletion, and overlapping MIDI mappings. After the fixes,
`swift test` passes all 217 tests in 18 suites. Added coverage also exercises quick
CC taps, audio activation failure, relink during reorder/rename, and guarded redo.
`git diff --check` passes.

The earlier audio-routing and Stop-fade work is described in
[audio-stability-validation.md](audio-stability-validation.md), including the
physical-interface checks that have not yet been performed.
