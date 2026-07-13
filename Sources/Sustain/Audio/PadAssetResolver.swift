import Foundation

// Pad audio source/attribution:
// The bundled pads in `Resources/Pads/*.mp3` are "Ambient Pad Bases" by Karl Verkade
// (ambient guitar pads in all 12 keys), included on the basis of the artist's
// free-for-church-use offer. Support/buy: https://karlverkade.bandcamp.com/album/ambient-pad-bases
// See the Credits section in README.md.

extension Bundle {
    /// Resource bundle for pad audio and other packaged assets.
    ///
    /// SwiftPM's generated `Bundle.module` looks at `Bundle.main.bundleURL/<name>.bundle`
    /// (the .app root, where the bundle can't be placed without breaking code signing)
    /// and otherwise falls back to an absolute compile-time `.build` path. When the
    /// project lives under ~/Documents that fallback triggers a macOS "access your
    /// Documents folder" prompt on every launch. Resolve from the app's standard
    /// `Contents/Resources` first so we never hit that fallback; fall back to
    /// `.module` for tests and `swift run`.
    static let sustainResources: Bundle = {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Sustain_Sustain.bundle")
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return .module
    }()
}

struct PadAsset: Equatable {
    var url: URL
    var displayName: String
}

protocol PadAssetResolving {
    func asset(for padPack: PadPack, key: MusicalKey) -> PadAsset?
}

struct DefaultPadAssetResolver: PadAssetResolving {
    private let bundleResolver = BundlePadAssetResolver()

    func asset(for padPack: PadPack, key: MusicalKey) -> PadAsset? {
        bundleResolver.asset(for: padPack, key: key)
    }
}

struct BundlePadAssetResolver: PadAssetResolving {
    func asset(for padPack: PadPack, key: MusicalKey) -> PadAsset? {
        guard padPack.isBundled else { return nil }

        let candidates = [
            PadAssetCandidate(resourceName: "\(key.rawValue) Major", extension: "mp3", subdirectory: "Pads"),
            PadAssetCandidate(resourceName: "\(key.rawValue) Major", extension: "mp3", subdirectory: "Resources/Pads"),
            PadAssetCandidate(resourceName: key.rawValue, extension: "mp3", subdirectory: "Pads"),
            PadAssetCandidate(resourceName: key.rawValue, extension: "mp3", subdirectory: "Resources/Pads")
        ]

        guard let match = candidates.compactMap({ candidate -> (URL, String)? in
            Bundle.sustainResources.url(
                forResource: candidate.resourceName,
                withExtension: candidate.extension,
                subdirectory: candidate.subdirectory
            ).map { ($0, "\(candidate.resourceName).\(candidate.extension)") }
        }).first else {
            return nil
        }

        return PadAsset(
            url: match.0,
            displayName: match.1
        )
    }
}

private struct PadAssetCandidate {
    var resourceName: String
    var `extension`: String
    var subdirectory: String
}
