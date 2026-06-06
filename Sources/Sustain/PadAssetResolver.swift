import Foundation

struct PadAsset: Equatable {
    var url: URL
    var displayName: String
}

protocol PadAssetResolving {
    func asset(for padPack: PadPack, key: MusicalKey) -> PadAsset?
}

struct BundlePadAssetResolver: PadAssetResolving {
    func asset(for padPack: PadPack, key: MusicalKey) -> PadAsset? {
        let subdirectories = [
            "Pads/\(padPack.folderName)",
            "Resources/Pads/\(padPack.folderName)"
        ]

        guard let url = subdirectories.compactMap({ subdirectory in
            Bundle.module.url(
            forResource: key.rawValue,
            withExtension: "wav",
            subdirectory: subdirectory
            )
        }).first else {
            return nil
        }

        return PadAsset(
            url: url,
            displayName: "\(padPack.name) \(key.rawValue).wav"
        )
    }
}
