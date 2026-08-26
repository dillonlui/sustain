# Slice 00A — Signed Sandbox and Capability Spike

## Goal

Choose the actual distribution security model before external-file development,
using the same signing/entitlement path that release builds will use.

## Work

1. Add an experimental entitlements file and teach the SwiftPM bundle script to
   sign with explicit entitlements in development and Developer ID modes.
2. Start with least privilege: App Sandbox, user-selected read-only files, and
   app-scoped bookmarks. Add Bluetooth/USB capabilities only when a verified
   Core MIDI path needs them; do not add audio-input permission because Sustain
   does not record audio.
3. In one signed spike (using a minimal Core MIDI probe if the feature has not
   landed), verify included pad/click output, external Core Audio
   routing, open-panel import, in-window Finder drop, bookmark relaunch, USB
   MIDI discovery/input, Bluetooth MIDI discovery/input, sleep/wake, and device
   reconnect.
4. Inspect the built signature/entitlements and sandbox status, not only source
   configuration. Record OS, hardware, controller, signature type, and results.
5. Prefer the sandboxed configuration if every critical live path passes. If it
   cannot, document the precise failure and retain the direct-notarized
   unsandboxed distribution rather than adding broad or temporary exceptions.

## Acceptance

- The tracker records one chosen entitlement/distribution model with evidence.
- `bundle.sh` and release packaging cannot silently sign with a different
  entitlement set.
- File access works after relaunch in the chosen configuration.
- Core Audio routing and physical USB/Bluetooth MIDI behavior are verified, or
  the exact unavailable hardware QA is explicitly carried to Slice 08.
- Slice 02 does not begin while the security model is undecided.

## Apple references

- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
