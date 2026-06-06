# Day 1 Implementation Notes

## Completed Slice

The app now has a working technical foundation for the first live-service loop:

- Live store loads from local JSON persistence or falls back to seed data.
- Setlist key and BPM overrides save to `Library.json`.
- Live Service controls call an audio controller instead of only flipping UI state.
- Bundled MP3 pad audio loops indefinitely.
- Generated click audio follows song BPM.
- Click always starts with a countoff state before moving to playing.
- Failed transition validation preserves the currently playing entry.
- Live Service, Audio Setup, Setlist, and System Check show runtime status.

## Audio Approach

Day 1 originally proved the engine with generated audio. The current implementation now plays bundled MP3 pad files:

- Pads are resolved from `Resources/Pads/<Key> Major.mp3`.
- The engine loads the matching MP3 with `AVAudioFile`.
- Click and countoff are generated as scheduled PCM buffers.
- Pad transitions use two player nodes with mixer-volume fades.
- Click and pad use separate engine instances and can be assigned separate output devices.

This proves the file-backed pad path, but it is not yet the final user-imported pad library. The bundled MP3s are development/sample assets.

## Persistence Approach

Day 1 uses file-based JSON persistence in Application Support:

```text
Application Support/Sustain/Library.json
```

Persisted data:

- Songs
- Active setlist
- Key overrides
- BPM overrides

SwiftData or SQLite should wait until the editing model gets more complex.

## Still High Risk

The next technical spike should focus on real audio devices:

- Real-hardware verification of independent pad and click output routing.
- Device disconnect and reconnect behavior.
- Sleep/wake recovery.
- User-imported WAV pad packs.
- Glitch-free crossfade with real files.
- Long-running timing stability over a full service.

## Current Guardrail

Do not add more production features until the app can prove independent routing on real hardware and survive basic device changes.
