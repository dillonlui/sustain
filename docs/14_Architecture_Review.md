# 14 — Architecture Review (Fork-in-the-Road Checkpoint)

**Date:** 2026-07-08 · **Branch:** `redesign-native` · Build clean, `swift test` 63 passing.

Prompted by the Live layout saga (docs/13): the user asked, before building further, "are there
other foundational decisions that will bite us like this one did?" This is the answer — a
whole-app audit across five dimensions (state/reactivity, audio real-time safety, Swift-6
concurrency, persistence/data-safety, testing/structure), each done as a deep read of the code.

---

## TL;DR

**The foundation is genuinely good** — better than a prototype has any right to be. Dependency
injection is exemplary (every side effect behind a protocol with live/fake impls), the domain
model is clean, strict concurrency is actually ON and the code compiles clean under it, audio
uses the safe pre-decoded-buffer path (no hand-rolled render callback), and persistence writes
atomically to the right macOS location. The 63 tests cover the scary live paths.

**But there is one systemic decision and a cluster of "silent data/audio loss" gaps to fix at
this fork, before more features pile on:**

1. **`AppStore` is a classic `ObservableObject` god-object → object-level invalidation.** This is
   the *same root* that produced the layout flip: any of 15 `@Published` fields changing
   re-renders every view. It will cause re-render storms the moment a level meter or position
   clock ships. **Fix: migrate to `@Observable`.** Highest-leverage change in the codebase.
2. **No persistence schema-versioning or backup → a future model change silently wipes users'
   libraries** and boots the demo seed. Plus save-failures are invisible.
3. **Pad Start can decode a multi-MB file synchronously on the main thread → UI freeze + late
   audio at the worst possible moment** (operator presses Start mid-service).
4. **Zero visual verifiability** (no SwiftUI previews, no snapshot tests, no headless mode) — the
   reason this session's UI verification was so painful.

Everything else is hardening, not emergencies. Details and priorities below.

---

## Priority 0 — do at this fork (foundational; cheap now, expensive later)

### P0.1 · Migrate `AppStore` off classic `ObservableObject` to `@Observable`
`RuntimeSession.swift:78-93` (15 `@Published`), consumed by every view via `@EnvironmentObject`.
With `ObservableObject`, SwiftUI invalidation is **per-object, not per-property** — any publish
re-evaluates every view body. This *is* the layout-flip mechanism (docs/13), and it's a latent
re-render storm: the day a VU meter or song-position clock publishes at 30–60 Hz, the whole tree
re-renders every tick mid-song. `@Observable` (Observation framework; fine on the macOS 14 /
Swift 6 baseline) gives property-level dependency tracking for free — a view reading only
`runtime.countoffBeat` stops re-rendering when `audioStatus` changes. DI and tests are unaffected
by the migration. **Corollary rule going forward:** any high-frequency signal (metering, position)
lives in its *own* small `@Observable`, never on `AppStore`.

### P0.2 · Add persistence schema-versioning + a rolling backup
`Persistence.swift:40-51`, load path `RuntimeSession.swift:1096-1112`. There is no
`schemaVersion` field; `songs`/`activeSetlist` decode with plain `decode`, so **any** breaking
model change throws on decode → the catch silently discards the real library and boots the seed
demo. Corrupt/failed loads quarantine the file (good) but there's **no automatic restore, no
backup, no recovery UI** — from the user's chair mid-Sunday, their whole library is gone,
replaced by three demo songs. Fixes: stamp a top-level `schemaVersion: Int` now (cheap while the
format is trivial); keep a rolling `Library.bak` and try it before falling to seed; surface a
recoverable alert instead of a silent reset.

