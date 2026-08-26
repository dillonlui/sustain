# Custom Pad Library, Live Workflow, and App Updates — PRD

**Status:** Proposed

**Date:** 2026-08-25

**Execution source of truth:** [`custom-pads-live/00_EXECUTION_TRACKER.md`](custom-pads-live/00_EXECUTION_TRACKER.md)

**Related feature:** [`16_MIDI_Controller_PRD.md`](16_MIDI_Controller_PRD.md)

## Summary

Turn Sustain's fixed collection of twelve key-named pads into a flexible,
user-managed pad library. A user can reference any number of local audio files,
give each one a free-form label, reorder the library, assign a pad to a song,
and hide the included pads from browsing without deleting them.

This project also completes two related Live Service workflows and one
independently deliverable release-infrastructure feature:

1. Clear the active setlist in one confirmed action.
2. From fully idle Live state, start the cued song's pad before its
   click/countoff. Pressing **Start** for that same cue must keep the pad at its
   current playback position and add the countoff/click.
3. Give official Developer ID releases a native, signed Sparkle 2 update path
   without allowing update UI or relaunch to interrupt live use.

The result remains a focused worship utility, but its pad surface can also act
as a lightweight, user-configured sound-pad launcher.

## Why this is a model change, not only a UI change

Today the app assumes all of the following:

- there are exactly twelve pads;
- every pad is identified by `MusicalKey`;
- every song has a key and always uses the bundled pack;
- the audio engine resolves `PadPack + MusicalKey` to a bundle file;
- the Rehearse UI renders a fixed chromatic grid;
- a live pad can start only after a song has become the playing song; and
- `playingEntryID` is treated as the context for both pad and click.

Custom labeled audio breaks each of those assumptions. The implementation must
introduce a stable pad identity and separately represent the song that is
playing, the song that is cued, and the pad that is actually audible.

## Product goals

- Let users add any practical number of pads without an arbitrary product cap.
- Let users choose any AVFoundation-readable local audio file and reference it
  in place rather than duplicating it.
- Let users rename and reorder pads without breaking song assignments.
- Let each song select one pad or explicitly select **No Pad**.
- Keep the included twelve pads available and immutable, while allowing users
  to hide them from normal browsing.
- Make large libraries manageable through a scalable list, search, grouping,
  batch import, and drag-and-drop.
- When live transport is fully idle, let the cued pad start early and continue
  uninterrupted when that same song's click/countoff begins.
- Preserve live safety: validation before an audible change, no synchronous
  file decoding on the main thread, and truthful runtime state.
- Preserve all existing libraries through an explicit migration.
- Behave like a native Mac content app: standard selection, menus, keyboard
  commands, Undo/Redo, Finder drag-and-drop, focus, and system file panels.
- Use least-privilege file access and test the exact signed distribution shape
  throughout development, not only immediately before release.
- Provide user-approved, approximately daily update checks and a standard
  **Sustain → Check for Updates…** command for official releases only.
- Preserve the Developer ID, hardened-runtime, and notarization trust chain
  through download, verification, replacement, and relaunch.

## Non-goals for the first release

- Editing, trimming, normalizing, time-stretching, pitch-shifting, or waveform
  editing audio.
- One-shot/sampler playback modes, multiple simultaneous pads, per-pad volume,
  fade-duration editing, or MIDI velocity response.
- Managing or syncing files through iCloud. User-selected iCloud Drive or other
  File Provider items are supported only when macOS can materialize and grant
  read access to the file; Sustain remains a reference-based client.
- Watching arbitrary folders and importing new files automatically.
- Nested folders, tags, smart playlists, or multiple separately named pad
  collections.
- Changing a song's musical key model. A song still has a musical key for its
  own metadata even when its assigned pad has a non-key label.
- Deleting or editing the audio/labels of the bundled pad assets.
- Starting a next/cued song's pad while another live song is still the current
  playing song, even if that song's click has already been stopped. Between-song
  pad pre-roll/crossfade is a separate future workflow.
- Silent automatic update installation, beta/prerelease channels, differential
  updates, update telemetry/system profiling, or an updater for development,
  pull-request, ad-hoc, or unpublished builds. Sparkle-generated deltas may be
  evaluated later after the full-archive update path is proven.

## Product vocabulary

- **Pad track:** One launchable audio item with a stable ID and user-facing
  label. It is either included with Sustain or references an external file.
- **Pad Library:** The ordered catalog of included and custom pad tracks.
- **Assigned pad:** The pad track a song will use, or **No Pad**.
- **Audible pad:** The pad track currently playing, independent of which song
  owns the active click.
- **Pre-roll / start early:** Playing the cued song's pad without starting its
  click or promoting that song to `playingEntryID`, permitted only from fully
  idle Live Service state.

## Primary user stories

1. As a user, I can add several audio files at once, name each pad, and see them
   in my library immediately.
2. As a user, I can drag files from Finder into the Pad Library.
3. As a user, I can rename and reorder pads and have that order appear on the
   playback surface.
4. As a user, I can hide Sustain's included pads so a custom library does not
   feel cluttered.
5. As a worship leader, I can assign a custom pad to a song and trust that the
   song continues to reference it after the pad is renamed or moved.
6. As a user with many pads, I can search by label or original filename without
   rendering hundreds of eager controls.
7. As an operator before the first song—or after explicitly stopping the prior
   song—I can start the cued song's pad, then start its countoff without hearing
   the pad restart.
8. As an operator preparing a new week, I can clear the active setlist in one
   safe action without deleting songs from the library.
9. As a user of an official release, I can opt into daily update checks, inspect
   release notes, install, defer, or skip a stable version, and manually check
   at any time without an update interrupting a performance.

## Detailed behavior

### 1. Pad Library entry and navigation

Add **Pad Library** as a first-class app screen, not a Settings tab. Managing
content is a core workflow; Settings remains for app behavior and hardware.

The screen contains:

- an **Add Audio…** button using the native multi-file picker;
- a Finder drop target accepting multiple materializable file URLs;
- a standard search field in the screen toolbar/header, matching label and
  original filename as the user types with localized, case/diacritic-insensitive
  comparison;
- an ordered, lazy `List` suitable for hundreds of rows;
- a row for each pad showing label, source filename, source state, and whether
  it is assigned to any songs;
- inline label editing, a Reveal in Finder action, Replace File…, and Remove;
- drag handles / native row reordering when search is empty; and
- a **Show Included Pads** toggle, on by default.

Search results are filtered views and cannot be reordered. The UI explains that
search must be cleared to reorder. **Add Audio…** appends new custom pads.
Dropping over the list shows a native insertion indicator and inserts at that
position; dropping over empty space appends. Preserve provider/Finder order
where it is defined and otherwise use a stable localized filename order.
Included pads start in chromatic order but participate in the unified order, so
the user can place custom and included pads wherever they prefer.

