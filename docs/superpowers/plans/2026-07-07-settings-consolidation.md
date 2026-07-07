# Settings Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Audio Setup and System Check sidebar screens — move audio routing/diagnostics into the macOS Settings window (⌘,) and convert System Check into an automatic, background readiness safety-net surfaced on the Live Service screen.

**Architecture:** Reuse the existing pure `validate(entry:song:)` in `RuntimeSession` via a new lightweight `refreshReadiness()` (no engine work). Live Service triggers it on appear / cue change and shows blocking faults inline; non-blocking warnings stay on the existing routing badge. Audio routing UI (currently `AudioSetupView`) moves into a tabbed `Settings` scene as a `Form`. `AppScreen` drops to 3 cases.

**Tech Stack:** SwiftUI (macOS), Swift Testing (`import Testing`, `@Test`, `#expect`), Swift Package Manager. Build/bundle via `swift build` + `./scripts/bundle.sh debug`.

**Design doc:** `docs/12_Settings_Consolidation_Plan.md` (decisions + rationale).

**Prereq:** Working tree should be clean before Task 1 (commit the current Live-alignment + appearance-fix + design-doc work first). Each task ends in its own commit.

---

## File Structure

- `Sources/Sustain/RuntimeSession.swift` — add `refreshReadiness()`; call it from `cue(entryID:)`. (Owns `validate`, `systemCheck`, `SystemCheckResult`, `AppScreen`.)
- `Sources/Sustain/LiveServiceView.swift` — trigger `refreshReadiness()` on appear; render blocking faults in `messageStrip`.
- `Sources/Sustain/Settings/AudioSettingsView.swift` — **new**; the ported routing/diagnostics UI as a `Form`.
- `Sources/Sustain/SustainApp.swift` — `AppSettingsView` → `TabView` (General + Audio); inject store into the `Settings` scene; remove the "Run System Check" command.
- `Sources/Sustain/RootView.swift` — remove `.audio`/`.check` from `selectedScreen`, `backgroundMood`, `icon(for:)`.
- `Sources/Sustain/LibraryViews.swift` — delete `SystemCheckView`, `CheckMessageRow`, `AudioSetupView` (after port); keep `DiagnosticLine`, `AudioDeviceDiagnosticRow`, `RouteSignalView`, `SongLibraryView`.
- `Sources/Sustain/SustainDesignSystem.swift` — remove now-unused `SustainBackgroundMood.audio`/`.system`; evaluate `PanelPair` (delete if orphaned).
- `Tests/SustainTests/RuntimeSessionTests.swift` — add `refreshReadiness` tests.

---

## Task 1: Lightweight `refreshReadiness()` on `RuntimeSession`

**Files:**
- Modify: `Sources/Sustain/RuntimeSession.swift` (add method near `runSystemCheck()` ~`:681`)
- Test: `Tests/SustainTests/RuntimeSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `RuntimeSessionTests.swift` (inside the `RuntimeSessionTests` struct):

```swift
@Test func refreshReadinessReportsReadyWithoutTouchingEngine() {
    let audio = RecordingAudioEngine()
    let store = AppStore.preview(audioEngine: audio)
    let routingCallsBefore = audio.configureRoutingCount

    store.refreshReadiness()

    #expect(store.systemCheck.canStartPlayback)
    #expect(store.systemCheck.messages.contains("Ready for Goodness of God in G at 72 BPM."))
    // The safety-net must NOT reconfigure audio (that is runSystemCheck's job).
    #expect(audio.configureRoutingCount == routingCallsBefore)
}

@Test func refreshReadinessBlocksWhenPadOutputUnavailable() {
    let provider = StaticAudioRoutingProvider(
        snapshotValue: AudioRoutingSnapshot(
            outputs: [AudioOutputDevice(id: 2, name: "Click Bus", isDefault: true)],
            padOutputID: 2,
            padOutputName: "Click Bus",
            clickOutputID: 2,
            clickOutputName: "Click Bus",
            independentRoutingEnabled: false,
            padOutputUnavailable: true
        )
    )
    let store = AppStore.preview(audioRoutingProvider: provider)

    store.refreshReadiness()

    #expect(!store.systemCheck.canStartPlayback)
    #expect(store.systemCheck.messages.contains("Selected pad output is unavailable."))
}

