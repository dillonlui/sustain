import Foundation

struct WaveWriter {
    static func write(
        url: URL,
        frequencies: [Double],
        duration: Double = 6.0,
        sampleRate: Int = 44_100
    ) throws {
        let frameCount = Int(duration * Double(sampleRate))
        let channelCount = 2
        var pcm = Data()
        pcm.reserveCapacity(frameCount * channelCount * 2)

        for frame in 0..<frameCount {
            let t = Double(frame) / Double(sampleRate)
            var sample = 0.0

            for (index, frequency) in frequencies.enumerated() {
                let weight = [0.58, 0.28, 0.14][index]
                let loopSafeFrequency = round(frequency * duration) / duration
                sample += sin(2.0 * Double.pi * loopSafeFrequency * t) * weight
            }

            let fadeLength = min(frameCount / 12, sampleRate / 2)
            let fadeIn = min(1.0, Double(frame) / Double(fadeLength))
            let fadeOut = min(1.0, Double(frameCount - frame - 1) / Double(fadeLength))
            let envelope = min(fadeIn, fadeOut)
            let shaped = Int16(max(-1.0, min(1.0, tanh(sample) * envelope * 0.42)) * Double(Int16.max))

            for _ in 0..<channelCount {
                var littleEndian = shaped.littleEndian
                withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
            }
        }

        var data = Data()
        appendString("RIFF", to: &data)
        appendUInt32(UInt32(36 + pcm.count), to: &data)
        appendString("WAVE", to: &data)
        appendString("fmt ", to: &data)
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(UInt16(channelCount), to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(sampleRate * channelCount * 2), to: &data)
        appendUInt16(UInt16(channelCount * 2), to: &data)
        appendUInt16(16, to: &data)
        appendString("data", to: &data)
        appendUInt32(UInt32(pcm.count), to: &data)
        data.append(pcm)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    private static func appendString(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/Sustain/Resources/Pads", isDirectory: true)

let baseFrequencies: [String: Double] = [
    "C": 130.8128,
    "Db": 138.5913,
    "D": 146.8324,
    "Eb": 155.5635,
    "E": 164.8138,
    "F": 174.6141,
    "Gb": 184.9972,
    "G": 195.9977,
    "Ab": 207.6523,
    "A": 220.0,
    "Bb": 233.0819,
    "B": 246.9417
]

for (pack, keys) in [
    ("Warm", Array(baseFrequencies.keys)),
    ("Airy", ["C", "D", "E", "F", "G", "A"])
] {
    for key in keys.sorted() {
        let rootFrequency = baseFrequencies[key]!
        let brightness = pack == "Airy" ? 2.5 : 2.0
        let url = root
            .appendingPathComponent(pack, isDirectory: true)
            .appendingPathComponent("\(key).wav")

        try WaveWriter.write(
            url: url,
            frequencies: [rootFrequency, rootFrequency * 1.5, rootFrequency * brightness]
        )
    }
}

print("Generated pad sample WAV files in \(root.path)")
