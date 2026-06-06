import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    var id: AudioDeviceID
    var name: String
    var isDefault: Bool
}

struct AudioRoutingSnapshot: Equatable {
    var outputs: [AudioOutputDevice]
    var padOutputName: String
    var clickOutputName: String
    var independentRoutingEnabled: Bool

    var summary: String {
        if independentRoutingEnabled {
            return "Pad: \(padOutputName) | Click: \(clickOutputName)"
        }

        return "Pad and click share \(padOutputName)"
    }

    var warning: String? {
        independentRoutingEnabled ? nil : "Pad and click are currently sharing the default system output."
    }

    static let unavailable = AudioRoutingSnapshot(
        outputs: [],
        padOutputName: "Unavailable",
        clickOutputName: "Unavailable",
        independentRoutingEnabled: false
    )

    static let previewDefault = AudioRoutingSnapshot(
        outputs: [
            AudioOutputDevice(id: 1, name: "Preview Output", isDefault: true)
        ],
        padOutputName: "Preview Output",
        clickOutputName: "Preview Output",
        independentRoutingEnabled: false
    )
}

protocol AudioRoutingProviding {
    func snapshot() -> AudioRoutingSnapshot
}

struct CoreAudioRoutingProvider: AudioRoutingProviding {
    func snapshot() -> AudioRoutingSnapshot {
        let outputs = outputDevices()
        let defaultOutput = outputs.first(where: \.isDefault)?.name ?? outputs.first?.name ?? "Default Output"

        return AudioRoutingSnapshot(
            outputs: outputs,
            padOutputName: defaultOutput,
            clickOutputName: defaultOutput,
            independentRoutingEnabled: false
        )
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

    func snapshot() -> AudioRoutingSnapshot {
        snapshotValue
    }
}
