# Sustain Design System

## Purpose

Sustain is a native macOS app for worship leaders running pads, click, countoffs, and transitions in live settings. The interface should feel high-end, calm, and deeply trustworthy. It should look like a boutique Mac app built by a small team with excellent taste, while behaving like it belongs on macOS.

The design system exists to make every screen feel intentional:

- clear enough for a volunteer under pressure
- beautiful enough to feel like a premium instrument
- native enough to avoid friction
- restrained enough to keep worship service operation calm

## Product Feeling

Sustain should feel like a quiet piece of reliable stage equipment, translated into modern Apple software.

It is not a studio tool, a dashboard, a worship planning suite, or a visualizer. It is closer to an elegant live utility: focused, tactile, legible, and composed. The best version feels like it could sit beside Things, Bear, Screen Studio, Linear's Mac app, Audio Hijack's clarity, GarageBand's approachable audio tactility, and Apple's own utility apps, while still having its own softer musical identity.

The product should have a subtle physicality. Controls can borrow from mixers, speakers, and music hardware when the metaphor helps the user understand signal, level, routing, and playback. The interface should feel crafted, not themed.

### Brand Attributes

- Calm
- Premium
- Native
- Focused
- Atmospheric
- Tactile
- Reliable
- Warm
- Sparse
- Musical

### Product Promise

The app should make the user feel:

- "I know what is happening."
- "I know what will happen if I click this."
- "I can recover if something goes wrong."
- "The room will not notice the software."

## Design Principles

### 1. State Before Controls

The app's current state must always be more visually prominent than the available actions. In live contexts, the user first needs to know what is playing, what is cued, whether click is active, whether pad is active, and whether the system is healthy.

Controls should be clear, but they should not visually compete with playback state.

### 2. Native Form, Bespoke Atmosphere

Use native macOS structures: sidebars, toolbars, lists, forms, popovers, sheets, menus, keyboard focus, system typography, and standard control behavior.

Make the app feel custom through:

- color
- spacing
- layout hierarchy
- icon treatment
- soft material surfaces
- state visualization
- subtle motion
- branded empty states

Avoid custom controls that break platform expectations.

### 2.1 Modern Apple Materials

Sustain should adopt modern Apple material language as the platform evolves. On systems that support Liquid Glass, native SwiftUI and AppKit controls should be allowed to inherit the new material behavior instead of recreating it manually.

Use glass-like depth for chrome, navigation, overlays, and floating controls. Keep dense data, song titles, routing details, and live status on stable readable surfaces.

### 3. Calm Density

Sustain is operational software, so it should not be sparse in a marketing-page way. It should be information-rich, but organized into calm zones with strong alignment, consistent rhythm, and a limited number of visual weights.

The interface should feel composed, not roomy for its own sake.

### 4. One Primary Thing Per Moment

Each screen should have one dominant purpose:

- Live: run the set safely
- Rehearse: practice pad and click quickly
- Setlist: arrange and prepare
- Library: manage reusable songs
- Audio: configure confidence
- Check: confirm readiness

If a screen has two competing purposes, split the layout into clear regions instead of giving everything equal treatment.

### 5. Motion Confirms, Never Performs

Motion is part of Sustain's identity, but it must always communicate state, transition, continuity, or readiness. It should never feel decorative, busy, or like an audio production gimmick.

Motion should be slow, soft, and low-amplitude.

## Visual Language

### The Core Metaphor

Sustain's visual language is built around the idea of a modern live audio instrument: signal flowing through a quiet, premium control surface.

This creates five recurring visual motifs:

- **Wave**: active sound, continuity, pad motion
- **Pulse**: click, countoff, tempo, timing
- **Signal**: routing, output, readiness, path
- **Level**: pad volume, click volume, gain, balance
- **Field**: the room, resonance, ambience, system atmosphere

These motifs should be quiet. They should appear in active-state indicators, subtle backgrounds, loading moments, empty states, and transitions. Digital audio patterns are welcome when they feel like modern music-player UI: elegant waveforms, soft level movement, calm pulse lines, and low-amplitude signal animation. They should not become EDM graphics, dense frequency analyzers, or decorative oscilloscope UI.

### Audio Hardware Language

Sustain can tastefully borrow from real audio equipment:

- mixer faders for pad and click level
- small signal LEDs for active, ready, warning, and blocked states
- speaker/output cards for routing
- channel pairing for pad and click controls
- transport controls with dedicated hardware confidence
- subtle level meters when audio is active

