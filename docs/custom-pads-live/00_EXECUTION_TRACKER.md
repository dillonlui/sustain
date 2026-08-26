# Custom Pads, Live Workflow, and App Updates — Execution Tracker

This is the durable handoff and progress record for the custom Pad Library,
early-pad Live workflow, Clear Setlist action, and native app-update pipeline.

PRD: [`../17_Custom_Pads_And_Live_Workflow_PRD.md`](../17_Custom_Pads_And_Live_Workflow_PRD.md)

## Operating protocol

1. Confirm branch/worktree and preserve unrelated changes.
2. Read the PRD, this tracker, and the assigned slice in full.
3. Check the current persistence schema and MIDI tracker before any model work.
4. Mark only the assigned slice **In progress** before editing.
5. Do not start a slice whose dependencies are incomplete.
6. Keep AppStore authoritative for product actions; keep file IO/decode out of
   SwiftUI and off the main actor.
7. Run the slice tests plus the relevant full suite.
8. On completion, update status and add test/commit/manual-QA evidence here.

## Current status

| Slice | Status | Dependency | Completion evidence |
| --- | --- | --- | --- |
| [00A — Signed capability spike](00A_signed_capability_spike.md) | Complete (manual release QA pending) | — | Sandboxed least-privilege model chosen; one explicit entitlement file drives dev/release signing. Universal ad-hoc artifact signature/entitlements verified, including Sparkle's documented installer mach services; Developer ID, bookmark relaunch, Core Audio, and physical USB/Bluetooth QA carried to Slice 08. |
| [01 — Model and migration](01_model_and_migration.md) | Complete | — | Schema v3 atomically adds ordered pad catalog, optional stable song assignment, external fingerprint/metadata, and disabled MIDI defaults. v1/v2 migrate losslessly; current missing/null/value semantics tested. |
| [02 — External file access](02_external_file_access.md) | Complete (signed manual QA pending) | 00A, 01 | Actor-isolated bookmark/scope/coordinator/validator boundary; checked 256 MiB admission; typed states; partial ordered batch import; duplicate identity/path handling; ID-preserving Locate. |
| [03 — Pad Library management UI](03_pad_library_ui.md) | Complete (manual accessibility/drop QA pending) | 01, 02 | Native lazy multi-select catalog; picker/drop import; localized search; filtered reorder guard; inline rename; typed metadata/state; repair/reveal; atomic replacement removal; menus; undo; included visibility. |
| [04 — Audio and song integration](04_audio_and_song_integration.md) | Complete (real-format manual QA pending) | 01, 02 | Immutable two-phase pad/click preparation; latest-wins decode; 256/512 MiB byte-cost LRU; fingerprint-aware external reads; explicit No Pad/searchable assignment; typed readiness and safe live edits. |
| [05 — Early-pad live transport](05_early_pad_transport.md) | Complete (real-output manual QA pending) | 04 | Authoritative full-idle pre-roll; current-entry ownership; matching reuse; mismatch/No Pad atomic replacement; truthful fade re-arm; shared UI/commands/MIDI-facing action; race tests. |
| [06 — Rehearse catalog surface](06_rehearse_surface.md) | Complete (manual adaptive/accessibility QA pending) | 03, 04 | Ordered visible catalog, localized search, equal-height two-line launchers, full-label active/help/accessibility text, typed launch guards, ID-based no-restart/crossfade, and Play in Rehearse routing. |
| [07 — Clear setlist](07_clear_setlist.md) | Complete | — | `clearActiveSetlist` authoritative all-audio guard; native confirmation; atomic save; standard Undo/Redo; focus/VoiceOver result handling. Focused tests pass. |
| [08A — Native app updates and release pipeline](08A_app_updates.md) | Complete (protected release/staging-update gates pending) | 00A, 05 | Sparkle 2.9.6 is pinned; explicit Developer-ID/stable eligibility owns startup/menu/settings; AppStore-derived checks and relaunch are coalesced until idle/save; Universal helper signing and canonical DMG/ZIP validation plus protected appcast-last workflow are implemented. |
| [08 — Integration, release, and MIDI alignment](08_integration_release.md) | Complete (external/manual release gates pending) | 03–07, 08A | One authoritative import→assign→add→pre-roll→Start→Stop/fade→Clear/reload path passes; click preparation races are closed; schema/MIDI/actions/docs are reconciled; all implementable automation and local packaging verification pass. |

