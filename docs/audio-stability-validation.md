# Audio stability follow-up

The intermittent report of pads and click briefly sharing an output has not been
reproduced with a physical interface. AV routing, cables, and interface reconnects
remain possible causes; the code findings below do not prove the cause of that event.

## Code fixes

- Resolve a saved device ID only if its saved name also matches. A reused Core Audio
  ID must not silently select an unrelated device; recover the intended device by name.
- Reconfigure routes before idle playback even when the pad engine is still running
  after its last player stopped.
- Poll alongside hardware notifications, because an existing device's channel count
  or sample rate can change without a device-list/default-output notification.
- Compare used-device formats and actual audio-unit output assignments/channel pan.
  A detected routing mismatch stops playback and requires an intentional restart;
  unrelated default-output changes leave explicitly selected, unchanged routes playing.
  Polling is a two-second backstop, not a guarantee of zero transient misrouting.
- Validate missing/failed routes before starting Rehearse audio too.
- Wait for each pad's actual volume ramp to finish before stopping its player. Stop
  fades both players if a crossfade is underway; ramps use absolute deadlines to
  avoid accumulating timer drift. Rehearse reports fading activity during Stop.
- Keep Rehearse levels, accent mode, and countoff sound in session state. Starting
  Live restores its own levels and sound settings. Rehearse edits are not saved as
  Live defaults. Navigation alone continues existing audio until a transport action.

## Physical interface acceptance checks (not yet performed)

1. Route pad to output 1 and click/countoff to output 2. Verify isolation at the
   physical outputs in both modes, including countoff, transitions, and pad-only pre-roll.
2. Stop during pad fade-in, steady playback, and a crossfade. Repeat Stop and verify
   a smooth fade with no abrupt ending. Repeat with a busy UI.
3. Change Rehearse levels, accent, countoff sound, BPM, and subdivision; start Live
   and verify its own settings. Return to Rehearse and verify its session settings.
4. Unplug/reconnect the interface and change sample rate/channel configuration in
   Audio MIDI Setup. Verify a clear stop/block, preserved selections, and correct
   routing after an intentional restart. Also test reconnect while idle after Stop.
5. Change the system default while explicitly selected outputs remain connected.
   Playback should continue on the chosen outputs.

Device loss, engine reconfiguration, app termination, and failures outside Sustain
can interrupt sound; the smooth-fade guarantee concerns normal transport Stop.
