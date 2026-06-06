# Production Readiness Checkpoint

## Current Foundation

The app now has the first production-shaped audio path:

- Pads are real WAV files bundled with the app.
- Pad lookup is based on pad pack and musical key.
- Missing pad files block playback during system check.
- Pad transitions use two player nodes and mixer fades.
- Click and countoff are generated from BPM and time signature.
- macOS output devices are enumerated through Core Audio.
- Pad and click now use separate AVAudioEngine instances.
- Audio Setup can select separate pad and click output devices.
- Routing selections persist across relaunch.
- System Check warns when pad and click resolve to the same output.

## What Is Still Prototype

- Bundled WAVs are development sample assets, not the final pad library.
- User-imported pad packs do not exist yet.
- Independent routing is implemented structurally but has not been validated on multiple real hardware outputs.
- Device disconnect/reconnect recovery is not implemented.
- Sleep/wake recovery is not implemented.
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

## Product Rule

UX polish should wait until the audio engine can play real files, route outputs independently, and report hardware failures accurately.