Slices 00A, 01, and 07 may be implemented independently. After 00A and Slice
01, Slices 02 and the non-file portions of 04 may proceed in parallel if changes
are coordinated. Slice 08A's release-pipeline foundation may be prototyped after
00A, but its Live deferral contract cannot complete until Slice 05. MIDI
foundations may proceed independently, but MIDI persistence and final action
dispatch must wait for schema/action coordination.

## Decisions and blockers

| Date | Item | Owner | Resolution / next action |
| --- | --- | --- | --- |
| 2026-08-25 | File ownership | Product | Reference in place with durable bookmarks; never delete source audio. |
| 2026-08-25 | Labels | Product | Free-form, duplicate labels allowed, stable ID authoritative. |
| 2026-08-25 | Bundled pads | Product | Visible by default; hideable in browsers; immutable and still playable when assigned. |
| 2026-08-25 | Song without pad | Product | Supported; click/countoff starts and outgoing pad fades. |
| 2026-08-25 | Early-pad eligibility | Product | Cued-pad pre-roll is idle-only. A current playing entry owns Pad even with click/pad manually off; use Stop and finish fade before pre-roll. |
| 2026-08-25 | Pre-roll cue change | Product | Cue change alone keeps old pre-roll; Start atomically replaces it with the newly cued pad/click, preserving position when pad IDs match. |
| 2026-08-25 | Clear during playback | Product | Disabled until all live audio is stopped. |
| 2026-08-25 | App Sandbox | Release | Required early signed spike before Slice 02; prefer least-privilege sandbox if Core Audio/MIDI/file workflows pass. |
| 2026-08-25 | Schema ownership | Engineering | Inspect at Slice 01 start; coordinate with MIDI and never reuse an already-landed version. |
| 2026-08-25 | App update consent | Product/Release | Preserve Sparkle's native automatic-check permission; manual checks remain available. Disallow automatic installs in v1. |
| 2026-08-25 | Update publication | Release | Stable tag/draft immutable assets first; signed appcast is published last and remains unchanged on failure. |
| 2026-08-25 | Update trust | Release | Sign archive, feed, and external notes with EdDSA; notarize/staple the canonical app before deriving DMG and ZIP. |
| 2026-08-25 | Updater bootstrap | Release | Existing builds have no Sparkle path and require one manual DMG install. Before bootstrap, prove lower→higher signed Sparkle builds; later releases test from the prior public version. |
| 2026-08-25 | Baseline verification | Engineering | Initial `swift test` was blocked by the managed sandbox's default Clang cache path; rerun with task-local cache paths under `/tmp`. No product-code failure was observed. |
| 2026-08-25 | Distribution capability model | Engineering/Release | Chosen model: App Sandbox with app-scoped bookmarks, user-selected read-only files, and outbound network client. No audio-input, USB, or Bluetooth entitlement is present. Slice 08A adds only Sparkle's documented `com.sustain.app-spks`/`-spki` mach-lookup exception required by its Installer XPC service; Downloader.xpc is removed because the app already owns network client access. `config/Sustain.entitlements` is applied by both ad-hoc and Developer ID bundle paths and verified from the signed artifact. Physical capability and Developer ID/notarized evidence remains a Slice 08 release gate. |

## Cross-slice invariants

- Pad identity is UUID-based; label/path/key are not identity.
- Included IDs are deterministic across launches and versions.
- Pad array order is the only persisted ordering authority.
- External audio stays external and is never deleted by Sustain.
- Bookmark/path resolution is behind `PadAssetResolving`.
- Main-actor UI/store code performs no synchronous file validation or decode.
- Full-buffer audio is limited to mono/stereo, 256 MiB per pad and 512 MiB
  total decoded memory unless measured evidence changes the documented policy.
