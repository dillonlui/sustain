# Sustain 2.0 UX/UI launch audit

**Reviewed:** 2026-09-25, current working tree including uncommitted advanced-click work.

**Method:** three independent source reviews (visual system, flows/accessibility, production readiness), cross-check against the Future Signal interaction contract and Live acceptance criteria, plus a local Swift build/test run. The findings below describe the initial working tree; the remediation record that follows describes the updated tree. This is not a signed-app or physical-device walkthrough.

## Remediation and automated app walkthrough

All actionable findings below were addressed in the working tree except the three presentation choices accepted by Product: visible Pad/Click state words, visible Playing/Cued words in setlist rows, and the count-in overlay. Live Pad and Click remain visually compact, but are now separate accessibility elements that announce their states.

- Global Stop now clears Rehearse pad and click audio/state as well as Live. Navigation away from a dirty song editor prompts before the screen changes. Compact Live sheet dismissal is blocked while dirty, and removing or clearing an edited entry warns about unsaved changes.
- Live moves the editor to a sheet whenever a side pane would leave less than 700 points for the performance area. The pad decoder detaches callbacks under its lock before invoking them. Rehearse now identifies a pending subdivision change in text. An unrecoverable library opens read-only, preserving the failed primary and backup files.
- Release metadata and notes now target 2.0.0 (build 5). `scripts/validate-release.sh config/release.json v2.0.0` passed. The Universal 2 debug app bundle was built, signed ad hoc, and verified by `scripts/bundle.sh debug` at `/private/tmp/sustain-2-audit-apps/Sustain.app`.
- The **full** `swift test --disable-sandbox` run passed **201 tests in 18 suites** when given host CoreAudio access. The earlier audio-unit abort was specific to the restricted execution environment.
- Automated computer-use walkthrough of the bundled app verified: Song Library dirty-navigation prompt, Keep Editing retention and Discard navigation; Rehearse pad and count-in click stopping with Cmd+.; Live editor appearing as a sheet at minimum and 900-point window widths; separate Pad/Click accessibility state elements; dark and light Live layouts. The original System appearance setting was restored. No saved song or setlist data was changed.
- The walkthrough exposed an additional keyboard defect: Right Arrow advanced the Live cue while the wide song-title field had focus. The unmodified Left/Right/Return transport shortcuts now apply only when the Live editor is closed. After rebuilding, Right Arrow kept focus in the title field and left the cue unchanged.

The signed/notarized release workflow, physical MIDI/audio-device runs, Intel hardware, and an assistive-technology session remain release-process checks rather than results of this local walkthrough.

## Decision

**Initial assessment, before remediation:** hold the 2.0 launch. The global Stop command did not stop Rehearse pad audio, unsaved song edits could disappear, and the Live performance UI lost usable width in common layouts. The pad decoder race and incomplete release configuration also needed resolution. Product subsequently accepted the compact visual state treatment and count-in overlay as intentional.

## Initial launch blockers and high-priority findings