The hardware metaphor should be used for operational clarity. It should help the user understand "signal is flowing," "this channel is active," "this output is ready," or "this level changed." Avoid fake screws, brushed metal, heavy bevels, rubberized novelty controls, rack-unit aesthetics, and anything that makes Sustain feel like a DAW.

The tone is closer to GarageBand's friendly tactility and Apple Music's modern playback surfaces than a professional mixing console.

### Digital Audio Patterns

Sustain may use music-player-inspired visuals in active states:

- a slow pad waveform behind the active key
- a compact animated pulse for click/countoff
- small level bars beside pad/click volume
- a route line connecting pad and click to outputs
- a soft resonance field during song transitions

These patterns should be functional first. If a pattern does not communicate playback, timing, level, routing, or transition, it should not be on the screen.

### Shape Language

Use simple, confident geometry:

- rounded rectangles at 8px for cards and panels
- 10px to 12px only for larger modal surfaces or prominent active regions
- circular indicators for status and transport
- pill shapes only for badges, segmented controls, and compact status chips
- avoid oversized bubbly corners

Panels should feel like native Mac surfaces, not web cards.

### Surface Language

Sustain should use layered surfaces sparingly:

- app background
- sidebar background
- content background
- panel background
- elevated active surface
- transient overlay

Avoid card nesting. A screen may contain panels, and panels may contain rows or controls, but rows should not become another full visual card unless they represent a repeated item.

## Color System

The existing palette is strong but should be turned into semantic roles. Raw brand colors should rarely be used directly in views.

### Brand Palette

| Token | Hex | Use |
| --- | --- | --- |
| `nearBlack` | `#0E0F10` | Dark app chrome, icon base, high-contrast text |
| `charcoal` | `#171917` | Dark panels, deep active backgrounds |
| `deepOlive` | `#1E231E` | Branded dark surface, active state depth |
| `moss` | `#3A4A39` | Secondary accent, subdued active fills |
| `sage` | `#A8BE9A` | Primary accent, active sound, success |
| `warmIvory` | `#F1EFE6` | Warm light surface, brand contrast |
| `mutedGold` | `#DCCB8A` | Rare highlight, premium accent |

### Semantic Color Tokens

Use semantic names in SwiftUI:

- `SustainColor.background`
- `SustainColor.sidebar`
- `SustainColor.panel`
- `SustainColor.panelElevated`
- `SustainColor.textPrimary`
- `SustainColor.textSecondary`
- `SustainColor.textTertiary`
- `SustainColor.accent`
- `SustainColor.accentSoft`
- `SustainColor.padActive`
- `SustainColor.clickActive`
- `SustainColor.ready`
- `SustainColor.warning`
- `SustainColor.destructive`
- `SustainColor.separator`
- `SustainColor.focusRing`

### Recommended Mapping

For light mode:

- background: system window background, warmed slightly where possible
- sidebar: native sidebar material
- panel: `NSColor.controlBackgroundColor`
- panel elevated: warm ivory with low opacity or system elevated surface
- accent: sage
- pad active: sage
- click active: muted gold
- ready: sage
- warning: system orange, softened
- destructive: system red

For dark mode:

- background: near black or system window background
- sidebar: charcoal
- panel: deep olive mixed with native material
- panel elevated: charcoal
- accent: sage
- pad active: sage
- click active: muted gold
- ready: sage
- warning: warm amber
- destructive: system red, not neon

### Color Rules

- Sage is the main accent, but not a flood fill.
- Gold is reserved for countoff, tempo, premium highlight moments, or one small active detail.
- Orange means warning, not brand.
- Red means destructive or blocked.
- Do not create a monochrome green app. The system needs warm neutrals, native grays, and careful contrast.
- Use native semantic colors for text whenever possible, then tune only where brand expression matters.

## Typography

Use Apple's system fonts exclusively.

### Type Roles

| Role | Font Direction | Use |
| --- | --- | --- |
| `display` | large SF Pro, semibold | Current song, major screen state |
| `title` | title/title2, semibold | Screen and panel headings |
| `body` | system body | General content |
| `metric` | rounded, semibold, monospaced digits | BPM, count, route status, numerical states |
| `label` | caption/callout, medium | Field labels, tile labels |
| `caption` | caption, regular | Secondary metadata |

### Typography Rules

