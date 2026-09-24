import SwiftUI

/// A playback-identity mark for a setlist entry. It is deliberately unrelated to
/// volume or measured signal level.
struct FutureSignalPlayingGlyph: View {
    var isPlaying: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        Group {
            if isPlaying && !reduceMotion {
                PhaseAnimator([false, true]) { phase in
                    mark
                        .opacity(phase ? 0.76 : 1)
                        .scaleEffect(phase ? 0.94 : 1)
                } animation: { _ in
                    .easeInOut(duration: 0.85)
                }
            } else {
                mark
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private var mark: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.activeSignal)
    }
}

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
                .frame(width: 24, alignment: .trailing)

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
                if isPlaying || isCued {
                    HStack(spacing: SustainSpace.xs) {
                        if isPlaying {
                            FutureSignalPlayingGlyph(isPlaying: true)
                        }
                        Text(statusText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isPlaying ? palette.activeSignal : palette.cuedEdge)
                            .lineLimit(1)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, SustainSpace.sm)
        .padding(.vertical, SustainSpace.sm)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPlaying ? palette.activeSignal.opacity(0.08) :
                        isSelected ? palette.surfaceEdge.opacity(0.16) : .clear)
        }
        .overlay {
            if isCued {
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

    private var statusText: String {
        if isPlaying && isCued { return "Playing · Cued" }
        return isPlaying ? "Playing" : "Cued"
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
