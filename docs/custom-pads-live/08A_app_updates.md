# Slice 08A — Native App Updates and Release Pipeline

## Goal

Add a stable-release-only Sparkle 2 update experience that preserves Sustain's
Developer ID/notarization trust chain, requires an explicit install choice, and
cannot interrupt live or Rehearse audio.

## Dependencies

- Slice 00A must first establish the sandbox/entitlement distribution shape.
- Slice 05 must expose the final authoritative Live/pre-roll activity state
  before live-deferral acceptance can complete.
- This slice does not change `LibrarySnapshot` and must not claim a persistence
  schema version.

## Product configuration

1. Add a reviewed Sparkle 2 SwiftPM dependency, pin the resolved dependency,
   and add its license to third-party acknowledgements.
2. Create a main-actor `UpdateCoordinator` owned for the application lifetime.
   Instantiate `SPUStandardUpdaterController` programmatically after app launch
   so updater and standard-user-driver delegates can be retained and tested.
3. Official stable Developer ID builds alone receive `SUFeedURL`,
   `SUPublicEDKey`, and an enabled coordinator. Make updater eligibility an
   explicit signed-build configuration, not only `#if DEBUG`.
   Treat the first such release as a bootstrap: older public builds without
   Sparkle need one manual DMG install and cannot be promised an in-app update.
4. Configure `SUScheduledCheckInterval = 86400`,
   `SUAutomaticallyUpdate = NO`, `SUAllowsAutomaticUpdates = NO`,
   `SUEnableSystemProfiling = NO`, `SUShowReleaseNotes = YES`,
   `SUVerifyUpdateBeforeExtraction = YES`, `SURequireSignedFeed = YES`, and
   `SUSignedFeedFailureExpirationInterval = 0`. Preserve Sparkle's standard
   permission request instead of setting `SUEnableAutomaticChecks`.
5. Add **Sustain → Check for Updates…** in the conventional app-menu location
   and an **Automatically check for updates** General Settings control bound to
   Sparkle's persisted setting. Do not maintain a second preference authority.
6. Use Sparkle's standard UI for available, current, incompatible, offline,
   later, skip, install, download, authorization, and relaunch states.

## Live-safety integration

1. Add/test authoritative read-only AppStore properties for live-performance
   activity and all-audio activity. Include playing identity, countoff, click,
   pre-roll, pad preparation/fades, and Rehearse preparation/playback; screen
   selection alone is irrelevant.
2. In `SPUUpdaterDelegate`, reject background checks while audio is active.
   Coalesce them into one deferred request and run one background check after
   the store becomes fully idle.
3. Preflight a manual command in `UpdateCoordinator` before calling Sparkle. If
   audio is active, set a concise nonmodal status and coalesce the request; keep
   the delegate guard as a race-safety backstop rather than allowing Sparkle to
   present a denial alert. Update failures never mutate transport or content.
4. Implement `shouldPostponeRelaunchForUpdate` as a second safety gate. Retain
   at most one install handler, wait for all audio to become idle, flush pending
   persistence, and invoke once on the main actor. A save failure keeps the app
   running and presents recovery; no timeout forces a quit.
5. If playback starts after a user already opened/downloaded an update, do not
   stop audio or change routing. Measure a feed check/download during sustained
   playback for stalls and dropouts.
6. Detect a read-only launch volume using URL resource properties. Defer
   background checks there and make a manual command explain quit → drag to
   Applications → eject → reopen. Do not block ordinary Applications installs
   that Sparkle can update through its authorization service.

## Bundle and signing work

1. Update the custom SwiftPM bundler to copy `Sparkle.framework` and its required
   helpers/XPC services into `Contents/Frameworks` for both architectures.
2. Apply the Slice 00A sandbox choice using Sparkle's documented Installer XPC
   service, communication entitlement, and downloader/network configuration.
   Do not add broad exceptions or keep unused services without a recorded need.
3. Replace generic nested signing with an explicit, inside-out Sparkle helper,
   XPC, app, framework, executable, and outer-app signing sequence. Never sign
   with `--deep`; use it only if needed for a non-authoritative verification in
   addition to strict component checks.
4. Verify architectures, dynamic-library resolution, designated requirements,
   hardened runtime, secure timestamps, helper entitlements, outer entitlements,
   and strict code signatures on the final app.
