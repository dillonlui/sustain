# Click subdivisions: UI/UX implementation plan

Builds on [18_Click_Subdivisions_Investigation.md](18_Click_Subdivisions_Investigation.md). The UI must tell an operator which rhythm is selected, which rhythm is audible, and when a live change will take effect. It must preserve the current BPM and countoff meaning.

## User-facing contract

| Choice | Control label | Spoken/accessibility label | Timing |
| --- | --- | --- | --- |
| 1 | Beat | One click per beat | Current behavior |
| 2 | 2 per beat | Two clicks per beat | Even halves |
| 3 | 3 per beat | Three clicks per beat, triplets | Even thirds |
| 4 | 4 per beat | Four clicks per beat | Even quarters |

Use the same order and wording in Live, Rehearse, and Song Library. A short “Click: 3 per beat” readout is preferable to an unlabeled note glyph. Avoid eighth/sixteenth-note labels in the first release: the app currently defines BPM against each numbered unit in 6/8, 9/8, and 12/8, so those names would imply a compound-meter interpretation the engine does not yet provide. Help text can say: “Adds evenly spaced clicks inside each BPM beat; tempo and measure length stay the same.”

The active downbeat/beat must remain audible above subdivisions. Accent remains a separate setting. Counted countoff continues to speak once per beat; Click Only countoff follows the selected subdivision. The on-screen countoff displays numbered beats, never subdivision slots.

## Surfaces and placement

| Surface | Control | Persistent readout | Reason |
| --- | --- | --- | --- |
| Rehearse Click panel | Four-option segmented `Picker` in its own row, directly below Accent and Countoff Sound. Use compact visible segments `Beat`, `2`, `3`, `4`; the row label and accessibility values expand their meaning. | Add subdivision to `clickText`, e.g. `72 BPM · 4/4 · 3 per beat`, and retain the existing Click state tile. | Rehearse is the exploratory surface and has a scrolling panel. Keeping this on its own row avoids crowding the existing two-column Accent/Countoff controls at the 520-point minimum click-panel width. |
| Live song editor (`SongInspectorPane`) | Labeled `Picker("Subdivision", ...)` using a menu, immediately after Time and before Pads. Add the help sentence as secondary Form text. | The selector reflects the canonical song value, or a clearly marked pending value. | Fits the fixed 320-point inspector without adding another wide segmented row. Edits continue to apply to every setlist occurrence of that song. |
| Live performance surface | No extra transport button. Add a compact text line `Click: 3 per beat` in NOW and NEXT song cards, below the existing Key/BPM/Time chips. Add the current click choice as a small footer below the Click fader slider, not in its already crowded header. | While playing, NOW and the fader show the audible rhythm; while click is off, show `Click off · next start: 3 per beat`. NEXT always shows the cued song's committed default. | A service operator can check the current and next pattern at a glance without opening the editor or changing the transport layout. Do not add a fourth chip to the existing minimum 220-point cards. |
| Song Library row | Add a labeled compact menu `Click: Beat` in a second metadata line under the title/chips, not in the already crowded trailing controls. | The row always shows the song default. | Makes the per-song choice discoverable while preserving title, key, BPM, time, pad, and add-to-setlist controls. The menu changes the canonical song and the Live inspector updates from the same source. |

Reserve the readout's space in both Beat and subdivided modes so a state change does not resize the Live cards. At narrow window widths and with the Live inspector open, allow the secondary text to wrap or truncate with a tooltip; do not let it push transport or fader controls outside the window. Preserve the existing custom Live editor pane rather than introducing `.inspector`, which previously caused layout jumps.

## Interaction states

| Context | User action | Immediate UI | Completion/failure |
| --- | --- | --- | --- |
| Click off, any surface | Select mode | The song default or Rehearse session choice and its readout update immediately. | Next start/countoff uses it; only song defaults are persisted. |
| Rehearse playing | Select mode | Segment shows the requested mode; status says `Switching to 3 per beat at next measure`. Existing sound continues. | On audio boundary confirmation, audible readout changes and status clears. On failure, segment returns to the audible mode and a persistent inline error explains that the click kept playing unchanged. |
| Live current song playing | Select in editor or Library | Editor shows the pending mode with `At next measure`; NOW card and Click fader keep showing the audible mode. | On confirmed switch, commit/save the canonical song choice and update all readouts. On failure, restore the prior choice and keep the old audio loop; show an inline error in the editor plus the existing Live message strip. |
| Live song cued but not playing | Select mode | NEXT card and song editor update immediately. | The song starts with the saved mode. The current NOW rhythm is unaffected. |
| Current song or Rehearse click preparing | Select mode | Show the latest requested mode and `Preparing`; keep transport available. | Invalidate and rebuild any stale prepared click. Activation must use the latest BPM, meter, subdivision, accent, and countoff settings. |
| During any countoff | Try to select the active song's or Rehearse mode | Disable that picker and explain `Subdivision can change after countoff`. Editing another, inactive song remains available. | Re-enable when regular click playback begins; this avoids changing the spoken or click-only countoff partway through. |
| Rapid repeated selections | Select several modes | Only the last choice remains pending; no queue of UI notices. | The latest prepared pattern wins at a measure boundary. |
| BPM, meter, or accent changes while a subdivision is pending | Edit another click setting | Show the latest complete requested click configuration. | Invalidate the older prepared pattern. Apply the new configuration under the existing BPM/meter restart policy or a verified boundary switch; never let the older subdivision callback restore stale settings. |
| Stop or switch song while pending | Stop/transition | Clear pending/audible status for the old session; the picker returns to the last committed mode. | A stale audio callback cannot alter the new song or Rehearse state. The requested mode is canceled unless it was already confirmed and committed. |
| Audio switches but saving fails | None | Audible readouts change to the confirmed mode; show `Unsaved changes` via the existing persistence error path. | Do not roll back the audio or claim the song file was updated. |

