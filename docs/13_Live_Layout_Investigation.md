# 13 — Live Layout Instability: Findings & Experiment Plan

**Status: RESOLVED (2026-07-08).** Tier 3 shipped — custom paned layout. Flip eliminated,
verified live. `swift build` clean, `swift test` 63 passing.
**Branch:** `redesign-native` (changes uncommitted pending review).

---

## RESOLUTION (2026-07-08) — the flip had TWO independent causes

The root cause was **not one thing but two**, each *independently sufficient* to flip the
window's top safe-area inset (~90px on play):

1. **`NavigationSplitView`** (outer sidebar+detail shell), under `.hiddenTitleBar`, re-decides
   its top inset when `RootView`'s body re-evaluates on a state publish.
2. **`.inspector`** (the Live song editor) — a NavigationSplitView-*family* feature that, even
   standalone, wraps content in its own split-view container with the same inset behavior.

This is why the earlier spikes were each inconclusive: removing `.inspector` while keeping
`NavigationSplitView` still flipped (cause #1 remained); replacing `NavigationSplitView` with a
custom `HStack` while keeping `.inspector` still flipped (cause #2 remained). Only removing
**both** stops it. Confirmed via `p2_idle`/`p2_playing` and `final_live_idle`/`final_live_playing`
captures: every structural element holds position across idle↔playing; only content changes.

**The fix (tier 3), all native SwiftUI — a net simplification:**
- `RootView`: `NavigationSplitView` → `HStack { SidebarView.frame(width:220); Divider; detail }`
  in a `ZStack` over the background. One fixed, self-owned top inset (`topChrome = 28`) clears the
  traffic lights and can't flip. `.hiddenTitleBar` **restored** (safe now — nothing fights us for
  the top inset), so the brand-forward chrome is back.
- `SidebarView`: full-height, brand header padded by `topChrome + sm`. Removed
  `navigationSplitViewColumnWidth` / `columnVisibility`.
- `LiveServiceView`: `.inspector` → a plain conditional trailing pane in the existing `HStack`
  (`SongInspectorPane` made self-contained with its own "Edit Song" header + close button).
  Editor verified live (`final_editor` capture).
- Deleted all the safe-area hacks from the pre-experiment design (see below).

**Trade-off accepted:** lost `NavigationSplitView`'s free sidebar-collapse toggle. Fine for an
always-on performance sidebar; a custom toggle is cheap to add later if wanted.

**Deeper note (see docs/14):** the *reason* a state publish re-evaluated the whole `RootView`
body is the `AppStore` god-object using classic `ObservableObject` (object-level invalidation).
Migrating to `@Observable` (property-level tracking) would remove the broad re-render that fed
this bug and prevent a class of future re-render storms. Tracked in the architecture review.

---

## Experiment result (2026-07-08) — flip is FRAMEWORK-LEVEL, not our hacks

Ran the cheap experiment exactly as planned: `.hiddenTitleBar` → `.titleBar`, and stripped ALL
four safe-area hacks (detail `.padding`, sidebar `isLive` brand pad, `reclaimTopSafeArea` +
helper, setlist-header `.padding(.top, 26)`). Built, bundled, relaunched.

**Measured the flip before/after, same method, controlled A/B:**
- **Baseline (committed hacks):** on ⌘Return the whole split view drops ~90px (logical);
  `idle` and `stopped` captures are byte-identical, `playing` differs. Reproduced cleanly.
- **Clean stock config:** the **~90px flip STILL happens** on play (transport row ~y203 idle →
  ~y332 playing; sidebar mounts flush-under-traffic-lights when idle, drops when playing).
  Removing the hacks + standard title bar did NOT stop it.

**Conclusion:** the "our hacks caused it" hypothesis is **falsified**. The flip is
`NavigationSplitView`'s own macOS safe-area/mount-mode behavior, re-triggered when
`store.runtime` publishes on play and the whole `RootView` body re-evaluates. Per the decision
tree → **tier 3.**

Evidence: `clean_idle.png` vs `clean_playing.png` (visual, unambiguous, captured pre-lock).
Numeric AX confirmation was blocked mid-run — the Mac auto-locked during the scripted waits
(synthetic ⌘-keys and AX window queries fail at the lock screen). Re-run the AX position check
after unlock if a hard number is wanted; the visual A/B already settles the decision.

### Refined tier-3 scope (smaller than first thought)
`LiveServiceView` is **already** a custom `HStack { List; resize-handle; performanceSurface }`
(`LiveServiceView.swift:41-49`) — the internal setlist/performance split is NOT
`NavigationSplitView`. Only two framework-magic layers remain:
1. The **outer** `NavigationSplitView` in `RootView` (sidebar + detail) — replace with a custom
   `HStack { sidebar; Divider; detail }` and one consistent, self-owned top inset.
2. **`.inspector`** in `LiveServiceView` (`:51`) — a NavigationSplitView-family feature that
   splices into the enclosing split view. Replace with a custom trailing pane (trivial, since
   the view is already an HStack) or a `.sheet`.

Candidate cheaper-than-full-tier-3 spike to try first: **remove `.inspector` alone** (keep the
outer `NavigationSplitView`) and re-measure the flip. The flip triggers on play (not on
inspector toggle), so `.inspector`'s mere presence putting the split view in the fragile mode is
plausible-but-unconfirmed. If dropping it stops the flip, that's a much smaller fix.

### `.inspector` spike RESULT (2026-07-08) — NOT the culprit

Ran it: commented out the `.inspector` modifier only, kept the outer `NavigationSplitView` and
the clean baseline. Rebuilt/rebundled/relaunched, measured the same way.

**The ~90px flip persists** (`spike_idle.png` vs `spike_playing.png`: transport row ~y242 idle →
~y372 playing, ≈86px logical; sidebar flush-when-idle → dropped-when-playing). Restored
`.inspector` afterward (confirmed innocent; leaving it disabled only breaks the song editor).

That is now **three independent configs all flipping ~86–90px**: (1) committed hacks, (2) clean
stock, (3) clean-minus-inspector. The outer `NavigationSplitView` is the **irreducible cause**.
→ Full tier 3 (replace the outer split view) is required; the `.inspector` still needs replacing
as part of tier 3 (it's a split-view feature) but it is not the flip trigger.

Measurement note: numeric AX position queries (`entire contents … whose role is "AXButton"/…`)
did **not** surface the SwiftUI transport button / sidebar text reliably — a known SwiftUI↔AX
gap. The flip was measured from screenshots (retina 2×, captured region 1320 logical wide), which
is the reliable channel here. Also: the Mac **auto-locks during scripted `sleep`s** — wrap live
measurement in `caffeinate -d -t N &` or the window deregisters (`windows=0`) mid-run.

---

## Original handoff (pre-experiment)

---

## TL;DR

The Live Service screen has a family of layout bugs (whole-view shift on playback,
sidebar extending past the window edges, content sitting too high, earlier a nav "jump"
between screens). They are **all one root cause**: `NavigationSplitView` + `.hiddenTitleBar`
+ a pile of safe-area hacks fighting the framework. The next step is a **cheap experiment**:
strip the hacks, go with the framework's grain (standard title bar, stock split view), and
measure whether the shift simply disappears. That result decides between "tier 1" (keep
`NavigationSplitView`, done) and "tier 3" (custom layout).

**Do NOT keep hacking paddings onto the current setup.** That is what created the fragility.

---

## What currently works (committed — don't redo)

All of this is shipped and verified; it is independent of the layout problem:

- **Settings consolidation** (`docs/12`): Audio Setup + System Check removed as sidebar
  screens; audio routing lives in the ⌘, Settings window (General + Audio tabs); readiness
  is an automatic Live safety-net. Sidebar is Live · Rehearse · Song Library.
- **Appearance "System" bug** fixed (drives `NSApplication.appearance` + pushes to each
  window so background controls refresh on theme switch).
- **Live warnings**: blocking faults show red inline; non-blocking warnings (e.g. shared
  output) show orange inline.
- **Countoff** rendered as a zero-footprint overlay just below the controls (this part is
  fine — it does NOT cause the shift; see below).
- **Setlist header** has a small top margin.

Relevant recent commits: `a9b93ea`, `0ce3eb3`, `5702255`, `076e05c`, `a7dcc6f`, `fbff10f`,
`7a84973`, `664d7cc`, `9bf72fd`, `79f9334`.

---

## The core problem

On the **Live** screen, the entire split view (sidebar + both columns) shifts down **~90px**
when playback starts. Reproduced with the countoff **removed**, so it is NOT the countoff —
it is a `NavigationSplitView` **mount-mode flip** (flush ↔ reserved top inset) triggered by
the detail re-rendering on a state change.

Same root cause produces the other complaints:
- Sidebar renders full-height under the traffic lights and "extends past the window edges."
- Setlist header / NOW-NEXT panels sit too close to the top.
- (Earlier) the sidebar "jumped" ~8px when switching Live ↔ other screens.

### Why it happens
- `.hiddenTitleBar` makes the window full-size-content (content runs under the window
  controls). SwiftUI's `NavigationSplitView` then decides — inconsistently, per render —
  whether to reserve a top safe area, and flips on state changes.
- The Live detail is a real `List` (setlist) + `.inspector`, which pushes the split view
  toward the "flush" mount and makes in-column headers get dragged under the window edge.
- On top of that we layered compensations (`safeAreaInset` brand header, `ignoresSafeArea`
  via `reclaimTopSafeArea`, per-screen `.padding(.top, isLive ? …)`). **Stacked hacks
  interact unpredictably and are likely amplifying the instability.**

### What was tried and FAILED (don't repeat)
- Per-screen top paddings on the split view / detail (partially compensates position, does
  not stop the flip).
- `reclaimTopSafeArea` (`ignoresSafeArea(.container, .top)`) on sidebar and/or detail.
- Forcing the detail to a consistent flush mount.
- `.windowStyle(.titleBar)` + `WindowConfigurator` NSWindow tweaks
  (`titlebarAppearsTransparent`, `titleVisibility = .hidden`, removing
  `.fullSizeContentView`). **SwiftUI re-applied full-size-content / full-height sidebar and
  overrode the NSWindow changes; the flip persisted.** → Reverted.

Conclusion: while `NavigationSplitView` owns the top-level layout with `.hiddenTitleBar`, we
cannot stop the flip from the outside.

---

## The cheap experiment (do this next)

**Goal:** determine whether the instability is the framework or our hacks, at low cost, by
going with the grain.

**Hypothesis:** a stock `NavigationSplitView` with a **standard title bar** and **no
safe-area manipulation** is stable (no flip). This is how most Mac apps ship.

### Steps
1. **Window:** in `SustainApp.swift`, change `.windowStyle(.hiddenTitleBar)` →
   `.windowStyle(.titleBar)` (standard). Optionally later: transparent-but-standard title
   bar for aesthetics — but for the experiment, use the plain standard title bar.
2. **Strip ALL safe-area hacks** — get back to a stock split view:
   - `RootView` detail closure: remove `.padding(.top, store.selectedScreen == .live ? 40 : 0)`.
   - `SidebarView`: brand header → plain `.padding(.top, SustainSpace.sm/.md)` (remove the
     `isLive ? 104 : 50` conditional); remove `.reclaimTopSafeArea(!isLive)`; delete the
     `reclaimTopSafeArea` helper if now unused; remove the `isLive` computed if unused.
   - `LiveServiceView`: remove the setlist header `.padding(.top, 26)` hack (back to normal
     vertical padding). Leave the countoff overlay as-is (it's fine).
3. **Build + run** (`swift build` → `./scripts/bundle.sh debug` → open the app).
4. **Measure the flip:** on Live, capture the top strip idle, press ⌘Return (Start), capture
   again ~0.6s later, ⌘. to stop. Compare whether the sidebar / "Sunday Morning" / NOW panel
   move. (See "How to drive/verify the app" below.)

### Decision tree
- **Shift is gone (likely):** the framework was fine; our hacks caused it. Keep
  `NavigationSplitView`. Then do light, cooperative polish only (accept the standard
  full-height sidebar; small consistent margins via normal means). Ship tier 1. This is a
  net *deletion* of code.
  - If the standard title bar's look is unwanted, try a transparent standard title bar
    (`titlebarAppearsTransparent = true` but keep it a normal title bar, NOT
    `.hiddenTitleBar`) and re-test the flip.
- **Shift persists even clean:** the framework genuinely can't do what we want here. Move to
  **tier 3 — custom layout**: replace `NavigationSplitView` with a custom
  `HStack { sidebar; Divider; detail }` (or `HSplitView`), set one consistent top inset
  yourself, and **replace `.inspector`** (the Live song key/tempo editor) with a custom
  trailing panel or a `.sheet`, since `.inspector` is a `NavigationSplitView` feature. Scope
  this as its own change and verify each screen + the editor.

---

## Files & the current hacks to remove in the experiment

- `Sources/Sustain/SustainApp.swift` — `.windowStyle(.hiddenTitleBar)` (line ~50).
- `Sources/Sustain/RootView.swift` —
  - detail `.padding(.top, store.selectedScreen == .live ? 40 : 0)`;
  - `SidebarView` brand `.padding(.top, isLive ? 104 : 50)`, `.reclaimTopSafeArea(!isLive)`,
    `isLive`, and the `reclaimTopSafeArea` `View` extension helper.
- `Sources/Sustain/LiveServiceView.swift` — setlist header `.padding(.top, 26)`; the
  countoff overlay (KEEP). Note the setlist header is a `.safeAreaInset(edge: .top)` on the
  `List`; in a stock setup it should behave — verify.

---

## How to drive / verify the app (macOS SwiftUI, SwiftPM)

See also the `verifying-sustain-app` memory. Key points:

- Build loop: `swift build` → `./scripts/bundle.sh debug` → `open /Users/dillonlui/Applications/Sustain.app`.
- Screenshots work if Screen Recording is granted: `screencapture -x -R<x,y,w,h> out.png`.
- Position/size the window and navigate via System Events / ⌘1–⌘3:
  ```
  osascript -e 'tell application "System Events" to tell process "Sustain" to set position of window 1 to {60, 80}'
  ```
- **Gotcha:** an "Audio Output Change Detected" sheet pops up (real — detects Bluetooth
  headphones like "Sony XM4"). Dismiss it before capturing:
  ```
  osascript -e 'tell application "System Events" to tell process "Sustain" to click button "Keep Current Settings" of sheet 1 of window 1'
  ```
- **Gotcha:** captures right after launch/reposition can catch an unsettled transient — wait
  ~1.5–2s before measuring, and confirm the window is frontmost (synthetic ⌘-keys are
  dropped if it isn't).
- The flip test that matters: idle vs. ~0.6s after ⌘Return, compare vertical positions of
  the sidebar logo / "Sunday Morning" / NOW panel.

---

## Lessons (why this got expensive, for next time)

- **Choosing `.hiddenTitleBar` up front was the fork in the road.** It's the non-standard
  choice that put us off the framework's paved path; every later layout bug traces back to
  it. Non-standard window chrome should be a deliberate, validated decision, not a default.
- **We treated symptoms, not the cause.** Each visual glitch got a local padding/safe-area
  patch. Patches on a fragile base compound into worse fragility. The moment a *second* hack
  was needed to fix the *first* hack's side effect, that was the signal to stop and question
  the foundation.
- **Verify the foundation with a clean baseline before layering.** A 20-minute "does a stock
  `NavigationSplitView` + standard title bar do what I need?" spike at the start would have
  answered the whole question.
