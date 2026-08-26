# Slice 05 — Early-Pad Live Transport

## Goal

Let the operator start the cued song's pad only from fully idle Live state,
then start that song's click/countoff without restarting its pad. Never expose
independent next-pad pre-roll while a current live song exists.

## Work

1. Add runtime audible pad ID and optional originating entry ID; stop inferring
   pad identity from `playingEntryID`.
2. Add AppStore actions `startCuedPad`, `stopPad`, and a context-aware pad
   toggle suitable for UI, commands, and future MIDI dispatch.
3. Define one authoritative full-idle guard: no `playingEntryID`, live click
   off, live pad off (not preparing/fading/audible), and Rehearse audio off.
   Recheck it in AppStore; UI disabled state is not authority.
4. While `playingEntryID` exists, Pad starts/stops only the current song's pad.
   Never expose or dispatch Play Next Pad, even if current click/pad is off.
5. Global Stop must clear the current song and complete/cancel any fade before
   the idle pre-roll action becomes eligible.
6. Prepare route/file before idle fade-in. Preparation cannot alter audio;
   activate only after success. Record both pad ID and owning setlist-entry ID,
   while keeping NOW empty and NEXT cued.
7. For a matching pre-roll owner/assignment, prepare and start click/countoff,
   promote that entry, and issue no second pad preparation/activation.
8. If cue/assignment changes during pre-roll, keep audio stable and show both
   sounding and cued identities. Start remains available: prepare the new pad
   and click, then atomically crossfade/replace the old pre-roll. For No Pad,
   start click then fade old pre-roll; for the same pad ID, preserve position
   and transfer entry ownership without restart.
9. Any replacement preparation failure leaves the old pre-roll audible and
   `playingEntryID == nil`.
10. Update Pad labels/help, mismatch presentation, global Stop availability,
    commands, and MIDI-facing toggle semantics.
11. Handle stop/cancel during preparation, stop/fade/re-arm, double press,
    Rehearse audio, unavailable files, same-pad entries, and live assignment
    edits.

## Acceptance

- Audio fake proves early start issues one activation and later transition
  issues zero additional pad activations for the same ID.
- A current playing entry never exposes or dispatches next-pad pre-roll,
  including when its click and pad have been manually stopped.
- Stop plus completed fade is required before another cued pre-roll can start.
- Cue changes alone never alter pre-roll audio and mismatch is visible.
- Starting a mismatched cue prepares first, then replaces old pre-roll and
  starts the new click atomically; failure preserves old pre-roll and idle song
  identity.
- Same-pad mismatch transfers ownership without restart; No Pad starts click
  then fades old pre-roll.
- Stop works before the first song when only a pre-roll pad is active.
- Injected failures at pad prepare, click prepare, and pre-commit validation do
  not alter outgoing audio or playing identity.
- MIDI-facing context action is an AppStore method with no MIDI dependency.