The list uses standard macOS selection highlighting. It supports multiple
selection for batch removal and movement where the result is unambiguous.
Return begins rename, Escape cancels editing, Delete requests removal, and
arrow keys navigate rows. Context-menu commands are conveniences, never the
only route to an action; File/Edit/View menu equivalents and Full Keyboard
Access must cover the complete workflow.

### 2. Adding audio

Supported input is described to the user as **MP3, M4A/AAC, WAV, AIFF, CAF, and
other audio formats readable by macOS**. The authoritative test is opening the
file with `AVAudioFile`, not its extension. A file must have a positive frame
count, sample rate, and channel count.

For each selected or dropped file:

1. Resolve and standardize the file URL.
2. Immediately acquire the security-scoped access supplied by the system
   picker/drop before reading or creating a bookmark.
3. Coordinate and materialize the read when the item comes from iCloud Drive or
   another File Provider.
4. Validate it off the main actor with `AVAudioFile`, including decoded-memory
   cost and supported channel layout.
5. Create a durable bookmark and store last-known metadata/fingerprint.
6. Release the temporary security scope on every success/failure/cancel path.
7. Create a `PadTrack` with the filename without extension as its initial label.
8. Insert it at the requested position and save once for the completed batch.

Batch import reports a summary such as “Added 8 pads; 2 files could not be
read,” with per-file error details available. Valid files are not rolled back
because another file failed. Selecting the same path twice is allowed only
after an explicit duplicate warning; the default action skips it. Different
files and duplicate labels are allowed.

There is no arbitrary track-count maximum. “Unlimited” means library metadata
and UI scale with the collection; it does not mean all audio is decoded into
memory. Track count and individual file size are separate constraints. See
**Audio memory and format policy** below.

External drops always add a reference; Sustain never moves, rewrites, or deletes
the Finder source. Reject folders, directories, non-file URLs, and unsupported
items with an inline batch result. Resolve aliases/symlinks to the user-approved
target before bookmarking. File promises that do not yield a durable source URL
are not supported in v1; explain that the user should save/materialize the file
and use Add Audio… instead.

### 3. Labels

- Labels are free-form Unicode text, trimmed at both ends.
- A blank label is rejected and the last valid label remains.
- Duplicate labels are allowed. Management and assignment UI show the original
  filename as secondary text so duplicates remain distinguishable.
- The full label is persisted. Rehearse buttons must retain uniform height,
  wrap to at most two lines, then tail-truncate. They never expand one grid cell
  independently and never use marquee text. The full label appears in the
  active-pad surface, tooltip, and accessibility value.
- Renaming changes display only. Song assignments use `PadTrack.ID`.

### 4. Referenced-file ownership and access

The first release uses **reference in place** semantics, matching the requested
desktop workflow. Sustain does not copy or delete the user's source audio.

Persist both bookmark data and non-authoritative last-known metadata. Resolve
the bookmark whenever the app needs the file, balance every successful
`startAccessingSecurityScopedResource()` call with `stopAccessing…`, and refresh
stale bookmarks after the user grants access again. Hold access through the
entire validation or decode operation; once the existing engine has fully read
the file into its own PCM buffer, release the file scope because playback/cache
no longer reads the source URL. A plain path is diagnostic and recovery
information, never the sole persisted authority. Use `NSFileCoordinator` (or an
equivalent tested coordinated-read boundary) for File Provider/iCloud content
and files that may be concurrently changed by another process.

The App Sandbox decision is an early architecture gate, not final-release
cleanup. Before Slice 02, build a signed spike that verifies pad/click output,
Core Audio routing, USB and Bluetooth Core MIDI, file import/drop, relaunch, and
bookmark resolution under the proposed entitlements. Prefer a sandboxed,
least-privilege build if all critical live capabilities pass; otherwise record
the specific incompatibility and ship the direct-notarized build unsandboxed
rather than adding broad/temporary exceptions blindly.

For a sandboxed build, include at least App Sandbox, user-selected read-only
file access, and app-scoped bookmark access. Add Bluetooth/USB or other hardware
entitlements only if the tested Core MIDI path requires them. Never request
read-write audio-file permission: Sustain does not modify source audio. Ensure
the bundle script applies the same entitlements to development and release
signatures. Bookmark handling remains the product boundary in either mode.

External source state is typed rather than collapsed into “missing”:

- **Available**
- **Preparing / downloading**
- **External volume unavailable**
- **Permission required / denied**
- **File missing**
- **File changed since preparation**
- **Unsupported or protected format**
- **Unreadable / corrupt**

If a file is moved, renamed, removed, an external volume is absent, or bookmark
resolution fails:

- keep the pad and all song assignments;
- show the accurate typed state and block only actions that require that pad;
- offer **Locate File…** to replace its reference while preserving ID, label,
  order, and assignments; and
- never silently fall back to another same-named file.

Locate File preserves identity only after the replacement validates. If
bookmark refresh/save then fails, retain the previous recoverable record and
surface the save failure; never leave a half-updated reference.

### 5. Included pads

The twelve bundled pads become deterministic `PadTrack` records at runtime.
Their IDs must be stable across launches and releases. They cannot be renamed,
relinked, or removed.

**Show Included Pads** hides them from the Pad Library and Rehearse browsing
surfaces. It does not disable an included pad already assigned to a song, remove
it from the song editor's current-value display, or make a service fail. This
is intentionally a visibility preference rather than destructive disablement.
Store it in `@AppStorage`/UserDefaults as per-user interface personalization,
not in the versioned musical library. Behavior remains consistent after
relaunch without expanding the content migration surface.

### 6. Song assignment

Replace the implicit `Song.padPack + Song.defaultKey` audio lookup with an
explicit optional `Song.padTrackID`.

- New songs default to the included pad matching their initial musical key.
- Changing a song's key does not silently change a custom pad assignment.
- If the song is assigned to the matching included-key pad, changing its key
  automatically selects the new matching included pad to preserve today's
  convenient behavior.
- If the song uses a custom pad or **No Pad**, changing key leaves it alone.
- The song editor offers a searchable pad picker plus **No Pad**.
- A missing assigned track is shown as unavailable with a Locate/Choose action.

**No Pad** is a supported song configuration. Starting such a song starts its
countoff/click and fades out any outgoing pad; readiness must not classify the
intentional absence of a pad as an error.

### 7. Removing a custom pad

Removal deletes only Sustain's catalog record and bookmark, never the source
file. It requires confirmation.

- If unassigned and not audible, remove immediately after confirmation.
- If assigned to songs, confirmation lists the affected song count and the user
  must choose a replacement (including **No Pad**) before removal. Apply the
  reassignment and removal in one save.
- If currently audible, removal is blocked until the pad is stopped. The UI
  must not claim deletion while its audio continues.
