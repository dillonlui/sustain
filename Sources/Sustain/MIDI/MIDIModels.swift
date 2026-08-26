import Foundation

enum MIDIMessageKind: String, Codable, CaseIterable, Equatable, Hashable {
    case noteOn
    case controlChange
}

struct MIDIMessageIdentity: Codable, Equatable, Hashable {
    var kind: MIDIMessageKind
    /// MIDI channels are stored zero-based, matching the wire protocol.
    var channel: UInt8
    var number: UInt8

    init(kind: MIDIMessageKind, channel: UInt8, number: UInt8) {
        self.kind = kind
        self.channel = min(channel, 15)
        self.number = min(number, 127)
    }

    var displayName: String {
        let prefix = kind == .noteOn ? "Note" : "CC"
        return "\(prefix) \(number) · Channel \(channel + 1)"
    }
}

struct MIDIMessage: Equatable, Hashable {
    var sourceUniqueID: Int32
    var identity: MIDIMessageIdentity
    var value: UInt8

    init(sourceUniqueID: Int32, kind: MIDIMessageKind, channel: UInt8, number: UInt8, value: UInt8) {
        self.sourceUniqueID = sourceUniqueID
        self.identity = MIDIMessageIdentity(kind: kind, channel: channel, number: number)
        self.value = min(value, 127)
    }
}

struct MIDIControllerSource: Codable, Identifiable, Equatable, Hashable {
    var uniqueID: Int32
    var name: String
    var manufacturer: String?
    var model: String?

    var id: Int32 { uniqueID }
}

enum MIDIControllerSelection: Codable, Equatable, Hashable {
    case any
    case source(uniqueID: Int32)

    func matches(sourceUniqueID: Int32) -> Bool {
        switch self {
        case .any: true
        case let .source(uniqueID): uniqueID == sourceUniqueID
        }
    }
}

enum MIDIAction: String, Codable, CaseIterable, Identifiable, Equatable, Hashable {
    case startTransition
    case nextCue
    case previousCue
    case stopAll
    case toggleClick
    case togglePad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startTransition: "Start / Transition"
        case .nextCue: "Next cue"
        case .previousCue: "Previous cue"
        case .stopAll: "Stop all"
        case .toggleClick: "Toggle click"
        case .togglePad: "Toggle pad"
        }
    }
}

struct MIDIMapping: Codable, Identifiable, Equatable, Hashable {
    var action: MIDIAction
    var source: MIDIControllerSelection
    var message: MIDIMessageIdentity

    var id: MIDIAction { action }
}

struct MIDIControllerSettings: Codable, Equatable {
    var isEnabled: Bool
    var selectedSource: MIDIControllerSelection
    var mappings: [MIDIMapping]

    static let disabled = MIDIControllerSettings(
        isEnabled: false,
        selectedSource: .any,
        mappings: []
    )
}

enum MIDIControllerServiceState: Equatable {
    case stopped
    case running
    case failed(message: String)
}

struct MIDIControllerMappingResolver {
    private struct CCEdgeKey: Hashable {
        var sourceUniqueID: Int32
        var channel: UInt8
        var number: UInt8
    }

    private var activeCCEdges: Set<CCEdgeKey> = []

    static func duplicateIdentity(in mappings: [MIDIMapping], candidate: MIDIMapping) -> MIDIMapping? {
        mappings.first {
            $0.action != candidate.action &&
                $0.source == candidate.source &&
                $0.message == candidate.message
        }
    }

    mutating func action(
        for event: MIDIMessage,
        settings: MIDIControllerSettings
    ) -> MIDIAction? {
        guard settings.isEnabled, settings.selectedSource.matches(sourceUniqueID: event.sourceUniqueID) else { return nil }

        let shouldFire: Bool
        switch event.identity.kind {
        case .noteOn:
            shouldFire = event.value > 0
        case .controlChange:
            let key = CCEdgeKey(
                sourceUniqueID: event.sourceUniqueID,
                channel: event.identity.channel,
                number: event.identity.number
            )
            if event.value == 0 {
                activeCCEdges.remove(key)
                shouldFire = false
            } else {
                shouldFire = activeCCEdges.insert(key).inserted
            }
        }

        guard shouldFire else { return nil }
        return settings.mappings.first {
            $0.source.matches(sourceUniqueID: event.sourceUniqueID) &&
                $0.message == event.identity
        }?.action
    }

