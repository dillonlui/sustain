import Foundation
import CoreAudio
import AVFoundation
import Testing
@testable import Sustain

@MainActor
final class RecordingAudioEngine: AudioControlling {
    private var padIsActive = false
    private var clickIsActive = false
    var isEngineRunning: Bool { padIsActive || clickIsActive }
    var padStartCount = 0
    var padPrepareCount = 0
    var padActivateCount = 0
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
    var defersPadPreparation = false
    var defersClickPreparation = false
    private var pendingPadPreparation: (@MainActor () -> Void)?
    private var pendingClickPreparation: (@MainActor () -> Void)?
    private var preparedPadKeys: [UUID: MusicalKey] = [:]
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

    func padAssetState(for pad: PadTrack) -> PadAssetState {
        if let key = pad.source.bundledKey, missingPadKeys.contains(key) { return .missing }
        return .available(PadAudioMetadata(duration: 1, channelCount: 2, sampleRate: 44_100, decodedByteCount: 8))
    }

    func preparePad(
        _ pad: PadTrack,
        completion: @escaping @MainActor @Sendable (Result<PreparedPad, Error>) -> Void
    ) {
        padPrepareCount += 1
        if let key = pad.source.bundledKey { preloadedKeys.append(key) }
        if shouldFailPadStart {
            completion(.failure(AudioEngineError.unreadablePadFile(URL(fileURLWithPath: "pad.mp3"))))
            return
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        let fingerprint = ExternalFileFingerprint(resourceIdentifierData: nil, fileSize: 1, modificationDate: nil)
        let key = PadBufferKey(padID: pad.id, resourceIdentityData: nil, fingerprint: fingerprint)
        let prepared = PreparedPad(
            padID: pad.id,
            displayName: pad.label,
            generation: UInt64(padPrepareCount),
            token: UUID(),
            key: key,
            pcm: ImmutablePCMBuffer(buffer: buffer, byteCount: 8)
        )
        if let key = pad.source.bundledKey { preparedPadKeys[prepared.token] = key }
        if defersPadPreparation {
            pendingPadPreparation = { completion(.success(prepared)) }
        } else {
            completion(.success(prepared))
        }
    }

    func activatePad(_ prepared: PreparedPad) {
        padActivateCount += 1
        padStartCount += 1
        if let key = preparedPadKeys.removeValue(forKey: prepared.token) { startedPadKeys.append(key) }
        padIsActive = true
    }

    func discardPreparedPad(_ prepared: PreparedPad) {}
    func cancelPendingPadPreparation() {}

    func completePendingPadPreparation() {
        let pending = pendingPadPreparation
        pendingPadPreparation = nil
        pending?()
    }

    func prepareClick(
        bpm: Int,
        timeSignature: TimeSignature,
        includesCountoff: Bool,
        settings: ClickSettings,
        completion: @escaping @MainActor @Sendable (Result<PreparedClick, Error>) -> Void
    ) {
        clickBPMHistory.append(bpm)
        clickTimeSignatureHistory.append(timeSignature)
        clickIncludesCountoffHistory.append(includesCountoff)
        clickSettingsHistory.append(settings)
        if shouldFailClickStart {
            completion(.failure(AudioEngineError.invalidOutputFormat))
            return
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        let pcm = ImmutablePCMBuffer(buffer: buffer, byteCount: 8)
        let prepared = PreparedClick(loop: pcm, countoff: includesCountoff ? pcm : nil)
        if defersClickPreparation {
            pendingClickPreparation = { completion(.success(prepared)) }
        } else {
            completion(.success(prepared))
        }
    }

    func completePendingClickPreparation() {
        let pending = pendingClickPreparation
        pendingClickPreparation = nil
        pending?()
    }

    func activateClick(_ prepared: PreparedClick) {
        clickStartCount += 1
        clickIsActive = true
    }

    func handleMemoryPressure() {}

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

@MainActor
final class RecordingMIDIController: MIDIControlling {
    var availableSources: [MIDIControllerSource]
    var state: MIDIControllerServiceState = .stopped
    var eventHandler: ((MIDIMessage) -> Void)?
    var sourceLifecycleHandler: ((Int32) -> Void)?
    var startCount = 0
    var stopCount = 0

    init(sources: [MIDIControllerSource] = []) { availableSources = sources }
    func start() { startCount += 1; state = .running }
    func stop() { stopCount += 1; state = .stopped }
    func refresh() {}
    func send(_ event: MIDIMessage) { eventHandler?(event) }
    func disconnect(_ uniqueID: Int32) {
        availableSources.removeAll { $0.uniqueID == uniqueID }
        sourceLifecycleHandler?(uniqueID)
    }
}
