import AVFoundation
import AudioToolbox
import Foundation

enum AudioEngineError: LocalizedError {
    case invalidBPM(Int)
    case invalidOutputFormat
    case outputDeviceAssignmentFailed(deviceID: AudioDeviceID, status: OSStatus)
    case missingPadFile(pack: String, key: MusicalKey)
    case unreadablePadFile(URL)

    var errorDescription: String? {
        switch self {
        case .invalidBPM(let bpm):
            "BPM must be greater than zero. Received \(bpm)."
        case .invalidOutputFormat:
            "The system output format is not available."
        case .outputDeviceAssignmentFailed(let deviceID, let status):
            "Could not assign output device \(deviceID). Core Audio status: \(status)."
        case .missingPadFile(let pack, let key):
            "\(pack) does not include a pad for \(key.rawValue)."
        case .unreadablePadFile(let url):
            "The pad file could not be loaded: \(url.lastPathComponent)."
        }
    }
}

@MainActor
protocol AudioControlling: AnyObject {
    var isEngineRunning: Bool { get }
    var statusSummary: String { get }
    var supportsAudioCountoffCompletion: Bool { get }
    var countoffHasCompleted: Bool { get }
    var clickStoppedAfterCountoff: Bool { get }

    func prepare()
    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws
    func padAssetState(for pad: PadTrack) -> PadAssetState
    func preparePad(
        _ pad: PadTrack,
        completion: @escaping @MainActor @Sendable (Result<PreparedPad, Error>) -> Void
    )
    @discardableResult func activatePad(_ prepared: PreparedPad) -> Bool
    func discardPreparedPad(_ prepared: PreparedPad)
    func cancelPendingPadPreparation()
    func prepareClick(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision,
        includesCountoff: Bool,
        settings: ClickSettings,
        completion: @escaping @MainActor @Sendable (Result<PreparedClick, Error>) -> Void
    )
    func prepareClick(
        bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision,
        pulseInterpretation: PulseInterpretation, accentPattern: [ClickAccentLevel]?,
        countoffPolicy: CountoffPolicy, settings: ClickSettings,
        completion: @escaping @MainActor @Sendable (Result<PreparedClick, Error>) -> Void
    )
    func activateClick(_ prepared: PreparedClick) throws
    func scheduleClickChange(
        _ prepared: PreparedClick,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    )
    func cancelScheduledClickChange()
    func handleMemoryPressure()
    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String
    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool
    func preloadPad(for key: MusicalKey, padPack: PadPack)
    func startPad(for key: MusicalKey, padPack: PadPack) throws
    func stopPad()
    func startClick(bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision, includesCountoff: Bool, settings: ClickSettings) throws
    func startClick(bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision,
                    pulseInterpretation: PulseInterpretation, accentPattern: [ClickAccentLevel]?,
                    countoffPolicy: CountoffPolicy, settings: ClickSettings) throws
    func stopClick()
    func setPadVolume(_ volume: Double)
    func setClickVolume(_ volume: Double)
    func stopAll()
}

extension AudioControlling {
    /// Optional: engines that decode real files override this to warm a cache off the
    /// main thread. No-op by default.
    func preloadPad(for key: MusicalKey, padPack: PadPack) {}
    var supportsAudioCountoffCompletion: Bool { false }
    var countoffHasCompleted: Bool { false }
    var clickStoppedAfterCountoff: Bool { false }
    func prepareClick(
        bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision,
        pulseInterpretation: PulseInterpretation, accentPattern: [ClickAccentLevel]?,
        countoffPolicy: CountoffPolicy, settings: ClickSettings,
        completion: @escaping @MainActor @Sendable (Result<PreparedClick, Error>) -> Void
    ) {
        prepareClick(bpm: bpm, timeSignature: timeSignature, subdivision: subdivision,
                     includesCountoff: countoffPolicy.hasCountoff, settings: settings, completion: completion)
    }
    func startClick(bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision,
                    pulseInterpretation: PulseInterpretation, accentPattern: [ClickAccentLevel]?,
                    countoffPolicy: CountoffPolicy, settings: ClickSettings) throws {
        try startClick(bpm: bpm, timeSignature: timeSignature, subdivision: subdivision,
                       includesCountoff: countoffPolicy.hasCountoff, settings: settings)
    }
}

@MainActor
final class SustainAudioEngine: AudioControlling {
    private let padEngine = AVAudioEngine()
    private let clickEngine = AVAudioEngine()
    private let padPlayers = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let padMixers = [AVAudioMixerNode(), AVAudioMixerNode()]
    private var clickSourceNode: AVAudioSourceNode!
    private var clickRenderer: ClickLoopRenderer!
    private let clickMixer = AVAudioMixerNode()
    private let clickFormat: AVAudioFormat
    private let padAssetResolver: PadAssetResolving
    private let externalAudioReferencer: any ExternalAudioReferencing
    private let voiceRenderer: CountoffVoiceRendering?

