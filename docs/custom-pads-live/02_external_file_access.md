# Slice 02 — External File Access

## Goal

Create a testable boundary for coordinating, materializing, validating,
bookmarking, resolving, repairing, and safely accessing user-selected audio
files under the signed security model chosen in Slice 00A.

## Work

1. Read Slice 00A evidence and use its exact entitlement/signing model. Define
   injectable `ExternalAudioReferencing` / bookmark and validation
   seams; tests must not depend on real security scope.
2. Acquire picker/drop security scope before reading or bookmarking; release it
   on every success/failure/cancellation path.
3. Coordinate File Provider/iCloud and concurrently editable reads with
   `NSFileCoordinator` or an equivalent tested boundary; handle materialization.
4. Validate finite, positive frames/sample-rate and mono/stereo channels with
   `AVAudioFile` off-main. Estimate decoded bytes with checked arithmetic and
   apply the PRD's 256 MiB single-pad limit before allocation.
5. Create read-only app-scoped bookmarks and last-known display/fingerprint
   metadata without logging full paths. Prefer filesystem resource identity,
   with size/modification date as supporting evidence.
6. Resolve bookmarks, refresh stale data, and balance security-scope lifetime
   across the full async decode. Release scope once PCM is fully read;
   cached/scheduled buffers no longer need source-file access.
7. Add typed states/errors: available, preparing/downloading, missing,
   permission denied, protected/unsupported, unreadable, changed, and external
   volume/provider unavailable.
8. Implement Locate/Replace as an ID-preserving, validate-then-commit reference
   update operation.
9. Add batch import with partial success, deterministic order, cancellation,
   and one result summary. Resolve aliases/symlinks; reject folders, non-file
   URLs, protected/DRM, MIDI, multichannel, and non-durable file promises.

## Acceptance

- Tests cover create/resolve/stale refresh, denied access, provider
  materialization, coordinated reads, moved/missing source, drive removal,
  aliases/symlinks, duplicate selection, partial batch failure, checked-size
  overflow, and scope cleanup on every exit.
- Validation and bookmark work cannot block `MainActor`.
- Resolving never guesses another same-named file.
- Duplicate detection prefers resolved file identity and uses standardized path
  only as fallback; an in-place content change is not treated as a new pad.
- No operation copies or deletes the source file.

## Manual hold

Real security-scoped and removable-volume behavior is verified in Slice 08 on
the final signed distribution shape.