- Use monospaced digits for BPM, countdowns, durations, and device IDs.
- Avoid wide tracking except in the brand wordmark or very small identity moments.
- Do not use oversized hero typography inside utility panels.
- Live-state text can be large, but control labels should remain native and compact.
- Prefer hierarchy through weight and placement before size.

## Spacing And Layout

### Spacing Tokens

Use a compact 4px-based scale:

| Token | Value | Use |
| --- | --- | --- |
| `space2` | 2 | Hairline adjustments |
| `space4` | 4 | Tight label groups |
| `space6` | 6 | Compact row internals |
| `space8` | 8 | Standard small gap |
| `space12` | 12 | Control groups |
| `space16` | 16 | Rows and panel internals |
| `space20` | 20 | Dense panels |
| `space24` | 24 | Screen sections |
| `space28` | 28 | Main content padding |
| `space36` | 36 | Major screen separation |

### Layout Rules

- Align screen content to a consistent inset, currently 24 to 28px.
- Use a persistent left navigation sidebar for top-level areas.
- Prefer two or three functional columns on wide Mac windows.
- Collapse to stacked regions at narrower widths.
- Keep live controls in predictable positions.
- Avoid decorative full-screen compositions inside the app.

## Iconography

Use SF Symbols as the default icon language. They preserve native feel, scale correctly, and fit system accessibility.

### Icon Rules

- Prefer simple line symbols for secondary actions.
- Use filled symbols only for active, selected, or primary states.
- Keep icon color semantic: active pad, active click, warning, destructive.
- Avoid music-note-heavy iconography. Use waveform, metronome, speaker, route, check, and transport symbols.
- Never rely on icon color alone. Pair important state with text.

## Components

### App Sidebar

Purpose: global navigation and brand presence.

Guidelines:

- Keep native `NavigationSplitView`.
- Use a compact brand lockup at top.
- Use SF Symbol labels for screens.
- Avoid over-branding the sidebar.
- Selected state should remain native.

### Screen Header

Purpose: establish screen context and operational status.

Variants:

- standard: title, subtitle, trailing status/action
- live: setlist title, service mode, global status
- utility: title plus primary action

Rules:

- Header should not be visually heavier than live playback state.
- Use trailing area for status, not decoration.
- Keep height stable across screens.

### Status Tile

Purpose: show compact, glanceable state.

Fields:

- icon
- label
- value
- optional detail
- optional severity

Rules:

- 8px radius
- stable minimum width
- icon at fixed width
- active states use accent stroke or soft fill
- values use semibold type

### Song State Panel

Purpose: show playing and cued song information.

Fields:

- song title
- key
- BPM
- time signature
- pad source
- state badge

Rules:

- Playing panel should be most prominent in Live.
- Cued panel should feel connected but secondary.
- Empty state should be calm and explicit.

### Transport Bar

Purpose: safe live operation.

Controls:

- Start
- Previous
- Next
- Stop

Rules:

- Start is primary when a song is cued.
- Stop is visually available but not over-emphasized.
- Buttons should keep stable width.
- Destructive stop should use role and native styling.
- Keyboard shortcuts should be considered later for live operation.

### Secondary Audio Controls

Purpose: manage pad and click independently.

Controls:

- start/stop pad
- start/stop click
- pad volume
- click volume
- countoff

Rules:

- Pad and click should be distinct channels in UI.
- Use waveform language for pad.
- Use pulse/metronome language for click.
- Independent volume should feel mixer-inspired without becoming a full mixer.
- Channel controls should feel paired, tactile, and easy to scan.

### Volume Control

Purpose: adjust pad and click level independently.

Recommended design:

- compact horizontal fader or native slider with custom visual treatment
- icon or channel label at leading edge
- optional small level meter adjacent to the control
- value hidden in Live/Rehearse by default, shown as percentage in Audio Setup or on hover/focus
- pad and click controls paired but visually distinct

Rules:

- Borrow from mixer faders and GarageBand-style controls tastefully.
- Preserve native slider behavior, keyboard interaction, focus, and accessibility.
- Avoid vertical console strips unless the screen specifically benefits from a more instrument-like layout.
- Avoid making Sustain look like a DAW.
- Persist values.
- Changes should apply live.

### Signal Indicator

Purpose: show whether a channel, route, or system check is active, ready, warning, or blocked.

Recommended design:

- small LED-like dot or capsule
- restrained glow only when active
- semantic color plus text
- optional tiny pulse for active click

Rules:

- Do not rely on glow alone.
- Avoid bright neon.
- Active indicators should feel like premium hardware, not gaming UI.

