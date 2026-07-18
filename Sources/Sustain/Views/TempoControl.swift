import SwiftUI

/// A compact tempo editor shared by Library and Live: direct typing plus precise stepper arrows.
struct TempoControl: View {
    @Binding var value: Int
    var label = "Tempo"
    var range = 40...220

    @State private var draft = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            if !label.isEmpty {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer(minLength: SustainSpace.md)
            }

            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .focused($textFieldFocused)
                .accessibilityLabel("Tempo")
                .onSubmit { commitDraft() }
                .onChange(of: textFieldFocused) { _, isFocused in
                    if !isFocused { commitDraft() }
                }

            Text("BPM")
                .font(.callout)
                .foregroundStyle(.secondary)

            Stepper("Adjust tempo", value: stepperBinding, in: range)
                .labelsHidden()
                .accessibilityLabel("Adjust tempo")
                .accessibilityValue("\(value) beats per minute")
        }
        .onAppear { syncFromValue() }
        .onChange(of: value) { _, _ in
            if !textFieldFocused {
                syncFromValue()
            }
        }
    }

    private var stepperBinding: Binding<Int> {
        Binding {
            value
        } set: { newValue in
            commit(newValue)
        }
    }

    private func commitDraft() {
        guard let candidate = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            syncFromValue()
            return
        }
        commit(candidate)
    }

    private func commit(_ candidate: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, candidate))
        if clamped != value {
            value = clamped
        }
        // The binding may reject a live audio change. Always reflect the authoritative value.
        syncFromValue()
    }

    private func syncFromValue() {
        draft = String(value)
    }
}
