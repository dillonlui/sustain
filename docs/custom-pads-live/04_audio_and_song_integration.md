# Slice 04 — Audio and Song Integration

## Goal

Generalize pad resolution/playback from key/pack to `PadTrack`, wire explicit
song assignments including No Pad, and preserve the existing audio-safety
invariants.

## Work

1. Change `PadAssetResolving` and `AudioControlling` pad APIs to accept stable
   pad identity/source and use two phases: async `preparePad` plus main-actor
   `activatePad`, instead of `PadPack + MusicalKey` or optimistic `startPad`.
2. Resolve included bundle files and external bookmarks behind one resolver.
3. Keep decode/conversion off-main, generation supersession, looping behavior,
   and crossfades. Replace the four-item cache with a byte-cost LRU and one
   shared 512 MiB budget across cache, prepared, active, and fading buffers;
   enforce 256 MiB per pad and count shared buffers once.
4. Preparation owns all likely failure (permission, coordination, decode,
   conversion, memory admission) and cannot alter audio. Activation accepts an
   immutable prepared buffer and performs only nonthrowing
   scheduling/crossfade work. Engine/output readiness and stale-token checks
   complete before commit eligibility.
5. Use separate `.preparing`, `.fadingIn`, and `.playing` truth states.
6. Ensure resource access remains valid through complete decode and closes once
   PCM is owned by the app; cancellation and failure must also close it.
7. Implement one-active-plus-one-latest pending decode with same-identity
   deduplication; generation checks alone must not queue obsolete large files.
8. Cache by pad ID + resource identity + fingerprint. Re-stat before coordinated
   decode, retain already-prepared/active buffers, and observe revisions on the
   next preparation without hot-swapping audio.
9. Update readiness to distinguish intentional No Pad from each typed external
   failure state.
10. Add searchable Assigned Pad / No Pad editing to songs.
11. Preserve key-follow convenience only while a song uses its matching
   included pad; never overwrite a custom/No Pad selection on key change.
12. Define safe live editing: changing an audible pad assignment does not
   silently restart it; the next explicit start/transition uses the new value.
13. Update fakes, previews, seed data, status summaries, and tests.
14. Add an injectable memory-pressure response that evicts inactive cache
    buffers without stopping or corrupting active/prepared audio.

## Acceptance

- Included playback is regression-equivalent.
- Verified MP3, unprotected M4A/AAC, WAV, AIFF, and CAF mono/stereo fixtures
  resolve, decode, loop, and crossfade; unsupported/DRM/MIDI/multichannel files
  fail specifically.
- A missing custom file blocks only the affected pad/song with recovery text.
- Preparation exposes pending state and reports success only after decode and
  memory admission; activation alone moves through fade/playback state.
- No Pad starts click/countoff and fades an outgoing pad.
- Reassigning/renaming uses IDs and does not accidentally restart audio.
- Decoded bytes stay within per-pad/total budgets during preparation, cache
  churn, active playback, and crossfade; checked overflow fails safely.
- Replacing file contents at the same URL cannot replay a stale cache entry on
  the next explicit start and never hot-swaps currently audible audio.
- Rapid requests never create more than one active and one latest pending
  decode, and obsolete completion cannot commit.
- Warning/critical memory-pressure tests purge inactive cache while active audio
  remains uninterrupted and total accounting stays correct.
