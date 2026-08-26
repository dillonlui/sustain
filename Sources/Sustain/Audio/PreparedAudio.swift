import AVFoundation
import Foundation

/// PCM is written exactly once by the decoder and never mutated by consumers. That explicit
/// immutability contract is what permits the buffer to cross the decode/MainActor boundary.
final class ImmutablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let byteCount: UInt64

    init(buffer: AVAudioPCMBuffer, byteCount: UInt64) {
        self.buffer = buffer
        self.byteCount = byteCount
    }
}

struct PadBufferKey: Hashable, Sendable {
    var padID: PadTrack.ID
    var resourceIdentityData: Data?
    var fingerprint: ExternalFileFingerprint
}

final class PreparedPad: @unchecked Sendable {
    let padID: PadTrack.ID
    let displayName: String
    let generation: UInt64
    let token: UUID
    let key: PadBufferKey
    let pcm: ImmutablePCMBuffer

    init(
        padID: PadTrack.ID,
        displayName: String,
        generation: UInt64,
        token: UUID,
        key: PadBufferKey,
        pcm: ImmutablePCMBuffer
    ) {
        self.padID = padID
        self.displayName = displayName
        self.generation = generation
        self.token = token
        self.key = key
        self.pcm = pcm
    }
}

final class PreparedClick: @unchecked Sendable {
    let loop: ImmutablePCMBuffer
    let countoff: ImmutablePCMBuffer?

    init(loop: ImmutablePCMBuffer, countoff: ImmutablePCMBuffer?) {
        self.loop = loop
        self.countoff = countoff
    }
}

enum PadMemoryError: LocalizedError, Equatable {
    case singlePadLimitExceeded(bytes: UInt64, limit: UInt64)
    case totalBudgetExceeded(required: UInt64, available: UInt64)

    var errorDescription: String? {
        switch self {
        case let .singlePadLimitExceeded(bytes, limit):
            "The decoded pad requires \(bytes) bytes; the per-pad limit is \(limit) bytes."
        case let .totalBudgetExceeded(required, available):
            "The decoded pad requires \(required) bytes, but only \(available) bytes are available in Sustain's live audio budget."
        }
    }
}

final class PadBufferMemoryStore: @unchecked Sendable {
    static let singlePadLimit: UInt64 = 256 * 1024 * 1024
    static let totalBudget: UInt64 = 512 * 1024 * 1024

    private struct Entry {
        var pcm: ImmutablePCMBuffer
        var pinCount: Int
        var lastAccess: UInt64
    }

    private let lock = NSLock()
    private let singlePadLimit: UInt64
    private let totalBudget: UInt64
    private var entries: [PadBufferKey: Entry] = [:]
    private var clock: UInt64 = 0

    init(
        singlePadLimit: UInt64 = PadBufferMemoryStore.singlePadLimit,
        totalBudget: UInt64 = PadBufferMemoryStore.totalBudget
    ) {
        self.singlePadLimit = singlePadLimit
        self.totalBudget = totalBudget
    }

    func retainedBuffer(for key: PadBufferKey) -> ImmutablePCMBuffer? {
        lock.withLock {
            guard var entry = entries[key] else { return nil }
            clock &+= 1
            entry.pinCount += 1
            entry.lastAccess = clock
            entries[key] = entry
            return entry.pcm
        }
    }

    func admitAndRetain(_ pcm: ImmutablePCMBuffer, for key: PadBufferKey) throws {
        try lock.withLock {
            if var existing = entries[key] {
                clock &+= 1
                existing.pinCount += 1
                existing.lastAccess = clock
                entries[key] = existing
                return
            }
            guard pcm.byteCount <= singlePadLimit else {
                throw PadMemoryError.singlePadLimitExceeded(bytes: pcm.byteCount, limit: singlePadLimit)
            }

            evictInactiveUntilFits(additionalBytes: pcm.byteCount)
            let used = totalBytesLocked
            guard used <= totalBudget, pcm.byteCount <= totalBudget - used else {
                throw PadMemoryError.totalBudgetExceeded(
                    required: pcm.byteCount,
                    available: used <= totalBudget ? totalBudget - used : 0
                )
            }
            clock &+= 1
            entries[key] = Entry(pcm: pcm, pinCount: 1, lastAccess: clock)
        }
    }

    func release(_ key: PadBufferKey) {
        lock.withLock {
            guard var entry = entries[key] else { return }
            entry.pinCount = max(0, entry.pinCount - 1)
            entries[key] = entry
        }
    }

    func evictInactive() {
        lock.withLock {
            entries = entries.filter { $0.value.pinCount > 0 }
        }
    }

    var totalBytes: UInt64 { lock.withLock { totalBytesLocked } }
    var pinnedBytes: UInt64 {
        lock.withLock {
            entries.values.reduce(0) { $0 + ($1.pinCount > 0 ? $1.pcm.byteCount : 0) }
        }
    }

    private var totalBytesLocked: UInt64 {
        entries.values.reduce(0) { partial, entry in
            let (next, overflow) = partial.addingReportingOverflow(entry.pcm.byteCount)
            return overflow ? .max : next
        }
    }

    private func evictInactiveUntilFits(additionalBytes: UInt64) {
        while true {
            let used = totalBytesLocked
            if used <= totalBudget, additionalBytes <= totalBudget - used { return }
            guard let candidate = entries
                .filter({ $0.value.pinCount == 0 })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { return }
            entries[candidate] = nil
        }
    }
}

/// Executes at most one decode plus one newest pending request. An obsolete pending request is
/// completed as cancelled immediately; same-key requests share the in-flight operation.
final class LatestWinsPadDecoder: @unchecked Sendable {
    typealias Operation = @Sendable () async throws -> ImmutablePCMBuffer
    typealias Completion = @Sendable (Result<ImmutablePCMBuffer, Error>) -> Void

    private final class Request: @unchecked Sendable {
        let key: PadBufferKey
        let operation: Operation
        var completions: [Completion]

        init(key: PadBufferKey, operation: @escaping Operation, completion: @escaping Completion) {
            self.key = key
            self.operation = operation
            self.completions = [completion]
        }
    }

    private let lock = NSLock()
    private var active: Request?
    private var pending: Request?

    func submit(
        key: PadBufferKey,
        operation: @escaping Operation,
        completion: @escaping Completion
    ) {
        let decision: (requestToStart: Request?, superseded: [Completion]) = lock.withLock {
            if let active, active.key == key {
                active.completions.append(completion)
                return (nil, [])
            }
            if let pending, pending.key == key {
                pending.completions.append(completion)
                return (nil, [])
            }
            let request = Request(key: key, operation: operation, completion: completion)
            guard active != nil else {
                active = request
                return (request, [])
            }
            let superseded = pending
            pending = request
            return (nil, superseded?.completions ?? [])
        }
        decision.superseded.forEach { $0(.failure(CancellationError())) }
        if let requestToStart = decision.requestToStart { run(requestToStart) }
    }

    func cancelPending() {
        let completions: [Completion] = lock.withLock {
            let completions = pending?.completions ?? []
            pending = nil
            return completions
        }
        completions.forEach { $0(.failure(CancellationError())) }
    }

    private func run(_ request: Request) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<ImmutablePCMBuffer, Error>
            do { result = .success(try await request.operation()) }
            catch { result = .failure(error) }
            request.completions.forEach { $0(result) }

            guard let self else { return }
            let next: Request? = self.lock.withLock {
                if self.active === request { self.active = nil }
                let next = self.pending
                self.pending = nil
                self.active = next
                return next
            }
            if let next { self.run(next) }
        }
    }
}
