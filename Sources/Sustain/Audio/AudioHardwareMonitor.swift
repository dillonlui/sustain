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

    deinit {
        // Owned by AppStore (main actor) for the app's lifetime, so this runs on main. Guard on
        // the thread rather than using a bare assumeIsolated, which would trap if a future change
        // ever released this off-main — degrade to a harmless no-op at shutdown instead.
        if Thread.isMainThread {
            MainActor.assumeIsolated { timer?.invalidate() }
        }
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
    private let fallbackMonitor: AudioHardwareMonitoring
    private let queue = DispatchQueue(label: "com.sustain.audio-hardware-monitor")
    private var isListening = false
    private var isFallbackActive = false
    private var devicesListenerRegistered = false
    private var defaultOutputListenerRegistered = false
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

    init(fallbackMonitor: AudioHardwareMonitoring = PollingAudioHardwareMonitor()) {
        self.fallbackMonitor = fallbackMonitor
    }

    deinit {
        // See PollingAudioHardwareMonitor.deinit: guard the main-actor assumption instead of
        // trapping if released off-main.
        if Thread.isMainThread {
            MainActor.assumeIsolated { stop() }
        }
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        relay.update(onChange: onChange)
        guard !isListening, !isFallbackActive else { return }

        devicesListenerRegistered = addListener(for: &devicesAddress)
        defaultOutputListenerRegistered = addListener(for: &defaultOutputAddress)
        isListening = devicesListenerRegistered || defaultOutputListenerRegistered

        if !isListening {
            fallbackMonitor.start(onChange: onChange)
            isFallbackActive = true
        }
    }

    func stop() {
        if devicesListenerRegistered {
            removeListener(for: &devicesAddress)
        }
        if defaultOutputListenerRegistered {
            removeListener(for: &defaultOutputAddress)
        }

        if isFallbackActive {
            fallbackMonitor.stop()
        }

        devicesListenerRegistered = false
        defaultOutputListenerRegistered = false
        isListening = false
        isFallbackActive = false
        relay.update(onChange: nil)
    }

    private func addListener(for address: inout AudioObjectPropertyAddress) -> Bool {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        ) == noErr
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
    private var pending = false

    func update(onChange: (@MainActor () -> Void)?) {
        lock.lock()
        self.onChange = onChange
        pending = false
        lock.unlock()
    }

    /// CoreAudio fires this on a private serial queue, and a device unplug/replug or wake can
    /// produce a rapid burst. Coalesce: keep at most one hop in flight so callbacks can't run
    /// out of order or flap the route-change prompt. `pending` is cleared before invoking the
    /// callback, so a change that arrives while it's running still schedules a fresh hop.
    func notify() {
        lock.lock()
        guard let onChange, !pending else {
            lock.unlock()
            return
        }
        pending = true
        lock.unlock()

        Task { @MainActor in
            self.clearPending()
            onChange()
        }
    }

    private func clearPending() {
        lock.lock()
        pending = false
        lock.unlock()
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
