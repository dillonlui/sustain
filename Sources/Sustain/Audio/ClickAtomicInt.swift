import ClickAtomics

/// C11 atomics are available on the app's macOS 14 minimum; Swift's Atomic starts at macOS 15.
final class ClickAtomicInt: @unchecked Sendable {
    private let storage: UnsafeMutableRawPointer

    init(_ initial: Int) {
        guard let storage = sustain_atomic_create(Int64(initial)) else {
            fatalError("Could not allocate click atomic")
        }
        self.storage = storage
    }

    deinit { sustain_atomic_destroy(storage) }

    func load() -> Int { Int(sustain_atomic_load(storage)) }
    func store(_ value: Int) { sustain_atomic_store(storage, Int64(value)) }
    func exchange(_ value: Int) -> Int { Int(sustain_atomic_exchange(storage, Int64(value))) }
    func add(_ value: Int) { _ = sustain_atomic_add(storage, Int64(value)) }
}
