# Duration Test Checklist

Use this before calling the audio path production-reliable. The goal is to prove that pads, click, routing, and app state remain stable during a realistic service-length run.

## Setup

- Plug in the hardware outputs you want to validate.
- Set macOS sleep settings so the computer does not sleep during the timed run.
- Select separate pad and click outputs in Sustain when available.
- Run System Check and resolve blocking messages before starting.
- Start with Activity Monitor visible for Sustain CPU and memory.

## 30-Minute Run

- Start a song with pad and countoff/click active.
- Leave playback running for 30 minutes.
- Every 5 minutes, note CPU, memory, routing labels, and audible click/pad behavior.
- Cue the next song at least twice during the run.
- Stop and restart click at least once.
- Stop and restart pad at least once.

## Hardware Events

Run these as separate passes after the baseline 30-minute pass succeeds:

- Change macOS default output during playback.
- Unplug or disconnect the selected pad output during playback.
- Unplug or disconnect the selected click output during playback.
- Lock the screen while playback continues.
- Wake the display after it sleeps without system sleep.

## Pass Criteria

- Pads do not glitch, stop unexpectedly, or drift in volume.
- Click remains steady and does not audibly drift against the pad.
- Routing labels continue to match the actual audible outputs.
- Hardware changes stop/prompt/block clearly instead of silently rerouting.
- CPU and memory remain stable enough for a full service-length run.
- After any failure or disconnect, restarting requires an explicit user action.

## Record

For each run, record:

- Date and app commit SHA.
- macOS version and machine.
- Pad output device.
- Click output device.
- Any Bluetooth devices involved.
- Total run length.
- CPU and memory range.
- Failures, prompts, or unexpected output changes.
