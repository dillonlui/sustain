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

    func prepare()
    func configureRouting(_ snapshot: AudioRoutingSnapshot) throws
    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String
    func hasPadAsset(for padPack: PadPack, key: MusicalKey) -> Bool
    func preloadPad(for key: MusicalKey, padPack: PadPack)
    func startPad(for key: MusicalKey, padPack: PadPack) throws
    func stopPad()
    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool, settings: ClickSettings) throws
    func stopClick()
    func setPadVolume(_ volume: Double)
    func setClickVolume(_ volume: Double)
    func stopAll()
}

extension AudioControlling {
    /// Optional: engines that decode real files override this to warm a cache off the
    /// main thread. No-op by default.
    func preloadPad(for key: MusicalKey, padPack: PadPack) {}
}

@MainActor
final class SustainAudioEngine: AudioControlling {
    private let padEngine = AVAudioEngine()
    private let clickEngine = AVAudioEngine()
    private let padPlayers = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let padMixers = [AVAudioMixerNode(), AVAudioMixerNode()]
    private let clickPlayer = AVAudioPlayerNode()
    private let clickMixer = AVAudioMixerNode()
    private let clickFormat: AVAudioFormat
    private let padAssetResolver: PadAssetResolving
    private let voiceRenderer: CountoffVoiceRendering?

    /// Below this beat length a spoken word cannot stay intelligible, so the count-off
    /// falls back to clicks (matching how Ableton only clicks at fast tempos).
    private let minSpokenBeatDuration: TimeInterval = 0.33
    private var activePadIndex: Int?
    private var nextPadIndex = 0
    private var activePadKey: MusicalKey?
    private var activePadAssetName: String?
    private var clickIsActive = false
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
    private let padBufferCache = PadBufferCache()
    private let padDecodeQueue = DispatchQueue(label: "com.sustain.pad-decode", qos: .userInitiated)

    var isEngineRunning: Bool {
        padEngine.isRunning || clickEngine.isRunning
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
        if clickIsActive {
            active.append("Click")
        }

        if active.isEmpty {
            return isEngineRunning ? "Idle (\(routingSummary))" : "Stopped"
        }

        return "\(active.joined(separator: " + ")) (\(routingSummary))"
    }

