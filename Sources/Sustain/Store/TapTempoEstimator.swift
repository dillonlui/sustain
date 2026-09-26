import Foundation

/// A short, monotonic sequence of taps. The clock is supplied by the caller so
/// both UI and MIDI input use the same timeline and tests need no real delays.
struct TapTempoEstimator: Equatable {
    private(set) var intervals: [TimeInterval] = []
    private(set) var tapCount = 0
    private(set) var lastTap: TimeInterval?
    private(set) var didResetOnLastTap = false

    var bpm: Int? {
        guard tapCount >= 3, intervals.count >= 2 else { return nil }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        return min(220, max(40, Int((60 / median).rounded())))
    }

    /// A provisional estimate is usable only while the tap sequence is still fresh.
    func bpm(at time: TimeInterval) -> Int? {
        guard time.isFinite, let lastTap, time >= lastTap, time - lastTap < 2 else { return nil }
        return bpm
    }

    mutating func reset() {
        intervals = []
        tapCount = 0
        lastTap = nil
        didResetOnLastTap = false
    }

    mutating func tap(at time: TimeInterval) {
        didResetOnLastTap = false
        guard time.isFinite else { return }
        guard let previous = lastTap else {
            lastTap = time
            tapCount = 1
            return
        }
        let interval = time - previous
        guard interval > 0 else { return }
        if interval >= 2 || interval < 0.15 {
            reset()
            lastTap = time
            tapCount = 1
            didResetOnLastTap = true
            return
        }
        if intervals.count >= 2 {
            let sorted = intervals.sorted()
            let median = sorted[sorted.count / 2]
            if interval < median * 0.65 || interval > median * 1.5 {
                reset()
                lastTap = time
                tapCount = 1
                didResetOnLastTap = true
                return
            }
        }
        lastTap = time
        tapCount += 1
        intervals.append(interval)
        if intervals.count > 5 { intervals.removeFirst() }
    }
}
