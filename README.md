# Sustain

**A calm, reliable macOS app for running pads, click, count-offs, and smooth song
transitions during live worship.**

Sustain helps a worship leader build a setlist, cue songs, and move through a
Sunday service — pads, click track, and count-offs — without needing production
software like Ableton. It's local-first and works fully offline: no account, no
cloud, no internet required.

---

## Download

**[⬇︎ Download the latest release](https://github.com/dillonlui/sustain/releases/latest)**
— grab `Sustain-<version>-<build>.dmg`.

Requires **macOS 14 (Sonoma) or newer**. Release downloads are Universal 2 and
run natively on both Apple-silicon and Intel Macs. Intel support is currently a
preview: it is covered by an Intel CI build and test run, but still needs
physical-hardware audio validation. See the [1.0.2 release notes](docs/releases/1.0.2.md).

### Install

1. Open the downloaded disk image and drag **Sustain.app** onto the
   **Applications** folder shown in its window.
2. Open Sustain. It is signed with a Developer ID certificate and notarized by
   Apple, so macOS can verify it normally.

Full installation instructions are in **[INSTALL.md](INSTALL.md)**.

---

## What it does

- **Song Library** — reusable songs with a default key, BPM, and time signature.
- **Setlist builder** — add and reorder reusable library songs.
- **Live Service screen** — see the playing and cued song at a glance; Start,
  Next, Previous, and Stop with clear transport controls and keyboard shortcuts.
- **Pads** — ambient pads in all 12 keys, with gapless looping and true
  crossfades between songs, plus a custom Pad Library that references your own
  mono or stereo audio files in place without copying or deleting them.
- **Click & count-off** — sample-accurate click generated from BPM and time
  signature, with spoken counts layered over audible beat clicks and an on-screen count-in.
- **Rehearse mode** — free-play pads, click, and count-off, with live level
  control, without touching your setlist.
- **MIDI controller mappings** — optionally learn MIDI Note On or Control
  Change messages for Start/Transition, cue navigation, Stop all, click, and
  the same context-aware pad action used by the Live screen.
- **Independent audio routing** — send pads and click to separate output devices;
  Sustain runs a System Check and warns you before a service if outputs are
  missing, shared, or misconfigured.
- **Reliable by design** — it never silently fails: playback is blocked with a
  clear message if a required output is unavailable, and your library is
  auto-saved with a rolling backup.
- **Native updates in official stable builds** — Sparkle's standard macOS flow
  supports manual checks and optional daily checks, but never silently installs.
  Checks and updater relaunch wait until Live and Rehearse audio are fully idle.

The first Sparkle-enabled release is a one-time bootstrap: users of earlier
builds must install its DMG manually because those builds contain no updater.
Development, ad-hoc, CI, branch, and unpublished builds never contact the stable
update feed.

### MIDI controller scope and troubleshooting

MIDI control is disabled by default and does nothing until you explicitly
enable it and learn mappings in **Settings > MIDI Controller**. Learned mappings
are locked to the controller's Core MIDI unique ID unless you deliberately
choose “Any controller.” Sustain accepts MIDI 1.0 Note On and Control Change
messages; it does not treat keyboard-emulating HID pedals as MIDI devices.

If a controller is not listed, open **Audio MIDI Setup**, confirm the device is
present and sending MIDI, then reconnect it or relaunch Sustain. USB and
Bluetooth controller compatibility varies by hardware and must be verified on
the signed app; no specific pedal model is claimed as supported without that
test evidence.

### What it is *not*

Sustain is deliberately focused. It is not a DAW, mixer, recorder, lyrics/chart
tool, or planning platform. Every feature answers one question:

> Does this directly help a worship leader run pads, click, count-offs, or
> transitions on Sunday morning?

---

## Building from source

Contributors and developers can build Sustain locally.

**Toolchain:** Xcode 26 (macOS 26 SDK) is supported — it provides Liquid Glass
and swift-testing. Make sure it's the active developer directory:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

The app deploys back to macOS 14 (compatibility appearance on macOS 14–25,
Liquid Glass on macOS 26+).

```sh
swift run Sustain      # run from source
swift test             # run the test suite
./scripts/bundle.sh    # build a Universal 2 app into ~/Applications (ad-hoc signed)
./scripts/package.sh   # build matching Universal 2 DMG + Sparkle ZIP into dist/
```

> Official GitHub releases are signed with a Developer ID certificate and
> notarized by Apple. Local builds remain ad-hoc signed unless you sign them with
> your own Developer ID identity.

---

## License

Sustain's parts are licensed **separately** — see [`NOTICE`](NOTICE) for the full
details:

- **Source code** — [MIT License](LICENSE). This is the only part covered by MIT.
- **Sparkle 2** — bundled under its upstream license; see
  [third-party acknowledgements](docs/THIRD_PARTY_ACKNOWLEDGEMENTS.md).
- **Pad audio** (`Sources/Sustain/Resources/Pads/*.mp3`) — “Ambient Pad Bases” ©
  Karl Verkade, all rights reserved by the artist; **not** MIT-licensed and no
  rights to it are granted here (see Credits).
- **Name & brand** — the “Sustain” name, app icon, and wordmark are © 2026 Dillon
  Lui, all rights reserved; **not** MIT-licensed.

## Credits

The included ambient pads are **“Ambient Pad Bases” by Karl Verkade** — ambient
guitar pads in all 12 keys — included with gratitude on the basis of the artist's
stated offer that they are free for church use. Sustain is a free, non-commercial,
church-use tool. The pad audio remains © Karl Verkade; see [`NOTICE`](NOTICE).

Please support the artist and buy the pads:
https://karlverkade.bandcamp.com/album/ambient-pad-bases

If you are Karl Verkade and would like the audio changed or removed, please open
an issue on this repository and it will be addressed.
