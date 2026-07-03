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
    func startPad(for key: MusicalKey, padPack: PadPack) throws
    func stopPad()
    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool, settings: ClickSettings) throws
    func stopClick()
    func setPadVolume(_ volume: Double)
    func setClickVolume(_ volume: Double)
    func stopAll()
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

    init(padAssetResolver: PadAssetResolving = DefaultPadAssetResolver()) {
        self.padAssetResolver = padAssetResolver

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

    func startPad(for key: MusicalKey, padPack: PadPack) throws {
        guard let asset = padAssetResolver.asset(for: padPack, key: key) else {
            throw AudioEngineError.missingPadFile(pack: padPack.name, key: key)
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: asset.url)
        } catch {
            throw AudioEngineError.unreadablePadFile(asset.url)
        }

        try startPadEngineIfNeeded()

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
        player.scheduleBuffer(try makeLoopingBuffer(from: audioFile), at: nil, options: .loops)
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
        activePadAssetName = asset.displayName
    }

    func stopPad() {
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

        let channelCount = Int(clickFormat.channelCount)
        let clickLength = Int(sampleRate * 0.045)

        for beat in 0..<beats {
            let startFrame = Int(Double(beat) * secondsPerBeat * sampleRate)
            let accented = settings.accentMode == .downbeat && beat % timeSignature.beatsPerMeasure == 0
            let frequency = accented ? 1_760.0 : 1_200.0
            let amplitude = accented ? 0.78 : 0.48

            for offset in 0..<clickLength {
                let frame = startFrame + offset
                guard frame < Int(frameCount) else { break }

                let t = Double(offset) / sampleRate
                let envelope = exp(-55.0 * t)
                let sample = Float(sin(2.0 * .pi * frequency * t) * envelope * amplitude)

                for channel in 0..<channelCount {
                    buffer.floatChannelData?[channel][frame] += sample
                }
            }
        }

        return buffer
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
        let duration = secondsPerBeat * Double(beats)
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: clickFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for beat in 0..<beats {
            addCountSyllable(
                beatNumber: beat + 1,
                startFrame: Int(Double(beat) * secondsPerBeat * sampleRate),
                maxDuration: secondsPerBeat * 0.72,
                to: buffer
            )
        }

        return buffer
    }

    private func addCountSyllable(
        beatNumber: Int,
        startFrame: Int,
        maxDuration: TimeInterval,
        to buffer: AVAudioPCMBuffer
    ) {
        let sampleRate = clickFormat.sampleRate
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(clickFormat.channelCount)
        let duration = min(0.34, max(0.18, maxDuration))
        let syllableLength = Int(sampleRate * duration)
        let profile = countSyllableProfile(for: beatNumber)

        for offset in 0..<syllableLength {
            let frame = startFrame + offset
            guard frame < frameCount else { break }

            let progress = Double(offset) / Double(max(1, syllableLength - 1))
            let t = Double(offset) / sampleRate
            let attack = min(1.0, progress / 0.08)
            let release = min(1.0, (1.0 - progress) / 0.28)
            let envelope = max(0, min(attack, release))
            let pitch = profile.pitchStart + (profile.pitchEnd - profile.pitchStart) * progress
            let vowel = sin(2.0 * .pi * pitch * t)
                + 0.45 * sin(2.0 * .pi * profile.formant * t)
                + 0.18 * sin(2.0 * .pi * profile.formant * 1.72 * t)
            let consonant = offset < Int(sampleRate * 0.045)
                ? sin(2.0 * .pi * profile.consonant * t) * exp(-70.0 * t)
                : 0
            let sample = Float((vowel * 0.28 + consonant * 0.16) * envelope)

            for channel in 0..<channelCount {
                buffer.floatChannelData?[channel][frame] += sample
            }
        }
    }

    private func countSyllableProfile(for beatNumber: Int) -> (
        pitchStart: Double,
        pitchEnd: Double,
        formant: Double,
        consonant: Double
    ) {
        return switch ((beatNumber - 1) % 12) + 1 {
        case 1: (185, 150, 730, 2_100)
        case 2: (178, 142, 920, 1_850)
        case 3: (192, 154, 780, 2_450)
        case 4: (170, 136, 660, 1_650)
        case 5: (184, 147, 700, 2_300)
        case 6: (176, 141, 830, 2_700)
        case 7: (190, 152, 760, 2_150)
        case 8: (168, 134, 880, 2_550)
        case 9: (181, 145, 690, 1_900)
        case 10: (174, 139, 810, 2_050)
        case 11: (188, 150, 740, 2_350)
        default: (172, 138, 860, 2_600)
        }
    }

    private func makeLoopingBuffer(from file: AVAudioFile) throws -> AVAudioPCMBuffer {
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
