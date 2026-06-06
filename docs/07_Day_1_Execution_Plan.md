# Sustain Day 1 Execution Plan

## Objective

End Day 1 with one believable live-service slice working end to end:

- A song can be cued, started, stopped, and transitioned.
- A pad sound actually plays and loops.
- A BPM-locked click actually plays after a countoff.
- The app has enough persistence to survive a relaunch.
- The remaining technical risks are named instead of hidden.

This is not a pixel-polish day. It is a risk-reduction day.

## What Already Exists

The original planning list is directionally right, but this repository already contains several of its proposed deliverables:

- Product requirements: `docs/05_V1_PRD.md`
- Operating principles: `docs/01_Operating_Charter.md`
- Anti-requirements: `docs/02_Anti_Requirements.md`
- Domain model: `docs/03_Domain_Model.md`
- Runtime state machine: `docs/04_Runtime_State_Machine.md`
- Technical architecture: `docs/06_Technical_Architecture.md`
- SwiftUI shell, in-memory models, runtime store, and basic tests

Day 1 should therefore move from "create the blueprint" to "prove the riskiest parts of the blueprint."

## Phase 1 - Tighten Scope

Define the first usable vertical slice:

- One bundled or generated pad source.
- Loop pad indefinitely.
- Fade pad in and out.
- Generate a click from BPM.
- Run a countoff before click.
- Transition from the current song to the cued song without destroying the current playback state if validation fails.
- Save and reload a small local library/setlist.

Defer these until the foundation behaves:

- Multi-output routing.
- User-imported pad packs.
- Spoken countoff samples.
- Full song-library editing.
- Drag-and-drop setlist reordering.
- MIDI, remote control, lyrics, charts, integrations, sync, and collaboration.

## Phase 2 - Audio Spike

The highest-risk question is whether the app can run simple, stable audio without glitches.

Build the smallest real `AVAudioEngine` implementation that can:

- Start and stop the engine.
- Play a looping pad tone or file.
- Fade pad volume smoothly.
- Generate a click at the selected BPM.
- Generate a countoff before the click starts.
- Keep pad and click running at the same time.

Success criteria:

- Pad continues indefinitely.
- Click timing follows BPM changes predictably.
- Stop silences click immediately and fades pad.
- Starting a new cued song produces an audible transition.
- No UI action claims audio is playing unless audio was actually started.

## Phase 3 - Runtime Wiring

Replace the current instant state flips with runtime actions that reflect audio work:

- `startCuedSong()` validates first, then starts pad/countoff/click.
- `stop()` stops click immediately and fades pad out.
- `startPad()` and `stopPad()` control real pad playback.
- `startClick()` always goes through countoff.
- Failed transitions keep the currently playing song intact.

Add focused tests around state and validation. Keep audio implementation test seams small so business rules can be tested without requiring sound hardware.

## Phase 4 - Local Persistence

Add simple file-based persistence before choosing heavier storage.

Persist:

- Songs.
- Active setlist.
- Key overrides.
- BPM overrides.

Use JSON in Application Support for Day 1. SwiftData or SQLite can wait until the data model proves it needs them.

Success criteria:

- Add or edit seed data in code or UI.
- Relaunch app.
- Same library and setlist return.
- Corrupt or missing storage recovers to seed data with a visible message.

## Phase 5 - Minimum Usable UI

Keep the current screens, but make the Live Service screen truthful and useful:

- Show whether audio engine is running.
- Disable actions that cannot work.
- Show current song, cued song, key, BPM, pad state, and click state.
- Surface validation failures in plain language.
- Add one obvious system-check action.

Avoid polishing secondary screens until Live Service can be trusted.

## Phase 6 - Document Remaining Risk

At the end of Day 1, update docs with what was learned:

- Audio timing approach.
- Crossfade approach.
- Persistence choice.
- Known failure modes.
- What must be proven next.

The next major spike after Day 1 should be independent output routing, because that depends on real devices and is likely to expose Core Audio complexity.

## End Of Day Deliverables

- Real audio spike wired into app actions.
- Focused tests for runtime behavior.
- Basic JSON persistence.
- Live Service UI that reflects actual playback state.
- Updated technical notes for audio, persistence, and remaining risk.

## Guiding Principle

Audio continuity is sacred. If the app cannot safely complete a transition, it must preserve what is already playing and explain what happened.
