# Sustain visual system refresh — implementation plan

**Status:** Foundation committed; Rehearse is the first runtime pilot, pending manual state walkthrough. Live remains a static composition.
**Direction:** [Signal Grid with open Pad/Click status](future-signal/signal-grid-live-open-status.png), informed by [Future Signal research and explorations](future-signal/README.md).
**Grounding:** [Current design system](../11_Design_System.md), [brand brief](../sustain_brand_assets_final/sustain-brand-brief.md), [Live layout findings](../13_Live_Layout_Investigation.md), and current SwiftUI code.

## Answer to readiness

We are ready for an implementation plan, but not for a screen-by-screen reskin directly from a generated image. The remaining pre-work is bounded and belongs in the first phase of this plan: define semantic tokens, interaction/state rules, and a component specimen set, then approve one static Live composition and one Rehearse composition using real Sustain content. That gives the implementation a source of truth beyond the mockup.

## Current implementation checkpoint

The first pass of [system tokens and state rules](system-spec.md), [interaction rules](interaction-contract.md), reusable SwiftUI components, and static Live/Rehearse compositions was committed as `b68cc0d` on `codex/future-signal-design-system`. Review the [actual SwiftUI renders](renders/README.md) alongside the generated visual reference. The Rehearse runtime pilot now uses the shared components, with its [acceptance walkthrough](rehearse-acceptance.md) still to be completed on an unlocked Mac. Live still uses its previous runtime presentation.

## Locked direction for the first design-system pass

- Dark, graphite and olive foundation with one green family. No gold in the working palette.
- The large Live performance surface remains a dark, subtly glassy square with fine edge lines and corner markers. Its content stays readable and mostly opaque; it is not a translucent sheet over busy content.
- NOW and NEXT are the first read. Pad and Click status are open readouts inside the larger surface, not separate status cards.
- A small playing glyph plus text marks the active song in the setlist. It signals playback state, not audio amplitude. A different, quiet treatment marks the cue.
- Glow and gradient are local to selected, active, focused, or changing state. No repeated wave motif across content. The wave remains in the brand mark and, if justified, a rare transition moment.
- Preserve native Mac semantics and the existing Live geometry, transport order, keyboard shortcuts, and routing truth.

## Phase 0 — define the system before editing screens

1. **State inventory.** Capture the actual Live and Rehearse states from `RuntimeSession` and `RehearseSession`: empty, cued, pad pre-roll, starting, countoff, playing, pad fading, click off, transition, warning, and blocked. Document which song is playing, which is cued, and which pad is audible for each state. Include pending versus audible click settings from [the subdivision plan](../19_Click_Subdivisions_UI_UX_Plan.md).
2. **Visual tokens.** Specify and review a light/dark color ramp, type roles, spacing, radii, stroke weights, surface opacity, glow intensity, and motion durations. Use semantic names such as `canvas`, `performanceSurface`, `surfaceEdge`, `activeSignal`, `cuedEdge`, `focus`, `textPrimary`, `warning`, and `blocked`; do not scatter raw green values through views. Start from the existing near-black, olive, sage, and ivory brand colors, then tune for this darker direction. Gold remains unused.
3. **Component state sheets.** Make deterministic SwiftUI previews or an equivalent review board for every variant listed below, using real product labels and long song/pad/device names. The generated image is a mood reference; these specimens become the UI contract.
4. **Two reference compositions.** Compose Live and Rehearse from the same tokens and components at the app's minimum 1200 × 700 window, plus one wider size. Review idle, active, warning, and narrow/inspector cases before wiring runtime behavior.

**Phase 0 exit:** the component state sheets and two compositions show readable hierarchy, distinct playing/cued/selected/audible states, a viable light appearance, and a Reduce Motion alternative. This is a design review gate, not a request to approve every implementation detail.

## Component contracts

