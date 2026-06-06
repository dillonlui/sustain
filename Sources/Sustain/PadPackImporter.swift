import Foundation

struct PadPackImportResult: Equatable {
    var padPack: PadPack
    var missingKeys: [MusicalKey]
}

enum PadPackImportError: LocalizedError {
    case noUsablePads(URL)

    var errorDescription: String? {
        switch self {
        case .noUsablePads(let url):
            "No usable pad files were found in \(url.lastPathComponent)."
        }
    }
}

struct PadPackImporter {
    private let destinationRoot: URL
    private let fileManager: FileManager

    init(destinationRoot: URL, fileManager: FileManager = .default) {
        self.destinationRoot = destinationRoot
        self.fileManager = fileManager
    }

    func inspectFolder(_ sourceURL: URL, name: String? = nil) throws -> PadPackImportResult {
        let availableKeys = try availableKeys(in: sourceURL)
        let padPack = PadPack(
            name: resolvedName(from: sourceURL, override: name),
            folderName: sourceURL.lastPathComponent,
            availableKeys: availableKeys
        )

        return PadPackImportResult(
            padPack: padPack,
            missingKeys: MusicalKey.allCases.filter { !availableKeys.contains($0) }
        )
    }

    func importFolder(_ sourceURL: URL, name: String? = nil) throws -> PadPackImportResult {
        let inspected = try inspectFolder(sourceURL, name: name)
        guard !inspected.padPack.availableKeys.isEmpty else {
            throw PadPackImportError.noUsablePads(sourceURL)
        }

        if !fileManager.fileExists(atPath: destinationRoot.path) {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        }

        let folderName = uniqueFolderName(for: inspected.padPack.name)
        let destinationURL = destinationRoot.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let padPack = PadPack(
            name: inspected.padPack.name,
            folderName: folderName,
            availableKeys: inspected.padPack.availableKeys
        )

        return PadPackImportResult(
            padPack: padPack,
            missingKeys: inspected.missingKeys
        )
    }

    private func availableKeys(in folderURL: URL) throws -> Set<MusicalKey> {
        let fileURLs = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        )
        let fileNames = Set(fileURLs.map { $0.deletingPathExtension().lastPathComponent.lowercased() })

        return Set(MusicalKey.allCases.filter { key in
            fileNames.contains(key.rawValue.lowercased()) ||
                fileNames.contains("\(key.rawValue.lowercased()) major")
        })
    }

    private func uniqueFolderName(for name: String) -> String {
        let base = sanitizedFolderName(for: name)
        var candidate = base
        var suffix = 2

        while fileManager.fileExists(atPath: destinationRoot.appendingPathComponent(candidate, isDirectory: true).path) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func sanitizedFolderName(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = name.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Pad Pack" : sanitized
    }

    private func resolvedName(from sourceURL: URL, override: String?) -> String {
        let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }

        return sourceURL.lastPathComponent
    }
}
