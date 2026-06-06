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
    private let fileSystemResolver: FileSystemPadAssetResolver?

    init(fileSystemRoot: URL? = nil) {
        if let fileSystemRoot {
            fileSystemResolver = FileSystemPadAssetResolver(rootDirectory: fileSystemRoot)
        } else {
            fileSystemResolver = nil
        }
    }

    func asset(for padPack: PadPack, key: MusicalKey) -> PadAsset? {
        if padPack.isBundled {
            return bundleResolver.asset(for: padPack, key: key)
        }

        return fileSystemResolver?.asset(for: padPack, key: key)
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
            displayName: "\(key.rawValue).\(match.1)"
        )
    }
}

struct FileSystemPadAssetResolver: PadAssetResolving {
    private let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func asset(for padPack: PadPack, key: MusicalKey) -> PadAsset? {
        guard !padPack.isBundled else { return nil }

        let packDirectory = directory(for: padPack)
        let candidates = [
            "\(key.rawValue)",
            "\(key.rawValue) Major"
        ].flatMap { name in
            ["wav", "aif", "aiff", "mp3", "m4a", "flac"].map { fileExtension in
                packDirectory.appendingPathComponent("\(name).\(fileExtension)", isDirectory: false)
            }
        }

        guard let match = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }

        return PadAsset(
            url: match,
            displayName: "\(padPack.name)/\(match.lastPathComponent)"
        )
    }

    private func directory(for padPack: PadPack) -> URL {
        if (padPack.folderName as NSString).isAbsolutePath {
            return URL(fileURLWithPath: padPack.folderName, isDirectory: true)
        }

        return rootDirectory.appendingPathComponent(padPack.folderName, isDirectory: true)
    }
}

private struct PadAssetCandidate {
    var resourceName: String
    var `extension`: String
    var subdirectory: String
}
