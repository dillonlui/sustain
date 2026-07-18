import Foundation
import CoreAudio
import Testing
@testable import Sustain

@MainActor
final class RecordingAudioEngine: AudioControlling {
    private var padIsActive = false
    private var clickIsActive = false
    var isEngineRunning: Bool { padIsActive || clickIsActive }
    var padStartCount = 0
    var clickStartCount = 0
    var clickStopCount = 0
    var padStopCount = 0
    var stopAllCount = 0
    var startedPadKeys: [MusicalKey] = []
    var clickBPMHistory: [Int] = []
    var clickTimeSignatureHistory: [TimeSignature] = []
    var clickIncludesCountoffHistory: [Bool] = []
    var clickSettingsHistory: [ClickSettings] = []
    var configureRoutingCount = 0
    var lastConfiguredSnapshot: AudioRoutingSnapshot?
    var lastPadVolume = 0.42
    var lastClickVolume = 0.75
    var missingPadKeys: Set<MusicalKey>
    var preloadedKeys: [MusicalKey] = []
    var shouldFailPadStart = false
    var shouldFailClickStart = false
    var shouldFailConfigureRouting = false
    var statusSummary: String { isEngineRunning ? "Running" : "Stopped" }
    var isPadActive: Bool { padIsActive }
    var isClickActive: Bool { clickIsActive }

    init(missingPadKeys: Set<MusicalKey> = []) {
        self.missingPadKeys = missingPadKeys
    }

    func prepare() {}

    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws {
        configureRoutingCount += 1
        lastConfiguredSnapshot = snapshot
        if shouldFailConfigureRouting {
            throw AudioEngineError.invalidOutputFormat
        }
    }

    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String {
        missingPadKeys.contains(key) ? "Missing included pad \(key.rawValue).mp3" : "Found \(key.rawValue).mp3"
    }

    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool {
        !missingPadKeys.contains(key)
    }

    func preloadPad(for key: MusicalKey, padPack: PadPack) {
        preloadedKeys.append(key)
    }

    func startPad(for key: MusicalKey, padPack: PadPack) throws {
        padStartCount += 1
        startedPadKeys.append(key)
        if shouldFailPadStart {
            throw AudioEngineError.unreadablePadFile(URL(fileURLWithPath: "\(key.rawValue).mp3"))
        }
        padIsActive = true
    }

    func stopPad() {
        padStopCount += 1
        padIsActive = false
    }

    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool, settings: ClickSettings) throws {
        clickStartCount += 1
        clickBPMHistory.append(bpm)
        clickTimeSignatureHistory.append(timeSignature)
        clickIncludesCountoffHistory.append(includesCountoff)
        clickSettingsHistory.append(settings)
        if shouldFailClickStart {
            throw AudioEngineError.invalidOutputFormat
        }
        clickIsActive = true
    }

    func stopClick() {
        clickStopCount += 1
        clickIsActive = false
    }

    func setPadVolume(_ volume: Double) {
        lastPadVolume = volume
    }

    func setClickVolume(_ volume: Double) {
        lastClickVolume = volume
    }

    func stopAll() {
        stopAllCount += 1
        padIsActive = false
        clickIsActive = false
    }
}

final class MutableAudioRoutingProvider: AudioRoutingProviding {
    var snapshotValue: AudioRoutingSnapshot

    init(snapshotValue: AudioRoutingSnapshot) {
        self.snapshotValue = snapshotValue
    }

    func snapshot(settings: AudioRoutingSettings = .default) -> AudioRoutingSnapshot {
        snapshotValue
    }
}
