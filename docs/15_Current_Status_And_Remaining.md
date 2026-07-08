# 15 — Current Status & Remaining Work

**Date:** 2026-07-08 · **Branch:** `redesign-native` · Build clean · `swift test` **69 passing** · working tree per commit history.

This is the running handoff snapshot. Deep detail lives in `docs/13` (layout resolution) and
`docs/14` (architecture review + per-item status).

---

## Where we are

The Live layout instability is **fixed** (custom paned `HStack`, `.hiddenTitleBar` restored;
root cause was two independent triggers — `NavigationSplitView` and `.inspector`). On top of
that, this session cleared **all P0, all P1, and most P2** from the architecture review:

- **State:** `AppStore` migrated to `@Observable` (property-level tracking; killed the whole-app
  re-render that fed the layout bug and future meter/position storms).
- **Data safety:** persistence schema-versioning + rolling `Library.bak` recovery; save-failure
  retry + dirty-flag + blocking alert + scene-phase flush.
- **Audio reliability:** pad decode moved off the main thread at Start; bounded LRU pad cache;
  guarded throws replacing fatal force-unwraps; keep-playing through unrelated device changes;
  smoother crossfade ramp.
- **Concurrency:** coalesced CoreAudio hardware events (no prompt flapping); non-trapping
  monitor deinits; documented the `@unchecked Sendable` buffer contract.
- **Structure/verifiability:** SwiftUI previews for every screen + key states; source split into
  concern folders; test fakes → `TestSupport`; the monolithic test file split by concern.
- **Cleanup:** removed dead design-system shims; extracted `RoutingSettingsNormalizer` +
  `SetlistReadinessEvaluator` from the god-object.

Regression at this snapshot: `swift build` clean, `swift test` 69 passing, app drives correctly
(Live/Rehearse/Song Library render; play/stop/transition; editor pane; legacy library loads).

---

## What remains

### Real-gear work (deliberately not shipped blind — see docs/14 for rationale)
These need a real audio interface to verify **correctness** (not just feel); a blind
half-implementation risks silencing a live service without me being able to observe it.
- **Countoff driven off the audio clock** — engine→store per-beat callbacks; verify the visual
  beat tracks the audible click on real output.
- **Config-change observer + reconfigure-and-resume across an output-ID replug** (the P1.2
  leftover) — re-establish the running graph and resume playback; needs device hot-plug to test.

### Deferred (low ROI right now)
- **Persisted device UID** — the resolver already recovers a device *by name* on ID change
  (tested), so UID only adds duplicate-name robustness for real model/selection/migration churn.
- **Drop the dead `padPack` persisted schema** — harmless today (always `.bundled`); round-trip
  faithfully when custom pad packs are actually built.

### Done since
- ✅ **Live layout spacing polish** — root cause was the pane `HStack` respecting the window top
  safe area (borders didn't reach the top) plus an extra top padding on the detail only (main
  sat ~28px below the nav, unaligned). Fixed with one rule: `HStack.ignoresSafeArea(.top)` so
  panes/dividers fill to the physical top, and a single `SustainLayout.topChrome` content inset
  applied uniformly (sidebar brand, setlist header, NOW/NEXT, Rehearse/Song-Library headers) so
  all top content aligns; plus Add-Song bottom padding. Verified by pixel probe.

---

## Suggested next steps
1. Finish the Live spacing polish (small, principled top-inset/alignment fix).
2. Pair on real gear for countoff-sync + config-change/replug-resume.
3. Revisit device-UID + `padPack` only if/when duplicate device names or custom pad packs become real.
