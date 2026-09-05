# Sustain 1.1.0 (unreleased)

This release adds a custom Pad Library, early-pad Live workflow, catalog-based
Rehearse surface, safer setlist clearing, and optional MIDI controller mappings.

Custom pads retain stable IDs and reference approved external audio files in
place. Sustain never deletes source audio. Songs can use an included pad, a
custom pad, or No Pad. Live playback now prepares files and click buffers before
an atomic activation, and a cued pad can be pre-rolled only while transport is
fully idle.

MIDI control is disabled by default. Settings can learn source-specific MIDI
1.0 Note On and Control Change mappings for Start/Transition, cue navigation,
Stop all, click, and the context-aware Live pad action. HID keyboard pedals are
outside this feature's scope. Physical USB/Bluetooth controller support remains
a release QA gate until recorded against a signed/notarized build.

Official stable Developer ID builds add Sparkle 2's standard native update
flow. Automatic checks remain opt-in and approximately daily; every install is
an explicit choice. Checks and updater relaunch defer while Live or Rehearse
audio is preparing, fading, or playing, and a failed library save blocks
relaunch. Development, ad-hoc, CI, branch, and unpublished builds do not start
Sparkle or contact the stable feed.

The first Sparkle-enabled build remains a one-time manual-install bootstrap for
users of older builds. Production publication is blocked until a real signed,
notarized lower-to-higher update succeeds through the staging feed and the
remaining signed-build, physical-audio/MIDI, accessibility, and failure-path QA
is recorded.
