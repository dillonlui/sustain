# Audio routing release check

The reported failure was click bleeding into the pad/main-speaker output on a
Focusrite Scarlett. Pad output 2 and click output 1 eventually worked after
repeated channel changes. The exact failing lifecycle has not been reproduced.

The implementation replaces pan routing with a mono mixer output and an explicit
hardware channel map for exclusive routes. Startup remains silent until the
channel map passes readback; click rendering begins afterward to preserve beat one.
This addresses a plausible stale routing path, but does not establish the cause of
the original incident or prove physical output isolation.

## Automated coverage

Run `swift test`. OutputChannelSignalTests renders PCM through an Apple converter
using the same map application as the device output. At 44.1 and 48 kHz, test mono
left, mono right, stereo, repeated route changes, and converter resets, with two
and four destination channels. Assert expected samples on selected outputs and
zero samples on every unselected output.

Run `SUSTAIN_TEST_HARDWARE=1 swift test --filter SessionBugRegressionTests` to check
actual output-unit property retention across configuration, prepare, and silent
click-engine startup. This selects the first available stereo output, not
necessarily the Scarlett, and does not record its physical outputs.

## Physical Scarlett acceptance gate

Record outputs 1 and 2 separately through a second interface or a hardware loopback
with monitoring disabled, so the recording cannot feed back into the output.
Record the Scarlett model, macOS version, app build, sample rate, and routing.
Use the installed release-shaped build with saved settings, not just unit tests.

For both pad 2 / click 1 and pad 1 / click 2:

1. Cold-launch with the Scarlett already connected and start without touching settings.
2. Record pad only, click only, spoken countoff without pad, then pad plus click/countoff.
3. Stop and restart repeatedly; transition songs and crossfade pads in Live; repeat in Rehearse.
4. Quit and reopen with routes saved, including a launch after another output was the system default.
5. Disconnect/reconnect the Scarlett while idle, then while playing. Check that unavailable
   routes stop playback and that recovery preserves the selected channel assignments.
6. Sleep/wake and change the interface sample rate between 44.1 and 48 kHz.
7. Change left/right and stereo selections repeatedly, then return to each split assignment.

Pass only if the intended output has the source, the opposite output has no
source-correlated bleed above the measured recording noise floor, and the first
countoff beat remains intact. Retain recordings and measured levels. No scenario
may require toggling channels to restore separation. Do not call this fix verified
on Scarlett until this gate passes.

## Recovery UX

Refresh Devices rescans. Restart Audio is a separate action with
"Stops playback and reconnects your selected outputs." Restart Audio stops and resets both engines, disconnects the output graph, and
rebuilds the output connections with the saved routes. It preserves device/channel
choices and reports unavailable exclusive routes without falling back to stereo.
Playback stays stopped; the UI displays the resulting Pad and Metronome routes
or a specific reconnect error. Include this action in the physical acceptance gate. Property readback
may establish that configuration succeeded; it must not be presented as proof of
physical isolation. A restore-defaults action, if added, is a separate intentional
configuration reset, not the recovery mechanism or a substitute for this fix.
