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
— grab `Sustain-<version>.zip`.

Requires **macOS 14 (Sonoma) or newer**.

### Install

1. Unzip and drag **`Sustain.app`** into your **Applications** folder.
2. On first launch macOS will block it (Sustain isn't distributed through the App
   Store). Approve it once via **System Settings → Privacy & Security → Open
   Anyway** — or on macOS 14, **right-click the app → Open**.

Full step-by-step instructions (including a fix if it still won't open) are in
**[INSTALL.md](INSTALL.md)**.

---

## What it does

- **Song Library** — reusable songs with a default key, BPM, and time signature.
- **Setlist builder** — add and reorder songs; override key or BPM per service.
- **Live Service screen** — see the playing and cued song at a glance; Start,
  Next, Previous, and Stop with clear transport controls and keyboard shortcuts.
- **Pads** — ambient pads in all 12 keys, with gapless looping and true
  crossfades between songs.
- **Click & count-off** — sample-accurate click generated from BPM and time
  signature, with an audible and on-screen count-off.
- **Rehearse mode** — free-play pads, click, and count-off, with live level
  control, without touching your setlist.
- **Independent audio routing** — send pads and click to separate output devices;
  Sustain runs a System Check and warns you before a service if outputs are
  missing, shared, or misconfigured.
- **Reliable by design** — it never silently fails: playback is blocked with a
  clear message if a required output is unavailable, and your library is
  auto-saved with a rolling backup.

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
./scripts/bundle.sh    # build Sustain.app into ~/Applications (ad-hoc signed)
./scripts/package.sh   # build + zip a distributable into dist/
```

> Downloads are ad-hoc signed, not notarized (notarization requires a paid Apple
> Developer ID). That's why the first-launch approval step above is needed. It
> does **not** require the Mac App Store.

---

## License

Sustain's parts are licensed **separately** — see [`NOTICE`](NOTICE) for the full
details:

- **Source code** — [MIT License](LICENSE). This is the only part covered by MIT.
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
