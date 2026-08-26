# Slice 03 — Pad Library Management UI

## Goal

Ship the scalable content-management screen for add/drop, rename, search,
reorder, repair, and remove workflows.

## Work

1. Add `Pad Library` to `AppScreen`, RootView, sidebar, native menu commands,
   keyboard shortcuts, and previews.
2. Build a lazy list with label, filename, availability, source type, assignment
   count, and active state.
3. Add multi-file Add Audio… and Finder drop using Slice 02 services. Show a
   native insertion indicator; insert at the drop location or append in empty
   space, never moving/deleting the Finder source.
4. Add inline rename with trim/blank validation; permit duplicates.
5. Add standard as-you-type, localized case/diacritic-insensitive
   label/filename search with Command-F. Disable reorder while filtered.
6. Add system list selection, multiple selection for safe batch actions, native
   drag reorder, and accessible move commands; persist once per move.
7. Add Reveal, Locate/Replace, Remove confirmation, and assignment replacement.
8. Add Show Included Pads while keeping assigned included values discoverable.
9. Add import progress/partial-failure feedback and accessibility announcements.
10. Integrate named Undo/Redo groups for import, rename, reorder, reassignment,
    and removal. View visibility toggles directly; Undo cannot alter currently
    audible audio.
11. Mirror context-menu commands in visible controls or File/Edit/View/Pad menu
    items. Add standard Return/Escape/Delete/arrow behavior and predictable
    focus after insertion, removal, and search clearing.
12. Show duration, channels, sample rate, filename, and typed source state.

## Acceptance

- Add and drop paths create the same records and append in selection order.
- Rename/reorder/hide survives relaunch.
- Removing assigned pads requires atomic reassignment; audible pads are blocked.
- Included pads cannot be mutated or removed.
- Search of a hundreds-item fixture remains responsive and reordering cannot
  corrupt the underlying order.
- All drag-only actions have keyboard/menu equivalents.
- Full Keyboard Access, VoiceOver, Voice Control, standard selection effects,
  focus restoration, menus/shortcuts, and batch Undo/Redo pass QA.
