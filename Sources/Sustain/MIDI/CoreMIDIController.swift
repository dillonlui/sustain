import CoreMIDI
import Foundation

enum MIDIProtocolEventParser {
    /// Parses MIDI 1.0 Channel Voice UMP words. Parsing copies scalar values only; packet
    /// storage never escapes the Core MIDI callback.
    static func messages(words: [UInt32], sourceUniqueID: Int32) -> [MIDIMessage] {
        var result: [MIDIMessage] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let messageType = UInt8((word >> 28) & 0x0F)
            defer { index += umpWordCount(for: messageType) }
            guard messageType == 0x02 else { continue }
            let statusByte = UInt8((word >> 16) & 0xFF)
            let status = statusByte & 0xF0
            let channel = statusByte & 0x0F
            let number = UInt8((word >> 8) & 0x7F)
            let value = UInt8(word & 0x7F)
            switch status {
            case 0x90 where value > 0:
                result.append(MIDIMessage(sourceUniqueID: sourceUniqueID, kind: .noteOn, channel: channel, number: number, value: value))
            case 0xB0:
                result.append(MIDIMessage(sourceUniqueID: sourceUniqueID, kind: .controlChange, channel: channel, number: number, value: value))
            default: break
            }
        }
        return result
    }

    private static func umpWordCount(for messageType: UInt8) -> Int {
        switch messageType {
        case 0x3, 0x4: 2
        case 0x5, 0xD, 0xF: 4
        default: 1
        }
    }
}

/// A callback-safe bounded relay. CC state for the same source/channel/number is replaced in
/// place; when full, new non-coalescible events are dropped. One main-queue drain is scheduled
/// regardless of callback burst size, so callback work and retained memory stay bounded.
final class BoundedMIDIEventRelay: @unchecked Sendable {
    typealias Delivery = @Sendable ([MIDIMessage]) -> Void

    private struct CCKey: Hashable {
        var source: Int32
        var channel: UInt8
        var number: UInt8
    }

    private let lock = NSLock()
    private let capacity: Int
    private var queued: [MIDIMessage] = []
    private var ccIndices: [CCKey: Int] = [:]
    private var drainScheduled = false
    private(set) var droppedEventCount = 0
    var delivery: Delivery?

    init(capacity: Int = 64, delivery: Delivery? = nil) {
        self.capacity = max(1, capacity)
        self.delivery = delivery
    }

    func offer(_ event: MIDIMessage) {
        let shouldSchedule = lock.withLock {
            if event.identity.kind == .controlChange {
                let key = CCKey(source: event.sourceUniqueID, channel: event.identity.channel, number: event.identity.number)
                if let index = ccIndices[key], queued.indices.contains(index) {
                    queued[index] = event
                    return false
                }
                guard queued.count < capacity else {
                    droppedEventCount += 1
                    return false
                }
                ccIndices[key] = queued.count
                queued.append(event)
            } else {
                guard queued.count < capacity else {
                    droppedEventCount += 1
                    return false
                }
                queued.append(event)
            }
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }

    func drainNowForTesting() { drain() }

    func reset() {
        lock.withLock {
            queued.removeAll(keepingCapacity: true)
            ccIndices.removeAll(keepingCapacity: true)
            drainScheduled = false
        }
    }

    var queuedCount: Int { lock.withLock { queued.count } }

    private func drain() {
        let batch: [MIDIMessage] = lock.withLock {
            let result = queued
            queued.removeAll(keepingCapacity: true)
            ccIndices.removeAll(keepingCapacity: true)
            drainScheduled = false
            return result
        }
        if !batch.isEmpty { delivery?(batch) }
    }
}

struct MIDISourceTopologyDelta: Equatable {
    var removed: Set<Int32>
    var added: Set<Int32>

    static func compare(connected: Set<Int32>, available: Set<Int32>) -> Self {
        Self(removed: connected.subtracting(available), added: available.subtracting(connected))
    }
}

private final class MIDISourceConnectionToken: @unchecked Sendable {
    let uniqueID: Int32
    init(uniqueID: Int32) { self.uniqueID = uniqueID }
}

@MainActor
final class CoreMIDIController: MIDIControlling {
    private struct Connection {
        var endpoint: MIDIEndpointRef
        var tokenPointer: UnsafeMutableRawPointer
    }

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connections: [Int32: Connection] = [:]
    private let relay: BoundedMIDIEventRelay

    private(set) var availableSources: [MIDIControllerSource] = []
    private(set) var state: MIDIControllerServiceState = .stopped
    var eventHandler: ((MIDIMessage) -> Void)?
    var sourceLifecycleHandler: ((Int32) -> Void)?

    init(relayCapacity: Int = 64) {
        relay = BoundedMIDIEventRelay(capacity: relayCapacity)
        relay.delivery = { [weak self] events in
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                for event in events { self.eventHandler?(event) }
            }
        }
    }

    deinit {
        // App composition owns a long-lived instance and calls stop. Avoid actor-isolated API
        // from deinit; Core MIDI also tears down ports when the client is disposed at process exit.
    }

