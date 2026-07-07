# 12 — Settings Consolidation Plan

**Goal:** Remove the **Audio Setup** and **System Check** sidebar screens. Move audio
routing + diagnostics into the native macOS **Settings** window (⌘,), and convert System
Check into an automatic, background **readiness safety-net** surfaced on the Live Service
screen. Sidebar goes from 5 items to 3 (Live Service · Rehearse · Song Library).

**Status:** Implemented 2026-07-07 (see `docs/superpowers/plans/2026-07-07-settings-consolidation.md`).

---

## Decisions (locked)

1. **Preferences location:** the macOS **Settings** window (⌘,), tabbed. Not a new sidebar item.
2. **System Check:** the standalone page is **dropped**. Its *validation* becomes an automatic
   safety-net that runs on entering Live Service and on relevant system changes, and only
   *surfaces* when something is wrong — quiet otherwise, never disruptive during playback.
3. **Audio Setup:** routing controls + device/engine diagnostics move into the Settings **Audio** tab.

### Banner scope (confirmed)
- **Blocking errors** → prominent warning-tinted `SustainInlineNotice` on the Live surface.
- **Non-blocking warnings** → stay on the subtle `LiveRoutingBadge` only; no banner.
- This maps directly onto the existing model: `validate()` already returns
  `SystemCheckResult(canStartPlayback:, messages:, warnings:)` — blocking messages drive the
  banner, `warnings` drive the badge. No model changes needed.

---

## Current state (as of this plan)

- **`AppScreen`** (`RuntimeSession.swift:5`): `.live .rehearse .songs .audio .check`.
- **`RootView`**: `selectedScreen` switch + `backgroundMood` switch + `icon(for:)` all enumerate the 5 cases.
- **`SidebarView`** iterates `AppScreen.allCases` — auto-updates when cases are removed.
- **`SustainApp`**: `Settings { AppSettingsView() }` (appearance-only). Commands: "Run System Check"
  (⌘⇧K), `Go` menu maps ⌘1…⌘N to `AppScreen.allCases`.
- **`AudioSetupView`** (`LibraryViews.swift:244–535`): routing summary, pad/click route panels
  (device + channel pickers via `store.updateRouting`), detected-devices list, engine panel.
  Helpers: `AudioDeviceDiagnosticRow`, `RouteSignalView`, `DiagnosticLine`.
- **`SystemCheckView`** (`LibraryViews.swift:609–744`): readiness panel + checks list + runtime
  readout. Helper: `CheckMessageRow`.
- **`RuntimeSession`** already owns the reusable logic:
  - `validate(entry:song:)` (`:977`) — **pure** (no side effects); returns
    `SystemCheckResult(canStartPlayback:, messages:, warnings:)`, already splitting blocking
    messages from warnings. Safe to call on any event. **Use this for the safety-net.**
  - `runSystemCheck()` (`:681`) — **heavy**: calls `audioEngine.prepare()` + `configureAudioRouting()`
    + status refresh. **Do NOT auto-trigger** (audio-glitch risk mid-service). Manual/explicit only.
  - `handleAudioHardwareChanged(...)` (`:905`) — already refreshes the snapshot and re-runs
    `validate` on real hardware changes, publishing `systemCheck`. The hardware trigger already exists.
  - `@Published systemCheck` (`:87`), `refreshAudioDiagnostics()` (`:639`, snapshot-only, safe),
    `routingSettings`, `routingSnapshot`, `updateRouting(...)`.
- **`selectedScreen`** (`:81`) is **in-memory only** (`@Published`, default `.live`) — not persisted.
  Removing enum cases carries **no migration/restore risk**.
- **`LiveServiceView.messageStrip`** (`:323`) already renders `routingSnapshot.hasUnavailableSelection`
  via `SustainInlineNotice` + `LiveRoutingBadge` — the surface to extend.

---

## Phase 1 — Settings window (⌘,) → tabbed

**Files:** `SustainApp.swift`, `LibraryViews.swift`, (new) settings views.

