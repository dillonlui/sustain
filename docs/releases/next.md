# Sustain 2.0.1

A maintenance release focused on reliable playback and a clearer installation experience.

## Installation

The disk image now opens with large Sustain and Applications icons, a clear drag
arrow, and a designed background explaining how to install and open the app.

## Playback and routing

- Stop fades pads to silence before stopping their players, including both voices
  during a song crossfade.
- Rehearse volume, click accent, and countoff sound stay separate from Live settings.
- Routing is restored before idle restarts and checked for device, channel, and
  sample-rate changes. Detected routing faults stop playback with a message so the
  operator can check outputs and restart intentionally.
- Rehearse blocks playback on unavailable routes. Failed audio activation no longer
  leaves an untracked pad playing, and audible pre-roll entries cannot be deleted.

## Library and MIDI fixes

- Pad undo/redo preserves later song edits and catalog changes.
- Libraries saved by a newer app version are preserved rather than replaced with
  older backups when their format changes.
- Custom-pad relinking handles concurrent reordering and renaming.
- Quick MIDI CC presses retain their press/release edges, and overlapping Any
  Controller/device-specific mappings are rejected.

## Updating

Use **Sustain → Check for Updates…**, or download the disk image and drag Sustain
into Applications. Requires macOS 14 or newer. Official downloads are signed and
notarized Universal 2 apps for Apple silicon and Intel Macs.

## Testing scope

Automated regression tests cover the fixes above. The intermittent live report of
pads and click sharing an output has not been reproduced with a physical interface;
these fixes do not establish its cause. External audio interfaces, physical MIDI
controllers, Intel hardware, assistive-technology workflows, and this release's
end-to-end Sparkle update still require manual validation. Check routing and
rehearse with your performance hardware before a service.
