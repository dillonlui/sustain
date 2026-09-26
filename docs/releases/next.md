# Sustain 1.1.2

This maintenance release fixes the Developer ID signature check that prevented
the public 1.1.1 app from starting Sparkle. Although 1.1.1 included Sparkle,
its **Check for Updates…** command was hidden and automatic checks could not
run. Install 1.1.2 from the notarized DMG once to enable future in-app updates.

The library format and user-facing features are unchanged from 1.1.1. Songs,
setlists, custom pads, MIDI mappings, and preferences remain in place. Automatic
update checks are opt-in, and every update installation remains an explicit
choice.

## Features carried forward from 1.1.1

The 1.1.1 line added a custom Pad Library, early-pad Live workflow, catalog-based
Rehearse surface, safer setlist clearing, and optional MIDI controller mappings.

Custom pads retain stable IDs and reference approved external audio files in
place. Sustain never deletes source audio. Songs can use an included pad, a
custom pad, or No Pad. Live playback now prepares files and click buffers before
an atomic activation, and a cued pad can be pre-rolled only while transport is
fully idle.

MIDI control is disabled by default. Settings can learn source-specific MIDI
1.0 Note On and Control Change mappings for Start/Transition, cue navigation,
Stop all, click, and the context-aware Live pad action. HID keyboard pedals are
outside this feature's scope.

## Known testing limitations

MIDI controller support has automated coverage but has not been exercised with
a physical USB or Bluetooth MIDI controller. Intel compatibility passes the
full automated test, Universal 2 packaging, launch-smoke, and artifact-validation
jobs on GitHub's Intel macOS runner, but this release has not been used on a
physical Intel Mac. Real audio interfaces, removable and cloud-hosted external
files, and assistive-technology workflows also have not completed manual QA.
These limitations are accepted for 1.1.2 and are not claims of verified hardware
compatibility.

Official stable Developer ID builds add Sparkle 2's standard native update
flow. Automatic checks remain opt-in and approximately daily; every install is
an explicit choice. Checks and updater relaunch defer while Live or Rehearse
audio is preparing, fading, or playing, and a failed library save blocks
relaunch. Development, ad-hoc, CI, branch, and unpublished builds do not start
Sparkle or contact the stable feed.

This corrective build is a one-time manual install for users of 1.1.1 and
older builds. The physical-device and manual QA items above are explicitly
deferred rather than represented as passed.
