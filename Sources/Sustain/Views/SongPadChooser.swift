import SwiftUI

/// The shared pad assignment picker used by Song Library and the Live editor.
/// Selection is committed only when a row is chosen; Cancel leaves the assignment alone.
struct SongPadChooser: View {
    let selectedPadID: PadTrack.ID?
    let padTracks: [PadTrack]
    let assetStates: [PadTrack.ID: PadAssetState]
    let onSelect: (PadTrack.ID?) -> Void

    init(
        selectedPadID: PadTrack.ID?,
        padTracks: [PadTrack],
        assetStates: [PadTrack.ID: PadAssetState],
        onSelect: @escaping (PadTrack.ID?) -> Void
    ) {
        self.selectedPadID = selectedPadID
        self.padTracks = padTracks
        self.assetStates = assetStates
        self.onSelect = onSelect
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var searchText = ""
    @State private var isManagingPads = false

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var matchingPads: [PadTrack] {
        guard !searchText.isEmpty else { return padTracks }
        return padTracks.filter { $0.label.localizedStandardContains(searchText) }
    }

    private var customPads: [PadTrack] { matchingPads.filter { !$0.isIncluded } }
    private var includedPads: [PadTrack] { matchingPads.filter(\.isIncluded) }

    private var hasUnavailablePads: Bool {
        padTracks.contains { !$0.isIncluded && !isAvailable($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SustainSpace.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    Text("Choose Pad")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Choose the audio this song will play.")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: SustainSpace.md)
                Button("Cancel") { dismiss() }
                    .accessibilityHint("Keep the current pad assignment")
            }

            TextField("Search pads", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search pads")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: SustainSpace.sm) {
                    noPadRow
                    Divider().padding(.vertical, SustainSpace.xs)

                    if !customPads.isEmpty {
                        sectionHeader("Custom Pads")
                        ForEach(customPads) { pad in padRow(pad) }
                    }

                    if !includedPads.isEmpty {
                        sectionHeader("Included Pads")
                            .padding(.top, customPads.isEmpty ? 0 : SustainSpace.md)
                        ForEach(includedPads) { pad in padRow(pad) }
                    }

                    if matchingPads.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, SustainSpace.xl)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if selectedPadID != nil && !padTracks.contains(where: { $0.id == selectedPadID }) {
                Label("The assigned pad is no longer in the library. Choose another pad or No Pad.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(palette.warning)
                    .font(.subheadline)
            }
            if hasUnavailablePads ||
                (selectedPadID != nil && !padTracks.contains(where: { $0.id == selectedPadID })) {
                Button("Open Pad Library…", systemImage: "waveform.badge.plus") {
                    isManagingPads = true
                }
                .help("Locate or replace unavailable pad audio")
            }
        }
        .padding(SustainSpace.xl)
        .frame(minWidth: 320, idealWidth: 480, maxWidth: 620, minHeight: 340, idealHeight: 520)
        .background(palette.canvas)
        .sheet(isPresented: $isManagingPads) {
            PadLibraryView()
                .frame(minWidth: 600, minHeight: 550)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, SustainSpace.sm)
            .accessibilityAddTraits(.isHeader)
    }

    private var noPadRow: some View {
        chooserRow(
            title: "No Pad",
            status: "Click and countoff only",
            isSelected: selectedPadID == nil,
            isEnabled: true,
            accessibilityName: "No Pad"
        ) {
            onSelect(nil)
            dismiss()
        }
    }

    private func padRow(_ pad: PadTrack) -> some View {
        let status = statusLabel(for: pad)
        return chooserRow(
            title: pad.label,
            status: status,
            isSelected: selectedPadID == pad.id,
            isEnabled: isAvailable(pad),
            accessibilityName: "\(pad.label), \(pad.isIncluded ? "included pad" : "custom pad")"
        ) {
            onSelect(pad.id)
            dismiss()
        }
    }

    private func chooserRow(
        title: String,
        status: String?,
        isSelected: Bool,
        isEnabled: Bool,
        accessibilityName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SustainSpace.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? palette.activeSignal : palette.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    Text(title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(palette.textPrimary)
                    if let status {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(isEnabled ? palette.textSecondary : palette.warning)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SustainSpace.md)
            .padding(.vertical, SustainSpace.sm)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(isSelected ? palette.activeSignal.opacity(0.13) : palette.panel,
                        in: RoundedRectangle(cornerRadius: FutureSignalEffects.surfaceRadius))
            .overlay {
                RoundedRectangle(cornerRadius: FutureSignalEffects.surfaceRadius)
                    .stroke(isSelected ? palette.activeSignal : palette.surfaceEdge.opacity(0.55), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(isSelected ? "Selected" : "Not selected"), \(status ?? "Available")")
        .accessibilityHint(isEnabled ? "Assign this pad to the song" : "Open Pad Library to restore this audio")
    }

    private func isAvailable(_ pad: PadTrack) -> Bool {
        pad.isIncluded || (assetStates[pad.id]?.isAvailable ?? true)
    }

    private func statusLabel(for pad: PadTrack) -> String? {
        guard !pad.isIncluded, let state = assetStates[pad.id] else { return nil }
        switch state {
        case .available: return nil
        case .preparing: return "Checking audio"
        case .externalVolumeUnavailable: return "Volume unavailable"
        case .permissionDenied: return "Permission needed"
        case .missing: return "Audio missing"
        case .changed: return "File changed"
        case .unsupportedOrProtected: return "Unsupported audio"
        case .unreadable: return "Unreadable audio"
        }
    }
}
