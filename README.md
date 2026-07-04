# Sustain

Sustain is a native macOS worship-leading utility for pads, click, count-off, and smooth song transitions.

The app is intentionally local-first, calm, and reliable. V1 focuses on helping a worship leader build a setlist, cue songs, start pads/click/countoff, and move through a service without needing production software.

## Requirements

Xcode 26 (macOS 26 SDK) is the supported toolchain — it provides Liquid Glass and
swift-testing. Make sure it's the active developer directory:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

The app still deploys back to macOS 14 (it renders in the compatibility appearance
on macOS 14–25, Liquid Glass on macOS 26+).

## Run Locally

Open `Package.swift` in Xcode, or run:

```sh
swift run Sustain
```

## Build an app bundle

Produces `build/Sustain.app` (menu bar, icon, pads, ad-hoc signed). Real
distribution still needs a Developer ID signature + notarization.

```sh
./scripts/bundle.sh
```

## Verify

```sh
swift test
```

## Credits

Included pad audio: **TODO — credit the pad creator before v1 release** (in this
README and where the asset catalog is defined). See
`docs/09_Production_Readiness_Checkpoint.md`.

## Product Guardrail

Every feature should answer:

> Does this directly help a worship leader run pads, click, countoffs, or transitions on Sunday morning?
