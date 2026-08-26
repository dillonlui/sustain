# Slice 07 — Clear Setlist

## Goal

Add a confirmed, atomic way to remove every active-setlist entry without
affecting the Song or Pad Libraries.

## Work

1. Add `AppStore.clearActiveSetlist()` with an authoritative active-audio guard.
2. Clear entries and runtime entry references, refresh readiness, announce the
   result, and save exactly once.
3. Add **Clear Setlist…** to the Live footer with count/title confirmation.
4. Hide/disable for empty lists and disable while any pad/click live audio is
   active, including pad-only pre-roll once Slice 05 lands.
5. Use buttons named **Cancel** and **Clear Setlist**. Cancel is not the default;
   Escape and Command-period cancel. Either default the deliberately requested
   Clear action or provide no default if accidental Return is a concern.
6. Register one named **Undo Clear Setlist** operation. Undo restores entries,
   order, and prior cue when safe but never starts audio.
7. Cover pending editing selection so the inspector/editor closes cleanly, then
   move focus to Add Song or the empty-state message.

## Acceptance

- Confirm clears all entries, cue/editor selection, and persists once.
- Cancel and an attempted call during audio change nothing.
- Escape/Command-period cancel, Undo/Redo round-trips the setlist with one save
  per operation, and neither path changes audio.
- Song and Pad Library records are byte-for-byte logically unchanged.
- Relaunch shows the empty setlist and Add Song remains usable.
- Unit/store tests cover 0, 1, many, cued, and playing cases.
- VoiceOver announces the result and keyboard focus never remains on a removed
  control.