- Included pads cannot be removed.
- Removing one or many pads registers one named Undo operation that restores
  records, order, assignments, and bookmark data. Undo never recreates or
  modifies the source audio because Sustain never owned it.

### 8. Rehearse / sound-pad surface

Replace the fixed `MusicalKey.allCases` grid with the visible ordered Pad
Library. Use a lazy adaptive grid for launch buttons and provide search when the
visible count exceeds twelve (search may always be present for consistency).

Pressing a pad starts/crossfades to it exactly as today. Only one pad plays at a
time. Pressing the already-audible pad is a no-op; it does not restart the file.
The active surface displays the custom label, not a presumed musical key.

Rehearse is the required audition path before live use. Management rows expose
**Play in Rehearse** rather than embedding a second competing preview engine.
The Pad Library shows duration, channels, sample rate, and source status so the
user can identify surprising files before launch. Release/help copy warns that
Sustain loops the decoded file as supplied and does not normalize loudness,
remove silence, repair loop boundaries, or eliminate compressed-file padding.

One-shot clips and overlapping samples are deferred. This remains looping,
single-pad playback, even though custom labels make the surface useful beyond
the bundled keys.

### 9. Live Service — start the cued pad early

Early pad is an idle-start workflow only. It is never offered as a separate
between-song transition control. `canStartCuedPadEarly` is true only when:

- `runtime.playingEntryID == nil` (there is no current live song identity);
- live click is off;
- live pad is off—not preparing, fading, or audible;
- Rehearse pad and click are off; and
- a cued song exists with an available assigned pad.

Stopping only the current song's click does not make the app eligible. Even if
its pad is also manually stopped, a non-nil `playingEntryID` means that song
still owns the Live controls. The operator must use global **Stop**, allow any
pad fade to finish, and return transport to fully idle before pre-rolling a
different cued song. Sustain does not implicitly stop Rehearse or current live
audio merely because Play Cued Pad was requested.

When a live song is playing, the Pad control reflects only that current song:
**Start Pad** restarts its assigned pad and **Stop Pad** stops it. It never
targets the NEXT card or exposes **Play Next Pad**. A normal **Transition** still
prepares and crossfades the next song's pad together with its click/countoff;
there is simply no independently triggered next-pad pre-roll.

When fully idle, the control behaves as follows:

- cued song has an assigned available pad → **Play [pad label]**;
- pad preparation is pending → **Cancel Pad Start** / Stop cancels it;
- that cued entry's pre-roll pad is audible → **Stop Pad**;
- cued song has **No Pad** or an unavailable pad → no Play action, with the
  appropriate explanation/recovery; and
- a prior pre-roll does not match the current cue → Pad control remains **Stop
  Pad**, the channel shows a mismatch warning, and the main **Start** action
  remains available to replace it with the cued song atomically.

`startCuedPad()` authoritatively rechecks the full-idle guard, prepares routing
and the pad without changing audio, then fades it in only after preparation
succeeds. It does not:

- start click/countoff;
- set `playingEntryID`;
- change the playing song's click metadata; or
- automatically advance the cue.

The runtime must track the audible `PadTrack.ID` independently. When
pre-roll activation succeeds, also record the owning `SetlistEntry.ID`. The NOW
card remains **No song playing**, NEXT continues to show the cued song, and the
Pad channel displays **Pre-roll · [label]** so state ownership is unambiguous.

When `startCuedSong()` runs with a matching pre-roll owner and assignment:

- require the pre-roll owning entry ID to equal `runtime.cuedEntryID` and its
  recorded pad ID to equal that song's current assignment;
- prepare the target countoff/click without mutating the pre-roll pad;
- start the prepared countoff/click and promote that same entry to playing;
- do not prepare, schedule, restart, or crossfade the already-audible pad; and
- if click preparation/start fails, leave the matching pad in pre-roll, keep
  `playingEntryID == nil`, and report the failure.

Changing the cue or assigned pad while pre-roll is audible never changes audio.
It creates an explicit mismatch, but does not trap the operator. Pressing the
main **Start** action for the newly cued song:

- prepares that song's pad (if any) and click/countoff while the old pre-roll
  continues untouched;
- after preparation succeeds, starts the new click/countoff and crossfades from
  the old pre-roll to the newly cued pad;
- if the newly cued song uses **No Pad**, starts its click/countoff and fades the
  old pre-roll out;
- if both entries use the same `PadTrack.ID`, keeps the audio position and
  explicitly transfers ownership at commit rather than restarting it; and
- if any preparation fails, leaves the old pre-roll audible, keeps
  `playingEntryID == nil`, and reports the failure.

The mismatch warning names both the sounding pre-roll and newly cued song so
the replacement is predictable. Entry ID remains the ownership authority; pad
ID only determines whether an audible restart/crossfade is necessary.

When `startCuedSong()` runs without idle pre-roll—including a normal transition
from a currently playing song—it follows the standard two-phase path:

- prepare the target pad and target countoff/click without mutating current
  audio;
- once every required resource is ready, commit the new countoff/click and pad
  crossfade as one main-actor transport operation;
- if the song has **No Pad**, fade out the outgoing pad; and
- only promote the cued entry to playing after required operations succeed.

The audio boundary is explicitly two-phase. `preparePad` may perform file
access, coordinated read, validation, decode, conversion, and memory admission,
but cannot alter audible nodes. `activatePad` accepts only a successfully
prepared immutable buffer and must not perform file IO or allocation likely to
fail. Likewise, build the new click/countoff buffers before stopping the old
click. For No Pad, start the prepared click successfully before fading the
outgoing pad. This preserves the existing sacred rule that failed transition
preparation cannot damage current playback.

The global Stop action is enabled whenever any click or pad is active, including
pad-only pre-roll before the first song. Stop cancels pending preparation or
fades the pre-roll out, clears its owning entry only after cancellation/fade is
settled, and returns the system to fully idle.

### 10. Live Service — clear setlist

Add a low-emphasis destructive **Clear Setlist…** action to the bottom of the
setlist pane, beside/below Add Song.

- Hide or disable it when the setlist is empty.
- Selecting it opens a confirmation naming the setlist and song count:
  “Remove all 8 songs from Sunday Service?”
- Confirmation is explicit and uses buttons named **Cancel** and **Clear
  Setlist**. Cancel is not the default button. Escape and Command-period cancel;
  either make Clear Setlist the default for the deliberately invoked action or
  provide no default if accidental Return is a concern.
- While any live audio is active, disable Clear Setlist with help text “Stop
  playback before clearing the setlist.” Do not combine stopping audio with
  clearing content in one surprise action.
- On confirmation, clear entries atomically, set cue and playing references to
  `nil`, refresh readiness, and persist once.
