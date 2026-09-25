# Song Library redesign plan

Status: implemented in the local app for review, following [the UI/UX audit](song-library-audit.md).

## Product decisions for this pass

- **Assigned Pad is the playback choice.** The primary song UI offers No Pad, included pads, and custom pads. Remove the Key picker and key chip from Song Library and the Live song editor.
- **Keep `Song.defaultKey` in persisted data for compatibility.** It remains historical musical metadata for older libraries and can be reconsidered in a separate migration. Do not show it as a description of a custom pad. When selecting an included key pad, synchronize the stored key to that pad; selecting a custom pad or No Pad leaves the stored key alone. Remove the current automatic pad switch from generic `updateSong` so changing BPM/title/meter cannot change assignment indirectly.
- **One editor for library and Live.** The same Title, Assigned Pad, BPM, Time Signature, and Click Subdivision controls appear in both contexts. Live adds only setlist-specific actions such as Remove from Setlist. Existing live-audio rules still apply: click changes affect a playing song through the store's safe update path; pad reassignment takes effect at the next start.
- **New songs begin as drafts.** Add Song opens a draft editor with Title focused. Save creates the song; Cancel leaves no `New Song` placeholder. Existing songs save intentionally from the editor, with validation and an unsaved-changes prompt on close. This replaces mixed immediate edits and title-only commit behavior.

## Layout and flow

1. **Song list.** Use compact rows with title, assigned pad name or No Pad, BPM, and meter. A selected row gets the brand fill and border. Keep a clear Add Song button and an empty-state action. Show persistent setlist membership or count separately from the Add to Setlist action; remove the two-second checkmark as a proxy for membership.
2. **Wide layout.** Show the list beside a detail editor. Use visible labels and group the editor into Song (Title, Assigned Pad) and Click (BPM, Time Signature, Subdivision). Put Add to Setlist and Delete Song in a separate action area. Do not repeat metadata chips above editable controls.
3. **Narrow layout.** Give the list the full content width. Selecting or adding a song opens the same editor in a sheet. Keep the list usable at the app's 640-point minimum window width and return focus to the selected row when the sheet closes.
4. **Pad chooser.** Provide searchable groups for Custom Pads and Included Pads, plus No Pad. Show the current assignment, availability, and a route to Pad Library for missing or unavailable files. Use pad names as the primary label; avoid repeated “Included” subtitles on every row.
5. **Live.** Replace `SongInspectorPane`'s separate form with the shared editor. Keep cue, playing, and audible-pad identities distinct. Closing the editor must not change the cue or interrupt audio.

## Implementation sequence

1. Extract a song draft model and store operation that validates and commits the editable fields and pad assignment together. Preserve existing IDs, setlist references, and library decoding. Add tests for Cancel, Save, included/custom/No Pad assignment, and editing a playing song.
2. Build the shared editor and pad chooser with visible labels, keyboard focus, VoiceOver names/values, unavailable-pad states, and safe Delete/Remove actions.
3. Replace the Song Library's dense inline rows with the responsive list/editor composition. Remove the duplicate Key/BPM/Time chips and transient Add checkmark. Keep Add to Setlist explicit.
4. Use the shared editor in Live and update setlist/NOW/NEXT/readiness copy to name the assigned pad where audio choice is meant. Show a musical key only if it is an explicit, trustworthy metadata field. Check all `defaultKey` display sites before release.
5. Verify both layouts and playback behavior, then update design acceptance docs and package a test build.

## Acceptance checks

- At 640-point window width, no horizontal clipping in Song Library, Pad chooser, or Live editor; list selection and edit controls remain keyboard and VoiceOver operable.
- A new song can be canceled without creating a persisted placeholder. Saving once creates one song with the chosen pad and click defaults; relaunch preserves it.
- Existing bundled-pad assignments, custom-pad assignments, and No Pad survive editing and relaunch. Selecting a different included pad updates the stored key for compatibility; selecting a custom pad does not overwrite that key.
- A missing or unavailable assigned pad is named clearly and does not appear playable. No Pad remains a valid configuration for click and countoff.
- Adding a song to the setlist gives confirmation and persistent membership feedback. Repeated song entries remain distinct in Live.
- Editing a playing song's BPM/meter/subdivision follows current audio safety rules; changing its pad assignment affects the next start, not the currently audible pad.
- Song Library and Live show the same editable fields and assignment, with no misleading Key or “Included” text for a custom pad.

## Existing code to change

- [Song Library layout](../../Sources/Sustain/Views/SongLibraryView.swift)
- [Shared song editor](../../Sources/Sustain/Views/SongEditorView.swift) and [pad chooser](../../Sources/Sustain/Views/SongPadChooser.swift)
- [Live editor integration and readouts](../../Sources/Sustain/Views/LiveServiceView.swift)
- [Song creation/update and assignment](../../Sources/Sustain/Store/RuntimeSession.swift)
- [Readiness copy](../../Sources/Sustain/Store/ReadinessAndRouting.swift)

The custom pads PRD currently treats musical key as independent metadata. This plan preserves that data while making Assigned Pad the only primary playback selection in the UI. Any later removal of `defaultKey` from storage would need its own migration plan.
