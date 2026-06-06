import Foundation

@MainActor
protocol AudioHardwareMonitoring: AnyObject {
    func start(onChange: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class PollingAudioHardwareMonitor: AudioHardwareMonitoring {
    private var timer: Timer?
    private var onChange: (@MainActor () -> Void)?
    private let interval: TimeInterval

    init(interval: TimeInterval = 2) {
        self.interval = interval
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onChange?()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onChange = nil
    }
}

@MainActor
final class NoopAudioHardwareMonitor: AudioHardwareMonitoring {
    private(set) var isStarted = false
    private var onChange: (@MainActor () -> Void)?

    func start(onChange: @escaping @MainActor () -> Void) {
        isStarted = true
        self.onChange = onChange
    }

    func stop() {
        isStarted = false
        onChange = nil
    }

    func simulateChange() {
        onChange?()
    }
}