- This does not delete Song Library records or pad tracks.
- Announce success to VoiceOver and set `runtime.lastMessage`.
- Register **Undo Clear Setlist** as one operation. Undo restores entries, order,
  and the prior cue when safe, but never starts audio automatically.
- After clearing, move keyboard/VoiceOver focus predictably to Add Song or the
  empty-setlist message instead of leaving focus on a removed control.

### 11. Native Undo, menus, selection, and focus

All reversible content edits integrate with the window `UndoManager` and the
standard Edit menu (`Command-Z`, `Shift-Command-Z`). Name operations narrowly:
Rename Pad, Reorder Pads, Import Pads, Remove Pads, Change Pad Assignment, and
Clear Setlist. Batch import/removal is one undo group, not one operation per
file. View preferences such as Show Included Pads toggle directly and do not
pollute content Undo history. Persist the post-undo snapshot once through the
existing atomic save path.

Undo/Redo restores content state but never starts, stops, restarts, or rewinds
audio. An operation whose inverse would invalidate currently audible audio is
temporarily unavailable with an accessible explanation until playback stops.

Expose all commands through native menus in addition to visible/context
controls:

- **File → Add Audio…**
- **Edit → Undo/Redo, Rename Pad, Remove Pad(s)**
- **View → Show Included Pads**
- **Find → Find Pads** or the standard Command-F behavior
- **Pad → Play in Rehearse, Reveal in Finder, Locate File…** (or an equivalent
  clearly scoped app menu)

Use standard system selection/focus effects. Do not move focus merely because
audio state changes. After insertion select the first new pad; after deletion
select the nearest surviving row; after search clears restore selection if the
item remains. Every context-menu action also exists in a visible or menu-bar
location.

### 12. App Updates

App Updates is a dedicated delivery slice because it changes app startup,
bundle composition, code signing, notarization, versioning, release automation,
and live-runtime coordination. Use Sparkle 2's standard AppKit user driver and
native update windows; do not recreate its update UI in SwiftUI.

#### Availability and user choice

- Only an official stable Developer ID release contains an enabled updater,
  stable HTTPS appcast URL, and Sparkle public EdDSA key. Debug, ad-hoc, CI,
  pull-request, branch, and unpublished builds do not start Sparkle, contact the
  feed, or show **Check for Updates…** as an actionable command.
- The first Sparkle-enabled release is a bootstrap release. Existing public
  builds that do not contain Sparkle cannot discover it in-app and require one
  normal manual DMG installation; communicate that limitation in release notes
  and support copy. Never imply that a build with no updater can self-update.
- Preserve Sparkle's standard permission request for automatic checks rather
  than forcing network access on first launch. After the user opts in, set the
  scheduled interval to 86,400 seconds (approximately once per day while the
  app runs). General Settings exposes **Automatically check for updates** and
  binds to Sparkle's persisted setting; a user who declines can check manually.
- Add **Sustain → Check for Updates…** in the conventional application-menu
  position with no custom keyboard shortcut. It performs a user-initiated check
  and Sparkle's standard UI reports an available version, already-current
  result, incompatible-system result, or actionable error.
- An available stable release shows its display version and release notes and
  offers Sparkle's standard equivalents of **Install**, **Remind Me Later**,
  and **Skip This Version**. A skipped version remains discoverable by an
  explicit manual check and does not suppress a later version.
- Set `SUAutomaticallyUpdate = NO` and `SUAllowsAutomaticUpdates = NO` for v1.
  Every version therefore requires an explicit install choice; Sparkle must not
  offer an opt-in to silent background installation. Reconsidering automatic
  installation is a separate product decision.
- Start the updater only after application launch completes and retain the
  updater controller and delegates for the app lifetime. Use
  `SPUStandardUpdaterController` programmatically so its updater and standard
  user-driver delegates can participate in live-safety rules.

#### Live-performance safety

Define one authoritative AppStore-derived state rather than inferring safety
from the selected screen:

```swift
var isLivePerformanceActive: Bool {
    runtime.playingEntryID != nil ||
    runtime.liveClickIsPreparingOrActive ||
    runtime.livePadIsPreparingFadingOrActive
}

var isAudioActivityActive: Bool {
    isLivePerformanceActive || runtime.rehearseAudioIsPreparingOrActive
}
```

The exact property names may change, but playing identity, pad-only pre-roll,
countoff, click, preparation, and fades all count as active. Merely viewing the
Live Service screen does not.

- Before a scheduled/background check, use the Sparkle updater delegate to
  decline the check while `isAudioActivityActive` is true. Record one deferred
  check and run it once, in the background, after the app becomes fully idle;
  do not poll or queue multiple checks.
- If the user manually chooses **Check for Updates…** during active audio,
  preflight in `UpdateCoordinator` before invoking Sparkle, acknowledge the
  command nonmodally with “Update check deferred until playback stops,” record
  the same single deferred check, and do not present an alert over the
  performance UI. The delegate repeats the guard as a race-safety backstop.
- If playback starts after an update window or download was already initiated,
  never stop audio. Use Sparkle's relaunch-postponement delegate as the final
  safety gate and hold exactly one install handler until all audio is idle,
  current library/preferences have saved successfully, and the user has not
  cancelled. Invoke the handler exactly once on the main actor. There is no
  forced timeout or forced quit during a performance.
- Update errors and offline failures never change transport, routing, cue,
  playback, or library state. Background failures are quiet and retried on a
  later scheduled check; user-initiated failures get a concise native result.
- Exercise feed checking and a user-approved download during a service-length
  audio test. The updater may not introduce main-actor stalls, audio dropouts,
  route changes, or meaningful memory spikes.

#### Install-location handling

An app running from a read-only mounted disk image cannot replace itself. Use
the bundle URL's resource/volume properties, not a fragile `/Volumes` string
test, to detect a known read-only volume before starting an update check.
Background checks remain deferred; a manual command shows native guidance to
quit, drag Sustain to Applications, eject the disk image, and reopen the
installed copy. Do not offer to move or delete the app automatically in v1.

Do not reject a normal `/Applications` install merely because replacement may
require administrator authorization; Sparkle's installer service owns that
standard authorization path. For other locked, managed, or genuinely
non-writable locations, surface Sparkle's installation error and provide the
official DMG/manual-install link without deleting the current app or downloaded
artifact prematurely.

#### Feed and update security

- Pin Sustain to a reviewed Sparkle 2 release compatible with macOS 14, commit
  `Package.resolved`, and update the dependency intentionally. Include Sparkle's
  required license notice in third-party acknowledgements.
- Embed `SUPublicEDKey` in official release builds. Keep the private EdDSA key
  out of the repository, logs, artifacts, caches, and pull-request jobs; place
  it in a protected release environment/secret and maintain a separately
  secured recovery backup plus a documented key-rotation procedure.
