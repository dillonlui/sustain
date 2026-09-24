import SwiftUI

/// Fixture composition for reviewing Signal Grid at the minimum Live window size.
/// All content is static: this view neither reads nor changes the session or audio engine.
struct FutureSignalLiveSpecimen: View {
    var warning: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            Rectangle()
                .fill(palette.surfaceEdge.opacity(0.5))
                .frame(width: 1)

            setlist
                .frame(width: 255)

            Rectangle()
                .fill(palette.surfaceEdge.opacity(0.5))
                .frame(width: 1)

            performanceColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1200, height: 700)
        .background(palette.canvas)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SUSTAIN")
                .font(.system(size: 14, weight: .semibold))
                .tracking(5)
                .foregroundStyle(palette.activeSignal)
                .padding(.horizontal, 18)
                .padding(.top, SustainLayout.topChrome + 12)
                .padding(.bottom, 28)

            sidebarItem("Live Service", symbol: "waveform", selected: true)
            sidebarItem("Rehearse", symbol: "metronome")
            sidebarItem("Song Library", symbol: "music.note.list")
            sidebarItem("Pad Library", symbol: "square.grid.2x2")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.performanceSurface.opacity(0.6))
    }

    private func sidebarItem(_ title: String, symbol: String, selected: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
        .padding(.horizontal, 17)
        .frame(height: 43)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.activeSignal.opacity(0.11) : .clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle()
                    .fill(palette.activeSignal)
                    .frame(width: 3)
            }
        }
    }

    private var setlist: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sunday Service")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("4 songs")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 13)
            .padding(.top, SustainLayout.topChrome + 12)
            .padding(.bottom, 16)

            Rectangle()
                .fill(palette.surfaceEdge.opacity(0.45))
                .frame(height: 1)

            VStack(spacing: 3) {
                FutureSignalSetlistRowContent(
                    index: 1,
                    title: "Build My Life",
                    detail: "D · 72 BPM · 4/4",
                    isPlaying: true
                )
                FutureSignalSetlistRowContent(
                    index: 2,
                    title: "Goodness of God",
                    detail: "G · 68 BPM · 4/4",
                    isCued: true,
                    isSelected: true
                )
                FutureSignalSetlistRowContent(index: 3, title: "Holy Forever", detail: "C · 70 BPM · 4/4")
                FutureSignalSetlistRowContent(index: 4, title: "Gratitude", detail: "A · 76 BPM · 4/4")
            }
            .padding(.horizontal, 4)
            .padding(.top, 5)

            Spacer()

            Text("Add Song")
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 15)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.performanceSurface.opacity(0.3))
    }

    private var performanceColumn: some View {
        VStack(spacing: 12) {
            FutureSignalPerformanceSurface(state: warning == nil ? .playing : .warning) {
                VStack(alignment: .leading, spacing: 0) {
                    FutureSignalSongReadout(
                        role: .now,
                        title: "Build My Life",
                        key: "D",
                        bpm: 72,
                        timeSignature: "4/4",
                        clickDescription: "Click: Beat",
                        stateLabel: "Playing"
                    )

                    Rectangle()
                        .fill(palette.surfaceEdge.opacity(0.5))
                        .frame(height: 1)
                        .padding(.vertical, 20)

                    FutureSignalSongReadout(
                        role: .next,
                        title: "Goodness of God",
                        key: "G",
                        bpm: 68,
                        timeSignature: "4/4",
                        clickDescription: "Click: Beat",
                        stateLabel: "Cued"
                    )

                    Spacer(minLength: 14)

                    HStack(alignment: .center, spacing: 18) {
                        FutureSignalOpenChannelStatus(
                            kind: .pad,
                            state: .playing,
                            detail: "C Major · Main Interface (1–2)"
                        )
                        Rectangle()
                            .fill(palette.surfaceEdge.opacity(0.4))
                            .frame(width: 1, height: 42)
                        FutureSignalOpenChannelStatus(
                            kind: .click,
                            state: .playing,
                            detail: "Beat · Monitor Interface (1–2)"
                        )
                    }

                    transport
                        .padding(.top, 22)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 18) {
                FutureSignalChannelLevel(kind: .pad, value: .constant(0.75), isActive: true)
                Rectangle()
                    .fill(palette.surfaceEdge.opacity(0.45))
                    .frame(width: 1, height: 55)
                FutureSignalChannelLevel(kind: .click, value: .constant(0.5), isActive: true)
            }
            .padding(16)
            .background(palette.performanceSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(palette.surfaceEdge.opacity(0.45), lineWidth: 1)
            }

            HStack(spacing: 8) {
                Image(systemName: warning == nil ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(warning == nil ? palette.activeSignal : palette.warning)
                Text(warning ?? "Outputs ready · Pad: Main Interface · Click: Monitor Interface")
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .help(warning ?? "Outputs ready · Pad: Main Interface · Click: Monitor Interface")
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .frame(height: 20)
        }
        .padding(.horizontal, 18)
        .padding(.top, SustainLayout.topChrome + 10)
        .padding(.bottom, 15)
    }

    private var transport: some View {
        HStack(spacing: 10) {
            transportButton("Previous", symbol: "backward.fill")
            transportButton("Transition", symbol: "arrow.triangle.2.circlepath", prominent: true)
            transportButton("Next", symbol: "forward.fill")
            transportButton("Stop", symbol: "stop.fill")
        }
    }

    private func transportButton(_ title: String, symbol: String, prominent: Bool = false) -> some View {
        Button {} label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(prominent ? palette.activeSignal : palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(prominent ? palette.activeSignal.opacity(0.09) : palette.canvas.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(prominent ? palette.activeSignal.opacity(0.8) : palette.surfaceEdge.opacity(0.6), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview("Signal Grid · Live · 1200 × 700") {
    FutureSignalLiveSpecimen()
        .preferredColorScheme(.dark)
}

#Preview("Signal Grid · Live · warning") {
    FutureSignalLiveSpecimen(warning: "Pad and click share the same output; verify routing before service")
        .preferredColorScheme(.dark)
}

#Preview("Signal Grid · Live · light") {
    FutureSignalLiveSpecimen()
        .preferredColorScheme(.light)
}