- Preparation cannot alter audio; activation consumes an already-prepared
  immutable buffer. Pre-commit failure preserves current playback.
- At most one decode is active and one newest request is pending; obsolete work
  cannot create an unbounded queue.
- Security scopes cover coordinated validation/decode only and are balanced on
  success, failure, and cancellation.
- Missing, unavailable-volume, permission, provider, protected, changed, and
  unreadable states remain distinct.
- `audiblePadTrackID` is independent from playing/cued song IDs.
- Starting a song never restarts an already-audible matching pad.
- Cue changes alone never alter audio.
- No Pad is intentional and never a missing-file error.
- Batch operations save once and preserve rolling-backup behavior.
- Old missing pad assignment and current explicit No Pad are distinct migration
  cases.
- Reversible content operations participate in standard named Undo/Redo without
  causing audio side effects.
- Native menus, context menus, selection, focus, Finder drops, and Full Keyboard
  Access are required rather than optional polish.
- MIDI invokes AppStore actions, never the resolver or audio engine.
- Only eligible official stable builds initialize Sparkle or contact the feed.
- Update checks and relaunch defer while any audio prepares, fades, or plays;
  one deferred request runs after idle and update code never mutates transport.
- Sparkle cannot offer silent automatic installation in v1.
- Release tag, marketing version, and monotonically increasing build agree;
  the signed appcast is the last publication step and references ready assets.
- The canonical app is signed/notarized/stapled before identical app contents
  are packaged into the DMG and Sparkle archive.

## Completion log

| Date | Slice | Commit(s) | Tests / QA | Notes |
| --- | --- | --- | --- | --- |
| 2026-08-25 | 07 | Working tree (no commit requested) | `swift test --disable-sandbox --filter clearing`: 4 passed. Full pre-slice suite: 79 passed. | Confirmation names title/count; empty hidden; active Live/Rehearse audio blocks; undo/redo restores order/cue without audio. Manual keyboard/VoiceOver alert inspection remains in final QA. |
| 2026-08-25 | 00A | Working tree (no commit requested) | Universal arm64/x86_64 debug bundle built; `codesign --verify --strict` and `scripts/verify-capabilities.sh` pass against `build/capability-spike/Sustain.app`. | Ad-hoc signed artifact proves applied sandbox/bookmark/read-only/network entitlement shape. Developer ID identity/notary access, external interface, removable file, USB pedal, and Bluetooth pedal were unavailable and are explicitly carried to Slice 08 manual QA. |
| 2026-08-25 | 01 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 88 passed. | Fixed literal UUIDs for 12 pads; unified order normalization; schema-aware old-missing/current-null/current-value/current-missing tests; v1/v2 routing/setlist/click/volume data retained. Coordinated schema v3 also carries MIDI disabled defaults. |
| 2026-08-25 | 02 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 94 passed, including 6 external-reference tests. | Scope balance, stale refresh, coordinated failure, changed identity, symlink resolution, checked overflow, duplicates, partial batch success, order, and ID-preserving repair automated. Real picker/drop bookmarks, File Provider, removable drives, and signed relaunch remain final manual QA. |
| 2026-08-25 | 04 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 97 passed, including prepared-audio memory, latest-wins, prepare/activate, failure preservation, No Pad, readiness, and live-edit tests. | Pad/click PCM creation and external validation/decode run off-main; activation is nonthrowing scheduling only. Cache keys include stable ID, resource identity, and current fingerprint. Changed files are rejected before stale cache lookup. Real MP3/M4A/WAV/AIFF/CAF looping/crossfade and memory-pressure observation remain final manual QA. |
| 2026-08-25 | 05 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 104 passed; 7 focused pre-roll/ownership/race tests added. | Matching pre-roll starts click without pad restart; cue mismatch prepares before replacing; same-ID transfers ownership; No Pad fades outgoing; Stop/cue-change late completions cannot commit; commands and Live controls call `toggleLivePad`. Real fade/output timing remains final manual QA. |
| 2026-08-25 | 03 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 106 passed; catalog mutation/atomic assignment/Undo and immutable/audible removal guards added. | Pad Library is in sidebar/Go/Pad menus; Add Audio picker and row/empty-space Finder drops share the batch service; search is localized label/filename matching; reorder is disabled while filtered; Show Included persists via AppStorage while assigned included pads remain visible. Native drop-indicator precision, large-library responsiveness, keyboard focus, and assistive technology remain final manual QA. |
| 2026-08-25 | 06 | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 108 passed; stable-ID selection/no-restart and typed-unavailable routing tests added. | Rehearse launchers follow persisted catalog order and Show Included preference; label/filename search, fixed 70pt button content, two-line tail truncation, source-disambiguated accessibility labels, full active label/help, and Pad Library Play routing implemented. Narrow/wide, Dynamic Type, Voice Control/VoiceOver, contrast, and Reduce Motion remain final manual QA. |
| 2026-08-25 | 08A | Working tree (no commit requested) | Full `swift test --disable-sandbox`: 132 passed, including 8 update-coordination and 4 release-validation tests. Universal ad-hoc `scripts/package.sh debug` passed nested strict signatures, both architectures, entitlements/rpath, DMG verification, Sparkle ZIP extraction, and recursive canonical-app identity across both containers. | Sparkle 2.9.6 exact revision is pinned. Dev builds carry no feed/key/eligibility flag and never start Sparkle. Developer ID/timestamp/notary/staple assertions are present but require protected credentials. Production feed publication is explicit, protected, atomic, and last; it was not run. A real signed lower→higher staging update and all failure-path/audio-duration QA remain release gates. |
| 2026-08-25 | 08 | Working tree (no commit requested) | Final full `swift test --disable-sandbox`: 135 passed in 10 suites. Final Universal ad-hoc `scripts/package.sh debug` passed strict nested signatures, capability verification, architecture/minimum-OS/rpath checks, DMG checksum/mount, ZIP extraction, and identical recursive app manifests. | End-to-end integration persists the imported external pad and assignment while atomically clearing only the setlist. Rehearse/Live click preparation is now explicit active audio and generation-guarded against late activation after Stop. README, release notes, third-party notices, protected release/runbook, and both trackers reflect the final software boundary. Remaining items below require a signed/notarized candidate, physical devices/interfaces, assistive-technology/manual observation, credentials, or external staging/hosting and are not claimed passed. |