Never replace the audible readout before the audio engine confirms the switch. A brief status belongs beside the affected control and in the existing message strip; avoid a modal alert or a timed toast for a normal successful change. Stop and other transport actions must remain immediately available while a switch is pending. If a newer request arrives after an earlier change has already been armed and cannot be canceled, report the actual audible mode at that first boundary and carry the newer request to the next one; do not announce the newest mode before it sounds.

## UI and state implementation tasks

1. Add `ClickSubdivision` presentation properties in one place: `menuLabel`, `compactLabel`, `accessibilityLabel`, and `summaryLabel`. Keep these separate from persisted raw values. Add a small shared `SubdivisionPicker` wrapper so all three edit surfaces use one option order and accessibility wording; configure its style per surface.
2. Add the canonical song binding in `SongInspectorPane` and `SongLibraryView`. Existing `updateSong` call sites copy title/key/BPM/time only, so update every path to carry the subdivision field; a title, key, or pad edit must not reset it. Refresh both surfaces from authoritative store state after an edit is accepted or rejected.
3. Add Rehearse selection through a store setter. Keep its session value independent of per-song Live values. Update `clickText` and the Click panel with the active, pending, and error states described above.
4. Expose explicit click UI state from `AppStore`: requested selection, audible selection (optional when off), pending request, and a local error/status message tied to the active session or song ID. Keep the committed song default separate from a pending request. Avoid deriving “audible” from `Song` after a queued edit; it may be different until the audio boundary. The engine should report successful activation or failure to the store on the main actor. Extend the existing generation checks to include the full click configuration so old preparation callbacks cannot activate stale audio or update the screen.
5. Add the compact Live readouts to `StatePanel` and a small optional footer slot in `ChannelFader` for the Click fader, then verify `ViewThatFits` at the current minimum widths and with the 320-point editor open. Keep NOW/NEXT heights stable for Beat and longer labels. Preserve the current `CountoffIndicator` placement and visual beat count.
6. Add error copy and accessibility announcements. A failed change should read `Could not change click subdivision. Still playing Beat.` with the actual retained mode; use the existing inline notice style. Announce a completed switch once, not on every intermediate preparation callback.

## Accessibility and usability checks

- Every picker has a visible or VoiceOver label of `Subdivision`; each choice speaks “clicks per beat,” with triplets named for the three-click option. Avoid conveying selected or pending state by tint alone.
- Keyboard focus reaches the Library menu, Live Form picker, and Rehearse segmented control in a predictable order. Arrow keys work in the segmented control; Space/Return opens the menus. Do not assign a global shortcut that could conflict with Live transport shortcuts.
- VoiceOver exposes pending versus audible state, for example `Subdivision, three per beat requested; Beat playing until next measure`. It announces switch completion or failure once. Do not announce each subdivision pulse.
- Check light/dark mode, increased contrast, large text, Reduce Motion, long song names, and the smallest supported window size. The new UI needs no beat-synced animation to be understandable.
- Test with a musician at 6/8 and 9/8: ask what `3 per beat` will sound like before playing it. If the answer diverges from the actual pattern, revise the wording before release, not the existing meter timing silently.

## UI acceptance scenarios

1. Open an older library: every song and Rehearse show Beat; starting click sounds exactly as before.
2. Set song A to 3 per beat and song B to Beat in Song Library. Live NEXT shows B's saved value when B is cued; starting B does not inherit A's rhythm.
3. During Live playback, request 4 per beat. The UI says pending, NOW/Click fader still describe the audible mode, and both update together at the confirmed measure boundary. Stop remains responsive.
4. Make a rapid 2 → 3 → 4 selection while playing. Only 4 takes effect; there is one completion message and no stale readout.
5. Force preparation failure. Audio stays on the old pattern, the selector rolls back, the failure message names the retained pattern, and the song file is unchanged.
6. Change Rehearse to triplets and visit Live. The song's choice stays as saved. Switch back: Rehearse retains its session choice.
7. Verify counted and Click Only countoffs at all four settings. Numbered visual beats remain stable, and the first regular measure matches the selected rhythm.
8. With the current song's click off, NOW and the fader say which pattern the next start will use rather than claiming any rhythm is audible. During countoff, the active picker is disabled and explains why.
9. Edit a subdivision during asynchronous click preparation. The final activated audio uses the latest full click configuration. If a save fails after a successful live switch, the audible mode remains truthful and the existing unsaved-changes warning remains visible.

Do the UI acceptance pass alongside the audio recording and transition tests in the investigation. A polished pending state cannot compensate for an audible skipped or doubled beat.
