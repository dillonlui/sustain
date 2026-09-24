# Future Signal — Phase 0 system specification

**Status:** implementation source of truth for component specimens and static Live/Rehearse compositions. [Selected visual reference](future-signal/signal-grid-live-open-status.png). Runtime behavior remains defined by `RuntimeSession`, `RehearseSession`, and `AppStore`; the generated image does not define controls or routing.

## Intent and hierarchy

Use a near-black, graphite, and deep-olive instrument face with one restrained sage-to-mint signal family. Live's dominant element is a large, dark, subtly glassy **square-like performance surface**: opaque enough for crisp content, a low-contrast internal gradient, a hairline edge, and sparse corner ticks. Keep NOW, NEXT, open Pad/Click readouts, and transport inside this single frame. Pad/Click get spacing or one faint divider, never individual status cards. The setlist stays beside it; channel level controls and route summary may sit below. Preserve the real Live pane geometry and transport order. Do not copy the mockup's invented navigation, route pickers, or labels.

Priority: **NOW → NEXT → Pad/Click and routing truth → transport → level settings → secondary metadata**. Green light indicates actionable or active state, not decoration. The Sustain wave belongs in the app mark and rare transition use; do not repeat it across rows or controls. No gold is used in this direction.

## Semantic tokens

Tokens resolve for the app appearance (`System`, `Light`, `Dark`) and `accessibilityContrast`; views use roles, not hex values. Values below are starting specimens to tune against rendered screenshots, not permission to scatter literals in view code. Use sRGB values only in the token layer. Warnings and errors use macOS semantic severity colors with text and symbols.

| Role | Dark start | Light start | Increased contrast rule |
| --- | --- | --- | --- |
| `canvas` | `#0E0F10` | `#F1EFE6` | Keep background solid. |
| `sidebar` | `#111613` | `#E9ECE5` | Separate from canvas with an explicit edge. |
| `performanceSurface` | `#141A17` to `#19251D` low-contrast gradient | `#F8F9F5` to `#EEF3EC` | Use the flatter first stop; remove atmospheric wash. |
| `panel` / `panelElevated` | `#171C19` / `#1E2520` | `#FFFFFF` / `#F4F7F1` | Increase border separation; no transparency-dependent text. |
| `surfaceEdge` / `divider` | ivory at ~18% / ~12% opacity | deep olive at ~22% / ~16% | ≥1 px visible solid edge, tune by screenshot. |
| `activeSignal` | `#A8DDB1` | `#326A43` | Brighter/darker until state and nearby text pass contrast checks. |
| `activeSignalSoft` | `activeSignal` at ~10–16% fill | `activeSignal` at ~8–12% fill | Replace wash with edge + glyph + text. |
| `cuedEdge` | sage at ~65% | deep green at ~70% | Solid edge plus `Cued` text; distinct from playing glyph. |
| `focus` | native focus ring, sage-tinted only if visible | native focus ring | Do not override system high-contrast ring. |
| `textPrimary` / `textSecondary` | `#F1EFE6` / `#B5BFB5` | `#182019` / `#4A594D` | Prefer native dynamic label colors where they provide stronger contrast. |
| `textTertiary` | `#92A096` | `#607064` | Never use for live state, route fault, or action labels. |
| `warning` / `blocked` | system orange / system red | system orange / system red | Icon + explicit message + stable notice placement. |

`selected` is an interaction state; `cued` is the target of Start; `playing` is playback identity; `audible` describes active audio. Do not collapse these into one green fill. Native selected-list treatment can remain, but a cue edge/label and playback glyph/text must still be independently visible. The active signal may light a single region or control at a time; inactive frames stay mostly dark. Do not use a global neon bloom.

## Geometry, type, and effects

