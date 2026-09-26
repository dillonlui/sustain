# Advanced click: implementation plan

This plan covers tap tempo, per-beat accent/mute patterns, compound-meter grouping, and count-off options. Click sound presets are outside this scope. Sustain is a live worship tool, so every new control must distinguish a requested change from the rhythm that is actually audible and must leave Stop available.

## Baseline and sequencing

Sustain currently persists each song's integer BPM, meter, and subdivision; Rehearse has separate session values. `ClickSettings` stores the global No Accent/Downbeat choice and Count + Click/Click Only count-off sound. Live starts with one bar of count-off; Rehearse has an on/off switch. `AudioEngine.makeClickBuffer` renders one measure of PCM, and `ClickLoopRenderer` can swap a prepared measure at a boundary. The counted count-off is currently one measure with spoken numbers. The visual count-off is driven by a separate task, so it is advisory rather than the audio clock.

Implement in four independently releasable milestones, in the order below. First, define a single `ClickConfiguration` or equivalent value containing BPM, meter/pulse interpretation, subdivision, accent pattern, count-off policy, and count-off sound. Use it to compare asynchronous preparation requests and to render the loop and count-off from the same snapshot. Keep session identity and a monotonically increasing request generation on every prepared change; a stale callback must never change the active song or audible readout. Reuse the boundary-switch path for same-length pattern edits. Changing BPM or pulse duration needs an explicit restart or a separately proven phase-safe transition; do not treat a loop of different frame length as an ordinary boundary swap.

## 1. Tap tempo

### Product contract

- Put **Tap tempo** beside BPM in Rehearse and in the Live editor for the cued song. Add a dedicated MIDI action and a non-conflicting keyboard shortcut after checking existing transport shortcuts. A tap must never trigger Start or Transition by itself in the first release.
- Accept at least three taps and display a provisional BPM plus a clear **Use tempo** action. Measure tap intervals with a monotonic clock; reset after a pause (proposed: two seconds), reject implausible/outlier intervals, use a short rolling median or trimmed mean, and clamp to the current supported BPM range. Show when the sequence resets. Test half-time/double-time interpretation with musicians rather than guessing from a meter.
- Rehearse applies the result to its session BPM. In Live, tapping a cued song changes a **session tempo override** for that setlist entry; provide an explicit **Save as song default** action. This prevents an improvised Sunday tempo from changing every future use of that library song. Make the override visible in NOW/NEXT and clear it at the end of the service or when the setlist is replaced. If the product does not want entry-level overrides, decide that before implementing the UI; do not silently write every tap to `Song.defaultBPM`.
- While the click is playing, leave tap-to-retime disabled in the first milestone. Add it later only after a measured, phase-safe tempo-change design. Pad playback must continue unaffected by tapping and applying a tempo before Start.

### Implementation and checks

Create a small pure `TapTempoEstimator` with injected timestamps. Route keyboard, button, and MIDI Note/CC edge events into the same estimator so MIDI repeats or held controls cannot count as multiple taps. Extend `MIDIAction` without changing existing mappings. Use the existing BPM validation and click preparation path when **Use tempo** is pressed. Test jitter, missed taps, timeout, range limits, rapid cue changes, MIDI duplicate edges, and persistence of the song default. Verify that applying a tapped BPM during preparation invalidates the old prepared click.

## 2. Per-beat accents and mute

### Product contract

- Add a compact pattern row for each BPM pulse in a bar. Each cell cycles **Strong / Normal / Soft / Mute**; make the downbeat visible, and provide **Reset to default**. Use words, level bars, and VoiceOver labels, not color alone. A muted pulse does not remove its subdivision clicks unless the UI explicitly says so; the recommended rule is that mute suppresses the pulse and its subdivisions for that position.
- Store the pattern per song, because songs in one setlist need different feels. Rehearse gets an independent session pattern. Keep the existing global No Accent/Downbeat setting as the fallback when no song pattern is specified. On first open after migration, the click must sound exactly as before. Editing a song in the library changes all occurrences of that canonical song, consistent with subdivision behavior.
- Require at least one audible event per measure or show an explicit **Silent bar** warning; a fully muted pattern should not accidentally masquerade as a broken output. Recompute or ask to reset a custom pattern when the pulse count changes; never truncate it without feedback.

### Implementation and checks

Represent levels as a stable Codable enum and a fixed-length array tied to the song's pulse count. Add optional song storage so `nil` preserves the current global behavior; bump `LibrarySnapshot.currentSchemaVersion` and migrate older files to `nil`. Extend the renderer's event gain/accent selection rather than generating additional overlapping tones. Prepare a complete new PCM loop off the audio thread, queue it at the next measure, and update the audible UI only when the renderer reports the switch. Test all levels, full mute, combined subdivisions, per-song isolation, migration PCM parity, peak headroom, rapid edits, and failed preparation. Record hardware output across repeated boundary changes to check for missing or doubled clicks.

## 3. Compound-meter grouping

### Product contract

