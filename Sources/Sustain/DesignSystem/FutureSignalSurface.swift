import SwiftUI

enum FutureSignalSurfaceState {
    case idle
    case cued
    case preparing
    case countoff
    case playing
    case transition
    case warning
    case blocked
}

/// The stable performance canvas. Its subtle green light is tied to state rather than
/// animation; content remains opaque and can contain native controls and accessibility text.
struct FutureSignalPerformanceSurface<Content: View>: View {
    var state: FutureSignalSurfaceState = .idle
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(state: FutureSignalSurfaceState = .idle, @ViewBuilder content: () -> Content) {
        self.state = state
        self.content = content()
    }

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var stateColor: Color {
        switch state {
        case .idle: palette.surfaceEdge
        case .cued: palette.cuedEdge
        case .preparing, .countoff, .playing, .transition: palette.activeSignal
        case .warning: palette.warning
        case .blocked: palette.blocked
        }
    }

    private var isLit: Bool {
        switch state {
        case .preparing, .countoff, .playing, .transition: true
        default: false
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FutureSignalEffects.surfaceRadius, style: .continuous)

        content
            .padding(FutureSignalEffects.surfacePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                shape.fill(palette.performanceSurface)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    stateColor.opacity(contrast == .increased ? 0 : (isLit ? 0.06 : 0.03)),
                                    .clear,
                                    palette.canvas.opacity(contrast == .increased ? 0 : 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(
                    stateColor.opacity(contrast == .increased ? 0.9 : 0.47),
                    lineWidth: FutureSignalEffects.edgeWidth
                )
            }
            .overlay {
                FutureSignalCornerMarks()
                    .stroke(
                        stateColor.opacity(contrast == .increased ? 1 : 0.86),
                        style: StrokeStyle(lineWidth: FutureSignalEffects.cornerWidth, lineCap: .square)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .shadow(
                color: isLit && contrast != .increased
                    ? stateColor.opacity(FutureSignalEffects.activeGlowOpacity)
                    : .clear,
                radius: contrast == .increased ? 0 : FutureSignalEffects.activeGlowRadius
            )
    }
}

private struct FutureSignalCornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = FutureSignalEffects.cornerInset
        let length = FutureSignalEffects.cornerLength
        let left = rect.minX + inset
        let right = rect.maxX - inset
        let top = rect.minY + inset
        let bottom = rect.maxY - inset

        var path = Path()
        path.move(to: CGPoint(x: left, y: top + length))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left + length, y: top))
        path.move(to: CGPoint(x: right - length, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: top + length))
        path.move(to: CGPoint(x: left, y: bottom - length))
        path.addLine(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left + length, y: bottom))
        path.move(to: CGPoint(x: right - length, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: bottom - length))
        return path
    }
}

#Preview("Signal Grid · dark") {
    FutureSignalPerformanceSurface(state: .playing) {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOW").font(.caption).tracking(4)
            Text("Build My Life").font(.largeTitle.bold())
            Text("D • 72 BPM").font(.title3)
        }
    }
    .frame(width: 580, height: 340)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Signal Grid · light") {
    FutureSignalPerformanceSurface(state: .playing) {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOW").font(.caption).tracking(4)
            Text("Build My Life").font(.largeTitle.bold())
            Text("D • 72 BPM").font(.title3)
        }
    }
    .frame(width: 580, height: 340)
    .padding()
    .preferredColorScheme(.light)
}
