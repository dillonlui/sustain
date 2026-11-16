# Sustain 2.0.3

This update improves audio-output isolation, saves song and rehearsal edits more
reliably, and adds a way to restart audio without rebuilding your setup.

## Audio routing and recovery

- Pad and metronome single-channel routes now use explicit output-channel maps
  instead of pan controls. Unselected outputs are silenced, and stereo pads are
  folded to mono when assigned to a single output.
- Playback checks the selected device and channel mapping before activation and
  after engine startup, including after audio preparation. Detected routing
  mismatches stop playback rather than continuing on an unexpected output.
- **Restart Audio** is available in Audio Settings. It stops playback, rebuilds the
  audio connection, and reapplies your selected devices and channels. Your output
  settings are kept, playback remains stopped, and the screen shows the restored
  routes or an error. **Refresh Devices** remains available to rescan hardware.

## Saving and persistence

- Song BPM edits save even when the tempo input still has focus.
- Rehearsal beat accents, countoff choices, and click-sound settings persist across
  launches, along with tempo, meter, pulse interpretation, and subdivision.
  Playback itself is never restored automatically.
- Failed song saves keep the editor open and retain the edit for retrying.
  Repeated save attempts do not create duplicate songs.
- Retrying a failed tempo-default save now keeps the requested BPM.
- Libraries that cannot be recovered remain protected across relaunches instead
  of being mistaken for a new installation and replaced with the starter library.
- A failed rehearsal click update no longer freezes countoff progress. Failed
  replacement activation clears the playback state so it can be restarted.

## Verification still needed

The reported intermittent click bleed on a Focusrite Scarlett motivated these
routing changes. Automated audio-sample tests and local device checks pass, but
**physical isolation on the Scarlett has not yet been verified**, and the exact
cause of the original incident has not been established.

Before using this update in a service, rehearse with your interface and confirm
that pad and metronome reach only their assigned outputs. For the reported setup,
check **Pad → Output 2** and **Metronome → Output 1**, including after relaunching or
reconnecting the interface. Use **Restart Audio** if the audio connection behaves
unexpectedly, then verify the outputs before resuming playback.

The release still needs physical Scarlett output recordings and an end-to-end
update check on the installed signed build. Physical Intel hardware, external MIDI
controllers, and assistive-technology workflows have not been manually validated
for this release. Automated tests do not replace these hardware checks.

## Updating

Use **Sustain → Check for Updates…**, or download the disk image and drag Sustain
into Applications. Requires macOS 14 or newer. Official downloads are signed and
notarized Universal 2 apps for Apple silicon and Intel Macs.
