import AVFoundation

/// Renders spoken count-off numbers ("one", "two", …) into PCM buffers that match
/// the click engine's audio format, so a real voice count-off can be scheduled on the
/// click player node — sample-accurate, routed through the selected click output, and
/// governed by the click volume. Buffers are cached because only 1…12 are ever needed.
protocol CountoffVoiceRendering: AnyObject {
    /// Returns the cached spoken word for `number` in `format`, or `nil` if it has not
    /// been rendered yet (or speech synthesis is unavailable). This is a non-blocking
    /// cache lookup safe to call on the main thread while building a count-off buffer.
    func renderedWord(for number: Int, format: AVAudioFormat) -> AVAudioPCMBuffer?

    /// Renders `numbers` on a background queue and stores them in the cache. Must be
    /// called ahead of time (app launch / when a song is cued): `AVSpeechSynthesizer`
    /// delivers its buffers on the main run loop, so synthesis has to happen off-main
    /// while the main run loop stays free to deliver those callbacks.
    func prewarm(numbers: [Int], format: AVAudioFormat)
}

final class SpeechCountoffVoiceRenderer: CountoffVoiceRendering, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private let gain: Float
    private let renderQueue = DispatchQueue(label: "com.sustain.countoff-voice")
    private let lock = NSLock()
    private var cache: [Int: AVAudioPCMBuffer] = [:]
    private var cacheFormatKey: String?

    init(voice: AVSpeechSynthesisVoice? = SpeechCountoffVoiceRenderer.preferredVoice(), gain: Float = 0.8) {
        self.voice = voice
        self.gain = gain
    }

    /// Highest-quality installed English voice, biased toward well-known clear voices,
    /// falling back to any en-US voice.
    static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        let preferredNames = ["Ava", "Samantha", "Alex", "Evan", "Zoe", "Allison"]

        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            var score: Int
            switch voice.quality {
            case .premium: score = 300
            case .enhanced: score = 200
            default: score = 100
            }
            if voice.language == "en-US" { score += 50 }
            if let index = preferredNames.firstIndex(where: { voice.name.localizedCaseInsensitiveContains($0) }) {
                score += (preferredNames.count - index) * 5
            }
            return score
        }

        return englishVoices.max { rank($0) < rank($1) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func renderedWord(for number: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let formatKey = Self.formatKey(for: format)
        lock.lock()
        defer { lock.unlock() }
        guard cacheFormatKey == formatKey else { return nil }
        return cache[number]
    }

    func prewarm(numbers: [Int], format: AVAudioFormat) {
        renderQueue.async { [weak self] in
            guard let self else { return }
            let formatKey = Self.formatKey(for: format)

            self.lock.lock()
            if self.cacheFormatKey != formatKey {
                self.cache.removeAll()
                self.cacheFormatKey = formatKey
            }
            self.lock.unlock()

            for number in numbers {
                self.lock.lock()
                let alreadyCached = self.cache[number] != nil
                self.lock.unlock()
                if alreadyCached { continue }

                guard let word = Self.word(for: number),
                      let rendered = self.render(word: word, to: format) else {
                    continue
                }

                self.lock.lock()
                self.cache[number] = rendered
                self.lock.unlock()
            }
        }
    }

    /// Renders a word to PCM via `AVSpeechSynthesizer.write` and converts it to `target`.
    /// MUST run off the main thread: `write` delivers its buffers on the main run loop,
    /// so blocking here on a background queue lets those callbacks be delivered while we
    /// wait. Called only from `prewarm` (never inline from a count-off build).
    private func render(word: String, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        let utterance = AVSpeechUtterance(string: word)
        if let voice {
            utterance.voice = voice
        }

        let accumulator = RenderAccumulator()
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                accumulator.complete()
                return
            }
            accumulator.append(pcm)
        }

        if accumulator.finished.wait(timeout: .now() + 5) == .timedOut {
            return nil
        }

        let pieces = accumulator.collected
        guard let sourceFormat = pieces.first?.format else { return nil }
        return convert(pieces: pieces, from: sourceFormat, to: target)
    }

    private func convert(
        pieces: [AVAudioPCMBuffer],
        from sourceFormat: AVAudioFormat,
        to target: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else { return nil }

        let totalSourceFrames = pieces.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard totalSourceFrames > 0 else { return nil }

        let ratio = target.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(totalSourceFrames) * ratio) + 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        // The input block is invoked synchronously on this thread during `convert`,
        // so the mutable cursor is not actually shared across concurrent execution.
        nonisolated(unsafe) var index = 0
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, statusPointer in
            if index < pieces.count {
                let next = pieces[index]
                index += 1
                statusPointer.pointee = .haveData
                return next
            }
            statusPointer.pointee = .endOfStream
            return nil
        }

        guard status != .error, output.frameLength > 0 else { return nil }

        if gain != 1, let channels = output.floatChannelData {
            for channel in 0..<Int(target.channelCount) {
                for frame in 0..<Int(output.frameLength) {
                    channels[channel][frame] *= gain
                }
            }
        }

        return output
    }

    private static func formatKey(for format: AVAudioFormat) -> String {
        "\(format.sampleRate)-\(format.channelCount)"
    }

    static func word(for number: Int) -> String? {
        let words = [
            "one", "two", "three", "four", "five", "six",
            "seven", "eight", "nine", "ten", "eleven", "twelve"
        ]
        guard number >= 1, number <= words.count else { return nil }
        return words[number - 1]
    }
}

/// Collects the PCM buffers `AVSpeechSynthesizer.write` delivers on the main run loop
/// while the renderer waits on a background queue.
private final class RenderAccumulator: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        buffers.append(buffer)
        lock.unlock()
    }

    func complete() {
        finished.signal()
    }

    var collected: [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return buffers
    }
}