    func start() {
        guard state == .stopped else { return }
        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("Sustain MIDI" as CFString, &newClient) { [weak self] _ in
            Task { @MainActor in self?.refreshSources() }
        }
        guard clientStatus == noErr else {
            fail("Could not create the Core MIDI client", status: clientStatus)
            return
        }
        client = newClient

        var newPort = MIDIPortRef()
        let relay = relay
        let portStatus = MIDIInputPortCreateWithProtocol(
            client,
            "Sustain MIDI Input" as CFString,
            ._1_0,
            &newPort
        ) { eventList, sourceConnection in
            guard let sourceConnection else { return }
            let sourceID = Unmanaged<MIDISourceConnectionToken>
                .fromOpaque(sourceConnection).takeUnretainedValue().uniqueID
            Self.copyMessages(from: eventList, sourceUniqueID: sourceID).forEach(relay.offer)
        }
        guard portStatus == noErr else {
            MIDIClientDispose(client)
            client = MIDIClientRef()
            fail("Could not create the Core MIDI input port", status: portStatus)
            return
        }
        inputPort = newPort
        state = .running
        refreshSources()
    }

    func stop() {
        guard state != .stopped else { return }
        disconnectAll()
        if inputPort != MIDIPortRef() { MIDIPortDispose(inputPort) }
        if client != MIDIClientRef() { MIDIClientDispose(client) }
        inputPort = MIDIPortRef()
        client = MIDIClientRef()
        availableSources = []
        relay.reset()
        state = .stopped
    }

    func refresh() { refreshSources() }

    func refreshSources() {
        guard inputPort != MIDIPortRef() else { return }
        let enumerated = Self.enumerateSources()
        let byID = Dictionary(uniqueKeysWithValues: enumerated.map { ($0.source.uniqueID, $0) })
        let delta = MIDISourceTopologyDelta.compare(
            connected: Set(connections.keys),
            available: Set(byID.keys)
        )
        availableSources = enumerated.map(\.source).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var hadConnectionFailure = false

        for uniqueID in delta.removed {
            disconnect(uniqueID: uniqueID)
            sourceLifecycleHandler?(uniqueID)
        }
        for uniqueID in delta.added {
            guard let item = byID[uniqueID] else { continue }
            let token = MIDISourceConnectionToken(uniqueID: uniqueID)
            let pointer = Unmanaged.passRetained(token).toOpaque()
            let status = MIDIPortConnectSource(inputPort, item.endpoint, pointer)
            guard status == noErr else {
                Unmanaged<MIDISourceConnectionToken>.fromOpaque(pointer).release()
                fail("Could not connect MIDI source \(item.source.name)", status: status)
                hadConnectionFailure = true
                continue
            }
            connections[uniqueID] = Connection(endpoint: item.endpoint, tokenPointer: pointer)
            sourceLifecycleHandler?(uniqueID)
        }
        if !hadConnectionFailure { state = .running }
    }

    private func disconnect(uniqueID: Int32) {
        guard let connection = connections.removeValue(forKey: uniqueID) else { return }
        MIDIPortDisconnectSource(inputPort, connection.endpoint)
        Unmanaged<MIDISourceConnectionToken>.fromOpaque(connection.tokenPointer).release()
    }

    private func disconnectAll() {
        for uniqueID in Array(connections.keys) {
            disconnect(uniqueID: uniqueID)
            sourceLifecycleHandler?(uniqueID)
        }
    }

    private func fail(_ message: String, status: OSStatus) {
        state = .failed(message: "\(message) (Core MIDI \(status)).")
    }

    private nonisolated static func copyMessages(
        from eventList: UnsafePointer<MIDIEventList>,
        sourceUniqueID: Int32
    ) -> [MIDIMessage] {
        var result: [MIDIMessage] = []
        guard let packetOffset = MemoryLayout<MIDIEventList>.offset(of: \MIDIEventList.packet) else { return [] }
        var packetPointer = UnsafeMutableRawPointer(mutating: eventList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIEventPacket.self)
        for _ in 0..<eventList.pointee.numPackets {
            let packet = packetPointer.pointee
            let words = withUnsafePointer(to: packet.words) { wordsPointer -> [UInt32] in
                wordsPointer.withMemoryRebound(to: UInt32.self, capacity: Int(packet.wordCount)) {
                    Array(UnsafeBufferPointer(start: $0, count: Int(packet.wordCount)))
                }
            }
            result.append(contentsOf: MIDIProtocolEventParser.messages(words: words, sourceUniqueID: sourceUniqueID))
            packetPointer = MIDIEventPacketNext(packetPointer)
        }
        return result
    }

    private nonisolated static func enumerateSources() -> [(endpoint: MIDIEndpointRef, source: MIDIControllerSource)] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != MIDIEndpointRef() else { return nil }
            var uniqueID: Int32 = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr,
                  uniqueID != 0 else { return nil }
            return (
                endpoint,
                MIDIControllerSource(
                    uniqueID: uniqueID,
                    name: stringProperty(endpoint, kMIDIPropertyDisplayName) ?? "MIDI Source \(index + 1)",
                    manufacturer: stringProperty(endpoint, kMIDIPropertyManufacturer),
                    model: stringProperty(endpoint, kMIDIPropertyModel)
                )
            )
        }
    }

    private nonisolated static func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