@Test func refreshReadinessIsNeutralWhenNothingCued() {
    let store = AppStore.preview()
    for entry in store.activeSetlist.entries { store.removeSetlistEntry(entry.id) }

    store.refreshReadiness()

    #expect(store.systemCheck == .notRun)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter refreshReadiness 2>&1 | tail -20`
Expected: FAIL — `value of type 'AppStore' has no member 'refreshReadiness'`.

- [ ] **Step 3: Implement `refreshReadiness()`**

In `RuntimeSession.swift`, add immediately after `runSystemCheck()` (~`:697`):

```swift
    /// Lightweight readiness re-check for the Live safety-net. Pure `validate()` only — never
    /// prepares the engine or reconfigures routing (that is `runSystemCheck()`'s job), so it is
    /// safe to call on screen entry and on state changes, including during playback.
    func refreshReadiness() {
        if let cuedEntry, let cuedSong = song(for: cuedEntry) {
            systemCheck = validate(entry: cuedEntry, song: cuedSong)
        } else {
            systemCheck = .notRun
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter refreshReadiness 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: `Test run with 62 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sustain/RuntimeSession.swift Tests/SustainTests/RuntimeSessionTests.swift
git commit -m "feat: add lightweight refreshReadiness() for Live safety-net"
```

---

## Task 2: Trigger readiness on cue change

**Files:**
- Modify: `Sources/Sustain/RuntimeSession.swift` — `cue(entryID:)` (~`:200`)
- Test: `Tests/SustainTests/RuntimeSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func cuingASongRefreshesReadiness() {
    let store = AppStore.preview()
    // Move the cue to the second entry and confirm systemCheck reflects it.
    let second = store.activeSetlist.entries[1].id
    store.cue(entryID: second)

    #expect(store.systemCheck.canStartPlayback)
    #expect(store.systemCheck.messages.contains { $0.hasPrefix("Ready for ") })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter cuingASongRefreshesReadiness 2>&1 | tail -15`
Expected: FAIL — `systemCheck` is still `.notRun` (its default), so `canStartPlayback` is false.

- [ ] **Step 3: Add the trigger**

In `cue(entryID:)`, after `preloadCuedPad()` (~`:208`), add:

```swift
        refreshReadiness()
```

Resulting tail of the method:

```swift
        runtime.cuedEntryID = entryID
        runtime.lastMessage = "Cued \(song.title)"
        preloadCuedPad()
        refreshReadiness()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter cuingASongRefreshesReadiness 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Full suite**

Run: `swift test 2>&1 | tail -3`
Expected: `Test run with 63 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sustain/RuntimeSession.swift Tests/SustainTests/RuntimeSessionTests.swift
git commit -m "feat: refresh readiness on cue change"
```

---

## Task 3: Live Service inline readiness banner

**Files:**
- Modify: `Sources/Sustain/LiveServiceView.swift` — `body` (~`:40`), `messageStrip` (~`:323`)

No unit test (SwiftUI view); verified by driving the app.

- [ ] **Step 1: Trigger a readiness refresh on appear**

In `LiveServiceView.body`, add `.onAppear` after `.inspector(...)` (~`:54`):

```swift
        .onAppear { store.refreshReadiness() }
```

(Correct hook: `LiveServiceView` is recreated when navigated to, so `onAppear` fires each entry. An `onChange(of: selectedScreen)` inside this view would not.)

- [ ] **Step 2: Add a computed property for the blocking fault**

In `LiveServiceView`, add near the other derived vars (~`:344`):

```swift
    /// Blocking readiness messages to surface as a prominent banner — only when a genuine
    /// fault exists. Excludes the neutral `.notRun` state (also `canStartPlayback == false`)
    /// and drops warning lines (those stay on the routing badge).
    private var blockingReadinessMessage: String? {
        let check = store.systemCheck
        guard !check.canStartPlayback, check != .notRun else { return nil }
        let blocking = check.messages.filter { !$0.hasPrefix("Warning:") }
        return blocking.isEmpty ? nil : blocking.joined(separator: " ")
    }
```

- [ ] **Step 3: Render the banner in `messageStrip`**

Replace the existing `messageStrip` body's leading notice. Current (~`:323`):

```swift
    private var messageStrip: some View {
        VStack(spacing: SustainSpace.sm) {
            if store.routingSnapshot.hasUnavailableSelection {
                SustainInlineNotice(
                    message: store.routingSnapshot.missingSelectionMessages.joined(separator: " "),
                    kind: .warning
                )
            }
```

Change the leading `if` to prefer the readiness fault (which is broader — invalid BPM, missing pad, unavailable device):

```swift
    private var messageStrip: some View {
        VStack(spacing: SustainSpace.sm) {
            if let blockingReadinessMessage {
                SustainInlineNotice(message: blockingReadinessMessage, kind: .warning)
            } else if store.routingSnapshot.hasUnavailableSelection {
                SustainInlineNotice(
                    message: store.routingSnapshot.missingSelectionMessages.joined(separator: " "),
                    kind: .warning
                )
            }
```

(Leave the rest of `messageStrip` — the info row + `LiveRoutingBadge` — unchanged. Non-blocking warnings continue to read from `routingSnapshot` via the badge.)

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -2`
Expected: `Build complete!`

- [ ] **Step 5: Drive the app — no false alarm, real fault shows**

```bash
./scripts/bundle.sh debug 2>&1 | tail -1
osascript -e 'tell application "Sustain" to quit' 2>/dev/null; sleep 1
open /Users/dillonlui/Applications/Sustain.app && sleep 3
```
Then position the window and screenshot the Live screen (see the verifying-sustain-app memory / `docs`): confirm with a normal setlist there is **no** banner. Force a fault to confirm the banner appears — easiest path: in Settings ▸ Audio (after Task 4) pick a device/channel that becomes unavailable, or temporarily seed `padOutputUnavailable`. Confirm the banner text names the problem and clears when resolved, and does not appear/jump while a song is playing.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sustain/LiveServiceView.swift
git commit -m "feat: surface blocking readiness faults inline on Live Service"
```

---

## Task 4: Audio settings view (Form) + tabbed Settings window

**Files:**
- Create: `Sources/Sustain/Settings/AudioSettingsView.swift`
- Modify: `Sources/Sustain/SustainApp.swift` — `AppSettingsView`
- Modify: `Sources/Sustain/LibraryViews.swift` — remove `AudioSetupView` (its logic moves)

- [ ] **Step 1: Create `AudioSettingsView` by porting `AudioSetupView`**

Create `Sources/Sustain/Settings/AudioSettingsView.swift`. **Move** these members out of `AudioSetupView` (`LibraryViews.swift:244–535`) into the new view, unchanged in behavior: the routing binding helpers (`padOutputBinding`, `clickOutputBinding`, `padChannelBinding`, `clickChannelBinding`, `storedChannel`, `output(id:)`, `deviceIDText`), the status computeds (`routeStatusTitle`, `routeStatusTint`, `isPadRouteReady`, `isClickRouteReady`), and the device/engine data. Re-layout the body as a `Form` (native Settings idiom) instead of the `SustainScreenHeader` + panel layout:

```swift
import CoreAudio
import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
                LabeledContent(routeStatusTitle, value: store.routingSnapshot.summary)
                if let warning = store.routingSnapshot.warning {
                    SustainInlineNotice(message: warning, kind: .warning)
                }
                Button("Refresh Devices", systemImage: "arrow.clockwise") {
                    store.refreshAudioDiagnostics()
                }
            }

            Section("Pad Output") {
                Picker("Device", selection: padOutputBinding) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(store.routingSnapshot.outputs) { output in
                        Text(output.isDefault ? "\(output.name) (Default)" : output.name)
                            .tag(AudioDeviceID?.some(output.id))
                    }
                }
                Picker("Channel", selection: padChannelBinding) {
                    ForEach(AudioOutputChannelSelection.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
            }

            Section("Click Output") {
                Picker("Device", selection: clickOutputBinding) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(store.routingSnapshot.outputs) { output in
                        Text(output.isDefault ? "\(output.name) (Default)" : output.name)
                            .tag(AudioDeviceID?.some(output.id))
                    }
                }
                Picker("Channel", selection: clickChannelBinding) {
                    ForEach(AudioOutputChannelSelection.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
            }

            Section("Detected Devices") {
                if store.routingSnapshot.outputs.isEmpty {
                    SustainInlineNotice(message: "No audio outputs detected.", kind: .warning)
                } else {
                    ForEach(store.routingSnapshot.outputs) { output in
                        AudioDeviceDiagnosticRow(output: output)
                    }
                }
            }

            Section("Engine") {
                DiagnosticLine(label: "Status", value: store.audioStatus)
                DiagnosticLine(label: "Pad Level", value: "\(Int((store.padVolume * 100).rounded()))%")
                DiagnosticLine(label: "Click Level", value: "\(Int((store.clickVolume * 100).rounded()))%")
            }
        }
        .formStyle(.grouped)
        .task { store.refreshAudioDiagnostics() }
    }

    // MARK: - Moved from AudioSetupView (unchanged)
    // padOutputBinding, clickOutputBinding, padChannelBinding, clickChannelBinding,
    // storedChannel(_:), output(id:), deviceIDText(_:), routeStatusTitle, routeStatusTint,
    // isPadRouteReady, isClickRouteReady — paste verbatim from AudioSetupView.
}
```

If `AudioDeviceDiagnosticRow` / `DiagnosticLine` are `private` in `LibraryViews.swift`, change them to internal (drop `private`) so the new file can use them.

- [ ] **Step 2: Convert `AppSettingsView` into a tabbed window**

In `SustainApp.swift`, replace `AppSettingsView` (~`:118`) with:

```swift
struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .frame(height: 100)
    }
}
```

- [ ] **Step 3: Inject the store into the Settings scene**

In `SustainApp.body`, change the `Settings` scene (~`:42`):

```swift
        Settings {
            AppSettingsView()
                .environmentObject(store)
        }
```

- [ ] **Step 4: Leave `AudioSetupView` in place (do NOT delete it here)**

`RootView.selectedScreen` still references `AudioSetupView()` and `SystemCheckView()`, so deleting
`AudioSetupView` now would break the build. **Leave it untouched in this task.** Its logic is
duplicated into `AudioSettingsView`; the old view is removed atomically in Task 5 alongside the
`.audio`/`.check` enum cases. (Temporary duplication between this commit and Task 5 is intentional
and keeps every commit building.)

- [ ] **Step 5: Build (with `AudioSetupView` still present)**

Run: `swift build 2>&1 | tail -2` → `Build complete!`

- [ ] **Step 6: Drive the app**

⌘, opens a tabbed window (General / Audio). Change pad device/channel → routing updates and persists (reflected by the Live routing badge). Appearance still works; System follows the OS live. Screenshot both tabs.

- [ ] **Step 7: Commit**

```bash
git add Sources/Sustain/Settings/AudioSettingsView.swift Sources/Sustain/SustainApp.swift
git commit -m "feat: tabbed Settings window with Audio routing tab"
```

---

## Task 5: Remove the Audio Setup + System Check screens

**Files:**
- Modify: `Sources/Sustain/RuntimeSession.swift` — `AppScreen` (`:5–13`)
- Modify: `Sources/Sustain/RootView.swift` — `selectedScreen` (~`:65`), `backgroundMood` (~`:43`), `icon(for:)` (~`:120`)
- Modify: `Sources/Sustain/LibraryViews.swift` — delete `SystemCheckView` + `CheckMessageRow`
- Modify: `Sources/Sustain/SustainApp.swift` — remove "Run System Check" command
- Modify: `Sources/Sustain/SustainDesignSystem.swift` — prune `SustainBackgroundMood`, evaluate `PanelPair`

- [ ] **Step 1: Trim `AppScreen`**

In `RuntimeSession.swift` (`:5`):

```swift
enum AppScreen: String, CaseIterable, Identifiable {
    case live = "Live Service"
    case rehearse = "Rehearse"
    case songs = "Song Library"

    var id: String { rawValue }
}
```

- [ ] **Step 2: Update `RootView`**

`selectedScreen` (~`:65`):

```swift
    @ViewBuilder
    private var selectedScreen: some View {
        switch store.selectedScreen {
        case .live:
            LiveServiceView()
        case .rehearse:
            RehearseView()
        case .songs:
            SongLibraryView()
        }
    }
```

`backgroundMood` (~`:43`):

```swift
    private var backgroundMood: SustainBackgroundMood {
        switch store.selectedScreen {
        case .live:
            return .live
        case .rehearse:
            return .rehearse
        case .songs:
            return .standard
        }
    }
```

`icon(for:)` (~`:120`) — remove the `.audio`/`.check` cases:

```swift
    private func icon(for screen: AppScreen) -> String {
        switch screen {
        case .live: "play.circle"
        case .rehearse: "music.quarternote.3"
        case .songs: "music.note.list"
        }
    }
```

- [ ] **Step 3: Delete `SystemCheckView` + `CheckMessageRow`**

In `LibraryViews.swift`, delete `struct SystemCheckView` (`:609–744`) and `private struct CheckMessageRow` (`:746–768`). (Keep `SongLibraryView`, `AudioDeviceDiagnosticRow`, `RouteSignalView`, `DiagnosticLine`.)

- [ ] **Step 4: Remove the "Run System Check" command**

In `SustainApp.swift`, delete the whole `CommandGroup(after: .newItem) { Button("Run System Check") ... }` block (~`:60–65`) — it becomes empty otherwise. Leave `Performance` and `Go` menus intact (`Go` auto-maps ⌘1–⌘3 now).

- [ ] **Step 5: Prune `SustainBackgroundMood` + `PanelPair`**

In `SustainDesignSystem.swift`, remove `case audio` and `case system` from `SustainBackgroundMood` (`:119–125`). Then search for remaining `PanelPair` uses:

Run: `grep -rn "PanelPair" Sources/Sustain`
If the only hit is the definition (`:340`), delete `struct PanelPair` (it was used only by the removed views). If other uses appear, leave it.

- [ ] **Step 6: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (no `AudioSetupView`/`SystemCheckView`/`.audio`/`.check` references remain).

- [ ] **Step 7: Full suite**

Run: `swift test 2>&1 | tail -3`
Expected: `Test run with 63 tests ... passed`. If any test references `.audio`/`.check`/`runSystemCheck` navigation and fails, fix the test to match the new model.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: drop Audio Setup and System Check screens (moved to Settings + Live safety-net)"
```

---

## Task 6: Final verification

- [ ] **Step 1: Tests**

Run: `swift test 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 2: Drive the whole app**

```bash
swift build 2>&1 | tail -1 && ./scripts/bundle.sh debug 2>&1 | tail -1
osascript -e 'tell application "Sustain" to quit' 2>/dev/null; sleep 1
open /Users/dillonlui/Applications/Sustain.app && sleep 3
```
Confirm by screenshot / AX:
- Sidebar shows exactly **Live Service · Rehearse · Song Library**; ⌘1/⌘2/⌘3 navigate.
- ⌘, opens the tabbed Settings (General / Audio); routing edits persist and reflect on Live's badge.
- Live with a normal setlist: **no** banner. Forced fault (unavailable device): banner names the problem; clears on fix; nothing appears/moves mid-song. Warning-only condition (pad+click share output) shows on the badge, not the banner.
- Live / Rehearse / Song Library keep their top alignment; Appearance System follows the OS live.

- [ ] **Step 3: Update the design doc status**

Set `docs/12_Settings_Consolidation_Plan.md` **Status** to "Implemented (<date>)".

- [ ] **Step 4: Commit**

```bash
git add docs/12_Settings_Consolidation_Plan.md
git commit -m "docs: mark settings consolidation implemented"
```

---

## Self-Review Notes

- **Spec coverage:** Settings location (Task 4) ✓; System Check → automatic Live net (Tasks 1–3) ✓; sidebar 5→3 (Task 5) ✓; heavy-vs-light validation (Task 1, `refreshReadiness` uses pure `validate`, asserted via `configureRoutingCount`) ✓; neutral-state gating (Task 1 test + Task 3 `blockingReadinessMessage`) ✓; warnings→badge / errors→banner (Task 3) ✓; dead-code sweep + empty CommandGroup + moods (Task 5) ✓; no persistence migration (in-memory `selectedScreen`) — no task needed ✓.
- **Ordering caveat (Task 4 ↔ Task 5):** deleting `AudioSetupView` breaks the build until `RootView`'s `.audio` case is removed. Keep `AudioSetupView` in place through Task 4's commit; remove both views + enum cases atomically in Task 5. (Task 4 Step 5 flags this.)
- **Type consistency:** `refreshReadiness()`, `SystemCheckResult(canStartPlayback:messages:warnings:)`, `.notRun`, `configureRoutingCount`, `padOutputUnavailable`, binding-helper names — all match existing code verified against source.
- **Test count:** starts at 59; +3 (Task 1) +1 (Task 2) = 63. Adjust the expected count in commands if reality differs.
