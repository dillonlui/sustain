# Future Signal interaction contract

**Status:** Phase 0 review contract for the Signal Grid direction. Grounded in `RuntimeSession`, `LiveServiceView`, `RehearseView`, the click subdivision plan, and the selected open-status mockup. The mockup supplies visual intent; runtime state and routing data supply truth.

## State sources and identity

Treat these as distinct values, even when they happen to name the same song:

| Question | Source | Presentation rule |
| --- | --- | --- |
| Which setlist occurrence is playing? | `runtime.playingEntryID` | Only this entry gets the small playing glyph and the word **Playing**. A repeated occurrence of the same `Song.ID` is not playing. |
| Which occurrence will Start use? | `runtime.cuedEntryID` | Cue outline and **Cued** text; it may coincide with Playing. `List(selection:)` currently edits this cue, so list selection must not be reused to infer playback. |
| Which song is in NOW/NEXT? | `store.playingEntry` / `store.cuedEntry` | NOW can be empty while NEXT is cued. NEXT can equal NOW until the operator cues another entry; do not automatically advance it in the UI. |
| Which pad is sounding or fading? | `runtime.audiblePadTrackID`, `runtime.audiblePadEntryID`, and `runtime.padState` | Use this pad's label/owner in status. Never infer it solely from NOW or NEXT; a cued pad can pre-roll without a playing song and an old pad can fade after Stop. |
| Which click pattern is audible? | `audibleClickSubdivision` plus `runtime.clickState` | A pending song default is not yet audible. With click off, describe the next-start setting instead of an audible pattern. |
| Which route is configured and available? | `routingSnapshot` | Show its actual device/channel summary and missing-selection messages. `systemCheck` supplies blocking versus advisory readiness. |

There is no separate arbitrary setlist selection in the current Live view: clicking a row cues it. Keep that interaction. If a later editor selection is added, give it a distinct focus/selection treatment without changing `cuedEntryID` implicitly.

## Live state mapping

| Runtime condition | Setlist / NOW and NEXT | Open Pad / Click status | Transport and notice |
| --- | --- | --- | --- |
| Empty setlist | No row marker; NOW “No song playing”; NEXT “Nothing cued” | Off, unless residual audio is fading; name that truth | Start disabled; clear unavailable. |
| Idle with cue | Cued row outlined and labeled; no Playing glyph; NOW empty, NEXT names cue | Off, or Pad Preparing / Fading In / Playing if cued pad is pre-rolled | Start available only if validation permits; route warning/blocker stays visible. |
| Cued pad pre-roll | Still no Playing glyph or NOW song | Pad names selected audible/preparing pad and says “Cued pad”; Click Off | Start promotes matching pre-roll without implying song playback began earlier. |
| Starting / preparing | No Playing glyph until `playingEntryID` is assigned; keep the cue and the prior NOW if transitioning | Show preparing for the target channel; preserve any already audible pad identity | Start must not issue a second start; Stop remains available. Use existing message strip for failure. |
| Countoff | `playingEntryID` row receives Playing glyph, but NOW/central state must say **Count in**; NEXT remains the cue, possibly the same entry | Click **Count in**; Pad follows its own preparing/fading/playing state | Numbered beat overlay remains in its fixed position; Stop available; active subdivision picker disabled. |
| Playing | Playing glyph + text on exact entry. Cue can be on the same or a different entry; show both roles when same | Pad and Click use independent state words, not one blanket “active” state | Start disabled when cue equals playing entry; otherwise label Transition. |
| Cue changed during playback | Playing marker stays put; cue moves to new entry and NEXT changes | Do not change audible Pad/Click status on cue alone | Transition uses cued entry; Previous/Next only move cue. |
| Transition preparation | Old playing entry stays marked until new activation succeeds; new entry stays cued | Old audible pad may continue; target pad may prepare | Keep transport and warning placement stable. On failure, retain old playback identity and current cue. |
| Stop / pad fade-out | Playing marker disappears and NOW becomes empty; cue is retained | Click Off immediately; Pad **Fading out** with old pad label/owner until cleared | Stop stays enabled while fading; do not say “all off” prematurely. |
| Click independently off / preparing | Song may still be playing | Click **Off**, “next start: [pattern]” / **Preparing**; Pad unchanged | Click action is Start/Stop Click as the current store permits. |
| Blocking fault or advisory | Do not fabricate a Playing state after a rejected start | Each channel continues to reflect runtime truth | Blocking `systemCheck` messages get persistent error notice; advisory warnings stay distinct; no timeout toast. |

The setlist glyph means **song playback identity**, not measured audio or pad/click output. A quiet pulse is optional only while `playingEntryID` is present; keep the word **Playing** and static glyph for Reduce Motion. Do not use the same glyph for cue or hover. The cue uses a distinct edge and **Cued** label. If playing and cued coincide, both labels must remain discoverable without two competing full-row highlights.

## Component behavior

