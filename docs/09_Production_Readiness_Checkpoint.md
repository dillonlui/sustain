# Production Readiness Checkpoint

## Current Foundation

The app now has the first production-shaped audio path:

- Pads are real MP3 files bundled with the app.
- Pad lookup is based on pad pack and musical key.
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
- The audio layer can resolve non-bundled pad packs from the app's local Pad Packs directory.
- System Check warns when pad and click resolve to the same output.
- Hardware routing is revalidated automatically through Core Audio device-change listeners.
- Playback and rehearsal are stopped visibly if a selected routed output disappears.
- Hardware/default routing changes prompt the user to keep current Sustain settings or switch pad/click to the detected output.
- Active playback and rehearsal are stopped before that prompt when hardware/default routing changes.
- Manual Audio Setup routing changes stop active playback and rehearsal so outputs can be rechecked before restart.
- Playback is blocked if Core Audio output-device assignment fails.

## What Is Still Prototype

- Bundled MP3s are development sample assets, not the final pad library.
- User-imported pad pack UI does not exist yet.
- Imported pad pack validation does not exist yet.
- Independent routing is implemented structurally but has not been validated on multiple real hardware outputs.
- Device disconnect recovery is implemented at the app-state level through Core Audio listener-driven routing refresh.
- Device reconnect recovery can rebind selected outputs by saved device name when Core Audio assigns a new device ID.
- Device reconnect recovery has not been validated across multiple real hardware combinations.
- Wake recovery now triggers an app-level routing recheck, but sleep/wake behavior has not been validated on real hardware.
- Long-running timing stability has not been measured.
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

### 2. User Pad Library

Add folder import for pad packs.

Expected folder shape:

```text
Warm/
├── C.wav
├── Db.wav
├── D.wav
└── ...
```

Success criteria:

- Import validates required keys.
- Missing keys are shown clearly.
- Imported songs use folder-backed pad assets during System Check and playback.
- Imported files persist across relaunch.
- System Check validates the cued song against imported files.

### 3. Duration Test

Run pad and click together for at least 30 minutes.

Observe:

- Click drift.
- Audio glitches.
- Memory growth.
- CPU usage.
- Behavior when display sleeps.

### 4. Listener Validation

The current monitor uses Core Audio property listeners for device-list and default-output changes. The implementation compiles under Swift concurrency using a small sendable relay back to the main actor, but it still needs real-hardware validation.

Success criteria:

- Device-list and default-output changes trigger routing refresh on real hardware.
- Listener registration and removal remain paired during app lifecycle.
- Existing playback-loss tests continue to pass unchanged.

## Product Rule

UX polish should wait until the audio engine can play real files, route outputs independently, and report hardware failures accurately.