- Sign every update archive with Sparkle EdDSA. Because the minimum Sparkle
  version will support it, also set `SUVerifyUpdateBeforeExtraction = YES`,
  `SURequireSignedFeed = YES`, and
  `SUSignedFeedFailureExpirationInterval = 0`; sign the appcast and any external
  release-note file so feed validation fails closed.
- Prefer embedded plain-text or Markdown release notes in the signed appcast.
  If notes are hosted separately, they must use HTTPS, be published before the
  feed, and carry Sparkle's signature. Do not render arbitrary scripts or
  untrusted remote HTML in the update window.
- Use the default stable appcast channel only. Drafts and GitHub prereleases are
  excluded. Each item includes machine build version, human display version,
  three-part `sparkle:minimumSystemVersion`, publication date, exact byte
  length, HTTPS enclosure URL, and EdDSA signature.
- Set `SUEnableSystemProfiling = NO`, add no custom feed parameters, require no
  account, and add no update analytics. The unavoidable HTTPS request exposes
  ordinary network metadata such as IP address and user agent to the feed host;
  it must not include library, audio, path, label, MIDI, hardware-profile, or
  usage data.
- Use normal HTTPS/ATS validation with no insecure transport exception. A
  malformed, unsigned, or tampered feed/artifact fails safely; an item whose
  build is not newer is ignored. In every case the installed app is untouched.

#### Bundle, signing, and notarization

Sparkle is executable code, not an ordinary resource. The current custom
SwiftPM bundler must copy `Sparkle.framework` into `Contents/Frameworks`, retain
the required XPC services/helpers for the Slice 00A sandbox decision, and sign
each nested helper in the order Sparkle documents before signing the framework
and outer app. Never use `codesign --deep` to perform signing. Verify nested
designated requirements, architectures, hardened runtime, entitlements, and
timestamps after assembly.

For a sandboxed Sustain build, enable Sparkle's Installer XPC service and the
documented minimal communication entitlement. Use the app's existing outbound
network entitlement instead of Sparkle's Downloader XPC service if Slice 00A
already requires network client access; otherwise record and test the chosen
least-privilege downloader configuration. For an unsandboxed direct-notarized
build, remove unused Sparkle services only through the documented packaging
path and reverify the final framework signature.

Build one canonical Developer ID-signed `.app`, submit a temporary supported
container containing it to Apple's notary service, and staple/validate the
resulting ticket on the `.app` before producing either distribution container.
From that exact stapled app, produce:

1. the existing user-facing signed, notarized, and stapled drag-to-install DMG;
2. a Sparkle-compatible archive such as `Sustain-<version>-<build>.zip` that
   preserves symlinks, resource forks, extended attributes, nested signatures,
   and the stapled ticket.

Do not independently rebuild the DMG and archive. Both must contain byte-for-
byte equivalent signed app contents and pass `codesign --verify --strict`,
`spctl`, Gatekeeper launch, Sparkle signature verification, and notarization
validation. Retain full archives as the required path; deltas are optional only
after full updates are proven.

#### Version and release pipeline

- Remove hard-coded version/build values from `scripts/bundle.sh`. The protected
  release workflow supplies them once and every packaging step reads that same
  source. `CFBundleShortVersionString` is the human semantic version;
  `CFBundleVersion` is a numeric, machine-readable build that increases across
  every published release and never resets.
- A stable tag such as `v1.2.3` must exactly match
  `CFBundleShortVersionString`. Before signing, compare the proposed
  `CFBundleVersion` with the latest stable appcast item and fail unless it is
  greater. Fail on a reused tag, version, build, or asset name.
- Keep ordinary push/pull-request CI read-only and secret-free. A separate
  protected release workflow runs only for an approved semantic-version tag or
  explicit release dispatch targeting that immutable tag; it alone receives
  Developer ID, notarization, Sparkle-key, and publication credentials.
- Create a draft GitHub release, build/test/sign/notarize/staple once, upload the
  DMG, update archive, checksums, and release notes, then verify every public
  enclosure URL, length, signature, bundle version, architecture, and minimum
  OS declaration. Prefer GitHub immutable releases so the tag and assets cannot
  change after publication.
- Publish the stable release, then publish the newly signed appcast as the final
  discoverability step using the feed host's atomic file/deployment mechanism.
  “Atomic” means the feed never points to an unavailable or mutable asset; it
  does not imply that GitHub Releases and the feed host support one shared
  transaction. If feed publication fails, leave the prior appcast in place and
  mark the release incomplete rather than exposing a partial update.
- Host the appcast at one stable HTTPS URL (GitHub Pages or an equivalent
  controlled static host) and use immutable GitHub release-asset URLs for
  enclosures. Retain supported prior archives/appcast history so an installed
  previous release can follow a full update path.
- Generate artifacts and appcast from the tag commit, never ordinary `main`
  state. Release notes come from the reviewed GitHub release notes and are
  embedded/signed during generation; changing them requires regenerating and
  re-signing the feed before it is published.

#### Update launch gate

Before the bootstrap release, create two lower/higher Sparkle-enabled builds
with the real distribution shape, install the lower signed/notarized build in
`/Applications`, and prove its update to the higher release candidate through a
staging signed feed. For every later release, repeat from the previous public
Sparkle-enabled version. Also test opted-in scheduled and manual checks, current
version, later, skip, subsequent version after skip, offline/DNS/TLS failure,
malformed feed, tampered archive/signature, incompatible macOS item, read-only
DMG, authorization failure, active Live playback/pre-roll, active Rehearse
audio, save failure before relaunch, relaunch, preserved preferences/library,
and rollback to the untouched prior app on failed installation. A release is
not complete based only on a local feed or an ad-hoc build.

## Proposed domain model

Illustrative shape; exact Swift names may change during Slice 01 without
changing these semantics.

```swift
struct PadTrack: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var label: String
    var source: PadSource
}

enum PadSource: Codable, Equatable, Hashable {
    case bundled(key: MusicalKey)
    case external(ExternalAudioReference)
}

struct ExternalAudioReference: Codable, Equatable, Hashable {
    var bookmarkData: Data
    var lastKnownPath: String
    var originalFilename: String
    var fingerprint: ExternalFileFingerprint
}

struct ExternalFileFingerprint: Codable, Equatable, Hashable {
    var resourceIdentifierData: Data? // when safely archivable/available
    var fileSize: Int64?
    var modificationDate: Date?
}

struct Song {
    // existing fields...
    var padTrackID: PadTrack.ID? // nil means intentional No Pad
}

struct RuntimeSession {
    // existing fields...
    var audiblePadTrackID: PadTrack.ID?
    var audiblePadEntryID: SetlistEntry.ID?
}
```

Pad order is the order of `LibrarySnapshot.padTracks`; do not persist a second
`sortIndex` that can disagree. Included tracks may be synthesized and merged
using stable IDs, but the user's unified order must round-trip.