- **Performance surface:** Keep the dark square and fine edge/corner lines, but reserve fixed positions for NOW, NEXT, open channel statuses, transport, and notices. The open Pad/Click readouts are not individual cards. Every status needs icon and words; color/glow only reinforces state. Preparing, fading, countoff, unavailable, and off must not look like ordinary Playing.
- **Transport:** Preserve Previous → Start/Transition → Next → Stop order, existing enablement and shortcuts (Left Arrow, Return, Right Arrow, Command–Period). The primary action says Start when no different song is playing and Transition when a different cue is ready. Start is disabled when the cue is already playing. Stop remains reachable during preparation, countoff, a pending click change, and pad fade. Retain the native button and focus semantics under any custom skin.
- **Level setting:** Pad and Click sliders are persisted 0–100% settings, not signal meters. `LevelMeter` currently renders five bars from the configured slider value. Rename/recast that visual as a setting indicator or remove it. A stylized audio bar glyph in the mockup must not fluctuate or imply measured amplitude. Show percentage and accessible `Pad Volume` / `Click Volume`; native slider keyboard behavior stays intact.
- **Click subdivision:** In Rehearse, the selected segment may show the request while the status/readout continues to name the audible subdivision until the engine confirms it. In Live, the inspector may show pending `At next measure`, while NOW and Click status show `audibleClickSubdivision`. NEXT always shows the cued song's committed default. Countoff displays numbered beats, never subdivision slots; disable the active picker during countoff. On stop, failure, or superseded request, clear pending language. The plan in `19_Click_Subdivisions_UI_UX_Plan.md` is the detailed copy and timing contract.
- **Routing:** Status is not a route picker. The mockup's “Main L/R” and “Click Out” are examples only. `routingSnapshot.summary` is the source for the concise Live readout; missing selection messages and `systemCheck` determine warnings. Route changes belong to Audio settings. A shared Pad/Click output is advisory, not “Outputs ready” without context. Avoid hard-coding device names or asserting separate outputs.
- **Rehearse:** Its selected pad is a session choice, not the Live cue. Rehearse pad and click states come from `rehearse.padState` / `rehearse.clickState`; its session subdivision is independent of song defaults. Preserve search, unavailable pad reasons, and the two-column-to-stacked breakpoint. A selected pad button and a playing pad state need separate appearance.

## Accessibility and stable layout

- Keep native `List`, `Button`, `Picker`, and `Slider` behavior. Ensure keyboard focus is visible on dark and light surfaces, including the cue row, editor action, route/settings navigation, and both faders. Decorative lines, corners, glow, and passive glyphs are hidden from accessibility; row accessibility value conveys “Playing,” “Cued,” or both.
- Use readable text for every state. Do not rely on green hue, animation, or glow. Verify increased contrast and light appearance as well as dark. Honor Reduce Motion for glyph pulse, glow transitions, and numeric countoff transitions. Announce a completed click switch or failure once, never each beat or animated frame.
- Preserve `RootView`'s fixed 220-point sidebar and custom `HStack` panes, Live's 200–340-point setlist width, and its optional 320-point editor. Do not reintroduce `NavigationSplitView` or `.inspector`: both caused the measured playback layout jump in `13_Live_Layout_Investigation.md`.
- Reserve heights for status words, longer subdivision labels, and notices; use wrapping/truncation plus help where necessary. Keep countoff as the existing zero-height overlay beneath controls. Check 1200 × 700, a wider window, and editor open; idle → countoff → playing → transition → stopped must not move the shell or transport.

## Mockup corrections before implementation

1. The “Playing” audio bars are a song-state symbol, not a real meter. Keep them static or gently pulsing and pair them with text.
2. The pictured route menus and device names are invented. Current Live exposes a route summary; editing routes belongs in Audio settings.
3. “Pad Active” and “Click Active” conceal preparing, countoff, fade, off, and failure states. The specimen board needs each variant.
4. NOW and NEXT can name the same setlist entry, and the pad can belong to an old or merely cued entry. The pictured different-song case is only one scenario.
5. The screenshot omits time signature, click subdivision, warning/blocked notices, countoff, and song editor. These remain required and need compositions at minimum size.
6. The pictured large glyph and level bars must not suggest amplitude measured by the audio engine; current app exposes configured volume only.

## Review checklist

- [ ] Fixture states cover empty, cue only, cued pad pre-roll, preparing, countoff, playing, changed cue, transition, pad fade, click off, warning, blocked, and pending subdivision.
- [ ] Exact setlist-entry identity drives Playing; cue and playing remain legible together or apart.
- [ ] NOW/NEXT, audible pad owner, audible click, pending click, and routes each come from their own authoritative state.
- [ ] Start/Transition/Stop semantics, shortcuts, focus, and disabled states match current behavior.
- [ ] Sliders read as settings; no visual implies real signal metering.
- [ ] VoiceOver names states and pending versus audible rhythm; Reduce Motion retains all meaning.
- [ ] 1200 × 700, wide, editor open, long labels, dark/light, and increased contrast remain stable and readable.
