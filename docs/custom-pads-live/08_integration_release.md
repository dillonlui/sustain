# Slice 08 — Integration, Release, and MIDI Alignment

## Goal

Harden the complete workflow, reconcile MIDI/persistence, and verify real file
access and audio behavior in the distribution build.

## Work

1. Re-read the MIDI tracker and reconcile the final schema migration chain.
   Ensure either landing order preserves all pad and MIDI fields/defaults.
2. Route MIDI Toggle Pad to the context-aware AppStore action from Slice 05.
3. Exercise import → assign → add song → idle pre-roll → Start → stop → clear
   as one integration path.
   Also verify that a current song never exposes next-pad pre-roll and that an
   idle pre-roll cue change is replaced only when Start commits successfully.
4. Audit prepare/activate atomicity, latest-wins cancellation, security-scope
   balance, coordinated reads, byte-budget accounting, save failures, backup
   recovery, sleep/wake, and audio-device changes.
5. Reconfirm the Slice 00A entitlement choice against the exact
   Developer-ID-signed/notarized build after relaunch, on a removable volume,
   with iCloud/File Provider materialization and physical USB/Bluetooth MIDI.
6. Run a service-length test with many catalog items, 256 MiB single-pad and
   512 MiB total admission boundaries, crossfades, rapid superseding presses,
   and no unbounded decode queue or bookmark scopes.
7. Complete standard menus/shortcuts, selection/focus, Finder drop insertion,
   Undo/Redo, Full Keyboard Access, VoiceOver, Voice Control, Reduce Motion,
   Differentiate Without Color, increased contrast/text, long/localized labels,
   narrow-window, and large-library QA.
8. Update README, current-status, domain/state-machine docs, release notes, and
   tested-format/support language only after behavior is implemented.
9. Review Slice 08A evidence: official-build updater gating, deferred-check and
   relaunch behavior across final Live/Rehearse states, canonical app/DMG/ZIP
   identity, nested Sparkle signing, appcast-last publication, and a real
   lower→higher signed/notarized update (previous public release after bootstrap).

## Acceptance

- Full unit/integration suite passes with migration fixtures for every supported
  prior schema and both feature landing orders where applicable.
- No early-pad transition restarts matching audio under UI, keyboard, or MIDI.
- Current-song Pad commands never target NEXT; idle mismatched pre-roll Start
  handles different-pad, same-pad, No Pad, and prepare-failure cases correctly.
- Failures injected before transition commit cannot change outgoing audio;
  activation never performs file IO or risky allocation.
- Signed-build bookmarks survive relaunch; missing/remounted files recover as
  documented.
- No source audio is copied/deleted and no full paths leak into ordinary logs.
- Service-duration test shows no unbounded decoded-memory or bookmark-scope
  growth.
- Entitlement inspection proves the distributed artifact matches Slice 00A and
  least privilege; no broad/temporary exception was added without evidence.
- Native menus, Undo/Redo, selection/focus, drag/drop, and accessibility QA have
  recorded evidence rather than being deferred as polish.
- Physical MIDI and real audio-interface QA evidence is recorded in both
  trackers before release is called complete.
- A feed check, download, and accepted update cannot interrupt audio or force a
  relaunch; one deferred check runs after idle and a failed save blocks install.
- Ordinary push/PR builds cannot contact or publish the stable feed. Release
  tag, display version, and monotonically increasing build are consistent.
- DMG and Sparkle archive contain the same canonical notarized/stapled app;
  archive/feed/note EdDSA checks and previous-release update evidence are
  recorded before the production appcast changes.
