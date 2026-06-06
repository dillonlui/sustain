import SwiftUI

struct RehearseView: View {
    @EnvironmentObject private var store: AppStore

    private let tempoRange = 40...220

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(alignment: .top, spacing: 24) {
                padPanel
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)

                clickPanel
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Rehearse")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rehearse")
                    .font(.largeTitle.weight(.semibold))
                Text("Free play pads and click")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(store.audioStatus)
                    .font(.callout.weight(.medium))
                Text(store.routingSnapshot.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var padPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(title: "Pads", value: store.rehearse.padState.rawValue, image: "waveform")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                ForEach(MusicalKey.allCases) { key in
                    Button {
                        store.startRehearsePad(key: key)
                    } label: {
                        VStack(spacing: 5) {
                            Text(key.rawValue)
                                .font(.title3.weight(.semibold))
                            Text(store.rehearse.selectedKey == key && store.rehearse.padState == .playing ? "Playing" : "Pad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(.bordered)
                    .tint(store.rehearse.selectedKey == key && store.rehearse.padState == .playing ? Color.sustainSage : nil)
                }
            }

            Button(role: .destructive) {
                store.stopRehearsePad()
            } label: {
                Label("Stop Pad", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(store.rehearse.padState == .off)

            messageStrip
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var clickPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(title: "Click", value: store.rehearse.clickState.rawValue, image: "metronome")

            HStack(alignment: .center, spacing: 18) {
                Button {
                    if store.rehearse.clickState == .off {
                        store.startRehearseClick()
                    } else {
                        store.stopRehearseClick()
                    }
                } label: {
                    Label(
                        store.rehearse.clickState == .off ? "Play Click" : "Pause Click",
                        systemImage: store.rehearse.clickState == .off ? "play.fill" : "pause.fill"
                    )
                    .frame(minWidth: 148)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Toggle("Countoff", isOn: countoffBinding)
                    .toggleStyle(.switch)

                Picker("Time", selection: timeSignatureBinding) {
                    Text("4/4").tag(TimeSignature.fourFour)
                    Text("6/8").tag(TimeSignature.sixEight)
                }
                .pickerStyle(.segmented)
                .frame(width: 148)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("\(store.rehearse.bpm)")
                        .font(.system(size: 84, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 150, alignment: .leading)

                    Text("BPM")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Stepper("Tempo", value: bpmBinding, in: tempoRange, step: 1)
                        .labelsHidden()
                }

                Slider(value: bpmSliderBinding, in: Double(tempoRange.lowerBound)...Double(tempoRange.upperBound), step: 1)

                HStack {
                    Text("\(tempoRange.lowerBound)")
                    Spacer()
                    Text("Drag or step to update live")
                    Spacer()
                    Text("\(tempoRange.upperBound)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                RehearseStateTile(label: "Pad", value: activePadText, systemImage: "waveform")
                RehearseStateTile(label: "Click", value: clickText, systemImage: "metronome")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var messageStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.sustainSage)
            Text(store.rehearse.lastMessage)
                .font(.callout)
            Spacer()
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(title: String, value: String, image: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: image)
                .foregroundStyle(Color.sustainSage)
            Text(title)
                .font(.title2.weight(.semibold))
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var activePadText: String {
        store.rehearse.padState == .off ? "Off" : "\(store.rehearse.selectedKey.rawValue) \(store.rehearse.padState.rawValue)"
    }

    private var clickText: String {
        "\(store.rehearse.bpm) BPM \(store.rehearse.timeSignature.description)"
    }

    private var bpmBinding: Binding<Int> {
        Binding {
            store.rehearse.bpm
        } set: { bpm in
            store.setRehearseBPM(bpm)
        }
    }

    private var bpmSliderBinding: Binding<Double> {
        Binding {
            Double(store.rehearse.bpm)
        } set: { bpm in
            store.setRehearseBPM(Int(bpm.rounded()))
        }
    }

    private var countoffBinding: Binding<Bool> {
        Binding {
            store.rehearse.countoffEnabled
        } set: { isEnabled in
            store.setRehearseCountoffEnabled(isEnabled)
        }
    }

    private var timeSignatureBinding: Binding<TimeSignature> {
        Binding {
            store.rehearse.timeSignature
        } set: { timeSignature in
            store.setRehearseTimeSignature(timeSignature)
        }
    }
}

private struct RehearseStateTile: View {
    var label: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.sustainSage)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
