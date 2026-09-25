import SwiftUI

/// Visual content for a native setlist row. The caller owns selection, cue actions,
/// editing, and the source of playback identity; none are inferred from the title.
struct FutureSignalSetlistRowContent: View {
    var index: Int
    var title: String
    var detail: String?
    var isPlaying: Bool = false
    var isCued: Bool = false
    var isSelected: Bool = false
    var isMissing: Bool = false
    var showsContainer = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        HStack(alignment: .center, spacing: SustainSpace.md) {
            Text("\(index)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: SustainSpace.xxs) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isMissing ? palette.warning : palette.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(title)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .help(detail)
                }
            }
        }
        .padding(.leading, SustainSpace.xs)
        .padding(.trailing, SustainSpace.sm)
        .padding(.vertical, SustainSpace.sm)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background {
            if showsContainer {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPlaying ? palette.activeSignal.opacity(0.08) :
                            isSelected ? palette.surfaceEdge.opacity(0.16) : .clear)
            }
        }
        .overlay {
            if showsContainer && isCued {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.cuedEdge.opacity(contrast == .increased ? 1 : 0.72), lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            if isPlaying {
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.activeSignal)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index), \(title)\(detail.map { ", \($0)" } ?? "")")
        .accessibilityValue(accessibilityState)
    }

    private var accessibilityState: String {
        var states: [String] = []
        if isPlaying { states.append("Playing") }
        if isCued { states.append("Cued") }
        if isSelected { states.append("Selected") }
        if isMissing { states.append("Missing song") }
        return states.isEmpty ? "Not playing or cued" : states.joined(separator: ", ")
    }
}

#Preview("Signal Grid · setlist states") {
    VStack(spacing: 8) {
        FutureSignalSetlistRowContent(index: 1, title: "Build My Life", detail: "D · 72 BPM · 4/4")
        FutureSignalSetlistRowContent(index: 2, title: "Goodness of God", detail: "G · 68 BPM · 4/4", isCued: true)
        FutureSignalSetlistRowContent(index: 3, title: "Holy Forever", detail: "C · 70 BPM · 4/4", isPlaying: true)
        FutureSignalSetlistRowContent(index: 4, title: "Gratitude", detail: "A · 76 BPM · 4/4", isPlaying: true, isCued: true, isSelected: true)
        FutureSignalSetlistRowContent(index: 5, title: "A Very Long Song Title That Should Remain Legible and Accessible", detail: "E♭ · 120 BPM · 6/8", isSelected: true)
        FutureSignalSetlistRowContent(index: 6, title: "Missing song", isMissing: true)
    }
    .frame(width: 340)
    .padding()
    .background(FutureSignalColor(colorScheme: .dark, contrast: .standard).canvas)
    .preferredColorScheme(.dark)
}

#Preview("Signal Grid · setlist light") {
    VStack(spacing: 8) {
        FutureSignalSetlistRowContent(index: 1, title: "Build My Life", detail: "D · 72 BPM · 4/4", isPlaying: true)
        FutureSignalSetlistRowContent(index: 2, title: "Goodness of God", detail: "G · 68 BPM · 4/4", isCued: true)
        FutureSignalSetlistRowContent(index: 3, title: "Holy Forever", detail: "C · 70 BPM · 4/4", isPlaying: true, isCued: true)
    }
    .frame(width: 340)
    .padding()
    .background(FutureSignalColor(colorScheme: .light, contrast: .standard).canvas)
    .preferredColorScheme(.light)
}