    /// Below this beat length a spoken word cannot stay intelligible, so the count-off
    /// falls back to clicks (matching how Ableton only clicks at fast tempos).
    nonisolated private static let minSpokenBeatDuration: TimeInterval = 0.33
    private var activePadIndex: Int?
    private var nextPadIndex = 0
    private var activePadKey: MusicalKey?
    private var activePadTrackID: PadTrack.ID?
    private var activePadMemoryKey: PadBufferKey?
    private var activePadAssetName: String?
    private var clickIsActive = false
    private var activeCountoffGeneration = 0
    private var activeClickStopsAfterCountoff = false
    private var clickSwitchSerial = 0
    private var clickSwitchTask: Task<Void, Never>?
    private var padVolume: Float = 0.42
    private var clickVolume: Float = 0.75
    private var routingSummary = "Default output"
    private var padOutputChannel: AudioOutputChannelSelection = .stereo
    private var clickOutputChannel: AudioOutputChannelSelection = .stereo
    private var padFadeTasks: [Task<Void, Never>?] = [nil, nil]
    private var padStopTasks: [Task<Void, Never>?] = [nil, nil]
    private var padGenerations = [0, 0]
    /// Bumped by every startPad/stopPad. A deferred (off-main) decode only commits if it still
    /// matches the latest value, so a stop or newer start during the decode window supersedes it.
    private var padStartGeneration = 0
    private var preparationGeneration: UInt64 = 0
    private var preparedKeysByToken: [UUID: PadBufferKey] = [:]
    private let padMemoryStore: PadBufferMemoryStore
    private let latestWinsDecoder = LatestWinsPadDecoder()
    private let padBufferCache = PadBufferCache()
    private let padDecodeQueue = DispatchQueue(label: "com.sustain.pad-decode", qos: .userInitiated)

    var isEngineRunning: Bool {
        padEngine.isRunning || clickEngine.isRunning
    }
    var countoffHasCompleted: Bool {
        activeCountoffGeneration > 0 &&
            clickRenderer.lastCompletedCountoffGeneration >= activeCountoffGeneration
    }
    var supportsAudioCountoffCompletion: Bool { true }
    var clickStoppedAfterCountoff: Bool {
        clickIsActive && activeClickStopsAfterCountoff && countoffHasCompleted
    }

    var statusSummary: String {
        var active: [String] = []
        if let activePadKey {
            if let activePadAssetName {
                active.append(activePadAssetName)
            } else {
                active.append("Pad \(activePadKey.rawValue)")
            }
        }
        if clickIsActive && !clickStoppedAfterCountoff {
            active.append("Click")
        }

        if active.isEmpty {
            return isEngineRunning ? "Idle (\(routingSummary))" : "Stopped"
        }

        return "\(active.joined(separator: " + ")) (\(routingSummary))"
    }

    init(
        padAssetResolver: PadAssetResolving = DefaultPadAssetResolver(),
        externalAudioReferencer: any ExternalAudioReferencing = ExternalAudioReferenceService(),
        padMemoryStore: PadBufferMemoryStore = PadBufferMemoryStore(),
        voiceRenderer: CountoffVoiceRendering? = SpeechCountoffVoiceRenderer()
    ) {
        self.padAssetResolver = padAssetResolver
        self.externalAudioReferencer = externalAudioReferencer
        self.padMemoryStore = padMemoryStore
        self.voiceRenderer = voiceRenderer

        let hardwareFormat = clickEngine.outputNode.inputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 44_100
        let channelCount = hardwareFormat.channelCount > 0 ? min(hardwareFormat.channelCount, 2) : 2
        // Safe unwrap: sampleRate is guaranteed > 0 and channelCount ∈ {1,2} above, which is a
        // valid standard PCM format. `init` can't throw; there's no non-failable AVAudioFormat
        // initializer, so the fallback is a hardcoded, always-valid format.
        clickFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)
            ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

        for index in padPlayers.indices {
            padEngine.attach(padPlayers[index])
            padEngine.attach(padMixers[index])
            padMixers[index].outputVolume = 0
            padEngine.connect(padPlayers[index], to: padMixers[index], format: nil)
            padEngine.connect(padMixers[index], to: padEngine.mainMixerNode, format: nil)
        }

        let renderer = ClickLoopRenderer(format: clickFormat)
        clickRenderer = renderer
        clickSourceNode = Self.makeClickSourceNode(format: clickFormat, renderer: renderer)
        clickEngine.attach(clickSourceNode)
        clickEngine.attach(clickMixer)
        clickMixer.outputVolume = clickVolume
        clickEngine.connect(clickSourceNode, to: clickMixer, format: clickFormat)
        clickEngine.connect(clickMixer, to: clickEngine.mainMixerNode, format: clickFormat)

