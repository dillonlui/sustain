import CoreAudio
import SwiftUI

struct AudioSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section {
                LabeledContent(routeStatusTitle, value: store.routingSnapshot.summary)
                if let warning = store.routingSnapshot.warning {
                    SustainInlineNotice(message: warning, kind: .warning)
                }
                Button("Refresh Devices", systemImage: "arrow.clockwise") {
                    store.refreshAudioDiagnostics()
                }
            }

            Section("Pad Output") {
                Picker("Device", selection: padOutputBinding) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(store.routingSnapshot.outputs) { output in
                        Text(output.isDefault ? "\(output.name) (Default)" : output.name)
                            .tag(AudioDeviceID?.some(output.id))
                    }
                }
                Picker("Channel", selection: padChannelBinding) {
                    ForEach(AudioOutputChannelSelection.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
            }

            Section("Click Output") {
                Picker("Device", selection: clickOutputBinding) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(store.routingSnapshot.outputs) { output in
                        Text(output.isDefault ? "\(output.name) (Default)" : output.name)
                            .tag(AudioDeviceID?.some(output.id))
                    }
                }
                Picker("Channel", selection: clickChannelBinding) {
                    ForEach(AudioOutputChannelSelection.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
            }

            Section("Detected Devices") {
                if store.routingSnapshot.outputs.isEmpty {
                    SustainInlineNotice(message: "No audio outputs detected.", kind: .warning)
                } else {
                    ForEach(store.routingSnapshot.outputs) { output in
                        AudioDeviceDiagnosticRow(output: output)
                    }
                }
            }

            Section("Engine") {
                DiagnosticLine(label: "Status", value: store.audioStatus)
                DiagnosticLine(label: "Pad Level", value: "\(Int((store.padVolume * 100).rounded()))%")
                DiagnosticLine(label: "Click Level", value: "\(Int((store.clickVolume * 100).rounded()))%")
            }
        }
        .formStyle(.grouped)
        // A definite size lets the Settings window grow to fit this tab (macOS keeps the
        // window at the first tab's height otherwise, clipping the routing sections). The
        // grouped Form scrolls internally if a machine reports many output devices.
        .frame(width: 460, height: 480)
        .task { store.refreshAudioDiagnostics() }
    }

    private var routeStatusTitle: String {
        if store.routingSnapshot.warning == nil {
            return "Routes are ready"
        }
        return store.routingSnapshot.independentRoutingEnabled ? "Routes need attention" : "Pad and click are sharing output"
    }

    private var padOutputBinding: Binding<AudioDeviceID?> {
        Binding {
            store.routingSettings.padOutputID
        } set: { outputID in
            store.updateRouting(
                padOutputID: outputID,
                clickOutputID: store.routingSettings.clickOutputID,
                padOutputChannel: storedChannel(store.routingSettings.padOutputChannel),
                clickOutputChannel: storedChannel(store.routingSettings.clickOutputChannel)
            )
        }
    }

    private var clickOutputBinding: Binding<AudioDeviceID?> {
        Binding {
            store.routingSettings.clickOutputID
        } set: { outputID in
            store.updateRouting(
                padOutputID: store.routingSettings.padOutputID,
                clickOutputID: outputID,
                padOutputChannel: storedChannel(store.routingSettings.padOutputChannel),
                clickOutputChannel: storedChannel(store.routingSettings.clickOutputChannel)
            )
        }
    }

    private var padChannelBinding: Binding<AudioOutputChannelSelection> {
        Binding {
            store.routingSettings.padOutputChannel ?? .stereo
        } set: { channel in
            store.updateRouting(
                padOutputID: store.routingSettings.padOutputID,
                clickOutputID: store.routingSettings.clickOutputID,
                padOutputChannel: storedChannel(channel),
                clickOutputChannel: storedChannel(store.routingSettings.clickOutputChannel)
            )
        }
    }

    private var clickChannelBinding: Binding<AudioOutputChannelSelection> {
        Binding {
            store.routingSettings.clickOutputChannel ?? .stereo
        } set: { channel in
            store.updateRouting(
                padOutputID: store.routingSettings.padOutputID,
                clickOutputID: store.routingSettings.clickOutputID,
                padOutputChannel: storedChannel(store.routingSettings.padOutputChannel),
                clickOutputChannel: storedChannel(channel)
            )
        }
    }

    private func storedChannel(_ channel: AudioOutputChannelSelection?) -> AudioOutputChannelSelection? {
        channel == .stereo ? nil : channel
    }
}

#Preview("Audio settings") {
    AudioSettingsView()
        .environment(AppStore.preview())
        .frame(width: 480, height: 420)
}