1. Convert `AppSettingsView` into a `TabView` using native Settings idioms:
   - Each tab uses `.tabItem { Label("General", systemImage: "gear") }` / `Label("Audio", systemImage: "speaker.wave.2")`
     so macOS renders the standard toolbar-tab preferences chrome.
   - Each tab is a `Form` with `.formStyle(.grouped)`; give the window a **fixed content width**
     (e.g. `.frame(width: 460)`) and let height fit per tab. Avoid a large scrolling panel.
   - **General** tab: existing Appearance picker.
   - **Audio** tab: port `AudioSetupView`'s content, reworked from the `SustainScreenHeader` + panel
     layout into Form sections:
     - Pad/Click **device** + **channel** pickers → `Picker` rows (reuse the existing binding
       helpers `padOutputBinding`, `clickOutputBinding`, `padChannelBinding`, `clickChannelBinding`
       and `store.updateRouting`).
     - Routing summary/warning → a header section (`routeStatusTitle`, `routingSnapshot.summary`,
       `SustainInlineNotice` for `warning`).
     - Detected devices → a section using `AudioDeviceDiagnosticRow`.
     - Engine/format diagnostics → a section using `DiagnosticLine`.
     - "Refresh Devices" → a button calling `store.refreshAudioDiagnostics()`.
     - **Refresh the device list when the Audio tab appears** (`.task`/`.onAppear` →
       `store.refreshAudioDiagnostics()`) so it's current on open. Snapshot-only — **do not**
       reconfigure the engine here.
2. **Inject the store into the Settings scene** — environment objects do NOT auto-propagate to
   the `Settings` scene: `Settings { AppSettingsView().environmentObject(store) }`.
3. **Appearance robustness (optional hardening):** the just-added `applyAppearance()` lives in
   `RootView` (`.onChange(of: appearanceRaw)`). For a single-window app the main window is always
   alive while Settings is open, so it fires. Optionally also apply from the General tab's
   `.onChange` so appearance updates even if the main window were ever closed.

**Verify:** ⌘, opens a tabbed window (General/Audio); changing a device/channel updates routing and
persists (reflected in the Live routing badge); tab switch doesn't jump size jarringly; Appearance
still works and System follows the OS live.

---

## Phase 2 — Live Service automatic readiness safety-net

**Files:** `RuntimeSession.swift`, `LiveServiceView.swift`.

1. **Add a lightweight `refreshReadiness()` to `RuntimeSession`** — validate-only, no engine work:
   - If a song is cued: `systemCheck = validate(cuedEntry, cuedSong)`.
   - If not: set a **neutral** state (e.g. `SystemCheckResult.notRun`) — "no song cued" is normal,
     not a fault.
   - Must NOT call `audioEngine.prepare()` / `configureAudioRouting()` (that's `runSystemCheck`'s job).
2. **Triggers** — call `refreshReadiness()` on:
   - **Entering Live** — `LiveServiceView.onAppear` / `.task`. (Note: `LiveServiceView` is recreated
     on navigation, so `onAppear` is correct; an `onChange(of: selectedScreen)` *inside* it would
     not help.)
   - **Cue change** — `cue(entryID:)` (`:200`) currently does not publish `systemCheck`; add a
     `refreshReadiness()` call there.
   - **Cued-song key/BPM edits** — after `updateEntry(...)` for the cued entry.
   - **Audio hardware change** — already wired via `handleAudioHardwareChanged` (`:905`); no new work.
3. **Playback gating:** when `runtime.playbackPhase == .songPlaying`, keep updates passive — no
   modal, no toast, no animated relayout. The banner may update text in place, but must not jump the
   surface. The safety-net is a net, not an interruption. Never reconfigure the engine on a trigger.
4. **Surface (Live only), banner-scope as confirmed:** extend `LiveServiceView.messageStrip`:
   - Show the prominent `SustainInlineNotice` (warning tint) **only when a genuine fault exists** —
     i.e. `!systemCheck.canStartPlayback` **and it is not the neutral/not-run state** (guard against
     `.notRun` and "no song cued", which also have `canStartPlayback == false`). Render the blocking
     messages (the non-"Warning:" entries).
   - Non-blocking `systemCheck.warnings` stay on the existing `LiveRoutingBadge` — no banner.
   - Stay fully silent when ready.

**Verify:** launching to Live with nothing cued shows **no** banner; entering Live with a forced
fault (e.g. an unavailable selected device) shows the banner with the specific problem; clearing the
fault removes it; a warning-only condition shows on the badge but not the banner; nothing
appears/moves mid-song.

---

## Phase 3 — Remove the two sidebar screens + cleanup

**Files:** `RuntimeSession.swift`, `RootView.swift`, `SustainApp.swift`, `LibraryViews.swift`.

