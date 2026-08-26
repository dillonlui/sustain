import Accessibility
import SwiftUI

struct MIDIControllerSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var useAnyController = false

    var body: some View {
        Form {
            Section("MIDI Controller") {
                Toggle("Enable MIDI Controller", isOn: enabledBinding)
                    .accessibilityHint("Allows learned Note On and Control Change messages to control performance actions.")
                Picker("Listen to", selection: sourceBinding) {
                    Text("Any connected controller").tag(MIDIControllerSelection.any)
                    ForEach(store.midiAvailableSources) { source in
                        Text(source.name).tag(MIDIControllerSelection.source(uniqueID: source.uniqueID))
                    }
                }
                .disabled(!store.midiControllerSettings.isEnabled)
                LabeledContent("Status", value: serviceStatus)
                    .foregroundStyle(serviceHasError ? SustainColor.warning : .primary)
                if selectedSourceIsMissing {
                    Text("The selected controller is disconnected. Reconnect that exact device or choose another source; display names are not used as identity.")
                        .font(.footnote)
                        .foregroundStyle(SustainColor.warning)
                }
            }

            Section("Mappings") {
                ForEach(MIDIAction.allCases) { action in
                    mappingRow(action)
                }
            }

            learnSection

            Section("Troubleshooting") {
                Text("Sustain accepts MIDI Note On and Control Change messages. If a pedal is missing, confirm it appears and sends MIDI in Audio MIDI Setup; HID keyboard pedals are not MIDI controllers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .onChange(of: store.midiLearnState) { _, state in
            useAnyController = false
            AccessibilityNotification.Announcement(learnAnnouncement(state)).post()
        }
    }

    @ViewBuilder
    private func mappingRow(_ action: MIDIAction) -> some View {
        HStack(spacing: SustainSpace.md) {
            VStack(alignment: .leading, spacing: SustainSpace.xxs) {
                Text(action.title)
                    .foregroundStyle(action == .stopAll ? SustainColor.destructive : .primary)
                Text(mappingSummary(action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Learn") { store.beginMIDILearn(for: action) }
                .disabled(!store.midiControllerSettings.isEnabled)
                .accessibilityLabel("Learn MIDI mapping for \(action.title)")
            Button("Clear") { store.clearMIDIMapping(for: action) }
                .disabled(store.midiMapping(for: action) == nil)
                .accessibilityLabel("Clear MIDI mapping for \(action.title)")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var learnSection: some View {
        switch store.midiLearnState {
        case .idle:
            EmptyView()
        case let .listening(action):
            Section("Learning \(action.title)") {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Press the desired pedal or controller. Waiting for Note On or nonzero CC\u{2026}")
                }
                .accessibilityElement(children: .combine)
                Button("Cancel Learn") { store.cancelMIDILearn() }
                    .keyboardShortcut(.cancelAction)
            }
        case let .preview(candidate):
            Section("Confirm Mapping") {
                LabeledContent("Action", value: candidate.action.title)
                LabeledContent("Message", value: candidate.event.identity.displayName)
                LabeledContent("Controller", value: candidate.source.name)
                Toggle("Allow this message from any controller", isOn: $useAnyController)
                Text("Mappings lock to the learned controller by default. Any controller is an explicit opt-in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { store.cancelMIDILearn() }
                    Button("Save Mapping") { _ = store.commitMIDILearn(useAnyController: useAnyController) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        case let .duplicate(candidate, existingAction):
            Section("Mapping Already Used") {
                Text("\(candidate.event.identity.displayName) from \(candidate.source.name) is already assigned to \(existingAction.title). Clear that mapping or learn another message.")
                    .foregroundStyle(SustainColor.warning)
                HStack {
                    Button("Cancel") { store.cancelMIDILearn() }
                    Button("Try Again") { store.beginMIDILearn(for: candidate.action) }
                }
            }
        case let .timedOut(action):
            Section("Learn Timed Out") {
                Text("No supported MIDI message was received. Check the controller in Audio MIDI Setup and try again.")
                    .foregroundStyle(SustainColor.warning)
                HStack {
                    Button("Cancel") { store.cancelMIDILearn() }
                    Button("Try Again") { store.beginMIDILearn(for: action) }
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding { store.midiControllerSettings.isEnabled } set: { store.setMIDIEnabled($0) }
    }

    private var sourceBinding: Binding<MIDIControllerSelection> {
        Binding { store.midiControllerSettings.selectedSource } set: { store.setMIDISelectedSource($0) }
    }

    private var serviceHasError: Bool {
        if case .failed = store.midiServiceState { return true }
        return false
    }

    private var serviceStatus: String {
        guard store.midiControllerSettings.isEnabled else { return "Disabled" }
        return switch store.midiServiceState {
        case .stopped: "Stopped"
        case .running:
            store.midiAvailableSources.isEmpty ? "Listening — no controllers found" : "Listening — \(store.midiAvailableSources.count) connected"
        case let .failed(message): message
        }
    }

    private func learnAnnouncement(_ state: MIDILearnState) -> String {
        switch state {
        case .idle: "MIDI Learn closed"
        case let .listening(action): "Listening for \(action.title)"
        case let .preview(candidate): "Received \(candidate.event.identity.displayName) from \(candidate.source.name)"
        case let .duplicate(_, existingAction): "MIDI message is already assigned to \(existingAction.title)"
        case .timedOut: "MIDI Learn timed out"
        }
    }

    private var selectedSourceIsMissing: Bool {
        guard case let .source(uniqueID) = store.midiControllerSettings.selectedSource else { return false }
        return !store.midiAvailableSources.contains { $0.uniqueID == uniqueID }
    }

    private func mappingSummary(_ action: MIDIAction) -> String {
        guard let mapping = store.midiMapping(for: action) else { return "Not mapped" }
        let source: String
        switch mapping.source {
        case .any: source = "Any controller"
        case let .source(uniqueID):
            source = store.midiAvailableSources.first(where: { $0.uniqueID == uniqueID })?.name ?? "Controller \(uniqueID) (disconnected)"
        }
        return "\(mapping.message.displayName) \u{2022} \(source)"
    }
}

#Preview("MIDI Controller Settings") {
    MIDIControllerSettingsView()
        .environment(AppStore.preview())
}