| Priority | Finding and evidence | User impact | Exit criterion |
| --- | --- | --- | --- |
| P0 | **Global Stop is not global.** `SustainApp.swift:125-129` enables Cmd+. for any audio activity, and MIDI Stop all calls `stop()` at `RuntimeSession.swift:1398`. `stop()` at `RuntimeSession.swift:535-554` changes Live state and calls `audioEngine.stopClick()`, but never stops the Rehearse pad or resets Rehearse click state. | In Rehearse, a pad can keep sounding after Cmd+. or MIDI Stop all. A Rehearse click may stop physically while still appearing active. | Cmd+. and MIDI Stop all end both Live and Rehearse activity and leave displayed state consistent; cover this with an integration test. |
| P1 | **Unsaved edits disappear on navigation.** `RootView.swift:82-94,120-123` and `SustainApp.swift:151-157` replace screens directly. The Song Library and Live inspector drafts live in local `@State` (`SongLibraryView.swift:9-15`, `LiveServiceView.swift:93-98,904-956`); local discard prompts are bypassed. Compact Live sheet dismissal also clears `editingEntryID` directly at `LiveServiceView.swift:113-124`. | A user can change a title or click setting, switch screens or dismiss the sheet, and return to find the work gone. Removing the edited setlist entry and clearing the setlist have similar paths. | All exits from a dirty editor share one save/discard/keep-editing decision, including sidebar/menu navigation, sheet dismissal, remove, and clear. |
| P1 | **Live Pad/Click state words are hidden.** `LiveServiceView.swift:496-504` passes `showsStateLabel: false` and exposes only route names in the accessibility value. The shared component hides its icon from VoiceOver (`FutureSignalChannelComponents.swift:73-100`). | Operators and VoiceOver users cannot reliably distinguish Off, Preparing, Count in, Playing, Fading, or Unavailable in the channel cards. This violates `docs/design-refresh/live-acceptance.md:12-18,31`. | Show the actual state in text and accessible value; show audible pad identity/owner and pending versus audible click information when relevant. |
| P1 | **Playing/Cued setlist state lacks visible words.** `FutureSignalSetlistComponents.swift:22-75` and `LiveServiceView.swift:850-888` use edge/outline/color while accessibility has the words. | Sighted operators must interpret decoration to distinguish playing from cued, including when both refer to one entry. This violates `docs/design-refresh/live-acceptance.md:25`. | Add concise visible Playing/Cued labels or glyph-plus-text treatments for each state and their combination. |
| P1 | **Editor width can crush Live performance controls.** `LiveServiceView.swift:112-145` keeps a 200–340 point setlist and a 320 point inspector whenever detail width is at least 680 points. At the threshold the performance pane has about 160 points, before its own padding, while the four-button transport is much wider (`LiveServiceView.swift:540-590`). | NOW/NEXT and transport can clip or become difficult to operate in an ordinary window with the inspector open. | Use an editor-aware sheet breakpoint or enforce a usable minimum performance width; render and check intermediate widths as well as 640 × 600 and 1200 × 700. |
| P1 | **Pad decode callbacks can race or be lost.** `PreparedAudio.swift:202-208` appends completions under a lock, but `PreparedAudio.swift:237` iterates the same array outside it before clearing the active request. | A same-pad request arriving near decode completion can miss its completion or race with array iteration, leaving a Live start/pre-roll stuck in Preparing or causing a crash. This is a code-path finding, not a reproduced user session. | Atomically detach the completed request and its callbacks before invoking them; test a same-key submission during completion. |
| P1 | **2.0 release metadata is not ready.** `config/release.json:2-3` still says 1.1.1/build 4, and `docs/releases/next.md:1` is 1.1.1. The protected workflow validates tag/version and publishes these notes (`scripts/validate-release.sh:9-20`, `.github/workflows/release.yml:89-128`). | A 2.0 tag fails validation or would carry stale release notes if the metadata were only partly updated. | Set a valid 2.0 version/build and reviewed 2.0 notes, then run the protected release gates. |

## Initial further UX and resilience issues

| Priority | Finding | Action |
| --- | --- | --- |
| P1, visual validation pending | Count-in badge overlays operational content: Live transport at `LiveServiceView.swift:369-381`, and the Rehearse Pad/Click status row at `RehearseView.swift:107-124`. The opaque badge is defined at `LiveServiceView.swift:765-787`. Saved specimen PNGs predate the Rehearse change. | Reserve layout space and capture actual count-in screens at minimum and typical widths. |
| P2 | Rehearse picker can display the requested subdivision while `clickText` still describes the audible value without clear pending-change copy (`RehearseView.swift:503-516,574-579`). | State “Switching to … at next measure” separately from “Now playing …”; clear it on commit/failure/stop. |
| P2 | If both primary and backup library loads fail, `RuntimeSession.swift:2858-2876` starts with a seed and writable store. Subsequent saves at `Persistence.swift:331-345` can make the seed the primary and eventually the rolling backup. | Put recovery mode behind an explicit recovery/restore decision before writes replace recoverable files. |

## Initial verification gaps and remaining launch checks

- The initial restricted `swift test --disable-sandbox` run aborted with CoreAudio exception `required condition is false: comp != nullptr` while constructing `AVAudioSourceNode`; the full suite subsequently passed with host CoreAudio access, as recorded above.
- The automated app walkthrough covered core flows in a locally signed debug bundle. Before an official release, capture real-runtime empty, cue-only, pre-roll, preparing, count-in, playing/cued-apart, transition, fade, blocked-route, advisory, and pending-rhythm states in a signed candidate. Check increased contrast, keyboard focus, Reduce Motion, and VoiceOver on that candidate.
- The wide-editor arrow-key interaction was checked and corrected in the bundled app, as recorded above. The final signed candidate should repeat the keyboard walkthrough with title and tempo fields.
- Perform the release-process manual audio, device-routing, MIDI, and signed-update walkthrough recorded in `docs/RELEASE_PROCESS.md` and `docs/design-refresh/live-acceptance.md`. Existing test results do not substitute for these checks.

## What is working well

The app has a coherent semantic palette for light/dark/increased contrast, a stable custom shell, clear NOW/NEXT hierarchy, native sliders and transport buttons, accessible setlist values, and useful empty states. The new click controls provide labels and hints. These foundations make the findings above targeted fixes rather than a full redesign.
