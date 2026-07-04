# Sustain

Sustain is a native macOS worship-leading utility for pads, click, count-off, and smooth song transitions.

The app is intentionally local-first, calm, and reliable. V1 focuses on helping a worship leader build a setlist, cue songs, start pads/click/countoff, and move through a service without needing production software.

## Run Locally

Open `Package.swift` in Xcode, or run:

```sh
swift run Sustain
```

On macOS 26+, to see the app in **Liquid Glass** (the default `swift run` links an
older SDK and shows the compatibility appearance), build against the macOS 26 SDK:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk swift run Sustain
```

## Build an app bundle

Produces `build/Sustain.app` (menu bar, icon, pads, ad-hoc signed). Real
distribution still needs a Developer ID signature + notarization.

```sh
./scripts/bundle.sh
```

## Verify

Requires the Xcode toolchain (swift-testing is not in the Command Line Tools SDK):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Credits

Included pad audio: **TODO — credit the pad creator before v1 release** (in this
README and where the asset catalog is defined). See
`docs/09_Production_Readiness_Checkpoint.md`.

## Product Guardrail

Every feature should answer:

> Does this directly help a worship leader run pads, click, countoffs, or transitions on Sunday morning?
