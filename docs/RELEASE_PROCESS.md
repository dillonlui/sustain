# Sustain Release Process

Production releases run only through the manually approved
`Protected macOS release` workflow and its `production-release` environment.
Ordinary push and pull-request jobs have read-only repository access and no
Developer ID, notarization, Sparkle, or feed credentials.

## Release metadata and order

1. Update `config/release.json`. `version` is a stable three-part semantic
   version, `build` is a positive integer greater than every stable appcast
   build, and `minimumSystemVersion` has three parts.
2. Review `docs/releases/next.md`, commit, and create the immutable tag
   `v<version>` at that exact commit. Reused versions, builds, tags, and release
   identifiers are rejected.
3. Manually dispatch the protected workflow with the tag. Enable its
   **bootstrap** input only for the first Sparkle-enabled public release, when
   the stable appcast is expected to return HTTP 404; later releases require a
   valid existing appcast. The workflow tests once, builds one Universal 2 app,
   signs every Sparkle helper inside-out, notarizes and staples the app, and
   derives the DMG and full Sparkle ZIP from that app.
4. The workflow verifies signatures, hardened runtime, timestamps,
   architectures, entitlements, minimum OS, notarization, archive preservation,
   and recursive DMG/ZIP app identity. It creates a draft release and uploads
   version/build-qualified containers, checksums, and reviewed notes.
5. Only after assets are public and their immutable URLs and hashes verify does
   the workflow atomically commit the signed appcast to the configured feed
   repository. Feed publication is last. A failure before that point leaves the
   prior appcast unchanged and the release incomplete.

Never run `scripts/publish-appcast-last.sh` casually. It refuses to publish
unless `SUSTAIN_PUBLISH_PRODUCTION=1` and protected feed configuration and
credentials are present. Development work must use a separate staging feed and
must never inject the production feed URL into an ad-hoc build.

## Required protected configuration

- Developer ID Application PKCS#12, password, identity name, and ephemeral
  keychain password.
- App Store Connect notarization API key, key ID, and issuer ID.
- Sparkle public EdDSA key and private EdDSA key as separate protected secrets.
- Stable appcast URL plus feed repository, branch, and path as environment
  variables. Enable immutable GitHub releases and protect the feed branch.
- A separately secured, access-audited recovery copy of the Sparkle private key.

Secrets must never be placed in repository files, command output, build caches,
pull-request jobs, release artifacts, or app bundles. The private EdDSA key is
passed to `generate_appcast` over standard input and is not written to disk.

## Bootstrap and launch gate

The first Sparkle-enabled public release is a manual-install bootstrap. Before
shipping it, create lower and higher signed/notarized candidates with the final
distribution shape. Install the lower build in `/Applications` and prove a real
update through a signed staging feed. For later releases, repeat from the
previous public build. Record versions/builds, tag, staging appcast URL, asset
hashes, notarization submission IDs, machines/macOS versions, and outcomes in
the execution tracker.

The gate includes manual and opted-in scheduled checks; current/later/skip and
a newer release after skip; release notes; Live song, idle pre-roll,
transition/fade, and Rehearse deferral; successful relaunch with preserved
library/preferences; offline/DNS/TLS failure; malformed or tampered feed/archive;
incompatible macOS; read-only DMG; locked install; authorization cancellation;
save failure; and failed-install recovery. Do not enable the production appcast
until all applicable evidence is recorded.

## EdDSA key rotation

Rotation is a protected incident/release operation:

1. Audit access and preserve the old recovery key while supported installed
   builds still trust it.
2. Generate the new key only in a controlled release environment. Store the new
   private key in the protected secret and offline recovery store.
3. Ship an intermediate release whose trusted configuration permits the planned
   transition, following Sparkle's version-specific key-rotation guidance.
4. Prove old-key lower → transition → new-key higher updates on the signed
   staging feed, including tampered-feed rejection and rollback.
5. Publish assets first and the newly signed feed last. Retire the old key only
   after the supported installed population can reach a new-key-trusting build.

Record the rotation rehearsal and approvals in the tracker. A paper-only
rotation plan is not release evidence.

## 1.1.1 accepted QA exceptions

For 1.1.1, Product accepted release without physical USB/Bluetooth MIDI,
physical Intel Mac, real audio-interface/file-provider, or assistive-technology
testing. Release notes must disclose these as unverified; automated Intel CI and
Universal 2 validation must not be described as physical Intel usage. This
exception does not waive Developer ID signing, notarization, immutable artifact
verification, Sparkle signatures, or appcast-last publication.
