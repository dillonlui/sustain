import SwiftUI

enum FutureSignalChannelKind {
    case pad
    case click

    var title: String {
        switch self {
        case .pad: "Pad"
        case .click: "Click"
        }
    }

    var symbol: String {
        switch self {
        case .pad: "square.grid.2x2.fill"
        case .click: "metronome"
        }
    }
}

enum FutureSignalChannelState {
    case off
    case preparing
    case countoff
    case fadingIn
    case playing
    case fadingOut
    case unavailable

    var label: String {
        switch self {
        case .off: "Off"
        case .preparing: "Preparing"
        case .countoff: "Count in"
        case .fadingIn: "Fading In"
        case .playing: "Playing"
        case .fadingOut: "Fading Out"
        case .unavailable: "Unavailable"
        }
    }

    var isAudible: Bool {
        switch self {
        case .countoff, .fadingIn, .playing, .fadingOut: true
        default: false
        }
    }
}

/// Open status for use inside the performance frame. `detail` carries the real route,
/// audible pad owner, or pending click setting supplied by the caller.
struct FutureSignalOpenChannelStatus: View {
    var kind: FutureSignalChannelKind
    var state: FutureSignalChannelState
    var detail: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var signalColor: Color {
        if state == .unavailable { return palette.blocked }
        if state.isAudible || state == .preparing { return palette.activeSignal }
        return palette.textSecondary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: state == .unavailable ? "exclamationmark.triangle" : kind.symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(signalColor)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(kind.title) \(state.label)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state.isAudible ? palette.textPrimary : signalColor)
                    .lineLimit(1)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(detail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A configured volume setting. The native slider retains keyboard and VoiceOver behavior.
/// Its value is never presented as a measured output level.
struct FutureSignalChannelLevel: View {
    var kind: FutureSignalChannelKind
    @Binding var value: Double
    var isActive: Bool
    var isEnabled: Bool = true
    var onCommit: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var percent: Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(kind.title) volume setting")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)

                Spacer(minLength: 8)

                Text("\(percent)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
                    .accessibilityHidden(true)
            }

            Slider(value: $value, in: 0...1) { editing in
                if !editing { onCommit() }
            }
            .tint(isActive ? palette.activeSignal : palette.textSecondary)
            .disabled(!isEnabled)
            .accessibilityLabel("\(kind.title) volume setting")
            .accessibilityValue("\(percent) percent")
        }
    }
}

#Preview("Open channels · dark") {
    VStack(alignment: .leading, spacing: 28) {
        FutureSignalOpenChannelStatus(kind: .pad, state: .playing, detail: "Warm Atmosphere · Main L/R")
        FutureSignalOpenChannelStatus(kind: .click, state: .countoff, detail: "Beat 2 of 4 · Click Out")
        FutureSignalOpenChannelStatus(kind: .pad, state: .fadingIn, detail: "Warm Atmosphere · Main L/R")
        FutureSignalOpenChannelStatus(kind: .pad, state: .fadingOut, detail: "Previous song: Build My Life")
        FutureSignalOpenChannelStatus(kind: .click, state: .unavailable, detail: "Click output missing")
        FutureSignalChannelLevel(kind: .pad, value: .constant(0), isActive: false)
        FutureSignalChannelLevel(kind: .click, value: .constant(1), isActive: true, isEnabled: false)
    }
    .padding(24)
    .frame(width: 420)
    .background(FutureSignalColor(colorScheme: .dark, contrast: .standard).performanceSurface)
    .preferredColorScheme(.dark)
}

#Preview("Open channels · light") {
    VStack(alignment: .leading, spacing: 28) {
        FutureSignalOpenChannelStatus(kind: .pad, state: .off, detail: "Next start: Warm Atmosphere")
        FutureSignalOpenChannelStatus(kind: .click, state: .preparing, detail: "Quarter notes · 72 BPM")
        FutureSignalChannelLevel(kind: .pad, value: .constant(0.75), isActive: true)
        FutureSignalChannelLevel(kind: .click, value: .constant(0.5), isActive: false)
    }
    .padding(24)
    .frame(width: 420)
    .background(FutureSignalColor(colorScheme: .light, contrast: .standard).performanceSurface)
    .preferredColorScheme(.light)
}
