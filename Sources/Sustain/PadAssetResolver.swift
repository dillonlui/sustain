import Foundation

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
            Bundle.module.url(
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
