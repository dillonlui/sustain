import SwiftUI

enum FutureSignalTransportRole {
    case secondary
    case primary
    case stop
    case destructive
}

/// Visual treatment only. Buttons keep their action, keyboard shortcut, disabled state,
/// focus behavior, and caller-defined width/height.
struct FutureSignalTransportStyle: ButtonStyle {
    var role: FutureSignalTransportRole = .secondary

    func makeBody(configuration: Configuration) -> some View {
        Face(label: configuration.label, role: role, isPressed: configuration.isPressed)
    }

    private struct Face<Label: View>: View {
        let label: Label
        let role: FutureSignalTransportRole
        let isPressed: Bool

        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var palette: FutureSignalColor {
            FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
        }

        private var isPrimary: Bool { role == .primary }
        private var isDestructive: Bool { role == .destructive }

        private var tint: Color {
            switch role {
            case .secondary: palette.surfaceEdge
            case .primary: palette.activeSignal
            case .stop, .destructive: palette.blocked
            }
        }

        private var fill: Color {
            if isPrimary {
                return palette.activeSignal.opacity(isPressed ? 0.24 : (isHovered ? 0.18 : 0.11))
            }
            if isDestructive {
                return palette.blocked.opacity(isPressed ? 0.22 : (isHovered ? 0.14 : 0.06))
            }
            if role == .stop && isHovered {
                return palette.blocked.opacity(isPressed ? 0.16 : 0.08)
            }
            return palette.textPrimary.opacity(isPressed ? 0.09 : (isHovered ? 0.05 : 0.02))
        }

        private var edge: Color {
            if !isEnabled { return palette.surfaceEdge }
            if isPrimary { return palette.activeSignal }
            if isDestructive || (role == .stop && isHovered) { return palette.blocked }
            return isHovered ? palette.textSecondary : palette.surfaceEdge
        }

        private var foreground: Color {
            if !isEnabled { return palette.textSecondary }
            if isPrimary { return palette.activeSignal }
            if isDestructive || (role == .stop && isHovered) { return palette.blocked }
            return palette.textPrimary
        }

        var body: some View {
            label
                .font(.system(size: 14, weight: isPrimary ? .semibold : .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            edge.opacity(contrast == .increased ? 1 : (isPrimary || isHovered ? 0.8 : 0.48)),
                            lineWidth: contrast == .increased ? 2 : 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(isEnabled ? 1 : 0.6)
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: isPressed)
        }
    }
}

#Preview("Transport · dark") {
    HStack(spacing: 12) {
        Button("Previous", systemImage: "backward.end.fill") {}
            .buttonStyle(FutureSignalTransportStyle(role: .secondary))
        Button("Transition", systemImage: "arrow.right") {}
            .buttonStyle(FutureSignalTransportStyle(role: .primary))
        Button("Next", systemImage: "forward.end.fill") {}
            .buttonStyle(FutureSignalTransportStyle(role: .secondary))
        Button("Stop", systemImage: "stop.fill") {}
            .buttonStyle(FutureSignalTransportStyle(role: .stop))
    }
    .frame(height: 68)
    .padding(24)
    .background(FutureSignalColor(colorScheme: .dark, contrast: .standard).performanceSurface)
    .preferredColorScheme(.dark)
}

#Preview("Transport · light") {
    HStack(spacing: 12) {
        Button("Previous", systemImage: "backward.end.fill") {}
            .buttonStyle(FutureSignalTransportStyle(role: .secondary))
        Button("Start", systemImage: "play.fill") {}
            .buttonStyle(FutureSignalTransportStyle(role: .primary))
        Button("Next", systemImage: "forward.end.fill") {}
            .buttonStyle(FutureSignalTransportStyle(role: .secondary))
        Button("Stop", systemImage: "stop.fill") {}
            .buttonStyle(FutureSignalTransportStyle(role: .stop))
    }
    .frame(height: 68)
    .padding(24)
    .background(FutureSignalColor(colorScheme: .light, contrast: .standard).performanceSurface)
    .preferredColorScheme(.light)
}