    mutating func reset(sourceUniqueID: Int32) {
        activeCCEdges = activeCCEdges.filter { $0.sourceUniqueID != sourceUniqueID }
    }

    mutating func resetAllSources() {
        activeCCEdges.removeAll()
    }
}

struct MIDILearnCandidate: Equatable {
    var action: MIDIAction
    var event: MIDIMessage
    var source: MIDIControllerSource

    var mapping: MIDIMapping {
        MIDIMapping(
            action: action,
            source: .source(uniqueID: event.sourceUniqueID),
            message: event.identity
        )
    }
}

enum MIDILearnState: Equatable {
    case idle
    case listening(action: MIDIAction)
    case preview(MIDILearnCandidate)
    case duplicate(candidate: MIDILearnCandidate, existingAction: MIDIAction)
    case timedOut(action: MIDIAction)
}

struct MIDILearnCoordinator {
    private(set) var state: MIDILearnState = .idle

    mutating func begin(_ action: MIDIAction) { state = .listening(action: action) }
    mutating func cancel() { state = .idle }

    mutating func receive(
        _ event: MIDIMessage,
        sources: [MIDIControllerSource],
        settings: MIDIControllerSettings
    ) {
        guard case let .listening(action) = state, event.value > 0 else { return }
        let source = sources.first(where: { $0.uniqueID == event.sourceUniqueID }) ?? MIDIControllerSource(
            uniqueID: event.sourceUniqueID,
            name: "Disconnected controller",
            manufacturer: nil,
            model: nil
        )
        let candidate = MIDILearnCandidate(action: action, event: event, source: source)
        if let duplicate = MIDIControllerMappingResolver.duplicateIdentity(in: settings.mappings, candidate: candidate.mapping) {
            state = .duplicate(candidate: candidate, existingAction: duplicate.action)
        } else {
            state = .preview(candidate)
        }
    }

    mutating func timeOut() {
        guard case let .listening(action) = state else { return }
        state = .timedOut(action: action)
    }

    mutating func commit(into settings: inout MIDIControllerSettings, useAnyController: Bool) -> Bool {
        guard case let .preview(candidate) = state else { return false }
        var mapping = candidate.mapping
        if useAnyController { mapping.source = .any }
        guard MIDIControllerMappingResolver.duplicateIdentity(in: settings.mappings, candidate: mapping) == nil else {
            if let existing = settings.mappings.first(where: {
                $0.action != mapping.action && $0.source == mapping.source && $0.message == mapping.message
            }) {
                state = .duplicate(candidate: candidate, existingAction: existing.action)
            }
            return false
        }
        settings.mappings.removeAll { $0.action == mapping.action }
        settings.mappings.append(mapping)
        settings.mappings.sort { $0.action.rawValue < $1.action.rawValue }
        state = .idle
        return true
    }
}

@MainActor
protocol MIDIControlling: AnyObject {
    var availableSources: [MIDIControllerSource] { get }
    var state: MIDIControllerServiceState { get }
    var eventHandler: ((MIDIMessage) -> Void)? { get set }
    var sourceLifecycleHandler: ((Int32) -> Void)? { get set }

    func start()
    func stop()
    func refresh()
}

@MainActor
final class NoopMIDIController: MIDIControlling {
    var availableSources: [MIDIControllerSource] = []
    var state: MIDIControllerServiceState = .stopped
    var eventHandler: ((MIDIMessage) -> Void)?
    var sourceLifecycleHandler: ((Int32) -> Void)?

    func start() { state = .running }
    func stop() { state = .stopped }
    func refresh() {}
}