The audio boundary should become identity/URL based:

```swift
func padAssetStatus(for pad: PadTrack) async -> PadAssetStatus
func preparePad(_ pad: PadTrack) async throws -> PreparedPad
func activatePad(_ preparedPad: PreparedPad)
func stopPad()
```

`PreparedPad` is an immutable, runtime-only capability containing the resolved
pad identity, content fingerprint, decoded/converted PCM, and generation token.
It is never persisted and is not made `Sendable` without an explicit immutable
buffer contract. Preparation may fail without changing audio; activation is
nonthrowing main-actor scheduling/crossfade work over already-owned memory.
Engine startup, format conversion, output readiness, memory admission, and
stale-generation validation must all complete before activation is eligible.

Bookmark resolution belongs behind `PadAssetResolving`, not in SwiftUI or the
real-time audio code. The resolved resource-access lifetime must remain valid
through asynchronous decode only. Once PCM is fully owned, release the file
scope; cached or active buffers do not keep external-file permission open.

## Persistence and migration

Current production code writes schema v2. Both this project and the proposed
MIDI feature alter `LibrarySnapshot`; they must not independently hard-code the
same next version.

Migration rule:

1. At implementation start, inspect `currentSchemaVersion`.
2. The first feature to land claims the next integer.
3. The second feature bumps again and preserves the first feature's fields.
4. If implemented together, one combined next-version migration may add both
   custom-pad and MIDI defaults atomically.

For every existing song, schema-aware migration creates/selects the
deterministic included pad matching `defaultKey` and writes its ID to
`padTrackID`. Existing pad pack data is no longer runtime authority. Legacy
libraries must produce the same audible behavior after migration.

Missing and explicit null are different states. For schemas predating custom
pads, absence of `padTrackID` migrates to the matching included pad. In schemas
that support custom pads, explicit JSON `null` means intentional No Pad and must
remain nil forever. A current-schema record that unexpectedly omits a required
key is a validation error rather than silently becoming No Pad or an included
pad. Do not use one unconditional `decodeIfPresent` default for all schemas.

Decode defaults:

- missing custom pad array → deterministic included pads;
- old-schema missing song `padTrackID` → included pad matching `defaultKey`;
- current-schema explicit null `padTrackID` → intentional No Pad;
- missing runtime fields → runtime-only defaults (never persisted); and
- missing MIDI fields, if that feature has landed → MIDI disabled/no mappings.

Bookmark data is sensitive local metadata. It remains only in Sustain's
Application Support library and backup; logs and user-visible errors must not
print the full path unless the user explicitly opens file details.

Included pad UUIDs are fixed literal constants covered by regression tests, not
derived with Swift `hashValue` or another process/version-dependent algorithm.
When a future release adds a new included pad, merge it without reordering the
user's existing catalog; append it after the final included item by default.

`showIncludedPads` is not part of `LibrarySnapshot`; it is a UserDefaults-backed
view preference and does not trigger a schema migration.

## Audio memory and format policy

The catalog has no arbitrary item-count maximum, but each source must be safe
to decode. The current engine reads an entire file into `AVAudioPCMBuffer`, so
compressed file size is not a useful memory bound. Before allocation, estimate
decoded cost from frame length, processing format, bytes per frame, and channel
count using checked integer arithmetic.

V1 policy while using full-buffer looping:

- accept finite, nonempty mono or stereo files only;
- use broad `UTType.audio` selection, but promise support only for manually
  verified MP3, unprotected M4A/AAC, WAV, AIFF, and CAF combinations;
- reject protected/DRM, MIDI, directory, stream, unsupported multichannel, and
  malformed content with a specific error;
- cap a single decoded pad at **256 MiB**;
- enforce a **512 MiB total decoded-audio budget** across cache, prepared pad,
  and active/crossfading player buffers, counting shared buffers once;
- use a byte-cost LRU rather than only a four-item count; and
- if representative real-world pads cannot fit these defaults, replace
  full-buffer playback with a tested bounded streaming/seamless-loop design
  rather than merely raising limits until memory pressure disappears in tests.

The limits are implementation defaults and may be revised only with recorded
memory/service-duration evidence. An over-budget import remains in the batch
failure list and explains that the decoded audio is too large for safe live
playback. Do not crash, page aggressively, or claim it was imported.

Custom audio is looped exactly as decoded. Sustain does not promise to remove
encoder delay, leading/trailing silence, clicks, clipping, or loudness mismatch.
Manual QA covers mono/stereo, common sample rates, compressed and PCM files,
loop boundaries, and radically different source levels.

## Performance and reliability constraints

- Validate and decode external audio off the main actor.
- `preparePad` reports actual decode/conversion completion. Use a distinct
  `.preparing` load state; set playback `.fadingIn` only after scheduling and
  `.playing` only when the fade completes or the defined audible threshold is
  reached. Failure restores the complete prior audible pad identity/state.
- Enforce the decoded-byte budget above; catalog count must not increase
  resident decoded-audio memory linearly.
- On an injectable macOS memory-pressure warning/critical event, evict inactive
  cache entries immediately while retaining active/crossfading/prepared buffers
  required for truthful playback. Never respond by stopping live audio.
- Preload only the cued pad and naturally retain recently used buffers.
- Record file resource identity when available plus size/modification date.
  Re-stat immediately before coordinated decode. Cache by pad ID + resolved
  resource identity + fingerprint, not URL alone.
- Check for changes only at import/Locate, preload, and explicit preparation.
  Never continuously monitor or hot-swap audible/prepared audio. A prepared
  immutable buffer remains valid for its pending activation; the subsequent
  preparation observes the new file revision.
- A pending decode must be superseded by a newer start/stop. Use a bounded,
  latest-wins loader: at most one active decode and one newest pending request,
  with in-flight deduplication for the same identity. Generation checks alone
  are insufficient if obsolete large decodes continue to accumulate work.
- Large-file validation/import shows progress and remains cancellable at the
  batch level. Cancellation stops admission of further files and discards
  obsolete results; no unbounded background queue is allowed.
- File access and bookmark scopes must be balanced on success, failure, and
  cancellation. With fully decoded PCM buffers, access ends after decode rather
  than remaining open for cache residency or playback.
- An unreadable custom file blocks only that pad/song, not the whole library.
- Handle file changes, permission loss, and drive removal between validation
  and decode as ordinary typed runtime failures; this time-of-check/time-of-use
  race must never crash or partially transition audio.
- Save a batch/reorder/removal once, using existing atomic-write and backup
  behavior.

## Accessibility and interaction requirements

- All import, rename, reorder, locate, remove, pad-start, and clear actions are
  keyboard accessible.
- Drag-and-drop is additive; every drag operation has a button/menu equivalent.
- Full Keyboard Access can reach every row, search field, menu action, dialog,
  and playback control without custom focus rings fighting system focus effects.
