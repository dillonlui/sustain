# Sustain — Design System Refresh Exploration

**Status:** Quiet Console is parked as one explored direction. The [Future Signal exploration](design-refresh/future-signal/README.md) tests a separate non-skeuomorphic visual language. Neither is yet a replacement for [the current design system](11_Design_System.md).
**Grounding:** [Sustain brand brief](sustain_brand_assets_final/sustain-brand-brief.md), [brand assets](sustain_brand_assets_final/README.md), [Live layout findings](13_Live_Layout_Investigation.md), and the current SwiftUI implementation.

## Design intent

Make Sustain feel like a contemporary, premium live audio instrument. Give Pad and Click controls the tactile clarity of a small soundboard, keep the single-wave identity and calm stage presence, and let native macOS glass identify navigation and floating controls. The playing song, cue, routing health, and warnings need stable, legible surfaces.

The existing brand's wave remains singular; the ripple field is supporting atmosphere. Sage remains the main active accent and warm ivory provides contrast. After reviewing the mockups, gold was removed from the active exploration, and the wave should not repeat across content surfaces. The brand brief's exclusions still apply: no DAW density, faux screws, brushed metal, neon, decorative equalizers, or music-note-heavy identity.

## Market patterns worth borrowing

| Reference | Observed implementation | Sustain application |
| --- | --- | --- |
| [Ableton Live 12 mixer release notes](https://www.ableton.com/en/release-notes/live-12/) | Larger fader handles, more legible meter/level relationships, independently revealed mixer sections, and drag behavior that avoids sudden level jumps. | Make the two level controls easy to grab; distinguish their setting from measured signal; reveal advanced routing only when needed. |
| [Ableton Session View](https://www.ableton.com/en/manual/session-view/) | Selected and launched states are distinct. | Keep *cued*, *playing*, and *audible* visually and verbally distinct, particularly during pre-roll. |
| [Logic Pro mixer](https://support.apple.com/guide/logicpro/mixer-interface-lgcpe9cc43f6/mac) and [Smart Controls](https://support.apple.com/en-lamr/guide/logicpro/lgcp7e59f24b/12.2/mac/15.6) | Channel strips expose signal flow; Smart Controls show a focused subset of parameters. | Present Pad and Click as two focused channels, with deeper device and channel choices in Audio settings. |
| [GarageBand Smart Controls](https://support.apple.com/guide/garageband/smart-controls-overview-gbndfd8fa312/mac) | Labeled, approachable controls for the selected sound. | Favor direct, clearly named controls over a miniature mixing console. |
| [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) | Liquid Glass forms a control/navigation layer; content uses stable materials. | Use native glass in sidebar, toolbar, popovers, and floating transport. Keep song text, BPM, warnings, and channel readouts opaque. |

## Three visual directions

### A. Quiet Console — explored, now parked

Deep olive and charcoal matte planes, warm ivory typography, shallow inset Pad/Click channels, satin fader thumbs, and sage signal lamps. The original study included a small gold countoff pulse; that color is no longer part of the proposed palette. The live song is the brightest, clearest information on the surface. Glass sits above the console in navigation, popovers, and transport. Rehearse has the richest tactile treatment; Live uses compact horizontal channels.

**Strength:** feels like crafted stage equipment while preserving three-second readability.
**Watch:** dark surfaces need deliberate contrast in bright rooms, not just dark-booth polish.

### B. Resonance Studio

Warm ivory/stone content surface, deep olive type, translucent chrome, and a thin organic resonance field tied to the active key or transition. Controls have soft edges and a luminous but restrained level fill. Critical live state would sit on more opaque panels.

**Strength:** welcoming and distinctly tied to the existing wave/ripple identity.
**Watch:** atmosphere and translucency can weaken contrast in a live setting.

### C. Field Instrument

Graphite chassis, ceramic control islands, short recessed rails, compact backlit channel buttons, and explicit signal paths to outputs. Rehearse and Audio settings could use short vertical faders; Live would retain compact horizontal ones.

**Strength:** strongest physical instrument identity.
**Watch:** higher custom-control cost and the greatest risk of looking like a DAW.

**Initial synthesis, now parked:** Quiet Console as the foundation, Resonance Studio's organic wave in a few active/transition moments, and a small amount of Field Instrument tactility in Rehearse. The repeated wave treatment in the generated mockups felt busy, so any future use needs a specific purpose.

Initial [Rehearse](design-refresh/mockups/quiet-console-rehearse.png), [Live](design-refresh/mockups/quiet-console-live.png), and [channel-state](design-refresh/mockups/quiet-console-channel-states.png) mockups explore this direction. They are visual studies; [their notes](design-refresh/mockups/README.md) identify where generated UI differs from implemented behavior.

## Proposed component grammar

1. **Channel module:** persistent Pad or Click name; explicit state text with a small signal lamp; a wide, keyboard-accessible native slider with a more tactile track/thumb treatment; visible percentage on focus, drag, or in detailed views; a separate route summary. Keep each channel's geometry stable as its state changes.
2. **Signal meter:** represent actual measured audio only. The current `LevelMeter` in `SustainDesignSystem.swift` renders the configured volume value; it is a *level setting indicator*, not a signal meter. Rename/reframe it in the pilot, or add a real metering source before showing active bars. A high-frequency meter should have isolated UI state and a restrained update rate.
3. **Transport:** retain the existing order, widths, keyboard shortcuts, and native button semantics. Add a subtle pressed face and clear hover/focus treatment. Keep Stop visible and stable; keep the current song and cue visually dominant.
4. **Status and routing:** pair every lamp/color with text. Show Pad and Click output destinations in a compact read-only summary; use native pickers in Audio settings. Keep audible state separate from requested settings when changes are pending.
5. **Resonance:** one low-amplitude wave/field linked to a real active pad or transition. Static equivalent under Reduce Motion. Do not put continuous motion behind Live song text.

## Pilot and rollout

1. **Resolve direction and palette.** Quiet Console is parked while Future Signal is explored; gold is removed for now. If a second highlight color is needed later, tie it to a clear semantic role.
2. **Prototype Rehearse at real window sizes.** Build one complete Pad/Click channel pair, active-pad surface, and restrained countoff pulse. Compare light/dark, idle/active, hover/focus, and a long pad name. Preserve native slider interaction and VoiceOver values.
3. **Validate the operating model.** Check keyboard level changes, click/drag behavior, Reduce Motion, Increase Contrast, narrow-window stacking, and whether the two channels are understood at a glance. Do not call configured level a live meter.
4. **Apply a compact version to Live.** Preserve NOW/NEXT prominence, transport positions, setlist column, countoff overlay, and the shell layout fixed in `docs/13_Live_Layout_Investigation.md`. Validate idle, cued, playing, countoff, transition, warning, and blocked states without layout movement.
5. **Extend to Audio, Library, and Setlist.** Share tokens and primitives; keep forms and lists native. Reserve richer control surfaces for places that handle sound directly.

## Decisions to make together

- Quiet Console was selected for the first mockup pass and is now parked while Future Signal is explored.
- Gold is removed for now. A second highlight can be reconsidered if a clear need emerges.
- Is a compact visual level setting sufficient for the first pass, or is true live signal metering important enough to add to the audio engine?
- How much physicality should Rehearse have compared with Live: subtle horizontal faders on both, or more instrument-like controls in Rehearse?