## Final manual QA still required

All implementable repository work and automated checks are complete. The
following release gates remain deliberately unchecked; none was inferred from
the ad-hoc build or published to production.

- [ ] Finder picker and drag/drop with MP3, M4A, WAV, and one invalid file.
- [ ] Signed capability spike and final artifact entitlement inspection.
- [ ] Bookmark relaunch plus moved file and removable-drive disconnect/reconnect.
- [ ] iCloud/File Provider materialization and coordinated-read failure states.
- [ ] Hundreds-row responsiveness and long-file memory observation.
- [ ] 256 MiB single/512 MiB total boundaries, rapid requests, and memory pressure.
- [ ] Idle pre-roll before first song and after explicit Stop/fade on real output.
- [ ] No Play Next Pad while a current song exists; cue-change replacement path.
- [ ] Menus, Undo/Redo, drop insertion, long labels, and focus restoration.
- [ ] Full Keyboard Access, VoiceOver, Voice Control, Reduce Motion, contrast.
- [ ] Signed/notarized build file access.
- [ ] Combined physical MIDI pedal behavior after MIDI implementation.
- [ ] Eligible/ineligible updater configuration and native app-menu/settings UX.
- [ ] Lower → higher Sparkle-enabled update from `/Applications` with signed
      notes, install/later/skip/current and preserved user data; previous public
      version is mandatory after the one-time bootstrap.
- [ ] Offline, TLS/feed/archive tamper, incompatible OS, read-only DMG, locked
      install, authorization cancellation, save failure, and failed-update recovery.
- [ ] Update check/download/relaunch deferral during Live pre-roll/current song,
      transition/fade, and Rehearse, with no dropout or duplicate deferred check.
- [ ] Nested Sparkle helper signatures/entitlements, app + DMG notarization,
      archive integrity, tag/version/build monotonicity, and appcast-last publish.
