import CoreAudio
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
final class CoreAudioHardwareMonitor: AudioHardwareMonitoring {
    private let relay = AudioHardwareChangeRelay()
    private let queue = DispatchQueue(label: "com.sustain.audio-hardware-monitor")
    private var isListening = false
    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private lazy var listener: AudioObjectPropertyListenerBlock = { [relay] _, _ in
        relay.notify()
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        relay.update(onChange: onChange)
        guard !isListening else { return }

        addListener(for: &devicesAddress)
        addListener(for: &defaultOutputAddress)
        isListening = true
    }

    func stop() {
        guard isListening else { return }

        removeListener(for: &devicesAddress)
        removeListener(for: &defaultOutputAddress)
        isListening = false
        relay.update(onChange: nil)
    }

    private func addListener(for address: inout AudioObjectPropertyAddress) {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        )
    }

    private func removeListener(for address: inout AudioObjectPropertyAddress) {
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        )
    }
}

private final class AudioHardwareChangeRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (@MainActor () -> Void)?

    func update(onChange: (@MainActor () -> Void)?) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()
    }

    func notify() {
        lock.lock()
        let onChange = onChange
        lock.unlock()

        guard let onChange else { return }
        Task { @MainActor in
            onChange()
        }
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