5. Submit a temporary supported container holding the canonical Developer
   ID-signed `.app` to Apple's notary service, then staple/validate the app's
   ticket first. Produce the DMG and Sparkle ZIP from that same staged app, then
   sign/notarize/staple the DMG. Preserve framework symlinks, resource forks,
   extended attributes, signatures, and the app's stapled ticket in the ZIP.
6. Validate the app extracted from each container with `codesign`, `spctl`,
   Gatekeeper launch, architecture/minimum-OS inspection, notarization checks,
   and a recursive manifest proving both containers carry the same app.

## Versioning and protected release workflow

1. Remove hard-coded marketing/build versions from `scripts/bundle.sh`. Accept
   one validated release metadata source and use it for Info.plist, artifact
   names, appcast, and GitHub release metadata.
2. Require an immutable semantic tag such as `v1.2.3` to exactly match
   `CFBundleShortVersionString`. Require numeric `CFBundleVersion` to be greater
   than the newest stable appcast build and never reset.
3. Keep push/PR CI secret-free and unable to publish. Add a separate protected,
   approved release workflow targeting the tag commit; only it can access the
   Developer ID certificate, notarization credentials, Sparkle private key, and
   publication credentials. Pin third-party actions to reviewed commit SHAs.
4. Build/test once, sign/notarize/staple once, create a draft GitHub release,
   and upload version/build-qualified DMG, ZIP, checksums, and reviewed notes.
   Enable/prefer immutable GitHub releases and fail on reused identifiers.
5. Use Sparkle's `generate_appcast`/signing tools to produce a signed stable
   feed with embedded Markdown or plain-text notes. Every item includes build,
   display version, three-part minimum macOS, date, exact length, immutable
   HTTPS asset URL, and EdDSA signature. Full archives are required; deltas are
   deferred.
6. Verify every public asset URL and signature, publish the stable GitHub
   release, then atomically replace/deploy the signed appcast last. If any prior
   step or feed deployment fails, keep the old feed and report the release as
   incomplete.
7. Keep the EdDSA key out of repository/logs/artifacts/caches/PRs. Establish a
   protected CI secret, separately secured recovery backup, access audit, and
   tested key-rotation runbook before production publication.

## Tests and launch gate

- Unit tests cover eligibility, manual/background check classification,
  check coalescing, idle release, update-current/error messaging, read-only
  volume handling, relaunch postponement, single handler invocation, save
  failure, and no transport mutations.
- Packaging tests fail for missing/mis-signed Sparkle helpers, mismatched
  architectures, absent hardened runtime/timestamps, mismatched versions/tags,
  non-increasing builds, non-HTTPS URLs, absent signatures, or container drift.
- Feed tests reject unsigned/tampered/malformed data, prerelease items,
  incompatible minimum OS, and unavailable enclosures without touching the app.
- Before bootstrap, test a lower signed/notarized Sparkle-enabled build installed
  in `/Applications` against the higher candidate through a signed staging feed.
  For later releases, the lower build must be the previous public version. Test
  manual and opted-in scheduled checks, notes, install/later/skip, a newer
  release after skip, relaunch, and preserved library/preferences.
- Test offline/DNS/TLS failure, tampered ZIP, read-only DMG, locked install,
  authorization cancellation, failed installation recovery, and save failure.
- Test background/manual checks and accepted relaunch during current-song Live,
  idle pad pre-roll, transition preparation/fade, and Rehearse audio. No prompt,
  forced quit, dropout, route mutation, or duplicate deferred check is allowed.
- Record the exact release tag, old/new versions and builds, appcast URL, asset
  hashes, notarization IDs, signature checks, machines/macOS versions, and QA
  outcomes in the execution tracker before enabling production updates.

## Acceptance

- Official stable builds provide the standard native Sparkle update flow;
  ineligible builds make no update network request.
- Daily checks are opt-in and manual checking remains available. Every version
  requires an explicit install choice; no silent installation option appears.
- Active audio defers update UI and relaunch until idle and a successful save.
- Archive, signed feed/notes, Developer ID, hardened runtime, and notarization
  form a verified end-to-end trust chain.
- The appcast is published last and cannot expose an unavailable artifact.
- A real lower-build update succeeds before bootstrap and every later release
  updates from the previous public version; every failure path leaves the
  installed app and user data usable.