1. `AppScreen`: remove `.audio` and `.check`. Sidebar auto-drops to 3 items.
2. `RootView`: remove `.audio`/`.check` from `selectedScreen`, `backgroundMood`, and `icon(for:)`.
3. `SustainApp` commands:
   - Remove the "Run System Check" (⌘⇧K) command. It is the **only** item in its
     `CommandGroup(after: .newItem)` — remove the whole group, don't leave it empty. (Optional:
     repurpose as a "Re-check readiness" that navigates to Live and calls `refreshReadiness()`.)
   - `Go` menu now maps ⌘1…⌘3 automatically (it iterates `AppScreen.allCases`).
4. Delete `SystemCheckView` and its `CheckMessageRow` helper (now unused — the Live banner uses
   `SustainInlineNotice`, not `CheckMessageRow`). Delete `AudioSetupView` after its content is
   ported (Phase 1); keep shared helpers still used by the Audio tab (`DiagnosticLine`,
   `AudioDeviceDiagnosticRow`, `RouteSignalView`).
5. **Dead-code sweep after removal:**
   - `PanelPair` (`SustainDesignSystem.swift:340`) was used only by the two removed views → becomes
     unused. Either delete it or keep intentionally as a DS primitive (decide; don't leave a
     silent orphan).
   - **Keep `AudioPatternView`** — still used by `RehearseView` (`:220`).
6. Tidy `SustainBackgroundMood`: the `.audio`/`.system` cases become unused (moods are already
   no-ops per the design-system note) — remove them and their references.
7. **Keep** in `RuntimeSession` (reused): `validate`, `refreshReadiness` (new), `runSystemCheck`
   (if repurposed, else remove), `systemCheck`, `refreshAudioDiagnostics`, `routingSettings`,
   `routingSnapshot`, `updateRouting`.

**Verify:** app compiles; sidebar shows exactly Live · Rehearse · Song Library; ⌘1/⌘2/⌘3 navigate.

---

## Phase 4 — Verification

- `swift test` — 59 tests pass. Check none assert navigation to `.audio`/`.check` or the removed
  command; update if any do.
- **Add coverage** for the safety-net: `refreshReadiness()` publishes a blocking `systemCheck` when
  a device is unavailable / BPM invalid, a clean result when ready, and a neutral state when nothing
  is cued; and that it does **not** touch the audio engine (no `prepare()`/reconfigure).
- Drive the app (screenshots): sidebar has 3 items; ⌘, opens tabbed Settings (General/Audio);
  routing changes persist and reflect in Live's badge; a forced fault shows the Live banner while a
  warning-only condition shows on the badge only; nothing appears mid-song;
  Live/Rehearse/Song Library top-alignment unchanged; Appearance System follows the OS live.

---

## Notes / risks (macOS best practices)

- **Never auto-run the heavy check.** `runSystemCheck()` prepares the engine and reconfigures
  routing; auto-triggering it (esp. mid-service) risks audio glitches. The safety-net uses the pure
  `validate()` via `refreshReadiness()` only. This is the single most important correctness point.
- **Neutral states are not faults.** `.notRun` and "no song cued" have `canStartPlayback == false`;
  the banner must exclude them or it false-alarms on launch / empty setlist.
- **Trigger on `onAppear`, not `onChange`,** for entering Live — the view is recreated on navigation.
- The Settings **Audio** tab is a *rework*, not a move — panel layout → Form rows. Budget iteration.
- **Inject the store into the `Settings` scene explicitly** — env objects don't auto-propagate there.
- **Settings idioms:** `TabView` + `.tabItem` (SF Symbols), `Form` + `.formStyle(.grouped)`, fixed
  content width; refresh device snapshot on tab appear (snapshot-only, no engine work).
- **Accessibility:** confirm the inline error banner (`SustainInlineNotice`) exposes its text to
  VoiceOver; Form pickers get labels automatically.
- **Dead code:** `CheckMessageRow` and (likely) `PanelPair` become orphans — remove or keep by
  intent, don't leave silently unused. Keep `AudioPatternView` (Rehearse uses it).
- **No persistence/migration risk:** `selectedScreen` is in-memory only.
- **Empty CommandGroup:** removing "Run System Check" empties its group — remove the group too.
- The safety-net's value is "quiet unless broken." Gate on discrete events + playback state; don't
  recompute on every published change.
