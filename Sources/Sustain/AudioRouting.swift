import CoreAudio
import Foundation

struct AudioRoutingSettings: Codable, Equatable {
    var padOutputID: AudioDeviceID?
    var padOutputName: String? = nil
    var clickOutputID: AudioDeviceID?
    var clickOutputName: String? = nil

    static let `default` = AudioRoutingSettings(
        padOutputID: nil,
        padOutputName: nil,
        clickOutputID: nil,
        clickOutputName: nil
    )
}

struct AudioOutputDevice: Identifiable, Equatable {
    var id: AudioDeviceID
    var name: String
    var isDefault: Bool
}

struct AudioRoutingSnapshot: Equatable {
    var outputs: [AudioOutputDevice]
    var padOutputID: AudioDeviceID?
    var padOutputName: String
    var clickOutputID: AudioDeviceID?
    var clickOutputName: String
    var independentRoutingEnabled: Bool
    var missingSelectionMessages: [String] = []

    var summary: String {
        if independentRoutingEnabled {
            return "Pad: \(padOutputName) | Click: \(clickOutputName)"
        }

        return "Pad and click share \(padOutputName)"
    }

    var warning: String? {
        if !missingSelectionMessages.isEmpty {
            return missingSelectionMessages.joined(separator: " ")
        }

        return independentRoutingEnabled ? nil : "Pad and click are currently sharing the same output."
    }

    static let unavailable = AudioRoutingSnapshot(
        outputs: [],
        padOutputID: nil,
        padOutputName: "Unavailable",
        clickOutputID: nil,
        clickOutputName: "Unavailable",
        independentRoutingEnabled: false
    )

    static let previewDefault = AudioRoutingSnapshot(
        outputs: [
            AudioOutputDevice(id: 1, name: "Preview Output", isDefault: true)
        ],
        padOutputID: 1,
        padOutputName: "Preview Output",
        clickOutputID: 1,
        clickOutputName: "Preview Output",
        independentRoutingEnabled: false
    )
}

protocol AudioRoutingProviding {
    func snapshot(settings: AudioRoutingSettings) -> AudioRoutingSnapshot
}

struct AudioRoutingResolver {
    func snapshot(settings: AudioRoutingSettings, outputs: [AudioOutputDevice]) -> AudioRoutingSnapshot {
        let defaultOutput = outputs.first(where: \.isDefault) ?? outputs.first
        let padOutput = resolveOutput(
            id: settings.padOutputID,
            name: settings.padOutputName,
            outputs: outputs,
            fallback: defaultOutput
        )
        let clickOutput = resolveOutput(
            id: settings.clickOutputID,
            name: settings.clickOutputName,
            outputs: outputs,
            fallback: defaultOutput
        )

        var missingSelectionMessages: [String] = []
        if settings.padOutputID != nil,
           padOutput == nil || isFallbackOutput(padOutput, fallback: defaultOutput, name: settings.padOutputName) {
            missingSelectionMessages.append("Selected pad output is unavailable.")
        }
        if settings.clickOutputID != nil,
           clickOutput == nil || isFallbackOutput(clickOutput, fallback: defaultOutput, name: settings.clickOutputName) {
            missingSelectionMessages.append("Selected click output is unavailable.")
        }

        let padOutputID = padOutput?.id
        let clickOutputID = clickOutput?.id

        return AudioRoutingSnapshot(
            outputs: outputs,
            padOutputID: padOutputID,
            padOutputName: padOutput?.name ?? "Unavailable",
            clickOutputID: clickOutputID,
            clickOutputName: clickOutput?.name ?? "Unavailable",
            independentRoutingEnabled: padOutputID != nil && clickOutputID != nil && padOutputID != clickOutputID,
            missingSelectionMessages: missingSelectionMessages
        )
    }

    private func resolveOutput(
        id: AudioDeviceID?,
        name: String?,
        outputs: [AudioOutputDevice],
        fallback: AudioOutputDevice?
    ) -> AudioOutputDevice? {
        if let id, let output = outputs.first(where: { $0.id == id }) {
            return output
        }

        if let name, let output = outputs.first(where: { $0.name == name }) {
            return output
        }

        return id == nil ? fallback : nil
    }

    private func isFallbackOutput(
        _ output: AudioOutputDevice?,
        fallback: AudioOutputDevice?,
        name: String?
    ) -> Bool {
        guard let name, let output, let fallback else { return output == nil }
        return output.id == fallback.id && output.name != name
    }
}

struct CoreAudioRoutingProvider: AudioRoutingProviding {
    private let resolver = AudioRoutingResolver()

    func snapshot(settings: AudioRoutingSettings = .default) -> AudioRoutingSnapshot {
        resolver.snapshot(settings: settings, outputs: outputDevices())
    }

    private func outputDevices() -> [AudioOutputDevice] {
        var devices = allAudioDeviceIDs().filter(hasOutputStreams)
        let defaultID = defaultOutputDeviceID()

        devices.sort { left, right in
            if left == defaultID { return true }
            if right == defaultID { return false }
            return name(for: left) < name(for: right)
        }

        return devices.map { deviceID in
            AudioOutputDevice(
                id: deviceID,
                name: name(for: deviceID),
                isDefault: deviceID == defaultID
            )
        }
    }

    private func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: count)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return []
        }

        return devices
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }

        return deviceID
    }

    private func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private func name(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "Unknown Output" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }

        return status == noErr ? name as String : "Unknown Output"
    }
}

struct StaticAudioRoutingProvider: AudioRoutingProviding {
    var snapshotValue: AudioRoutingSnapshot

    func snapshot(settings: AudioRoutingSettings = .default) -> AudioRoutingSnapshot {
        snapshotValue
    }
}