        voiceRenderer?.prewarm(numbers: Array(1...12), format: clickFormat)
    }

    /// The render block runs on Core Audio's real-time thread. Create it in a
    /// nonisolated context so Swift does not inherit this engine's main-actor
    /// isolation and trap when the first audio buffer is requested.
    nonisolated static func makeClickSourceNode(
        format: AVAudioFormat,
        renderer: ClickLoopRenderer
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            renderer.render(frameCount: frameCount, audioBufferList: audioBufferList)
        }
    }

    func prepare() {
        padEngine.prepare()
        clickEngine.prepare()
    }

    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws {
        if padEngine.isRunning || clickEngine.isRunning {
            stopAll()
            padEngine.stop()
            clickEngine.stop()
        }

        if let padOutputID = snapshot.padOutputID {
            try setOutputDevice(padOutputID, on: padEngine)
        }

        if let clickOutputID = snapshot.clickOutputID {
            try setOutputDevice(clickOutputID, on: clickEngine)
        }

        padOutputChannel = snapshot.padOutputChannel
        clickOutputChannel = snapshot.clickOutputChannel
        applyOutputChannelRouting()
        routingSummary = snapshot.summary
    }

    func padAssetState(for pad: PadTrack) -> PadAssetState {
        switch pad.source {
        case let .bundled(key):
            return padAssetResolver.asset(for: .bundled, key: key) == nil
                ? .missing
                : .available(PadAudioMetadata(duration: 0, channelCount: 2, sampleRate: 44_100, decodedByteCount: 0))
        case let .external(reference):
            return .available(reference.audioMetadata)
        }
    }

    func preparePad(
        _ pad: PadTrack,
        completion: @escaping @MainActor @Sendable (Result<PreparedPad, Error>) -> Void
    ) {
        do {
            try startPadEngineIfNeeded()
        } catch {
            completion(.failure(error))
            return
        }

        preparationGeneration &+= 1
        let generation = preparationGeneration
        let token = UUID()
        switch pad.source {
        case let .bundled(musicalKey):
            guard let asset = padAssetResolver.asset(for: .bundled, key: musicalKey) else {
                completion(.failure(AudioEngineError.missingPadFile(pack: PadPack.bundled.name, key: musicalKey)))
                return
            }
            let fingerprint = Self.fileFingerprint(at: asset.url)
            let key = PadBufferKey(
                padID: pad.id,
                resourceIdentityData: fingerprint.resourceIdentifierData,
                fingerprint: fingerprint
            )
            let operation: LatestWinsPadDecoder.Operation = {
                do {
                    let file = try AVAudioFile(forReading: asset.url)
                    let buffer = try Self.makeLoopingBuffer(from: file)
                    return ImmutablePCMBuffer(buffer: buffer, byteCount: try Self.byteCount(of: buffer))
                } catch let error as PadMemoryError {
                    throw error
                } catch {
                    throw AudioEngineError.unreadablePadFile(asset.url)
                }
            }
            submitPadDecode(
                pad: pad,
                generation: generation,
                token: token,
                key: key,
                operation: operation,
                completion: completion
            )
        case let .external(reference):
            let referencer = externalAudioReferencer
            Task { [weak self] in
                do {
                    // Validate and re-stat before consulting the PCM store. A file replaced at
                    // the same path can therefore never hit an entry keyed by stale metadata.
                    let current = try await referencer.refreshedReference(reference)
                    guard current.fingerprint == reference.fingerprint else {
                        throw ExternalAudioReferenceError.changed
                    }
                    guard let self, generation == self.preparationGeneration else {
                        throw CancellationError()
                    }
                    let key = PadBufferKey(
                        padID: pad.id,
                        resourceIdentityData: current.fingerprint.resourceIdentifierData,
                        fingerprint: current.fingerprint
                    )
                    let operation: LatestWinsPadDecoder.Operation = {
                        try await referencer.withCoordinatedRead(of: current) { url in
                            do {
                                let validated = try AVFoundationExternalAudioValidator().validate(url)
                                guard validated.fingerprint == current.fingerprint else {
                                    throw ExternalAudioReferenceError.changed
                                }
                                let file = try AVAudioFile(forReading: url)
                                let buffer = try Self.makeLoopingBuffer(from: file)
                                return ImmutablePCMBuffer(buffer: buffer, byteCount: try Self.byteCount(of: buffer))
                            } catch let error as ExternalAudioReferenceError {
                                throw error
                            } catch let error as PadMemoryError {
                                throw error
                            } catch {
                                throw AudioEngineError.unreadablePadFile(url)
                            }
                        }
                    }
                    self.submitPadDecode(
                        pad: pad,
                        generation: generation,
                        token: token,
                        key: key,
                        operation: operation,
                        completion: completion
                    )
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func submitPadDecode(
        pad: PadTrack,
        generation: UInt64,
        token: UUID,
        key: PadBufferKey,
        operation: @escaping LatestWinsPadDecoder.Operation,
        completion: @escaping @MainActor @Sendable (Result<PreparedPad, Error>) -> Void
    ) {
        if let pcm = padMemoryStore.retainedBuffer(for: key) {
            let prepared = PreparedPad(
                padID: pad.id,
                displayName: pad.label,
                generation: generation,
                token: token,
                key: key,
                pcm: pcm
            )
            preparedKeysByToken[token] = key
            completion(.success(prepared))
            return
        }

        latestWinsDecoder.submit(key: key, operation: operation) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                guard generation == self.preparationGeneration else {
                    completion(.failure(CancellationError()))
                    return
                }
                do {
                    let pcm = try result.get()
                    try self.padMemoryStore.admitAndRetain(pcm, for: key)
                    let prepared = PreparedPad(
                        padID: pad.id,
                        displayName: pad.label,
                        generation: generation,
                        token: token,
                        key: key,
                        pcm: pcm
                    )
                    self.preparedKeysByToken[token] = key
                    completion(.success(prepared))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    @discardableResult func activatePad(_ prepared: PreparedPad) -> Bool {
        guard prepared.generation == preparationGeneration,
              preparedKeysByToken.removeValue(forKey: prepared.token) != nil else {
            discardPreparedPad(prepared)
            return false
        }
        if activePadTrackID == prepared.padID, activePadMemoryKey == prepared.key {
            padMemoryStore.release(prepared.key)
            return true
        }

        let oldMemoryKey = activePadMemoryKey
        commitPad(
            buffer: prepared.pcm.buffer,
            key: nil,
            assetDisplayName: prepared.displayName
        )
        activePadTrackID = prepared.padID
        activePadMemoryKey = prepared.key
        if let oldMemoryKey, oldMemoryKey != prepared.key {
            Task { @MainActor [padMemoryStore] in
                try? await Task.sleep(for: .seconds(1.25))
                padMemoryStore.release(oldMemoryKey)
            }
        }
        return true
    }

    func discardPreparedPad(_ prepared: PreparedPad) {
        guard preparedKeysByToken.removeValue(forKey: prepared.token) != nil else { return }
        padMemoryStore.release(prepared.key)
    }

    func cancelPendingPadPreparation() {
        preparationGeneration &+= 1
        latestWinsDecoder.cancelPending()
        for key in preparedKeysByToken.values { padMemoryStore.release(key) }
        preparedKeysByToken.removeAll()
    }

    func prepareClick(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision,
        includesCountoff: Bool,
        settings: ClickSettings,
        completion: @escaping @MainActor @Sendable (Result<PreparedClick, Error>) -> Void
    ) {
        prepareClick(bpm: bpm, timeSignature: timeSignature, subdivision: subdivision,
                     pulseInterpretation: .legacy, accentPattern: nil,
                     countoffPolicy: CountoffPolicy(bars: includesCountoff ? 1 : 0, after: .continueClick),
                     settings: settings, completion: completion)
    }

    func prepareClick(
        bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision,
        pulseInterpretation: PulseInterpretation, accentPattern: [ClickAccentLevel]?,
        countoffPolicy: CountoffPolicy, settings: ClickSettings,
        completion: @escaping @MainActor @Sendable (Result<PreparedClick, Error>) -> Void
    ) {
        guard bpm > 0 else {
            completion(.failure(AudioEngineError.invalidBPM(bpm)))
            return
        }
        do { try startClickEngineIfNeeded() } catch {
            completion(.failure(error))
            return
        }
        let format = clickFormat
        nonisolated(unsafe) let renderer = voiceRenderer
        Task.detached(priority: .userInitiated) {
            do {
                let loop = try Self.makeClickBuffer(
                    format: format,
                    bpm: bpm,
                    timeSignature: timeSignature,
                    subdivision: subdivision,
                    measures: 1,
                    settings: settings,
                    pulseInterpretation: pulseInterpretation,
                    accentPattern: accentPattern
                )
                let countoff = countoffPolicy.hasCountoff
                    ? try Self.makeCountoffBuffer(
                        format: format,
                        voiceRenderer: renderer,
                        bpm: bpm,
                        timeSignature: timeSignature,
                        subdivision: subdivision,
                        settings: settings,
                        pulseInterpretation: pulseInterpretation,
                        accentPattern: accentPattern,
                        measures: countoffPolicy.bars
                    )
                    : nil
                let prepared = PreparedClick(
                    loop: ImmutablePCMBuffer(buffer: loop, byteCount: try Self.byteCount(of: loop)),
                    countoff: try countoff.map {
                        ImmutablePCMBuffer(buffer: $0, byteCount: try Self.byteCount(of: $0))
                    },
                    stopsAfterCountoff: countoffPolicy.after == .countoffOnly
                )
                await completion(.success(prepared))
            } catch {
                await completion(.failure(error))
            }
        }
    }

    func activateClick(_ prepared: PreparedClick) throws {
        clickSwitchTask?.cancel()
        if clickIsActive {
            // stop() drains the source callback before a slot can be reused by a full restart.
            clickEngine.stop()
            clickRenderer.stop()
            clickIsActive = false
        }
        clickMixer.pan = clickOutputChannel.pan
        activeCountoffGeneration = try clickRenderer.start(prepared, stopsAfterCountoff: prepared.stopsAfterCountoff)
        activeClickStopsAfterCountoff = prepared.stopsAfterCountoff
        try startClickEngineIfNeeded()
        clickIsActive = true
    }

    func scheduleClickChange(
        _ prepared: PreparedClick,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    ) {
        guard clickIsActive else {
            completion(.failure(AudioEngineError.invalidOutputFormat))
            return
        }
        clickSwitchSerial &+= 1
        let serial = clickSwitchSerial
        do {
            try clickRenderer.queue(prepared, serial: serial)
        } catch {
            completion(.failure(error))
            return
        }
        clickSwitchTask?.cancel()
        clickSwitchTask = Task { @MainActor in
            while !Task.isCancelled && clickIsActive && clickRenderer.lastAppliedSerial < serial {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard !Task.isCancelled, clickIsActive else { return }
            completion(.success(()))
        }
    }

    func cancelScheduledClickChange() {
        clickSwitchTask?.cancel()
        clickRenderer.cancelPending()
    }

    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String {
        if let asset = padAssetResolver.asset(for: padPack, key: key) {
            return "Found \(asset.displayName)"
        }

        if padPack.isBundled {
            return "Missing included pad \(key.rawValue).mp3"
        }

        return "\(padPack.name) does not include a pad for \(key.rawValue)."
    }

    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool {
        padAssetResolver.asset(for: padPack, key: key) != nil
    }

    /// Decodes the cued pad ahead of time on a background queue so pressing Start does
    /// not stall the main thread on a multi-MB file read/decode.
    func preloadPad(for key: MusicalKey, padPack: PadPack) {
        guard let asset = padAssetResolver.asset(for: padPack, key: key) else { return }
        guard !padBufferCache.contains(asset.url) else { return }

        let cache = padBufferCache
        padDecodeQueue.async {
            guard let file = try? AVAudioFile(forReading: asset.url),
                  let buffer = try? Self.makeLoopingBuffer(from: file) else { return }
            cache.store(buffer, for: asset.url)
        }
    }

    func startPad(for key: MusicalKey, padPack: PadPack) throws {
        guard let asset = padAssetResolver.asset(for: padPack, key: key) else {
            throw AudioEngineError.missingPadFile(pack: padPack.name, key: key)
        }

        try startPadEngineIfNeeded()

        padStartGeneration &+= 1
        let generation = padStartGeneration

        // Fast path: the pad was preloaded on cue, so scheduling is immediate.
        if let buffer = padBufferCache.buffer(for: asset.url) {
            commitPad(buffer: buffer, key: key, assetDisplayName: asset.displayName)
            return
        }

        // Cache miss (e.g. cue-then-immediate-start beat the preload). Decode OFF the main
        // thread so pressing Start never stalls the UI on a multi-MB file read, then commit
        // when ready — unless a later start/stop has superseded this one.
        let cache = padBufferCache
        let queue = padDecodeQueue
        let url = asset.url
        let displayName = asset.displayName
        Task { @MainActor [weak self] in
            guard let buffer = try? await Self.decodePadBuffer(at: url, cache: cache, queue: queue) else { return }
            guard let self, self.padStartGeneration == generation else { return }
            self.commitPad(buffer: buffer, key: key, assetDisplayName: displayName)
        }
    }

    /// Schedules an already-decoded pad buffer on a free player and crossfades from the
    /// previous one. Pure main-actor work — no file IO — so it's cheap and instant.
    private func commitPad(buffer: AVAudioPCMBuffer, key: MusicalKey?, assetDisplayName: String?) {
        let newIndex = nextPadIndex
        nextPadIndex = (nextPadIndex + 1) % padPlayers.count

        let player = padPlayers[newIndex]
        let mixer = padMixers[newIndex]
        let oldIndex = activePadIndex

        cancelPadTasks(at: newIndex)
        padGenerations[newIndex] += 1
        player.stop()
        player.pan = padOutputChannel.pan
        mixer.outputVolume = 0
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()

        fade(mixer: mixer, at: newIndex, to: padVolume, duration: 1.25)

        if let oldIndex, oldIndex != newIndex {
            let oldPlayer = padPlayers[oldIndex]
            let oldMixer = padMixers[oldIndex]
            let generation = nextPadGeneration(at: oldIndex)
            fade(mixer: oldMixer, at: oldIndex, to: 0, duration: 1.25)
            scheduleStop(player: oldPlayer, at: oldIndex, generation: generation, after: 1.25)
        }

        activePadIndex = newIndex
        activePadKey = key
        activePadAssetName = assetDisplayName
    }

    func stopPad() {
        padStartGeneration &+= 1  // supersede any pending off-main decode
        guard let activePadIndex else { return }

        let player = padPlayers[activePadIndex]
        let mixer = padMixers[activePadIndex]
        let generation = nextPadGeneration(at: activePadIndex)
        fade(mixer: mixer, at: activePadIndex, to: 0, duration: 1.0)
        scheduleStop(player: player, at: activePadIndex, generation: generation, after: 1.0)

        self.activePadIndex = nil
        activePadKey = nil
        activePadTrackID = nil
        activePadAssetName = nil
        if let activePadMemoryKey {
            Task { @MainActor [padMemoryStore] in
                try? await Task.sleep(for: .seconds(1))
                padMemoryStore.release(activePadMemoryKey)
            }
        }
        activePadMemoryKey = nil
    }

    func startClick(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision = .beat,
        includesCountoff: Bool = true,
        settings: ClickSettings = .default
    ) throws {
        try startClick(bpm: bpm, timeSignature: timeSignature, subdivision: subdivision,
                       pulseInterpretation: .legacy, accentPattern: nil,
                       countoffPolicy: CountoffPolicy(bars: includesCountoff ? 1 : 0, after: .continueClick),
                       settings: settings)
    }

    func startClick(
        bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision,
        pulseInterpretation: PulseInterpretation, accentPattern: [ClickAccentLevel]?,
        countoffPolicy: CountoffPolicy, settings: ClickSettings
    ) throws {
        guard bpm > 0 else {
            throw AudioEngineError.invalidBPM(bpm)
        }

        // Build every replacement buffer before touching a currently running click. A live
        // BPM/time-signature edit can then fail safely without silencing the old loop.
        let loop = try makeClickBuffer(bpm: bpm, timeSignature: timeSignature, subdivision: subdivision,
                                       measures: 1, settings: settings,
                                       pulseInterpretation: pulseInterpretation, accentPattern: accentPattern)
        let countoff = countoffPolicy.hasCountoff
            ? try makeCountoffBuffer(bpm: bpm, timeSignature: timeSignature, subdivision: subdivision,
                                     settings: settings, pulseInterpretation: pulseInterpretation,
                                     accentPattern: accentPattern, measures: countoffPolicy.bars)
            : nil

        let prepared = PreparedClick(
            loop: ImmutablePCMBuffer(buffer: loop, byteCount: try Self.byteCount(of: loop)),
            countoff: try countoff.map { ImmutablePCMBuffer(buffer: $0, byteCount: try Self.byteCount(of: $0)) },
            stopsAfterCountoff: countoffPolicy.after == .countoffOnly
        )
        clickSwitchTask?.cancel()
        if clickIsActive {
            clickEngine.stop()
            clickRenderer.stop()
            clickIsActive = false
        }
        activeCountoffGeneration = try clickRenderer.start(prepared, stopsAfterCountoff: prepared.stopsAfterCountoff)
        activeClickStopsAfterCountoff = prepared.stopsAfterCountoff
        try startClickEngineIfNeeded()
        clickMixer.pan = clickOutputChannel.pan
        clickIsActive = true
    }

    func stopClick() {
        clickSwitchTask?.cancel()
        clickRenderer.stop()
        clickEngine.stop()
        clickIsActive = false
        activeCountoffGeneration = 0
        activeClickStopsAfterCountoff = false
    }

    func setPadVolume(_ volume: Double) {
        padVolume = clampedVolume(volume)
        if let activePadIndex {
            padFadeTasks[activePadIndex]?.cancel()
            padFadeTasks[activePadIndex] = nil
            padMixers[activePadIndex].outputVolume = padVolume
        }
    }

    func setClickVolume(_ volume: Double) {
        clickVolume = clampedVolume(volume)
        clickMixer.outputVolume = clickVolume
    }

    func stopAll() {
        stopClick()
        stopPadsImmediately()
    }

    func handleMemoryPressure() {
        padMemoryStore.evictInactive()
    }

    private func startPadEngineIfNeeded() throws {
        if !padEngine.isRunning {
            try padEngine.start()
        }
    }

    private func startClickEngineIfNeeded() throws {
        if !clickEngine.isRunning {
            try clickEngine.start()
        }
    }

    private func setOutputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
        guard let outputAudioUnit = engine.outputNode.audioUnit else {
            throw AudioEngineError.invalidOutputFormat
        }
        var deviceID = deviceID
        let status = AudioUnitSetProperty(
            outputAudioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            throw AudioEngineError.outputDeviceAssignmentFailed(deviceID: deviceID, status: status)
        }
    }

    private func applyOutputChannelRouting() {
        for player in padPlayers {
            player.pan = padOutputChannel.pan
        }
        clickMixer.pan = clickOutputChannel.pan
    }

    private func fade(mixer: AVAudioMixerNode, at index: Int, to target: Float, duration: TimeInterval) {
        padFadeTasks[index]?.cancel()
        let start = mixer.outputVolume
        // ~120 Hz stepping: fine enough that the linear volume ramp is inaudible as steps even
        // under main-thread load (the old 24 steps ≈ 19 Hz could zipper). Still a timed ramp,
        // not a sample-accurate AU parameter automation — good enough for a 1s pad crossfade.
        let steps = max(2, Int((duration * 120).rounded()))
        let delay = UInt64(duration / Double(steps) * 1_000_000_000)

        padFadeTasks[index] = Task { @MainActor in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                mixer.outputVolume = start + (target - start) * progress
            }
        }
    }

    private func scheduleStop(
        player: AVAudioPlayerNode,
        at index: Int,
        generation: Int,
        after duration: TimeInterval
    ) {
        padStopTasks[index]?.cancel()
        padStopTasks[index] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, padGenerations[index] == generation else { return }
            player.stop()
        }
    }

    private func nextPadGeneration(at index: Int) -> Int {
        cancelPadTasks(at: index)
        padGenerations[index] += 1
        return padGenerations[index]
    }

    private func cancelPadTasks(at index: Int) {
        padFadeTasks[index]?.cancel()
        padStopTasks[index]?.cancel()
        padFadeTasks[index] = nil
        padStopTasks[index] = nil
    }

    private func clampedVolume(_ volume: Double) -> Float {
        Float(min(1, max(0, volume)))
    }

    private func stopPadsImmediately() {
        for index in padPlayers.indices {
            cancelPadTasks(at: index)
            padGenerations[index] += 1
            padPlayers[index].stop()
            padMixers[index].outputVolume = 0
        }

        activePadIndex = nil
        activePadKey = nil
        activePadTrackID = nil
        activePadAssetName = nil
        if let activePadMemoryKey { padMemoryStore.release(activePadMemoryKey) }
        activePadMemoryKey = nil
        for key in preparedKeysByToken.values { padMemoryStore.release(key) }
        preparedKeysByToken.removeAll()
    }

    private func makeClickBuffer(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision,
        measures: Int,
        settings: ClickSettings,
        pulseInterpretation: PulseInterpretation = .legacy,
        accentPattern: [ClickAccentLevel]? = nil
    ) throws -> AVAudioPCMBuffer {
        try Self.makeClickBuffer(
            format: clickFormat,
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision,
            measures: measures,
            settings: settings,
            pulseInterpretation: pulseInterpretation,
            accentPattern: accentPattern
        )
    }

    nonisolated static func makeClickBuffer(
        format: AVAudioFormat,
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision,
        measures: Int,
        settings: ClickSettings,
        pulseInterpretation: PulseInterpretation = .legacy,
        accentPattern: [ClickAccentLevel]? = nil
    ) throws -> AVAudioPCMBuffer {
        guard bpm > 0 else { throw AudioEngineError.invalidBPM(bpm) }
        let grid = ClickPulseGrid(timeSignature: timeSignature, pulseInterpretation: pulseInterpretation,
                                  bpm: bpm, sampleRate: format.sampleRate)
        guard accentPattern == nil || accentPattern?.count == grid.pulseCount else {
            throw AudioEngineError.invalidOutputFormat
        }
        let beats = grid.pulseCount * max(1, measures)
        let frameCount = AVAudioFrameCount(grid.frameCount(measures: measures))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioEngineError.invalidOutputFormat
        }
        buffer.frameLength = frameCount
        zeroBuffer(buffer, format: format)

        for beat in 0..<beats {
            let level = accentPattern?[beat % grid.pulseCount]
            if level == .mute { continue }
            let startFrame = grid.frame(forPulse: beat)
            let accented = level == .strong || (level == nil && settings.accentMode == .downbeat && beat % grid.pulseCount == 0)
            let gain: Float = level == .soft ? 0.45 : 1
            writeClickTone(into: buffer, format: format, startFrame: startFrame, accented: accented, gain: gain)
            if subdivision != .beat {
                for slot in 1..<subdivision.rawValue {
                    writeClickTone(
                        into: buffer,
                        format: format,
                        startFrame: grid.frame(forPulse: beat, subdivision: slot,
                                               subdivisionsPerPulse: subdivision.rawValue),
                        accented: false,
                        gain: 0.48 * gain
                    )
                }
            }
        }

        return buffer
    }

    nonisolated private static func writeClickTone(
        into buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        startFrame: Int,
        accented: Bool,
        gain: Float = 1
    ) {
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let clickLength = Int(sampleRate * 0.045)
        let frequency = accented ? 1_760.0 : 1_200.0
        let amplitude = Float(accented ? 0.78 : 0.48) * gain

        for offset in 0..<clickLength {
            let frame = startFrame + offset
            guard frame < frameCount else { break }

            let t = Double(offset) / sampleRate
            let envelope = exp(-55.0 * t)
            let sample = Float(sin(2.0 * .pi * frequency * t) * envelope) * amplitude

            for channel in 0..<channelCount {
                buffer.floatChannelData?[channel][frame] += sample
            }
        }
    }

    private func makeCountoffBuffer(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision,
        settings: ClickSettings,
        pulseInterpretation: PulseInterpretation = .legacy,
        accentPattern: [ClickAccentLevel]? = nil,
        measures: Int = 1
    ) throws -> AVAudioPCMBuffer {
        try Self.makeCountoffBuffer(
            format: clickFormat,
            voiceRenderer: voiceRenderer,
            bpm: bpm,
            timeSignature: timeSignature,
            subdivision: subdivision,
            settings: settings,
            pulseInterpretation: pulseInterpretation,
            accentPattern: accentPattern,
            measures: measures
        )
    }

    /// Pure PCM composition entry point for regression tests. It deliberately does not create
    /// AVAudioEngine/player nodes, so count-in behavior can be checked in headless test runners.
    nonisolated static func makeCountoffBuffer(
        format: AVAudioFormat,
        voiceRenderer: CountoffVoiceRendering?,
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision = .beat,
        settings: ClickSettings,
        pulseInterpretation: PulseInterpretation = .legacy,
        accentPattern: [ClickAccentLevel]? = nil,
        measures: Int = 1
    ) throws -> AVAudioPCMBuffer {
        guard bpm > 0 else { throw AudioEngineError.invalidBPM(bpm) }
        let grid = ClickPulseGrid(timeSignature: timeSignature, pulseInterpretation: pulseInterpretation,
                                  bpm: bpm, sampleRate: format.sampleRate)
        guard accentPattern == nil || accentPattern?.count == grid.pulseCount else {
            throw AudioEngineError.invalidOutputFormat
        }
        if settings.countoffSound == .click {
            return try makeClickBuffer(
                format: format,
                bpm: bpm,
                timeSignature: timeSignature,
                subdivision: subdivision,
                measures: measures,
                settings: settings,
                pulseInterpretation: pulseInterpretation,
                accentPattern: accentPattern
            )
        }

        let sampleRate = format.sampleRate
        let beats = grid.pulseCount * max(1, measures)
        let secondsPerBeat = grid.secondsPerPulse

        // At fast tempos a spoken word cannot stay intelligible within a beat, so fall
        // back to the click count-off rather than a garbled voice.
        guard secondsPerBeat >= minSpokenBeatDuration else {
            return try makeClickBuffer(
                format: format,
                bpm: bpm,
                timeSignature: timeSignature,
                subdivision: subdivision,
                measures: measures,
                settings: settings,
                pulseInterpretation: pulseInterpretation,
                accentPattern: accentPattern
            )
        }

        let frameCount = AVAudioFrameCount(grid.frameCount(measures: measures))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioEngineError.invalidOutputFormat
        }
        buffer.frameLength = frameCount
        zeroBuffer(buffer, format: format)

        let slotFrames = Int(secondsPerBeat * sampleRate)
        for beat in 0..<beats {
            let startFrame = grid.frame(forPulse: beat)
            let level = accentPattern?[beat % grid.pulseCount]
            let accented = level == .strong || (level == nil && settings.accentMode == .downbeat && beat % grid.pulseCount == 0)

            // The counted mode is deliberately click + voice. Put a quieter transient exactly
            // on the beat, then mix the already-rendered word into the same slot. This leaves
            // voice choice, prewarming, routing, scheduling, and fallback behavior untouched.
            // Speech is rendered at 0.8 gain; a 0.2 click gain keeps even the accented
            // transient below full-scale when the two overlap, without changing voice level.
            if level != .mute {
                writeClickTone(
                    into: buffer,
                    format: format,
                    startFrame: startFrame,
                    accented: accented,
                    gain: level == .soft ? 0.09 : 0.2
                )
            }

            if let word = voiceRenderer?.renderedWord(for: beat % grid.pulseCount + 1, format: format) {
                copyWord(word, into: buffer, format: format, at: startFrame, maxFrames: slotFrames)
            }
        }

        return buffer
    }

    nonisolated private static func copyWord(
        _ word: AVAudioPCMBuffer,
        into buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        at startFrame: Int,
        maxFrames: Int
    ) {
        guard let source = word.floatChannelData, let destination = buffer.floatChannelData else { return }

        let channelCount = Int(format.channelCount)
        let sourceChannelCount = max(1, Int(word.format.channelCount))
        let bufferFrames = Int(buffer.frameLength)
        let available = min(maxFrames, bufferFrames - startFrame)
        let copyCount = min(Int(word.frameLength), available)
        guard copyCount > 0 else { return }

        // Short fade at the trim boundary so a word cut off at the beat edge doesn't pop.
        let fadeFrames = min(copyCount, Int(format.sampleRate * 0.008))
        for offset in 0..<copyCount {
            var envelope: Float = 1
            if fadeFrames > 0, offset > copyCount - fadeFrames {
                envelope = Float(copyCount - offset) / Float(fadeFrames)
            }

            let frame = startFrame + offset
            for channel in 0..<channelCount {
                let sourceChannel = min(channel, sourceChannelCount - 1)
                destination[channel][frame] += source[sourceChannel][offset] * envelope
            }
        }
    }

    nonisolated private static func zeroBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(format.channelCount) {
            channels[channel].update(repeating: 0, count: frames)
        }
    }

    /// Returns a cached pad buffer immediately, or decodes it on `queue` (off the main thread)
    /// and caches it. `nonisolated` + static so the decode never touches the main actor.
    private nonisolated static func decodePadBuffer(
        at url: URL,
        cache: PadBufferCache,
        queue: DispatchQueue
    ) async throws -> AVAudioPCMBuffer {
        if let cached = cache.buffer(for: url) {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let file = try AVAudioFile(forReading: url)
                    let buffer = try makeLoopingBuffer(from: file)
                    cache.store(buffer, for: url)
                    continuation.resume(returning: buffer)
                } catch {
                    continuation.resume(throwing: AudioEngineError.unreadablePadFile(url))
                }
            }
        }
    }

    nonisolated static func byteCount(of buffer: AVAudioPCMBuffer) throws -> UInt64 {
        try AVFoundationExternalAudioValidator.decodedByteCount(
            frameCount: AVAudioFramePosition(buffer.frameLength),
            channelCount: buffer.format.channelCount,
            bytesPerFrame: buffer.format.streamDescription.pointee.mBytesPerFrame,
            isInterleaved: buffer.format.isInterleaved
        )
    }

    nonisolated static func fileFingerprint(at url: URL) -> ExternalFileFingerprint {
        let values = try? url.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let identity = values?.fileResourceIdentifier.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        return ExternalFileFingerprint(
            resourceIdentifierData: identity,
            fileSize: values?.fileSize.map(Int64.init),
            modificationDate: values?.contentModificationDate
        )
    }

    /// Reads a file fully into a PCM buffer. `nonisolated` so it can run on the pad
    /// decode queue as well as the main actor.
    nonisolated static func makeLoopingBuffer(from file: AVAudioFile) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioEngineError.unreadablePadFile(file.url)
        }

        try file.read(into: buffer)
        return buffer
    }
}

