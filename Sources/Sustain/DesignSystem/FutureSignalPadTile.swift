import SwiftUI

/// A selectable pad with distinct selection and playback identity. Availability
/// remains a separate fact so an unavailable pad never appears to be playing.
struct FutureSignalPadTile: View {
    var title: String
    var detail: String
    var isSelected = false
    var isPlaying = false
    var isAvailable = true
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var stateText: String {
        if !isAvailable { return detail }
        if isPlaying { return detail.isEmpty ? "Playing" : "Playing · \(detail)" }
        if isSelected { return detail.isEmpty ? "Selected" : "Selected · \(detail)" }
        return detail
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: SustainSpace.xs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !stateText.isEmpty {
                    Text(stateText)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(isPlaying ? palette.activeSignal : palette.textSecondary)
                }
            }
            .foregroundStyle(isAvailable ? palette.textPrimary : palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, SustainSpace.xs)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPlaying ? palette.activeSignal.opacity(0.12) :
                            isSelected ? palette.activeSignal.opacity(0.06) : palette.performanceSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isPlaying ? palette.activeSignal :
                            isSelected ? palette.cuedEdge : palette.surfaceEdge.opacity(0.5),
                        lineWidth: isPlaying && contrast == .increased ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(title)
        .accessibilityValue(stateText)
        .help("\(title). \(stateText)")
    }
}

#Preview("Signal Grid · pad tile states") {
    HStack(spacing: 8) {
        FutureSignalPadTile(title: "C", detail: "Included", isSelected: true, isPlaying: true) {}
        FutureSignalPadTile(title: "G", detail: "Included", isSelected: true) {}
        FutureSignalPadTile(title: "Warm Atmosphere — Extended Mix", detail: "Custom") {}
        FutureSignalPadTile(title: "Missing Audio", detail: "Missing", isAvailable: false) {}
    }
    .padding()
    .frame(width: 600)
    .background(FutureSignalColor(colorScheme: .dark, contrast: .standard).canvas)
    .preferredColorScheme(.dark)
}