- **Spacing:** preserve the existing 4/8/12/16/20/24/32 pt scale. Main pane inset 24 pt, setlist row hit height at least 44 pt, open channel readouts separated by at least 24 pt. Avoid shrinking the 1200 × 700 composition below readable native type.
- **Shape:** performance frame radius 8–10 pt and thin corner ticks only on that frame. Secondary panels radius 8–10 pt; controls 6–8 pt. Avoid nested framed cards inside the performance frame.
- **Stroke:** default 1 pt hairline; active frame 1 pt signal edge at moderate opacity; focus uses the native ring. No thick outline around every row. At increased contrast, use an opaque 1–2 pt outline where required.
- **Glass and light:** dark performance frame uses an opaque base and at most a 4–7% directional gradient lift; edge light can brighten locally for active/transition. Text sits on stable fill. Use native system material for appropriate control chrome on supported macOS, with an opaque fallback for macOS 14. No blur behind dense Live content.
- **Glow:** maximum one local green halo per active region, roughly 8–16 pt blur and ≤18% opacity at the token layer. Off, idle, and normal selected states have none. Increased contrast removes blur. The brighter Luminous Field studies are an upper bound, not the target.
- **Typography:** SF system fonts. NOW song 32–44 pt semibold at minimum-window width, with controlled truncation; NEXT 22–28 pt semibold. Screen title 24–28 pt; section heading 15–17 pt; body 13–15 pt; utility labels ≥11 pt. BPM, count, percentage, and meter use monospaced digits. Never require tightly tracked microcopy to convey status. Long titles get a useful single/two-line limit, help text, and full VoiceOver name.
- **Motion:** hover/press feedback 100–160 ms; state edge transition 180–280 ms; cue/playing glyph may pulse slowly (about 1.4–2 s cycle) only while playing, with very low amplitude. No simulated waveform or animation tied to volume setting. Reduce Motion uses a static glyph and instantaneous state/number updates. Countoff may change digits without moving layout; avoid per-beat VoiceOver announcements.

For normal text, verify at least 4.5:1 contrast; for large text and meaningful icons/edges, at least 3:1. Test actual composites, not token pairs alone. State always has words and/or shape in addition to color.

## State contract

Read identity from `runtime.playingEntryID`, cue from `runtime.cuedEntryID`, audible pad from `runtime.audiblePadTrackID` **and** `audiblePadEntryID`, and channel phase from `padState` / `clickState`. A song can be cued while an earlier pad remains audible. `playbackPhase == .songStarting` is preparation, not playing. The Live setlist playing glyph is driven only by a non-nil playing entry ID, never by pad/click activity or a level value. It is paired with `Playing` text. The cue uses `Cued` text and a quiet edge; an item may be both playing and cued. List selection/focus remain separate native interaction treatments.

| Situation | Main readout / setlist | Open Pad / Click readouts | Controls and notice |
| --- | --- | --- | --- |
| Empty setlist | `No song playing`; `Nothing cued`; no playing glyph | `Pad Off` / `Click Off` | Start disabled; clear add-song path. |
| Idle with cue | NOW empty; NEXT title and `Cued` row; no playing glyph | Off, unless pre-roll below | Start enabled if valid. |
| Cued pad pre-roll, no song playing | NOW still empty; NEXT stays cued; no playing glyph | Pad `Playing` or `Fading In`, with audible pad owner named if it differs from cue; Click Off | Show mismatch warning when cue changes while old pad sounds. |
| Start preparing | `Preparing <cued title>` in stable NOW footprint; no playing glyph until `playingEntryID` exists | Pad/Click `Preparing` as applicable | Start disabled/guarded by store; previous playback, if present, remains explicitly shown. |
| Countoff | NOW shows actual playing entry and `Playing` row; NEXT remains cue, possibly same entry | Pad phase from runtime; Click `Count in` and beat/total | Countoff overlay has reserved/stable placement. |
| Playing | NOW title + key/BPM/meter; row glyph + `Playing`; NEXT shows cue even if same | Pad `Playing`/`Fading In`/Off; Click `Playing`/Off | Start disabled when cue equals playing entry; Stop available. |
| Cue changed during playback | NOW and playing glyph stay on original entry; NEXT and `Cued` move | Audible pad owner remains original until actually switched | Start label may become `Transition`. |
| Transition | Keep old NOW until store commits new playing entry, then update atomically; no invented dual-playing rows | Show actual pad fades and click state | Do not imply both songs are audible merely from cue state. |
| Stop / pad tail | NOW empty once playing ID clears; no playing glyph | Pad `Fading Out` until actual off; Click Off | Stop remains available while audio activity persists. |
| Warning / blocked | Current song and cue remain readable | Retain actual channel states | Stable inline warning or blocked notice with icon and message; never paint all content red. |

