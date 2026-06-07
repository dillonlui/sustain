# Production Readiness Checkpoint

## Current Foundation

The app now has the first production-shaped audio path:

- Pads are real MP3 files included with the app.
- Pad lookup is based on the active musical key in the single included pad bundle.
- Missing pad files block playback during system check.
- System Check warns about missing pad assets elsewhere in the active setlist.
- System Check warns about invalid BPMs elsewhere in the active setlist.
- System Check warns about broken song references elsewhere in the active setlist.
- Pad transitions use two player nodes and mixer fades.
- Click and countoff are generated from BPM and time signature.
- macOS output devices are enumerated through Core Audio.
- Pad and click now use separate AVAudioEngine instances.
- Audio Setup can select separate pad and click output devices.
- Routing selections persist across relaunch.
- Persisted libraries are validated at launch and unusable setlists fall back to seed data.
- Legacy pad-pack metadata is normalized back to the included bundle on load.
- Songs can be created, edited, and added to the active setlist.
- The active setlist can be renamed and cleared when playback is stopped.
- Setlist entries can be removed when they are not actively playing.
- System Check warns when pad and click resolve to the same output.
- Hardware routing is revalidated automatically through Core Audio device-change listeners.
- Playback and rehearsal are stopped visibly if a selected routed output disappears.
- Hardware/default routing changes prompt the user to keep current Sustain settings or switch pad/click to the detected output.
- Active playback and rehearsal are stopped before that prompt when hardware/default routing changes.
- Manual Audio Setup routing changes stop active playback and rehearsal so outputs can be rechecked before restart.
- Playback is blocked if Core Audio output-device assignment fails.

## What Is Still Prototype

- Song and setlist editing is functional but intentionally unpolished.
- Independent routing is implemented structurally but has not been validated on multiple real hardware outputs.
- Device disconnect recovery is implemented at the app-state level through Core Audio listener-driven routing refresh.
- Device reconnect recovery can rebind selected outputs by saved device name when Core Audio assigns a new device ID.
- Device reconnect recovery has not been validated across multiple real hardware combinations.
- Wake recovery now triggers an app-level routing recheck, but sleep/wake behavior has not been validated on real hardware.
- Long-running click timing has passed a two-hour BlackHole recording/analyzer run.
- Audio scheduling is still coordinated partly by UI/runtime tasks.

## Next Production Spikes

### 1. Hardware Routing Verification

The app now uses the intended two-engine architecture:

- One AVAudioEngine for pads.
- One AVAudioEngine for click/countoff.
- Each engine attempts to set its own Core Audio output device.

This still needs to be proven on real hardware.

Success criteria:

- Pad can play through one selected output.
- Click can play through a different selected output.
- The app detects when a selected output disappears.
- Playback failure is visible and does not silently lie to the user.
- Output-device assignment failures block playback.
- Default-output changes during playback stop audio and prompt instead of allowing silent route drift.
- Manual output changes during playback stop audio instead of hot-swapping live routes.
- Reconnect behavior restores a safe, understandable routing state.
- Bluetooth-style reconnects that change Core Audio device IDs recover by matching the saved output name when possible.

Fallback decision:

- If AVAudioEngine output-device assignment proves unreliable, move the output layer to a lower-level Core Audio/AUHAL implementation.

### 2. Included Pad Library

The included pad tracks are the real v1 pad library, not demo assets.

Success criteria:

- Included pad tracks are present for every supported key.
- System Check validates included pad tracks before playback.
- The pad track artist/creator is credited before v1 release:
  - In code where the included asset catalog/source is defined.
  - In the repository README.
  - On any future landing page or public website for Sustain.

### 3. Duration Test

Run pad and click together for at least 30 minutes.

Use [10_Duration_Test_Checklist.md](10_Duration_Test_Checklist.md) to keep the run repeatable.

Observe:

- Audio glitches.
- Memory growth.
- CPU usage.
- Behavior when display sleeps.

Current timing result:

- A 2-hour click recording through BlackHole passed automated analysis at 72 BPM.
- Analyzer result: 72.002 observed BPM, 0.033 ms mean jitter, 0.091 ms worst jitter, 0 missing beats, 0 extra/doubled beats.
- Remaining duration-test work is focused on full app behavior during interaction, pad continuity, CPU/memory, display sleep, and real hardware routing.

### 4. Listener Validation

The current monitor uses Core Audio property listeners for device-list and default-output changes. The implementation compiles under Swift concurrency using a small sendable relay back to the main actor, but it still needs real-hardware validation.

Success criteria:

- Device-list and default-output changes trigger routing refresh on real hardware.
- Listener registration and removal remain paired during app lifecycle.
- Existing playback-loss tests continue to pass unchanged.

## Product Rule

UX polish should wait until the audio engine can play real files, route outputs independently, and report hardware failures accurately.
