# Slice 06 — Rehearse Catalog Surface

## Goal

Replace the fixed twelve-key launcher with the user's visible, ordered Pad
Library while keeping Rehearse a fast single-pad playback surface.

## Work

1. Replace `MusicalKey.allCases` with visible `PadTrack` records in a lazy
   adaptive grid.
2. Keep every launch button equal height. Wrap free-form labels to two lines,
   then tail-truncate; never independently expand or marquee. Expose full text
   in the active surface, tooltip, accessibility value, and unique Voice Control
   input label.
3. Add localized case/diacritic-insensitive label/filename search and useful
   empty states for custom-only views.
4. Track selected/audible pad by ID and label in `RehearseSession`.
5. Make pressing the audible pad a no-op; pressing another crossfades.
6. Preserve stop, volume, click/countoff, responsive layout, and previews.
7. Add **Play in Rehearse** routing from Pad Library management. Show source
   duration/channels/sample-rate there and explain that Sustain does not
   normalize loudness or repair loop boundaries.
8. Respect Full Keyboard Access, Reduce Motion, Differentiate Without Color,
   increased contrast/text, and system focus effects. Audio state never steals
   focus.

## Acceptance

- Visible order matches Pad Library after relaunch.
- Show Included Pads filters bundled launchers only.
- Duplicate and long labels remain equal-height, distinguishable, and
  accessibility-complete at narrow and wide window sizes.
- Every typed unavailable/error state blocks launch with accurate recovery.
- Only one loop plays and the active item does not restart on a second press.
- Keyboard, VoiceOver, Voice Control, Reduce Motion, contrast, and long
  localized-string QA pass.
