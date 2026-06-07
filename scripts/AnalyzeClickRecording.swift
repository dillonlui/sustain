#!/usr/bin/env swift

import AVFoundation
import Foundation

struct Options {
    var fileURL: URL?
    var bpm: Double?
    var thresholdRatio = 0.25
    var maxMeanJitterSeconds = 0.015
    var maxWorstJitterSeconds = 0.06
    var maxBPMError = 0.5
}

struct Analysis {
    var duration: Double
    var clickCount: Int
    var observedBPM: Double
    var expectedInterval: Double
    var medianInterval: Double
    var meanAbsoluteJitter: Double
    var worstJitter: Double
    var missingBeats: Int
    var extraBeats: Int
    var passed: Bool
}

enum AnalyzerError: LocalizedError {
    case missingFile
    case missingBPM
    case invalidBPM(String)
    case unreadableAudio(String)
    case noSignal
    case tooFewClicks(Int)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "Missing --file path."
        case .missingBPM:
            return "Missing --bpm value."
        case .invalidBPM(let value):
            return "Invalid BPM: \(value)."
        case .unreadableAudio(let path):
            return "Could not read audio file: \(path)."
        case .noSignal:
            return "No usable signal was detected in the recording."
        case .tooFewClicks(let count):
            return "Detected only \(count) clicks. Record a longer isolated click track."
        }
    }
}

func parseOptions() throws -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())

    if args.contains("--help") || args.contains("-h") {
        print("""
        Usage:
          swift scripts/AnalyzeClickRecording.swift --file recording.wav --bpm 72

        Options:
          --file PATH              Recording to analyze. WAV, AIFF, M4A, and other AVFoundation-readable files are supported.
          --bpm BPM                Expected click BPM.
          --threshold-ratio VALUE  Peak threshold as a ratio of max amplitude. Default: 0.25.

        Best results come from recording the click output alone, without pads or room noise.
        """)
        Foundation.exit(0)
    }

    while !args.isEmpty {
        let flag = args.removeFirst()
        guard !args.isEmpty else { continue }
        let value = args.removeFirst()

        switch flag {
        case "--file":
            options.fileURL = URL(fileURLWithPath: value)
        case "--bpm":
            guard let bpm = Double(value), bpm > 0 else {
                throw AnalyzerError.invalidBPM(value)
            }
            options.bpm = bpm
        case "--threshold-ratio":
            options.thresholdRatio = max(0.05, min(0.95, Double(value) ?? options.thresholdRatio))
        default:
            continue
        }
    }

    return options
}

func readMonoSamples(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
    let file: AVAudioFile
    do {
        file = try AVAudioFile(forReading: url)
    } catch {
        throw AnalyzerError.unreadableAudio(url.path)
    }

    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(file.length)
    ) else {
        throw AnalyzerError.unreadableAudio(url.path)
    }

    try file.read(into: buffer)

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    var samples = Array(repeating: Float(0), count: frameCount)

    if let channels = buffer.floatChannelData {
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += abs(channels[channel][frame])
            }
            samples[frame] = sum / Float(max(1, channelCount))
        }
    }

    return (samples, buffer.format.sampleRate)
}

func detectClickFrames(samples: [Float], sampleRate: Double, bpm: Double, thresholdRatio: Double) throws -> [Int] {
    guard let maxAmplitude = samples.max(), maxAmplitude > 0 else {
        throw AnalyzerError.noSignal
    }

    let threshold = maxAmplitude * Float(thresholdRatio)
    let expectedIntervalFrames = sampleRate * 60.0 / bpm
    let minimumGapFrames = Int(expectedIntervalFrames * 0.45)
    var peaks: [Int] = []
    var index = 0

    while index < samples.count {
        if samples[index] < threshold {
            index += 1
            continue
        }

        var peakIndex = index
        var peakValue = samples[index]

        while index < samples.count && samples[index] >= threshold {
            if samples[index] > peakValue {
                peakValue = samples[index]
                peakIndex = index
            }
            index += 1
        }

        if let last = peaks.last, peakIndex - last < minimumGapFrames {
            if peakValue > samples[last] {
                peaks[peaks.count - 1] = peakIndex
            }
        } else {
            peaks.append(peakIndex)
        }

        index += max(1, minimumGapFrames / 3)
    }

    return peaks
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

func analyze(options: Options) throws -> Analysis {
    guard let fileURL = options.fileURL else { throw AnalyzerError.missingFile }
    guard let bpm = options.bpm else { throw AnalyzerError.missingBPM }

    let audio = try readMonoSamples(from: fileURL)
    let peaks = try detectClickFrames(
        samples: audio.samples,
        sampleRate: audio.sampleRate,
        bpm: bpm,
        thresholdRatio: options.thresholdRatio
    )

    guard peaks.count >= 8 else {
        throw AnalyzerError.tooFewClicks(peaks.count)
    }

    let intervals = zip(peaks, peaks.dropFirst()).map { previous, next in
        Double(next - previous) / audio.sampleRate
    }
    let expectedInterval = 60.0 / bpm
    let medianInterval = median(intervals)
    let observedBPM = 60.0 / medianInterval
    let jitters = intervals.map { abs($0 - expectedInterval) }
    let meanJitter = jitters.reduce(0, +) / Double(jitters.count)
    let worstJitter = jitters.max() ?? 0
    let missingBeats = intervals.reduce(0) { total, interval in
        total + max(0, Int(round(interval / expectedInterval)) - 1)
    }
    let extraBeats = intervals.filter { $0 < expectedInterval * 0.55 }.count
    let duration = Double(audio.samples.count) / audio.sampleRate
    let passed = missingBeats == 0
        && extraBeats == 0
        && abs(observedBPM - bpm) <= options.maxBPMError
        && meanJitter <= options.maxMeanJitterSeconds
        && worstJitter <= options.maxWorstJitterSeconds

    return Analysis(
        duration: duration,
        clickCount: peaks.count,
        observedBPM: observedBPM,
        expectedInterval: expectedInterval,
        medianInterval: medianInterval,
        meanAbsoluteJitter: meanJitter,
        worstJitter: worstJitter,
        missingBeats: missingBeats,
        extraBeats: extraBeats,
        passed: passed
    )
}

func format(_ value: Double, digits: Int = 3) -> String {
    String(format: "%.\(digits)f", value)
}

do {
    let options = try parseOptions()
    let result = try analyze(options: options)

    print("Click Recording Analysis")
    print("Result: \(result.passed ? "PASS" : "FAIL")")
    print("Duration: \(format(result.duration)) sec")
    print("Detected clicks: \(result.clickCount)")
    print("Observed BPM: \(format(result.observedBPM))")
    print("Expected interval: \(format(result.expectedInterval)) sec")
    print("Median interval: \(format(result.medianInterval)) sec")
    print("Mean jitter: \(format(result.meanAbsoluteJitter * 1000)) ms")
    print("Worst jitter: \(format(result.worstJitter * 1000)) ms")
    print("Missing beats: \(result.missingBeats)")
    print("Extra/doubled beats: \(result.extraBeats)")

    Foundation.exit(result.passed ? 0 : 1)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    Foundation.exit(2)
}