### P0.3 · Never decode a pad inline on the main thread at Start
`AudioEngine.swift:193-198, 515-530`; `RuntimeSession.swift:803-806`. `startPad` → `loadPadBuffer`
does `AVAudioFile.read` on the main actor on cache miss — the assets are 10–15 MB MP3s (~100 MB
decoded), i.e. a hundreds-of-ms-to-second UI stall + late audio right when the operator presses
Start. The `preloadCuedPad` mitigation is best-effort and racy (cue-then-quick-start loses the
race). Fix: make Start never decode inline — await the in-flight preload (with a brief "loading
pad…" state) or gate Start on a pad-ready signal.

---

## Priority 1 — do soon (reliability + velocity)

### P1.1 · Surface save failures; add a quit/scenePhase flush
`RuntimeSession.swift:813-835`. `saveLibrary()` swallows write errors into a tiny status label —
disk-full/permission changes mean the user keeps editing believing they're saved, and loses work
on next launch. Escalate persistent failures to a visible signal + retry + in-memory dirty flag.
No save-on-quit backstop exists (relies on eager per-mutation saves); add a
`scenePhase`/terminate flush.

### P1.2 · Graceful audio-device-change recovery (don't hard-stop mid-song)
`RuntimeSession.swift:915-962`; `AudioEngine.swift:142-161`. Any route/device change calls
`stopAll()` → total silence, and the pad only resumes via manual Start **from the top of the
loop**. A bumped cable or Bluetooth blip kills the service audio. Distinguish "device I'm using
vanished" (must stop) from "device list changed but my outputs still exist" (keep playing);
attempt in-place restart with position resume for the transient case. Also add an
`AVAudioEngineConfigurationChange` observer (`AudioEngine.swift:115-118`) — currently the click
format is frozen at launch and config changes aren't observed.

### P1.3 · Add visual verifiability — SwiftUI previews + snapshot tests
No `#Preview` anywhere, despite a ready-made hardware-free `AppStore.preview()` factory
(`RuntimeSession.swift:1119`). This is the cheapest fix to the "driving the app is painful"
problem this session hit (Screen Recording perms, AX not surfacing SwiftUI, auto-lock). Add
`#Preview`s per view/state (mid-countoff, blocked readiness, route-change prompt, editor pane),
and snapshot tests over `AppStore.preview()` to make UI regressions diffable in CI. Highest ROI
for future development speed.

### P1.4 · Extract pure logic out of the `AppStore` god-object
`AppStore` is ~1000 lines / 40+ methods (`RuntimeSession.swift:77-1052`). Two pure blocks are
begging to be standalone testable types: a `SetlistReadinessValidator` (`validate` /
`setlistReadinessWarnings`, `:987-1050`) and a `RoutingSettingsNormalizer` (`:872-913`). Both are
already pure functions — extracting shrinks the god-object, drops the needless `@MainActor`
constraint, and lets tests hit them directly. Pairs naturally with P0.1.

---

## Priority 2 — hardening (correct today, fragile under change)

- **Pad buffer cache is unbounded** (`AudioEngine.swift:81,528,549-570`) — decoded PCM grows
  without eviction; a full service could accumulate >1 GB resident → paging risk mid-service.
  Add LRU/bounded eviction.
- **Cross-thread `AVAudioPCMBuffer` via `@unchecked Sendable`** (`AudioEngine.swift:549-570`):
  decoded off-main, consumed on main, scheduled on both crossfade players. Safe by the
  "immutable after decode" convention only — tighten the contract + document the invariant
  before anyone adds consumer-side buffer mutation.
- **`MainActor.assumeIsolated` in monitor `deinit`s** (`AudioHardwareMonitor.swift:20-24,72-76`,
  `PowerStateMonitor.swift:15-19`) — traps if the last release ever happens off-main. Prefer
  explicit `stop()` teardown over relying on ownership coincidence.
- **CoreAudio listener spawns per-event unstructured `Task { @MainActor }`**
  (`AudioHardwareMonitor.swift:140-149`) — no ordering guarantee under rapid device churn;
  idempotency saves it today but the route-change prompt can flap. Serialize via an `AsyncStream`
  drained by one task, or debounce.
- **Visual countoff drifts from the audible countoff** (`RuntimeSession.swift:718-743` vs the
  sample-accurate audio schedule) — the on-screen "1-2-3-4" is a separate `Task.sleep` clock.
  Drive the UI beat off the audio timeline (single source of truth for time).
- **Pad crossfade automation via `Task.sleep` on MainActor** (`AudioEngine.swift:329-344`) — 24
  coarse steps can zipper under UI load; use a sample-accurate ramp.
- **Force-unwraps on audio setup/render paths** (`AudioEngine.swift:118,309,401,456`) — hard
  crashes on odd hardware/format. Route through the existing `AudioEngineError` channel.
- **Persisted `AudioDeviceID`s are ephemeral** (`AudioRouting.swift:48-54`, `Persistence.swift:47`)
  — CoreAudio ids aren't stable across reboot/replug; persist the device UID string as the key,
  resolve the live id at launch (name already stored as fallback).
- **Dead `padPack` schema round-trips lossily** (`Persistence.swift:21-22,44-45,58-73`) — every
  song's `padPack` is normalized to `.bundled` on save/load; harmless now, silently eats custom
  pad-pack assignments the day they exist. Drop from the persisted model until packs are real.
- **`SustainAudioEngine` has zero tests** (`AudioEngine.swift:54-618`) — the highest-risk
  untested code. Extract the pure pieces (fade math, cache eviction, channel-mapping matrix,
  spoken-vs-click threshold) into free functions and unit-test them; script an on-device
  integration test for graph assembly.
- **Structure:** flat `Sources/Sustain` + a single 1365-line test file don't scale. Add folders
  (`Audio/`, `Persistence/`, `Models/`, `Views/`, `DesignSystem/` — free in SPM) and split tests
  by concern with a shared `TestSupport` for the fakes.
- **Design-system dead shims** (`SustainDesignSystem.swift:44-48,111-145`) — `glass*` tokens and
  `TopographicFieldView`/`AudioPatternView` render nothing; delete or gate behind a clear TODO.

---

## What's actually solid (don't "fix" these)

- **Dependency injection is exemplary.** Six protocols (`AudioControlling`,
  `AudioRoutingProviding`, `AudioHardwareMonitoring`, `PowerStateMonitoring`,
  `CountoffVoiceRendering`, `PadAssetResolving`) with init-default injection + `AppStore.live()` /
  `.preview()` factories. 63 tests run on fakes, no hardware.
- **Strict concurrency is genuinely ON and clean.** Swift 6 language mode, complete checking;
  `AudioEngine`/`CountoffVoice`/`RuntimeSession` recompile with zero warnings. All state is
  `@MainActor`-confined; every non-main callback is explicitly hopped. The `@unchecked Sendable`
  types each wrap a real lock. Async code re-validates after `await` and uses generation counters
  against reentrancy — correct patterns, applied uniformly.
- **Audio real-time strategy is right.** `AVAudioPlayerNode` + pre-decoded PCM buffers → no
  render-thread allocation/locking/ARC. The metronome is sample-accurate (looped one-measure
  buffer, zero cumulative drift); the spoken countoff is scheduled on the same node; pad looping
  is gapless; transitions are a real A/B crossfade with careful teardown-race handling
  (generation counters).
- **Persistence write path is sound.** Atomic writes, correct `Application Support/Sustain`
  location, corrupt files quarantined not overwritten, additive fields use `decodeIfPresent` with
  defaults, ids are stable `UUID`s preserved across edits, no `deleteSong` path so no orphaned
  setlist refs today.
- **Domain model + readiness logic** are explicit, readable, and well-tested; the
  `setXVolumeLive`/`commit` debounce split is exactly the right instinct.

---

## Suggested sequencing at this fork

1. **Now, with the layout work:** P0.1 (`@Observable`) — it's the same disease as the layout bug
   and everything else gets cleaner behind it.
2. **Next small PR:** P0.2 (schema version + backup) and P0.3 (no inline pad decode) — the two
   "silent loss" gaps (data, audio).
3. **Then, to speed all future UI work:** P1.3 (previews + snapshot tests).
4. P1/P2 hardening as features touch those areas.

Nothing here blocks shipping the current redesign; these are about not building the next layer on
a soft spot. The soft spots are few and named.