### Output Route Panel

Purpose: make pad and click routing understandable at a glance.

Recommended design:

- two parallel route panels for Pad and Click
- speaker/output icon
- selected device name
- channel selection
- readiness indicator
- warning area when the selected route is unavailable

Rules:

- Treat routing like signal flow.
- Keep diagnostics available but visually secondary.
- Use native pickers and forms for actual selection.
- Use custom panel composition for clarity around route status.

### Resonance Indicator

Purpose: branded active-state visualization.

Use cases:

- active pad
- song transition
- launch/loading
- system ready state

Rules:

- Use `Canvas` or `TimelineView`.
- Low contrast.
- Equalizer-like level movement is acceptable only when it maps to active pad/click state.
- No aggressive frequency animation.
- Prefer slow line drift, ripple expansion, or breathing opacity.
- Must be disable-friendly through Reduce Motion.

### Message Strip

Purpose: communicate last action, warning, or system note.

Rules:

- One line when possible.
- Use semantic icon.
- Informational messages should be quiet.
- Blocking messages should be more visually structured and actionable.

### Data Row

Purpose: show songs, setlist entries, and device rows.

Rules:

- Rows should be dense but breathable.
- Primary text left aligned.
- Metadata grouped after title.
- Inline controls should be aligned to the right.
- Active or cued states should use an icon and accent, not a whole-row color wash.

## Motion System

### Motion Personality

Motion should feel like air moving through a room, not a software trick.

### Interaction Quality Bar

Every interactive element should acknowledge the user's presence before it is clicked.

Required interaction states:

- hover: slight lift, brighter edge, or richer tint
- pressed: quick compression, lower shadow, or darker fill
- selected/on: lit signal state, not just a checkmark
- disabled: visibly unavailable without disappearing
- focus: native keyboard focus remains visible

The product should use tactile feedback inspired by audio hardware:

- buttons feel like responsive illuminated controls
- toggles can behave like lit console buttons
- faders and sliders show level and state
- active routes and channels use restrained LED-like indicators

Do not add bounce, wobble, or playful springiness. The delight should come from precision.

### Current Animation Evaluation

The app should avoid generic waveform motion as ambient decoration. Literal waveform animation is acceptable only when attached to active audio state.

Preferred motion:

- topographic resonance fields for ambient depth
- subtle animated contours on lower-pressure screens such as Rehearse and Audio Setup
- static or nearly static backgrounds on Live Service
- hover/press microinteractions on buttons and rows
- smooth transitions when cue, playing song, or readiness state changes

Live Service should be especially restrained. Motion there must reinforce confidence, not ambience.

### Timing Tokens

| Token | Duration | Use |
| --- | --- | --- |
| `instant` | 0.12s | Button state, small control feedback |
| `quick` | 0.18s | Selection changes |
| `standard` | 0.28s | Panel changes, status changes |
| `slow` | 0.55s | Song state transitions |
| `ambient` | 2.0s+ | Background resonance |

### Easing

Use SwiftUI default ease where possible:

- `.smooth` for most modern state changes
- `.easeInOut` for subtle opacity
- spring only for tactile controls, with low bounce

### Reduce Motion

All ambient motion must respect Reduce Motion:

- stop continuous animation
- replace with static active indicators
- keep state changes legible

## Screen Direction

### Live Service

Design goal: a calm live command surface for Sunday morning.

The screen should answer, in order:

1. What is playing?
2. What is cued?
3. Are pad and click active?
4. Is the system healthy?
5. What is my next safe action?

Recommended layout:

- left: playing and cued stack
- center/right: active signal field and transport
- lower region: pad/click controls, message strip, readiness

Visual emphasis:

- playing song title is dominant
- cued song is secondary but clear
- transport controls are large and stable
- status tiles are glanceable
- audio hardware metaphors are present but subdued
- volume controls are compact and secondary to playback state

### Rehearse

Design goal: a tactile practice surface that feels like a small focused instrument.

The screen should feel more instrument-like than administrative. This is the best place to lean into mixer-inspired level controls, pulse feedback, and active pad visuals.

Recommended layout:

- left: key pad grid with active pad waveform or resonance visual
- center: tempo and click controls
- right or lower: pad/click channel controls, volume, countoff, output summary

Visual emphasis:

- current key and BPM are large
- pad grid is easy to hit
- click pulse gives feedback
- volume controls are paired, tactile, and live
- digital audio patterns should make playback feel alive without becoming decorative