For Live and Rehearse, the click subdivision label shows **audible** `AppStore.audibleClickSubdivision` while click sounds. If `pendingLiveClickSubdivision` for the playing song or `pendingRehearseClickSubdivision` exists, show `Current: … · Switching to … next measure` in text; the selected value must not masquerade as already audible. While countoff is active, subdivision editing stays disabled as in current behavior. Click Off may show the configured value as `Next start: …`. Pad and Click use the same green family, distinguished by name and icon, never by gold.

In Rehearse, a pad can be selected while off; selected key/pad is not `Playing`. A tile becomes `Preparing`, `Fading In`, `Playing`, or `Fading Out` only from `rehearse.padState` and the selected pad ID. Unavailable assets show their real condition (`Missing`, `Permission needed`, etc.) and disabled action. Rehearse click shows `Off`, `Preparing`, `Count in`, or `Playing` from `rehearse.clickState`, with BPM/meter/subdivision visible. Pad and Click remain independent channel readouts; one active channel must not light the other.

## Component variants and specimen board

Build a deterministic SwiftUI preview gallery (or equivalent in-app debug board) before wiring the new skin. Each row below needs dark, light, and increased-contrast variants; hover, pressed, keyboard focus, and disabled where interactive. The gallery is the visual contract for screen migration.

| Component | Required variants / content |
| --- | --- |
| `PerformanceFrame` | idle, cued, preparing, countoff, playing, transition, warning, blocked; stable bounds and corner ticks; long NOW/NEXT titles. |
| `SongReadout` | empty, title/key/BPM/meter, same song NOW+NEXT, long title, missing song. |
| `SetlistRow` | plain, selected, cued, playing, playing+selected/cued, missing, disabled edit; static and animated playing glyph. |
| `OpenChannelStatus` | Pad/Click off, preparing, countoff, fading in/out, playing, unavailable; owner mismatch text. No local card. |
| `ChannelLevel` | 0, 50, 100%, active/off, focus, disabled; native keyboard-accessible slider. Label as `volume setting`, never `signal meter`; remove or rename the current `LevelMeter` bars if they imply measured amplitude. |
| `TransportControl` | Previous, Start/Transition, Next, Stop in current order; hover, press, focus, disabled, destructive. Preserve shortcuts. |
| `RouteSummary` and `Notice` | ready, shared output warning, missing device/channel, blocked; exact device/channel names, truncation help, full accessibility text. Routing selection remains in Audio settings. |
| `RehearsePadTile` and `ClickControl` | selected/off/playing/unavailable pad; click off/preparing/countoff/playing/pending subdivision; long pad and file labels. |

## Composition and acceptance examples

1. At **1200 × 700** and one wide size, Live retains its resizable setlist and optional editor pane, NOW/NEXT hierarchy, large frame, four-control transport order, and stable countoff placement. No content or pane shifts when playback starts, countoff ends, or the editor opens. Rehearse stacks columns below its existing 1040 pt threshold without horizontal overflow.
2. Fixture: `Build My Life` playing; `Goodness of God` cued; Pad `C` still audible for `Build My Life`; Click playing at `Beat`; `2 per beat` change pending. Expect one playing row with glyph+`Playing`, one `Cued` row, Pad owner text, `Current: Beat · Switching to 2 per beat next measure`, and no animated bars pretending to measure signal.
3. Fixture: no song playing, `Holy Forever` cued, earlier Pad `G` fading out. Expect no playing glyph, NOW empty, NEXT cued, Pad `Fading Out` with owner/mismatch notice, and Stop available until fade completes.
4. Fixture: Rehearse pad `Warm Atmosphere — Extended Mix` selected but off, Click countoff active, output unavailable. Expect selected pad styling without `Playing`, stable count numeral, route fault wording, and a visible blocked/warning notice. Long text remains accessible.
5. Verify pointer, keyboard, VoiceOver, dark/light, increased contrast, and Reduce Motion. A volunteer should distinguish **playing, cued, selected, and audible pad** without relying on hue or animation. Focus must be visible on every actionable element.

## Open decisions after specimen review

- Exact gradient stops, edge opacity, and glow strength should be tuned from app-rendered specimens against the selected mockup; the initial numbers above are guardrails.
- The playing glyph can be a static `speaker.wave.2.fill` or a restrained vertical signal mark. Choose after seeing its size in the real setlist. In either case it denotes playback identity, not sound amplitude.
- True audio metering is out of scope until measured engine levels exist. The present five-bar `LevelMeter` reflects a volume **setting** and should be renamed/redesigned or removed during component work.
