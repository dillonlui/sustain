# Sustain 2.0.0

Sustain 2.0 refreshes the Live and Rehearse screens with a consistent visual
system while keeping the performance controls and keyboard shortcuts familiar.

Advanced click settings now support per-song subdivisions, beat accents and
mutes, grouped pulses for compound meters, and zero-, one-, or two-bar count-ins.
Rehearse has independent click settings. A count-in-only option stops the click
after the count-in while pads continue. Tap tempo is available in Rehearse and
for a cued Live song; a Live tempo stays in the current session until saved as
the song default.

Live and Rehearse include clearer route information, pending click changes,
and explicit warnings when required outputs are unavailable. Custom pads and
optional MIDI controller mappings remain available.

## Before a service

Check pad and click routing in Settings, run System Check, and rehearse the
setlist with the audio devices and MIDI controller you will use live.

This release requires macOS 14 or newer. Official downloads are signed and
notarized Universal 2 apps for Apple silicon and Intel Macs.

## Testing scope

The signed 1.1.2 → 2.0 Sparkle update was exercised on an Apple silicon Mac,
including installation, relaunch, and migration of a test library. Apple silicon
and Intel CI and Universal 2 package checks passed. Physical Intel hardware,
USB/Bluetooth MIDI controllers, external audio interfaces and file locations,
Live/Rehearse playback on representative hardware, assistive-technology
workflows, and updater failure paths have not completed manual QA for this
release.

## Updating to 2.0

If you have 1.1.2 installed, use **Sustain → Check for Updates…** to update to
2.0. Automatic checks are optional, and installing always requires your choice.
Sustain 1.1.1 contains an updater activation bug, so first install 1.1.2 from
its disk image. Older versions also require a manual disk-image install.