### Setlist

Design goal: prepare the flow.

Recommended layout:

- top: setlist title and add-song control
- main: ordered setlist with cue state
- side or inspector: selected entry details and overrides

Visual emphasis:

- order is clear
- cue target is obvious
- overrides are visible but not noisy
- dangerous actions are quiet but available

### Song Library

Design goal: manage reusable material efficiently.

Recommended layout:

- searchable list/table
- inline metadata
- detail inspector for selected song

Visual emphasis:

- titles and defaults are easy to scan
- adding to setlist is available but not dominant
- editing feels native and low-friction

### Audio Setup

Design goal: routing confidence through signal-flow clarity.

Recommended layout:

- route summary at top
- pad route and click route as parallel speaker/output panels
- diagnostic details below

Visual emphasis:

- pad and click separation is immediately visible
- warnings are actionable
- default/system output is clearly labeled
- advanced diagnostics are available but visually secondary
- route state should feel like audio signal status, not a settings dump
- selected devices can use speaker/interface visual language tastefully

### System Check

Design goal: binary readiness plus actionable details.

Recommended layout:

- readiness summary
- checklist of requirements
- runtime diagnostics

Visual emphasis:

- ready/not ready is obvious
- blockers explain what to fix
- warnings are distinct from blockers

## Native macOS Integration

Sustain should lean into macOS instead of fighting it.

Use:

- `NavigationSplitView`
- native `List`, `Table`, and `Form` where appropriate
- `ToolbarItem`
- menus and keyboard shortcuts
- sheets for focused setup
- popovers for lightweight detail
- system materials
- SF Symbols
- accessibility labels and keyboard navigation

### Liquid Glass Direction

Liquid Glass should be treated as a platform material system, not a decorative effect. Use native SwiftUI/AppKit components and materials so the app inherits modern macOS behavior where available.

Best places for Liquid Glass:

- sidebar and navigation chrome
- toolbar areas
- popovers and sheets
- floating live controls
- compact overlays
- selected-state highlights
- transient status surfaces

Avoid Liquid Glass for:

- dense song rows
- long device names
- critical warning copy
- BPM and key readouts
- system check details
- any surface where transparency reduces confidence

Rules:

- Readability beats material richness.
- Glass is for hierarchy and focus, not decoration.
- Important operational state should sit on stable surfaces.
- If a material makes text feel soft or uncertain, use a more opaque panel.
- Do not hand-build generic glassmorphism when native material is available.

Customize:

- panel styling
- row composition
- active state indicators
- ambient visuals
- semantic color tokens
- screen layouts
- transitions

Avoid:

- web-app-style top nav
- decorative dashboards
- custom scrollbars
- non-native text inputs
- overly custom sliders unless there is a real interaction reason

## Accessibility

Accessibility is part of premium craft.

Requirements:

- support light and dark appearances
- support increased contrast
- support Reduce Motion
- use text plus color for state
- preserve keyboard navigation
- avoid tiny hit targets for live controls
- keep live controls stable in position
- use native control semantics where possible

## Implementation Strategy

### Phase 1: Tokens And Primitives

Create:

- `SustainTheme.swift`
- semantic colors
- spacing tokens
- radius tokens
- type roles
- shared panel styles
- shared status tile
- shared screen header

Outcome: current screens look mostly the same but use the system.

### Phase 2: Rehearse Pilot

Redesign Rehearse first because it exercises:

- pad grid
- click state
- BPM controls
- countoff
- independent volumes
- active audio visualization

Outcome: one complete screen proves the visual language.

### Phase 3: Live Service

Redesign the operational core after Rehearse validates the components.

Outcome: live flow feels premium and safer.

### Phase 4: Library, Setlist, Audio, Check

Bring the remaining screens into the system.

Outcome: full product coherence.

### Phase 5: Motion And Polish

Add:

- resonance indicator
- click pulse
- song transition animation
- subtle active-state changes
- loading and empty-state motion

Outcome: the app feels alive without becoming distracting.

## Design Quality Bar

Before a screen is considered done, it should pass these checks:

- Can the primary user understand the current state in three seconds?
- Does the most important action have the clearest visual path?
- Does the UI still feel native to macOS?
- Is the brand present without shouting?
- Are inactive, active, warning, and blocked states visually distinct?
- Does the layout remain stable under longer song names and device names?
- Does it work in light mode, dark mode, Reduce Motion, and increased contrast?
- Would this screen look credible in a boutique Mac app launch post?
