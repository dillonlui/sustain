# Future Signal — visual language exploration

**Status:** Signal Grid with open Pad/Click status is the preferred visual reference for [the implementation plan](../implementation-plan.md). Quiet Console remains parked. These images are visual studies, not app specifications or implementation changes.

## Feedback carried forward

- Remove muted gold from the active palette; revisit a second highlight only if a concrete semantic need emerges.
- Use the one-stroke Sustain wave as a brand mark, not as a repeated graphic across song cards and pad keys.
- Preserve the Live setlist idea of a small playing glyph beside the active song. Its motion represents **playback state**, not measured audio amplitude. Pair it with text, and show a static glyph under Reduce Motion.
- Keep current song, next cue, Pad/Click activity, and route health readable at a glance.
- Latest preference: return to Signal Grid's darker, less bright treatment and retain its larger glassy square performance surface; remove only the individual containers around Pad and Click status.

## Research and translation

The reference is the feeling of a futuristic interface in *Tron: Ares*, not its specific marks or screen compositions. [Lead UI designer Jayse Hansen](https://www.behance.net/gallery/243906803/TRON-ARES-UI-The-Concept) describes an architectural, scaffold-like system and a mixture of human-readable labels with machine-like patterns. [Motion director Darby Faccinto](https://www.darbyfui.com/tronares) describes finding a rhythmic processing cue that gave the HUD a sense of weight. [ILM's artists](https://www.ilm.com/tron-ares-ilm-sydney-visual-effects-capogreco-alvarado-interview/) emphasize shape and form without making every shot busy. Our inference for Sustain: use alignment, restrained light, and a tiny rhythmic state cue to communicate an operational system; keep decorative technical data out of the interface.

## Visual experiments

| Mockup | Tested idea | What to judge |
| --- | --- | --- |
| [Signal Grid · Live](signal-grid-live.png) | Fine architectural rails, corner markers, luminous active region, explicit status. | Is the framing compelling or too boxy? Does NOW remain the first read? |
| [Luminous Field · Live](luminous-field-live.png) | Broader emerald gradient depth, fewer panel borders, more spatial calm. | Does this feel future-facing without becoming too empty or atmospheric? |
| [Signal Field · Rehearse](signal-field-rehearse.png) | Green-light key and BPM states, flat pad matrix, linear levels, conceptual route flow. | Does the language extend to a denser, hands-on screen? |
| [Hybrid v1 · Live](signal-field-hybrid-v1.png) | Signal Grid's layout with a localized green gradient behind NOW. | Is this enough added depth, or too close to Signal Grid? |
| [Hybrid v2 · Live](signal-field-hybrid-v2.png) | The same layout with a more open NOW field, quieter status separators, and broader soft gradient. | Does the stronger spatial treatment improve the screen without weakening readability? |
| [Signal Grid · open status](signal-grid-live-open-status.png) | Dark Signal Grid surface and framing retained; Pad/Click readouts sit free inside it, separated by space and a faint rule. | Does this resolve the status-card clutter while keeping the original's depth? |

## Candidate system rules

- **Color:** graphite and near-black foundations; one green family from deep emerald to pale mint for active and selected states; off-white for essential text. No gold. Warnings and destructive actions retain explicit words and appropriate system severity cues.
- **Depth:** use broad, low-contrast gradients and local edge light near meaningful state. Do not apply glow to every panel, icon, or outline.
- **Geometry:** strong alignment, fine seams, occasional bracket or rail, flatter controls. Prefer stable rectangles and open space over nested cards.
- **Type:** native SF with large song/key/BPM readouts, compact labels, monospaced numbers. Avoid tiny letterspaced “movie HUD” copy for important information.
- **Motion:** only playback, cue transition, countoff, or route changes. A playlist playing glyph can pulse quietly; it must not imply a true audio meter. Reduce Motion gets a static state.
- **Platform behavior:** keep native keyboard, focus, hover, VoiceOver, lists, and safe Live layout. The futuristic language is a visual layer over trustworthy Mac behavior.

## Known mockup artifacts

The generated images invent some copy, navigation items, tempo controls, and route topology. Those are not proposals. In particular, the Rehearse diagram should not be taken as the actual Pad/Click routing model, and its bars are not real signal meters. The desktop app should preserve its actual song states, device selections, shortcuts, and accessible controls.

## Current direction

The chosen reference is [Signal Grid with open status](signal-grid-live-open-status.png): dark overall tone, a large subtle glassy performance square, and Pad/Click readouts without individual containers. The brighter hybrid is retained as an exploration but is not the current brightness target. The next work is the design-system specification, state sheets, and two real-content compositions described in the implementation plan.
