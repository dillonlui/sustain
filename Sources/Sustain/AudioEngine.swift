import AVFoundation
import Foundation

final class SustainAudioEngine {
    private let engine = AVAudioEngine()

    var isRunning: Bool {
        engine.isRunning
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    func stop() {
        engine.stop()
    }
}