    init(
        padAssetResolver: PadAssetResolving = DefaultPadAssetResolver(),
        voiceRenderer: CountoffVoiceRendering? = SpeechCountoffVoiceRenderer()
    ) {
        self.padAssetResolver = padAssetResolver
        self.voiceRenderer = voiceRenderer

        let hardwareFormat = clickEngine.outputNode.inputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 44_100
        let channelCount = hardwareFormat.channelCount > 0 ? min(hardwareFormat.channelCount, 2) : 2
        clickFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!

        for index in padPlayers.indices {
            padEngine.attach(padPlayers[index])
            padEngine.attach(padMixers[index])
            padMixers[index].outputVolume = 0
            padEngine.connect(padPlayers[index], to: padMixers[index], format: nil)
            padEngine.connect(padMixers[index], to: padEngine.mainMixerNode, format: nil)
        }

        clickEngine.attach(clickPlayer)
        clickEngine.attach(clickMixer)
        clickMixer.outputVolume = clickVolume
        clickEngine.connect(clickPlayer, to: clickMixer, format: clickFormat)
        clickEngine.connect(clickMixer, to: clickEngine.mainMixerNode, format: clickFormat)

        voiceRenderer?.prewarm(numbers: Array(1...12), format: clickFormat)
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
    private func commitPad(buffer: AVAudioPCMBuffer, key: MusicalKey, assetDisplayName: String?) {
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
        activePadAssetName = nil
    }

    func startClick(
        bpm: Int,
        timeSignature: TimeSignature,
        includesCountoff: Bool = true,
        settings: ClickSettings = .default
    ) throws {
        guard bpm > 0 else {
            throw AudioEngineError.invalidBPM(bpm)
        }

        try startClickEngineIfNeeded()

        clickPlayer.stop()
        clickPlayer.pan = clickOutputChannel.pan
        let loop = makeClickBuffer(bpm: bpm, timeSignature: timeSignature, measures: 1, settings: settings)
        if includesCountoff {
            let countoff = makeCountoffBuffer(bpm: bpm, timeSignature: timeSignature, settings: settings)
            clickPlayer.scheduleBuffer(countoff)
        }
        clickPlayer.scheduleBuffer(loop, at: nil, options: .loops)
        clickPlayer.play()
        clickIsActive = true
    }

    func stopClick() {
        clickPlayer.stop()
        clickIsActive = false
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
        var deviceID = deviceID
        let status = AudioUnitSetProperty(
            engine.outputNode.audioUnit!,
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
        clickPlayer.pan = clickOutputChannel.pan
    }

    private func fade(mixer: AVAudioMixerNode, at index: Int, to target: Float, duration: TimeInterval) {
        padFadeTasks[index]?.cancel()
        let start = mixer.outputVolume
        let steps = 24

        padFadeTasks[index] = Task { @MainActor in
            for step in 1...steps {
                let progress = Float(step) / Float(steps)
                let volume = start + (target - start) * progress
                let delay = UInt64(duration / Double(steps) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                mixer.outputVolume = volume
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
        activePadAssetName = nil
    }

    private func makeClickBuffer(
        bpm: Int,
        timeSignature: TimeSignature,
        measures: Int,
        settings: ClickSettings
    ) -> AVAudioPCMBuffer {
        let sampleRate = clickFormat.sampleRate
        let beats = max(1, timeSignature.beatsPerMeasure * measures)
        let secondsPerBeat = 60.0 / Double(bpm)
        let duration = secondsPerBeat * Double(beats)
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: clickFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for beat in 0..<beats {
            let startFrame = Int(Double(beat) * secondsPerBeat * sampleRate)
            let accented = settings.accentMode == .downbeat && beat % timeSignature.beatsPerMeasure == 0
            writeClickTone(into: buffer, startFrame: startFrame, accented: accented)
        }

        return buffer
    }

    private func writeClickTone(into buffer: AVAudioPCMBuffer, startFrame: Int, accented: Bool) {
        let sampleRate = clickFormat.sampleRate
        let channelCount = Int(clickFormat.channelCount)
        let frameCount = Int(buffer.frameLength)
        let clickLength = Int(sampleRate * 0.045)
        let frequency = accented ? 1_760.0 : 1_200.0
        let amplitude = accented ? 0.78 : 0.48

        for offset in 0..<clickLength {
            let frame = startFrame + offset
            guard frame < frameCount else { break }

            let t = Double(offset) / sampleRate
            let envelope = exp(-55.0 * t)
            let sample = Float(sin(2.0 * .pi * frequency * t) * envelope * amplitude)

            for channel in 0..<channelCount {
                buffer.floatChannelData?[channel][frame] += sample
            }
        }
    }

    private func makeCountoffBuffer(
        bpm: Int,
        timeSignature: TimeSignature,
        settings: ClickSettings
    ) -> AVAudioPCMBuffer {
        if settings.countoffSound == .click {
            return makeClickBuffer(bpm: bpm, timeSignature: timeSignature, measures: 1, settings: settings)
        }

        let sampleRate = clickFormat.sampleRate
        let beats = max(1, timeSignature.beatsPerMeasure)
        let secondsPerBeat = 60.0 / Double(bpm)

        // At fast tempos a spoken word cannot stay intelligible within a beat, so fall
        // back to the click count-off rather than a garbled voice.
        guard secondsPerBeat >= minSpokenBeatDuration else {
            return makeClickBuffer(bpm: bpm, timeSignature: timeSignature, measures: 1, settings: settings)
        }

        let duration = secondsPerBeat * Double(beats)
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: clickFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        zeroBuffer(buffer)

        let slotFrames = Int(secondsPerBeat * sampleRate)
        for beat in 0..<beats {
            let startFrame = Int(Double(beat) * secondsPerBeat * sampleRate)

            if let word = voiceRenderer?.renderedWord(for: beat + 1, format: clickFormat) {
                copyWord(word, into: buffer, at: startFrame, maxFrames: slotFrames)
            } else {
                // Voice unavailable — keep every beat audible with a click.
                let accented = settings.accentMode == .downbeat && beat == 0
                writeClickTone(into: buffer, startFrame: startFrame, accented: accented)
            }
        }

        return buffer
    }

    private func copyWord(
        _ word: AVAudioPCMBuffer,
        into buffer: AVAudioPCMBuffer,
        at startFrame: Int,
        maxFrames: Int
    ) {
        guard let source = word.floatChannelData, let destination = buffer.floatChannelData else { return }

        let channelCount = Int(clickFormat.channelCount)
        let sourceChannelCount = max(1, Int(word.format.channelCount))
        let bufferFrames = Int(buffer.frameLength)
        let available = min(maxFrames, bufferFrames - startFrame)
        let copyCount = min(Int(word.frameLength), available)
        guard copyCount > 0 else { return }

        // Short fade at the trim boundary so a word cut off at the beat edge doesn't pop.
        let fadeFrames = min(copyCount, Int(clickFormat.sampleRate * 0.008))
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

    private func zeroBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(clickFormat.channelCount) {
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

/// Thread-safe cache of decoded pad buffers keyed by file URL. Buffers are immutable
/// once decoded, so sharing them across player nodes and calls is safe.
private final class PadBufferCache: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [URL: AVAudioPCMBuffer] = [:]

    func buffer(for url: URL) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffers[url]
    }

    func contains(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffers[url] != nil
    }

    func store(_ buffer: AVAudioPCMBuffer, for url: URL) {
        lock.lock()
        buffers[url] = buffer
        lock.unlock()
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

    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool, settings: ClickSettings) throws {
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