- VoiceOver identifies label, source state, assignment count, order, and active
  playback state.
- Voice Control exposes unique spoken labels for duplicate-named pad buttons by
  including filename or position in the accessibility input label.
- Reordering announces the new position.
- Confirmation dialogs describe consequences without relying on color.
- Truncated custom labels expose their full text through accessibility and help.
- Missing files use text/icon state in addition to color.
- Respect Reduce Motion and Differentiate Without Color. Replace nonessential
  movement with fades and keep active/loading/error state legible without color.
- Meet or exceed the macOS 20×20-point minimum control target, with 28×28 or
  larger for frequently used performance controls.
- Test increased contrast, larger accessibility text, long localized strings,
  and keyboard focus after import/remove/search/clear. Audio-state changes do
  not steal focus.

## MIDI interaction and sequencing

The MIDI PRD currently maps **Toggle pad** to the existing
`startPad()/stopPad()` behavior. After this project, MIDI must dispatch the same
context-aware AppStore action as the Live button:

- current live song exists → start/stop only that current song's assigned pad;
- no current song and transport fully idle → start the cued pad as idle pre-roll;
- no current song and any pre-roll pad is audible/preparing → stop/cancel it;
- current song exists with a different NEXT cue → never start/crossfade NEXT's
  pad independently.

Do not let MIDI call an audio-engine method directly. Implementing the custom
pad model and early-pad AppStore actions before MIDI's final integration avoids
rewiring persisted mappings or behavior later. Core MIDI foundations can still
be developed independently. Direct MIDI mappings to individual arbitrary pad
tracks are a separate future feature; v1 MIDI continues to map transport-level
actions only.

## Analytics and privacy

No analytics are required for v1. Sustain must not upload audio, bookmarks,
paths, labels, MIDI data, hardware profiles, or usage. Feature data and playback
remain local/offline. If the user enables automatic checks or manually checks,
the only network operation in scope is the HTTPS appcast/update request with
ordinary transport metadata; Sparkle system profiling and custom feed
parameters remain disabled.

## Acceptance criteria

### Pad Library

- Importing one or many valid files creates ordered custom pads with filename-
  derived labels.
- Invalid files fail individually with an actionable message.
- Finder drag/drop and Add Audio… produce equivalent records.
- Finder drops insert at the visible drop indicator, preserve a stable item
  order, and never move/delete sources.
- Rename/reorder persists after relaunch and does not change song assignment.
- Duplicate labels are usable and distinguishable by secondary filename.
- Long labels produce equal-height, two-line, tail-truncated launch buttons and
  expose their full text through active state, tooltip, and accessibility.
- Hundreds of metadata rows remain responsive; decoded-memory use stays within
  the explicit total byte budget rather than scaling with library size.
- Hiding included pads removes them from browsers but not existing song
  playback.
- Moving/removing/unavailable sources produce the accurate typed state; Locate
  File repairs the same pad ID and all assignments.
- Removing a custom pad cannot orphan songs or delete the source file.
- Import, rename, reorder, reassignment, removal, and Clear Setlist participate
  in correctly named standard Undo/Redo without causing audio side effects.

### Song and audio behavior

- Migrated songs sound exactly as before using their included key pads.
- A custom pad can be assigned to a song and starts in Live Service.
- Runtime does not claim an uncached custom pad is playing until decode and
  scheduling succeed; a failed decode leaves state and controls truthful.
- Oversized, protected, unsupported-channel, malformed, unavailable-provider,
  and permission-denied files produce distinct actionable failures.
- Total decoded memory remains within the configured byte budget during
  preload, crossfade, cache churn, and rapid superseding presses.
- Changing a custom pad's label does not affect playback.
- **No Pad** songs start click/countoff and cleanly fade any outgoing pad.
- Rehearse launches the visible ordered catalog and never plays more than one
  pad at once.
- Pressing an already-audible pad does not restart it.

### Early-pad workflow

- With a first song cued and nothing playing, Play Pad starts only its pad.
- With song A still the playing entry and song B cued, the Pad control continues
  to operate only A's pad and offers no Play Next Pad action—even if A's click or
  pad was manually stopped.
- Global Stop plus completed pad fade returns the transport to idle and then
  permits B's pad pre-roll.
- Starting the matching pre-rolled song begins its countoff/click without a
  second pad preparation, activation, restart, or crossfade.
- Changing cue from pre-rolled A to B changes no audio and visibly names the
  mismatch. Pressing Start prepares B, then atomically starts B's click and
  replaces A's pre-roll with B's pad; No Pad fades A out.
- If A and B share a pad ID, Start transfers ownership and preserves playback
  position instead of restarting.
- A failed replacement preparation leaves A's pre-roll stable, keeps no song
  playing, and reports why.
- Rehearse or any preparing/fading audio blocks a new idle pre-roll; Sustain
  does not implicitly stop it.
- A two-phase transition test injects failures at target pad prepare, click
  prepare, and activation boundaries; no pre-commit failure alters current
  audio or playing identity.
- Stop is available and stops audio during pad-only pre-roll.

### Clear setlist

- Clear Setlist requires confirmation, removes all entries in one save, repairs
  runtime selection, and leaves songs/pads intact.
- Cancel changes nothing.
- Escape and Command-period cancel the confirmation; Cancel is not configured
  as the default alert action.
- The action cannot execute during active live audio.
- Empty setlists do not offer an active clear action.

### App Updates

- Only an installed official stable release starts Sparkle or offers an active
  **Sustain → Check for Updates…** command; branch, PR, ad-hoc, debug, and
  unpublished builds make no update request.
- Sparkle's permission flow and General Settings toggle control approximately
  daily checks; manual checks work when automatic checks are declined and show
  a clear already-current result.
- The standard update window identifies the version, renders signed release
  notes, and supports install, later, and skip without offering silent automatic
  installation.
- Scheduled and manual checks defer while any audio is preparing or active, run
  once after idle, and never alter playback. A pending updater relaunch waits
  for idle plus a successful save and invokes its install handler once.
- A read-only disk-image launch offers move-to-Applications guidance and does
  not attempt replacement. Normal `/Applications` authorization remains owned
  by Sparkle's installer service.
- The update archive, appcast, and any external notes validate with Sparkle
  EdDSA; tampering or malformed data leaves the installed app untouched.
- The canonical stapled `.app`, DMG, and update archive pass nested code-sign,
  hardened-runtime, entitlement, architecture, Gatekeeper, and notarization
  checks. The DMG and update archive contain the same canonical app.
- Tag, marketing version, and monotonically increasing build number are checked
  before signing. Ordinary main-branch pushes cannot publish an appcast item.
- The appcast is published last and never references a missing/mutable asset; a
  feed-publication failure leaves the prior valid feed available.
