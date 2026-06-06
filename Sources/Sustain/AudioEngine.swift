import AVFoundation
import AudioToolbox
import Foundation

enum AudioEngineError: LocalizedError {
    case invalidBPM(Int)
    case invalidOutputFormat
    case missingPadFile(pack: String, key: MusicalKey)
    case unreadablePadFile(URL)

    var errorDescription: String? {
        switch self {
        case .invalidBPM(let bpm):
            "BPM must be greater than zero. Received \(bpm)."
        case .invalidOutputFormat:
            "The system output format is not available."
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
    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool) throws
    func stopClick()
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
    private var routingSummary = "Default output"

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

    init(padAssetResolver: PadAssetResolving = BundlePadAssetResolver()) {
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
        clickMixer.outputVolume = 0.75
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

        routingSummary = snapshot.summary
    }

    func padAssetStatus(for padPack: PadPack, key: MusicalKey) -> String {
        if let asset = padAssetResolver.asset(for: padPack, key: key) {
            return "Found \(asset.displayName)"
        }

        return "Missing bundled pad \(key.rawValue).mp3"
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

        player.stop()
        mixer.outputVolume = 0
        player.scheduleBuffer(try makeLoopingBuffer(from: audioFile), at: nil, options: .loops)
        player.play()

        fade(mixer: mixer, to: 0.42, duration: 1.25)

        if let oldIndex, oldIndex != newIndex {
            let oldPlayer = padPlayers[oldIndex]
            let oldMixer = padMixers[oldIndex]
            fade(mixer: oldMixer, to: 0, duration: 1.25)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_250_000_000)
                oldPlayer.stop()
            }
        }

        activePadIndex = newIndex
        activePadKey = key
        activePadAssetName = asset.displayName
    }

    func stopPad() {
        guard let activePadIndex else { return }

        let player = padPlayers[activePadIndex]
        let mixer = padMixers[activePadIndex]
        fade(mixer: mixer, to: 0, duration: 1.0)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            player.stop()
        }

        self.activePadIndex = nil
        activePadKey = nil
        activePadAssetName = nil
    }

    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool = true) throws {
        guard bpm > 0 else {
            throw AudioEngineError.invalidBPM(bpm)
        }

        try startClickEngineIfNeeded()

        clickPlayer.stop()
        let loop = makeClickBuffer(bpm: bpm, timeSignature: timeSignature, measures: 1)
        if includesCountoff {
            let countoff = makeClickBuffer(bpm: bpm, timeSignature: timeSignature, measures: 1)
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

    func stopAll() {
        stopClick()
        stopPad()
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
            throw AudioEngineError.invalidOutputFormat
        }
    }

    private func fade(mixer: AVAudioMixerNode, to target: Float, duration: TimeInterval) {
        let start = mixer.outputVolume
        let steps = 24

        for step in 1...steps {
            let progress = Float(step) / Float(steps)
            let volume = start + (target - start) * progress
            let delay = UInt64(duration * Double(step) / Double(steps) * 1_000_000_000)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                mixer.outputVolume = volume
            }
        }
    }

    private func makeClickBuffer(
        bpm: Int,
        timeSignature: TimeSignature,
        measures: Int
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
            let accented = beat % timeSignature.beatsPerMeasure == 0
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

    func startClick(bpm: Int, timeSignature: TimeSignature, includesCountoff: Bool) throws {
        guard bpm > 0 else {
            throw AudioEngineError.invalidBPM(bpm)
        }
        clickIsActive = true
    }

    func stopClick() {
        clickIsActive = false
    }

    func stopAll() {
        padIsActive = false
        clickIsActive = false
    }
}
