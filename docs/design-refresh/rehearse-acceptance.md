# Future Signal Rehearse — Phase 2 acceptance

**Scope:** visual and interaction acceptance for applying the shared Future Signal system to the real `RehearseView`. Fixture [dark](renders/signal-grid-rehearse-dark.png), [light](renders/signal-grid-rehearse-light.png), and [stacked](renders/signal-grid-rehearse-stacked-dark.png) renders show intended composition; runtime state and control behavior come from `AppStore.rehearse` and the audio engine.

## State scenarios

| Scenario / setup | Expected UI and behavior |
| --- | --- |
| Open Rehearse with selected C pad, pad and click off | C may show `Selected` but never `Playing`; open Pad/Click readouts say `Off`. Pad Stop is disabled. The selected pad title remains visible independently of audio state. |
| Select and start an available pad | Tile first says `Preparing`, then `Fading In` / `Playing` from `rehearse.padState`; only that pad tile gets playing treatment. The open Pad readout uses the same state, and the Click readout does not light merely because a pad starts. |
| Start a different pad or stop current pad | Old playing identity clears or transitions according to store truth; no two tiles claim `Playing` from selection alone. `Fading Out` remains visible until the pad is actually off. Stop Pad remains available while pad activity persists. |
| Custom pad file missing, changed, unreadable, permission denied, or volume unavailable | Tile shows the specific asset condition, is disabled when `PadAssetState.isAvailable` is false, and remains distinguishable from an off but available pad. Full filename/label is available by help and VoiceOver. No green playing signal appears. |
| Click off → preparing → countoff → playing | The open Click readout names each phase from `rehearse.clickState`. Countoff is visibly distinct from ordinary playing; BPM and time signature remain fixed in place. The click button reflects the action it will take, and controls remain keyboard operable. |
| Change subdivision while click is playing | Keep the audible subdivision visible as current until the audio engine commits the change; show `Switching to … next measure` for `pendingRehearseClickSubdivision`. On commit, current updates and pending clears. On failure, retain the actual audible value and show the error. |
| Try to change subdivision during countoff | Picker is disabled and explains why; no pending change is implied. Once countoff ends, it becomes available again. |
| Click off with configured subdivision | Show the configured value as the next-start setting, not as audible click. Pad state remains independent. |
| Adjust Pad and Click levels, including 0 and 100% | Native sliders step by keyboard and announce `Pad/Click volume setting` with percentage. Values persist through the existing store commit path. No moving meter or waveform implies measured output; a nonzero setting does not imply the channel is playing. |

## Layout and accessibility checks

1. At **1200 × 700**, the pad and click panels sit side by side, their controls fit without clipping or overlap, and the selected/playing pad is visibly distinct from other pads by border/fill **and text**. The large top performance surface contains open Pad/Click statuses without separate status cards. Long custom labels and device names truncate only with a full help and accessibility value.
2. At **760 × 700**, the panels stack in a vertical scroll view. All pad controls and the entire click panel remain reachable by scrolling, with no horizontal overflow. Changing pad/click/countoff state does not jump the header or top surface.
3. In **dark and light**, normal text is at least 4.5:1 against its rendered background; meaningful icons/edges are at least 3:1. In **increased contrast**, active, selected, unavailable, focused, and disabled states stay distinct with text and a visible border/focus ring. Severity messages use words and icons, not hue alone.
4. With **Reduce Motion**, playback and countoff state remain readable through static glyphs and labels; no ambient glow animation or pseudo audio bars are required. VoiceOver says the selected pad, its actual playback state, the current and pending click subdivision when relevant, and slider labels/values. Avoid announcing every countoff beat.
5. Retain current Rehearse operations: pad search and Show Included Pads filter, pad start/stop, click start/stop, countoff, BPM slider and stepper, time signature, accent, countoff sound, subdivision, volume commits, and route/audio status. New visuals must not alter their enabled states or audio behavior.

**Review gate:** capture real-runtime screenshots for off, preparing, playing, unavailable, countoff, pending subdivision, and a route warning at both widths; compare with the specimens and run the existing build/tests. A screenshot alone cannot prove audio truth, so verify the displayed labels against the store fields during each manual scenario.