/// Bounded, thread-safe LRU cache of decoded pad buffers keyed by file URL.
///
/// Concurrency contract (the load-bearing invariant behind `@unchecked Sendable`): a buffer is
/// produced once on the decode queue, then only ever READ — never mutated — afterwards. It is
/// shared across the main actor and both crossfade player nodes concurrently, which is safe
/// precisely because the PCM data is immutable after `store`. Do not add consumer-side buffer
/// mutation (gain, trimming) without rethinking this. The `NSLock` guards only the dictionary
/// and LRU list, not the buffers.
///
/// Eviction matters for a long service: decoded pad buffers are large (a multi-minute stereo
/// pad ≈ 100 MB), so an unbounded cache could accumulate >1 GB. A buffer scheduled on a player
/// node is retained by that node, so evicting it here never interrupts playback.
private final class PadBufferCache: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [URL: AVAudioPCMBuffer] = [:]
    private var lru: [URL] = []  // least-recently-used first
    private let capacity: Int

    init(capacity: Int = 4) {
        self.capacity = capacity
    }

    func buffer(for url: URL) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = buffers[url] else { return nil }
        touch(url)
        return buffer
    }

    func contains(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffers[url] != nil
    }

    func store(_ buffer: AVAudioPCMBuffer, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        buffers[url] = buffer
        touch(url)
        while lru.count > capacity, let evicted = lru.first {
            lru.removeFirst()
            buffers[evicted] = nil
        }
    }

    /// Mark `url` most-recently-used. Caller must hold `lock`.
    private func touch(_ url: URL) {
        if let index = lru.firstIndex(of: url) {
            lru.remove(at: index)
        }
        lru.append(url)
    }
}