- For 6/8, 9/8, and 12/8, offer two explicit pulse interpretations: **Eighth-note BPM (legacy)** and **Dotted-quarter BPM (grouped)**. Grouped mode has respectively 2, 3, or 4 BPM pulses per bar, each spanning three written eighths. Label the tempo field with its pulse unit; `72 BPM` alone is ambiguous here. Existing songs remain in legacy mode and retain their exact duration and sound until edited.
- Subdivisions continue to mean clicks **per BPM pulse**. The accent row uses 2/3/4 cells in grouped mode. Spoken count-off says 1–2, 1–3, or 1–4, matching those pulses. For 2/4, 3/4, 4/4, and 5/4, keep current pulse behavior. Do not infer grouping from the denominator alone.
- When a user switches interpretation, preserve the current bar duration by proposing the equivalent BPM (legacy eighth-note BPM divided by three when moving to grouped mode; multiply by three in reverse), rounded only if needed and shown for confirmation. If the equivalent is outside the supported range, require an explicit valid BPM. A separate **keep numeric BPM** choice may be offered with a duration preview, but must not be the silent default.

### Implementation and checks

Add a persisted pulse interpretation to `Song` and a separate Rehearse value. Bump the library schema again if this lands in a later release; migration defaults to legacy. Introduce a pure meter/pulse-grid model: pulse count, frames per pulse, bar duration, grouping boundaries, and display label derive from one source. Render loop and count-off from that grid; avoid calculating loop duration in one place from `beatsPerMeasure` and onset positions elsewhere. Update the visual count-off total and all BPM/meter summaries. Test 6/8, 9/8, and 12/8 both ways at multiple BPMs and sample rates; assert exact expected onsets, measure length, subdivisions, accents, count-off numbers, and no loop-seam anomaly. Include an audible musician review of the label and tap interpretation before shipping.

## 4. Count-off options

### Product contract

- Add a per-song policy: **None**, **1 bar**, or **2 bars**, plus **Continue click** or **Count-off only**. Keep current Live behavior (one bar, continuing click) as the migration default. Rehearse can use the same controls as session settings; its existing on/off switch maps to None versus the last selected length. Retain the global Count + Click/Click Only sound choice for each count-off bar.
- A two-bar spoken count-off repeats the pulse numbers in each bar; the UI shows `Bar 1 of 2 · Beat 3 of 4`. Count-off only stops the click precisely after the final count-off bar while pads and song state continue. Show **Click stops after count-off** clearly in the editor and Live preflight/now state so the silence is intentional. None starts the click immediately when Continue click is selected; None plus Count-off only is invalid and should be unavailable.
- Preserve Sustain's existing start behavior: pads can begin or crossfade while the count-off sounds. **Count-off only** means the click becomes silent at the final count-off boundary while pads continue. Preserve Stop and transitions during either bar. A count-off policy change while counting is deferred to the next start or disabled, consistent with subdivision edits.

### Implementation and checks

Add a persisted `CountoffPolicy` to `Song`; bump schema and migrate old songs to one bar/continue. The audio engine should build 0/1/2 bars from the same pulse grid and render click-only or numbered speech accordingly. Remove any assumption that a count-off buffer is exactly one measure. The existing `ClickLoopRenderer` has an 18-second preallocated slot sized for 12 beats at 40 BPM; validate capacity against the new maximum two-bar count-off and resize safely before enabling the setting. Give the renderer an explicit terminal mode for Count-off only instead of queuing a silent loop whose state still says Playing. Report the audio-owned count-off completion to the store so the UI and click state cannot drift from the rendered audio; the existing timer can remain only as an approximate beat display until replaced by frame-based progress. Test every policy with every meter/pulse interpretation, counted and click-only sound, fast-tempo speech fallback, stop during bar 1 or 2, missing output, restart, and pad continuity.

## Shared release gates

1. **Persistence:** round-trip current data; migrate v1–v4 libraries without changing audible defaults; reject malformed current-schema values; retain rolling backup behavior. Check every song-copy path so editing key, pad, title, or BPM preserves the new fields.
2. **Audio:** pure PCM tests at 44.1/48 kHz, slow/typical/fast BPMs, all supported meters, subdivisions 1–4, and the new accents/count-off modes. Verify onset positions, one downbeat, no clipping, expected bar duration, and clean loop and terminal boundaries. Then record real output during live changes and a long pad-plus-click run. Do not ship a change based only on UI state or timer tests.
3. **Interaction:** cover Song Library, Live editor, NOW/NEXT, Rehearse, MIDI mapping, VoiceOver, narrow windows, and the existing system check. Show configured, pending, and audible states separately. On preparation or save failure, keep the actually audible state truthful and show the existing persistent error path.
4. **Acceptance:** a saved v4 setlist sounds unchanged after upgrade; a tapped one-time tempo does not overwrite a song; two songs can have different accent and count-off choices; legacy and grouped 6/8 are unmistakable in both label and sound; a two-bar count-off enters exactly once at the intended boundary; Count-off only becomes audibly silent while pads continue.

## Scope boundary

No new click samples, sample picker, DAW timeline, automatic tempo following, tempo maps, Link synchronization, or tap-to-start in these milestones. Those can be evaluated after the four controls work reliably in Live and Rehearse.
