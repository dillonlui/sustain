import AppKit
import Foundation

@MainActor
protocol PowerStateMonitoring: AnyObject {
    func start(onWake: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class MacPowerStateMonitor: PowerStateMonitoring {
    private var observer: NSObjectProtocol?
    private var onWake: (@MainActor () -> Void)?

    deinit {
        // Owned by AppStore (main actor) for the app's lifetime. Guard the main-actor
        // assumption instead of trapping if a future change releases this off-main.
        if Thread.isMainThread {
            MainActor.assumeIsolated { stop() }
        }
    }

    func start(onWake: @escaping @MainActor () -> Void) {
        self.onWake = onWake
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onWake?()
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        onWake = nil
    }
}

@MainActor
final class NoopPowerStateMonitor: PowerStateMonitoring {
    private(set) var isStarted = false
    private var onWake: (@MainActor () -> Void)?

    func start(onWake: @escaping @MainActor () -> Void) {
        isStarted = true
        self.onWake = onWake
    }

    func stop() {
        isStarted = false
        onWake = nil
    }

    func simulateWake() {
        onWake?()
    }
}
