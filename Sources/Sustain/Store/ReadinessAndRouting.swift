import CoreAudio
import Foundation

/// Pure reconciliation of persisted routing settings against the current hardware snapshot.
/// Extracted from `AppStore` so the rules can be reasoned about and unit-tested without a
/// store or a real audio engine.
enum RoutingSettingsNormalizer {
    static func normalize(
        _ settings: AudioRoutingSettings,
        snapshot: AudioRoutingSnapshot
    ) -> AudioRoutingSettings {
        AudioRoutingSettings(
            padOutputID: normalizedOutputID(currentID: settings.padOutputID, resolvedID: snapshot.padOutputID),
            padOutputName: normalizedOutputName(
                currentID: settings.padOutputID,
                currentName: settings.padOutputName,
                resolvedName: snapshot.padOutputName
            ),
            padOutputChannel: settings.padOutputChannel,
            clickOutputID: normalizedOutputID(currentID: settings.clickOutputID, resolvedID: snapshot.clickOutputID),
            clickOutputName: normalizedOutputName(
                currentID: settings.clickOutputID,
                currentName: settings.clickOutputName,
                resolvedName: snapshot.clickOutputName
            ),
            clickOutputChannel: settings.clickOutputChannel
        )
    }

    /// Keep a chosen device even if it's momentarily unresolved (e.g. unplugged), but if the
    /// user never chose one, stay on the system default (`nil`).
    static func normalizedOutputID(currentID: AudioDeviceID?, resolvedID: AudioDeviceID?) -> AudioDeviceID? {
        guard currentID != nil else { return nil }
        return resolvedID ?? currentID
    }

    static func normalizedOutputName(currentID: AudioDeviceID?, currentName: String?, resolvedName: String) -> String? {
        guard currentID != nil else { return nil }
        return resolvedName == "Unavailable" ? currentName : resolvedName
    }
}

/// Evaluates whether a cued song can start and what warnings apply, given audio capabilities
/// and the current routing. Decoupled from `AppStore` (dependencies passed in as closures/values)
/// so readiness rules can be unit-tested directly without driving the whole store.
struct SetlistReadinessEvaluator {
    var hasPadAsset: (PadPack, MusicalKey) -> Bool
    var padAssetStatus: (PadPack, MusicalKey) -> String
    var routingSnapshot: AudioRoutingSnapshot
    var routingFailureMessage: String?
    var entries: [SetlistEntry]
    var song: (SetlistEntry) -> Song?

    func validate(entry: SetlistEntry, song: Song) -> SystemCheckResult {
        var blockingMessages: [String] = []
        var warnings: [String] = []
        let key = song.defaultKey
        let bpm = song.defaultBPM

        if bpm <= 0 {
            blockingMessages.append("\(song.title) needs a valid BPM.")
        }

        if !hasPadAsset(song.padPack, key) {
            blockingMessages.append(padAssetStatus(song.padPack, key))
        }

        if routingSnapshot.outputs.isEmpty {
            blockingMessages.append("No output audio device is available.")
        } else if let routingFailureMessage {
            blockingMessages.append(routingFailureMessage)
        } else if !routingSnapshot.missingSelectionMessages.isEmpty {
            blockingMessages.append(contentsOf: routingSnapshot.missingSelectionMessages)
        } else if let warning = routingSnapshot.warning {
            warnings.append(warning)
        }

        warnings.append(contentsOf: setlistWarnings(excluding: entry.id))

        var messages = blockingMessages
        if messages.isEmpty {
            messages.append("Ready for \(song.title) in \(key.rawValue) at \(bpm) BPM.")
        }
        messages.append(contentsOf: warnings.map { "Warning: \($0)" })

        return SystemCheckResult(
            canStartPlayback: blockingMessages.isEmpty,
            messages: messages,
            warnings: warnings
        )
    }

    private func setlistWarnings(excluding cuedEntryID: SetlistEntry.ID) -> [String] {
        entries.enumerated().flatMap { index, entry -> [String] in
            guard entry.id != cuedEntryID else {
                return []
            }

            guard let song = song(entry) else {
                return ["Setlist entry \(index + 1): references a missing song."]
            }

            var warnings: [String] = []
            let key = song.defaultKey
            let bpm = song.defaultBPM

            if bpm <= 0 {
                warnings.append("\(song.title): needs a valid BPM.")
            }

            if !hasPadAsset(song.padPack, key) {
                warnings.append("\(song.title): \(padAssetStatus(song.padPack, key))")
            }

            return warnings
        }
    }
}