@MainActor
final class SilentAudioEngine: AudioControlling {
    private var padIsActive = false
    private var clickIsActive = false
    var isEngineRunning: Bool { padIsActive || clickIsActive }
    var statusSummary: String { isEngineRunning ? "Running" : "Stopped" }

    func prepare() {}

    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws {}

    func padAssetState(for pad: PadTrack) -> PadAssetState {
        .available(PadAudioMetadata(duration: 1, channelCount: 2, sampleRate: 44_100, decodedByteCount: 8))
    }

    func preparePad(
        _ pad: PadTrack,
        completion: @escaping @MainActor @Sendable (Result<PreparedPad, Error>) -> Void
    ) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        let fingerprint = ExternalFileFingerprint(resourceIdentifierData: nil, fileSize: 1, modificationDate: nil)
        let key = PadBufferKey(padID: pad.id, resourceIdentityData: nil, fingerprint: fingerprint)
        completion(.success(PreparedPad(
            padID: pad.id,
            displayName: pad.label,
            generation: 1,
            token: UUID(),
            key: key,
            pcm: ImmutablePCMBuffer(buffer: buffer, byteCount: 8)
        )))
    }

    @discardableResult func activatePad(_ prepared: PreparedPad) -> Bool {
        padIsActive = true
        return true
    }
    func discardPreparedPad(_ prepared: PreparedPad) {}
    func cancelPendingPadPreparation() {}

    func prepareClick(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: ClickSubdivision,
        includesCountoff: Bool,
        settings: ClickSettings,
        completion: @escaping @MainActor @Sendable (Result<PreparedClick, Error>) -> Void
    ) {
        guard bpm > 0 else {
            completion(.failure(AudioEngineError.invalidBPM(bpm)))
            return
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        let pcm = ImmutablePCMBuffer(buffer: buffer, byteCount: 8)
        completion(.success(PreparedClick(loop: pcm, countoff: includesCountoff ? pcm : nil)))
    }

    func activateClick(_ prepared: PreparedClick) throws { clickIsActive = true }
    func scheduleClickChange(
        _ prepared: PreparedClick,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    ) { completion(.success(())) }
    func cancelScheduledClickChange() {}
    func handleMemoryPressure() {}

    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String {
        "Found \(key.rawValue).mp3"
    }

    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool {
        true
    }

    func startPad(for key: MusicalKey, padPack: PadPack) throws {
        padIsActive = true
    }

    func stopPad() {
        padIsActive = false
    }

    func startClick(bpm: Int, timeSignature: TimeSignature, subdivision: ClickSubdivision, includesCountoff: Bool, settings: ClickSettings) throws {
        guard bpm > 0 else {
            throw AudioEngineError.invalidBPM(bpm)
        }
        clickIsActive = true
    }

    func stopClick() {
        clickIsActive = false
    }

    func setPadVolume(_ volume: Double) {}

    func setClickVolume(_ volume: Double) {}

    func stopAll() {
        padIsActive = false
        clickIsActive = false
    }
}