| Component | Variants and behavior | Existing seam |
| --- | --- | --- |
| App shell and sidebar | Selected navigation, focus, quiet wordmark; native list behavior. No broad shell rewrite. | `RootView.swift` |
| Performance surface | Idle, cued, preparing, countoff, playing, transition, warning, blocked. Stable size and text placement. | `LiveServiceView.swift` `performanceSurface` |
| NOW/NEXT readout | Strong current song; secondary cue; explicit empty states; key, BPM, meter, and click subdivision remain available. | `LiveServiceView.swift` `StatePanel` |
| Setlist row | Selected, cued, playing, playing-and-selected, missing song, disabled action; small playing glyph with text. Only actual playback drives the glyph. | `LiveServiceView.swift` `SetlistRowView` |
| Transport | Existing Previous, Start/Transition, Next, Stop order, roles, sizes, and shortcuts; hover, press, focus, disabled. | `LiveServiceView.swift` `transportRow` |
| Open channel status | Pad and Click: off, preparing, active, fading, countoff, unavailable. Icon + words; no individual status card. | New shared primitive used in Live/Rehearse |
| Level control | Pad/Click label, 0–100% setting, keyboard-accessible native slider, active/off and focus states. Do not present setting bars as measured signal. | `ChannelFader` and `LevelMeter` in `SustainDesignSystem.swift` |
| Route summary | Exact device/channel names, ready, shared output, missing selection, warning. Native pickers remain in Audio settings. | `LiveRoutingBadge`, `AudioSettingsView.swift` |
| Notices and countoff | Nonmoving error/warning placement; countoff remains a stable overlay; no per-beat VoiceOver announcements. | `SustainInlineNotice`, `CountoffIndicator` |
| Rehearse pad and click | Selected pad, playing pad, unavailable pad, BPM and click states; responsive grid with long custom labels. | `RehearseView.swift` |

## Phase 1 — foundation and visual primitives

- Split the current single `SustainDesignSystem.swift` into small token and component files only when the new contracts are settled. Keep compatibility wrappers temporarily so screen migrations remain incremental.
- Implement dynamic light/dark semantic colors and effects. A dark, glassy **appearance** for the performance surface can use a stable dark fill, restrained gradient, and fine border. Native Liquid Glass remains appropriate for system control chrome where available; the app supports macOS 14, so it needs an intentional fallback.
- Build shared status, surface, setlist playing glyph, level-setting, and transport styles. The playing glyph may have a slow, low-amplitude pulse only while a song is playing; Reduce Motion shows a static icon.
- Treat `LevelMeter` as a configured level indicator or remove it. Actual signal metering requires a separate audio-engine feature and should not be smuggled into this visual refresh.

**Phase 1 exit:** a component preview gallery covers idle, hover, pressed, selected, focused, disabled, active, warning, and blocked variants in dark/light and increased contrast. Keyboard focus and VoiceOver labels are inspectable.

## Phase 2 — pilot, then screen rollout

1. **Static Live composition:** assemble the new components with fixture data and compare it with the approved direction. This verifies the signature screen without touching service behavior.
2. **Rehearse integration:** apply the visual primitives to the pad grid, BPM/click, and paired channel levels. This is the safer interactive pilot for hover, focus, slider behavior, and real audio state.
3. **Live integration:** replace presentation components incrementally, leaving store/audio operations and the custom pane shell intact. Keep NOW/NEXT, setlist width, transport placement, countoff overlay, and editor pane stable. The current custom `HStack` exists because `NavigationSplitView` and `.inspector` caused a playback-time layout jump; do not reintroduce them as a styling shortcut.
4. **Remaining surfaces:** Song Library, Pad Library, Audio settings, and system check/diagnostics adopt the same tokens and compact status language. They remain native lists/forms, not copies of the Live command surface.

**Phase 2 exit:** all screens use the same token set and shared state primitives; Live and Rehearse reflect real runtime state without label, route, or layout regressions.

## Phase 3 — verification and polish

- Compare screenshots at 1200 × 700 and a wide window across idle, pre-roll, countoff, playing, transition, warning, blocked, and inspector-open states. Verify positions do not jump during playback.
- Review in dark, light, increased contrast, and Reduce Motion; test bright-room and dark-room legibility. Green glow cannot be the only state cue.
- Walk through keyboard navigation, focus ring, VoiceOver, long song/pad/device names, and every transport shortcut. Check that `Playing`, `Cued`, `Selected`, and `Audible Pad` never collapse into one visual state.
- Run the existing Swift test/build suite and targeted Live/rehearsal manual scenarios. Avoid adding tests that merely restate style implementation; add tests only for state mapping or behavior that could regress.
- If motion or a future real signal meter updates frequently, isolate that state from the whole `AppStore` view tree and verify it does not cause broad re-rendering or stage distraction.

## Work sequencing and current branch

The pre-refresh click-subdivision work was committed as `4758e1e` and the exploration documents as `56a7a41` on `main`, leaving a clean rollback point. The refresh is staged on `codex/future-signal-design-system`: foundation (`b68cc0d`), Rehearse pilot, then Live and remaining screens. Each stage should be committed separately after its build, behavior, and visual review.

## Decisions still to review

- **Light appearance:** default proposal is a designed light counterpart because Sustain already offers System/Light/Dark. Dark remains the signature presentation.
- **Gradient strength:** use the original dark Signal Grid as the baseline; the brighter hybrid is an upper bound, not a target.
- **Playing glyph motion:** default proposal is a quiet pulse with a static Reduce Motion state and explicit `Playing` text.
- **True metering:** defer unless measured signal levels become a product requirement. The present level control continues to show the volume setting.
