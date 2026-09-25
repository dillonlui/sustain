# Song Library UI/UX audit

Code review of the former Song Library, September 2026. These findings informed the implemented [redesign plan](song-library-redesign-plan.md).

## Main findings

1. **The row is doing too much.** [LibraryViews.swift](../../Sources/Sustain/Views/LibraryViews.swift) places Key, BPM, Time, Pad, Add, and More in one horizontal strip. The same metadata appears as chips under the title and as controls below it. This feels dense at desktop width and becomes cramped as the window narrows.
2. **Key and Pad look like competing audio choices.** A song now has an explicit `padTrackID`, while changing `defaultKey` can still change its included pad. The primary editor should use **Assigned Pad** as the playback choice, including custom pads and No Pad. Keep stored key metadata for compatibility during a migration, then decide whether a separate musical key belongs in an advanced section.
3. **Song Library and Live edit different song properties.** The Live editor still exposes Key and describes pads as included, while Song Library has an assignment selector. Editing should use one consistent set of fields and labels in both places.
4. **Adding a song creates a persistent placeholder immediately.** New Song is saved before the user finishes naming it. A draft editor with clear Save and Cancel would avoid accidental placeholder records.
5. **Add to Setlist feedback expires.** The row's checkmark is a two-second confirmation, not persistent membership. Use an explicit Add to Setlist action and, if useful, a separate membership count.
6. **The pad picker lacks context.** Group custom and included pads, show availability and missing-file state, and make No Pad an explicit option. Avoid repeating “Included” on every row.

## Recommended flow

- **Wide window:** a compact song list on the left and a detail editor on the right. List rows show title, assigned pad, tempo, and meter. Selection uses the brand palette.
- **Narrow window:** a full-width song list; selecting or adding a song opens the same editor in a sheet.
- **Editor:** visible labels for Title and Assigned Pad, then a Click group for BPM, time signature, and subdivision. Put Add to Setlist and Delete in clear, separate actions. Use consistent save behavior for every field.
- **Live:** reuse the editor's fields and pad assignment model so changes are predictable from either view.

## Data and copy to reconcile

`defaultKey` is retained as independent musical metadata in [the custom pads PRD](../17_Custom_Pads_And_Live_Workflow_PRD.md). Hiding the Key picker is a UI decision; removing the stored field is a separate migration. Before changing the editor, update Live readouts and readiness messages that display `defaultKey` so custom pad names are not presented as an incorrect key.