- A real lower → higher Sparkle-enabled signed/notarized update succeeds from
  `/Applications` and preserves library/preferences; after bootstrap, the lower
  build is the previous public release. Current, offline, skip, later,
  incompatible OS, bad signature, read-only location, active audio, save
  failure, and failed-install recovery paths have recorded evidence.

### Automated and manual verification

- Unit tests cover model coding, stable included IDs, migration, bookmark
  resolution/staleness, batch partial failure, duplicates, rename/reorder,
  delete/reassign, readiness, no-pad songs, early-pad idempotence, cue mismatch,
  transition failure, and atomic clear.
- Migration fixtures explicitly distinguish old missing `padTrackID`, current
  explicit null, current UUID, and invalid current missing-key data.
- File tests cover security-scope balance, coordinated File Provider reads,
  aliases/symlinks, drive removal during decode, resource-identity cache keys,
  same-path replacement, byte-overflow arithmetic, and latest-wins loading.
- Audio fakes assert exact prepare/activate call order and specifically prove no
  second pad activation on transition after early start.
- Manual QA covers file picker, Finder drop, rename/reorder, missing/remounted
  external drive, relaunch, at least one compressed and one PCM file, long-file
  memory behavior, keyboard/VoiceOver, and a signed/notarized build.
- Manual QA also covers Full Keyboard Access, Voice Control, Reduce Motion,
  Differentiate Without Color, increased contrast/text, menus/shortcuts,
  Undo/Redo, long/localized labels, drop insertion, iCloud/File Provider
  materialization, and the exact sandbox entitlement choice.
- A service-length test covers repeated idle pre-roll, cue replacement, normal
  transitions, and stop/fade/re-arm cycles with no leaks, stalls, ambiguous
  ownership, or unexpected restarts.
- Updater tests inject scheduled/manual check types, active/idle transitions,
  duplicate deferrals, read-only volumes, save failure, offline/malformed feeds,
  and relaunch callbacks. Release QA uses a real signed prior build and a
  tampered copy of the update archive, not only mocks.

## Release strategy

Ship behind completed migration and recovery tests; no feature flag is needed
because old behavior migrates directly to deterministic included pad records.
Release notes must explain reference-in-place behavior: moving or deleting a
source file requires locating it again, and uninstalling Sustain never removes
the user's audio files.

The sandbox capability spike is a merge gate for Slice 02, and the chosen
entitlements/signing path is a release gate. Verify entitlements with the built
artifact and run file import/relaunch plus USB/Bluetooth MIDI and external audio
routing against that exact artifact. Do not assume an Xcode/debug or ad-hoc
build proves Developer ID/notarized behavior.

App Updates is also a release gate once shipped. The appcast is the final
discoverability commit point: publish immutable assets first and the signed feed
last. A failed release must leave the prior valid appcast untouched. Do not
enable the production feed until a real lower-build update (the previous public
release after bootstrap), signed-feed test, and live-audio deferral test pass.

## Recommended delivery order

1. Ship Clear Setlist first as a small, isolated workflow improvement.
2. Complete the signed sandbox/capability spike and record the entitlement
   decision.
3. Land the custom-pad model/migration and external-file boundary while the
   release-only Sparkle packaging/feed workflow is developed against the signed
   capability decision.
4. Generalize audio and song assignment around prepare/activate and byte limits.
5. Add Pad Library management and the Rehearse catalog surface.
6. Add early-pad Live transport once audio identity is authoritative, then wire
   the updater's authoritative active-audio deferral and relaunch gate.
7. Finish MIDI persistence/UI/dispatch against the stabilized AppStore actions.
8. Prove a real lower-build Sparkle update (the previous public release after
   bootstrap) and run combined signed-build, real-audio, updater,
   removable-file, and physical-pedal QA.

Core MIDI input foundations may be built alongside steps 2–4, but its schema
migration and Toggle Pad dispatch should not merge until their shared contracts
are settled.

## Product decisions captured here

1. **Storage:** reference files in place; do not copy them.
2. **Scale:** no arbitrary count cap; scalable UI and bounded audio cache.
3. **Labels:** free-form and non-unique; stable IDs are authoritative.
4. **Bundled content:** hideable but not deletable or silently disabled for
   assigned songs.
5. **Song association:** one optional pad per song; No Pad is valid.
6. **Playback:** one looping pad at a time; sampler/one-shot behavior is later.
7. **Early pad:** is available only from fully idle Live state; while a song is
   current, Pad controls only that song. A matching idle pre-roll never restarts
   when its click/countoff begins.
8. **Clear setlist:** confirmed, atomic, and unavailable during live audio.
9. **Native Mac behavior:** standard menus, selection, keyboard focus,
   Undo/Redo, Finder drops, and system accessibility settings are required.
10. **Memory safety:** unlimited catalog metadata, but byte-bounded decoded
    audio with explicit per-file/total limits.
11. **Transitions:** prepare first, commit only after all required audio is ready.
12. **Preferences:** Show Included Pads lives in UserDefaults, not library data.
13. **Update checks:** Sparkle's native opt-in check flow runs approximately
    daily; manual checks always remain available in eligible official builds.
14. **Update installation:** each version requires an explicit install choice;
    automatic/silent installation is disallowed in v1.
15. **Update trust:** archive, feed, and external notes are EdDSA-signed; the
    canonical app remains Developer ID-signed, hardened, notarized, and stapled.
16. **Live safety:** any active/preparing audio defers checks and updater
    relaunch; the appcast is published only after immutable release assets.

## Open release inputs (not blockers for foundational implementation)

1. Identify representative user-owned MP3/M4A/WAV files for manual QA,
   including one on a removable drive.
2. Record results of the early sandbox/capability spike and the resulting
   entitlement set or documented reason to retain direct unsandboxed release.
3. Decide which physical MIDI pedal will be used for the combined final QA in
   the MIDI tracker.
4. Choose and provision the production stable HTTPS appcast URL/host, protected
   release environment, EdDSA recovery-key custody, and GitHub immutable-release
   setting before Slice 08A can publish a production feed.

## Apple platform references

Implementation and review should use current Apple documentation as authority:

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [SwiftUI fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aoncompletion%3A%29)
- [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers/)
- [Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo/)
- [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop)
- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- [Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)
- [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Sparkle 2 documentation](https://sparkle-project.org/documentation/)
- [Sparkle: Publishing an update](https://sparkle-project.org/documentation/publishing/)
- [Sparkle: Sandboxing](https://sparkle-project.org/documentation/sandboxing/)
- [Sparkle: Customization and update settings](https://sparkle-project.org/documentation/customization/)
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Signing Mac software with Developer ID](https://developer.apple.com/developer-id/)
- [GitHub: Immutable releases](https://docs.github.com/en/enterprise-cloud@latest/code-security/concepts/supply-chain-security/immutable-releases)
