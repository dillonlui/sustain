import SwiftUI

enum SustainColor {
    static let background = Color.sustainNearBlack
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let panel = Color.sustainCharcoal.opacity(0.74)
    static let panelElevated = Color.sustainDeepOlive.opacity(0.82)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.74)
    static let accent = Color.sustainSage
    static let accentSoft = Color.sustainSage.opacity(0.18)
    static let padActive = Color.sustainSage
    static let clickActive = Color.sustainMutedGold
    static let ready = Color.sustainSage
    static let warning = Color.orange
    static let destructive = Color.red
    static let separator = Color.sustainIvory.opacity(0.10)
    static let focusRing = Color.sustainSage.opacity(0.55)
    static let glassFill = Color.sustainIvory.opacity(0.055)
    static let glassTint = Color.sustainDeepOlive.opacity(0.30)
    static let glassHighlight = Color.sustainIvory.opacity(0.20)
    static let glassShadow = Color.sustainNearBlack.opacity(0.22)
}

enum SustainSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let screen: CGFloat = 28
    static let section: CGFloat = 36
}

enum SustainRadius {
    static let panel: CGFloat = 8
    static let elevated: CGFloat = 10
    static let control: CGFloat = 7
    static let capsule: CGFloat = 999
}

enum SustainType {
    static let display = Font.system(size: 48, weight: .semibold, design: .rounded)
    static let metric = Font.system(.title, design: .rounded, weight: .semibold)
    static let panelTitle = Font.title2.weight(.semibold)
    static let label = Font.caption.weight(.medium)
}

struct SustainPanel<Content: View>: View {
    var material: Material? = nil
    var isActive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(SustainSpace.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(panelBackground)
            .overlay(panelSheen)
            .overlay(panelStroke)
            .clipShape(RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
            .shadow(color: SustainColor.glassShadow, radius: isActive ? 20 : 12, y: isActive ? 10 : 6)
    }

    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
        ZStack {
            if let material {
                shape.fill(material)
            } else {
                shape.fill(SustainColor.panel)
            }

            shape.fill(
                LinearGradient(
                    colors: [
                        SustainColor.glassFill,
                        SustainColor.glassTint,
                        SustainColor.panelElevated.opacity(isActive ? 0.38 : 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var panelSheen: some View {
        RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        SustainColor.glassHighlight,
                        SustainColor.separator,
                        (isActive ? SustainColor.accent : SustainColor.separator).opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .blendMode(.plusLighter)
    }

    private var panelStroke: some View {
        RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
            .stroke(isActive ? SustainColor.focusRing : SustainColor.separator, lineWidth: isActive ? 1.2 : 1)
    }
}

struct SustainAppBackground: View {
    var mood: SustainBackgroundMood = .standard

    var body: some View {
        ZStack {
            SustainColor.background

            LinearGradient(
                colors: [
                    Color.sustainDeepOlive.opacity(0.42),
                    Color.sustainNearBlack.opacity(0.84),
                    Color.sustainCharcoal.opacity(0.46)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    mood.primaryGlow.opacity(0.32),
                    mood.secondaryGlow.opacity(0.14),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 60,
                endRadius: 620
            )
            .blur(radius: 28)

            RadialGradient(
                colors: [
                    mood.secondaryGlow.opacity(0.20),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 90,
                endRadius: 560
            )
            .blur(radius: 36)

            VStack {
                Spacer()
                TopographicFieldView(
                    tint: mood.contourTint,
                    animated: mood.isAnimated
                )
                .frame(height: mood.contourHeight)
                .opacity(mood.contourOpacity)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.45), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .ignoresSafeArea()
    }
}

enum SustainBackgroundMood {
    case standard
    case live
    case rehearse
    case audio
    case system

    var primaryGlow: Color {
        switch self {
        case .live: SustainColor.padActive
        case .rehearse: SustainColor.clickActive
        case .audio: SustainColor.accent
        case .system: SustainColor.ready
        case .standard: Color.sustainMoss
        }
    }

    var secondaryGlow: Color {
        switch self {
        case .live: Color.sustainMoss
        case .rehearse: SustainColor.padActive
        case .audio: SustainColor.clickActive
        case .system: SustainColor.warning
        case .standard: SustainColor.accent
        }
    }

    var contourTint: Color {
        switch self {
        case .live: Color.sustainIvory
        case .rehearse: SustainColor.accent
        case .audio: SustainColor.clickActive
        case .system: SustainColor.ready
        case .standard: SustainColor.accent
        }
    }

    var contourHeight: CGFloat {
        switch self {
        case .live: 170
        case .rehearse, .audio: 280
        case .system: 230
        case .standard: 220
        }
    }

    var contourOpacity: Double {
        switch self {
        case .live: 0.24
        case .rehearse, .audio: 0.48
        case .system: 0.38
        case .standard: 0.34
        }
    }

    var isAnimated: Bool {
        switch self {
        case .rehearse, .audio: true
        case .standard, .live, .system: false
        }
    }
}

struct TopographicFieldView: View {
    var tint: Color
    var animated = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                drawContours(in: &context, size: size, time: time)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawContours(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width * 0.56, y: size.height * 0.76)
        let maxRadius = hypot(size.width, size.height) * 0.72

        for index in 0..<18 {
            let path = contourPath(
                index: index,
                center: center,
                maxRadius: maxRadius,
                time: CGFloat(time)
            )
            let opacity = 0.08 + Double(index % 4) * 0.026
            let width = index % 3 == 0 ? 1.35 : 0.85
            context.stroke(path, with: .color(tint.opacity(opacity)), lineWidth: width)
        }
    }

    private func contourPath(index: Int, center: CGPoint, maxRadius: CGFloat, time: CGFloat) -> Path {
        let radius = maxRadius * (0.18 + CGFloat(index) * 0.045)
        let steps = 180
        var path = Path()

        for step in 0...steps {
            let theta = (CGFloat(step) / CGFloat(steps)) * .pi * 2
            let point = contourPoint(theta: theta, index: index, radius: radius, center: center, time: time)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func contourPoint(theta: CGFloat, index: Int, radius: CGFloat, center: CGPoint, time: CGFloat) -> CGPoint {
        let indexValue = CGFloat(index)
        let ripple = sin(theta * 3.0 + indexValue * 0.62 + time * 0.18) * 10
        let fine = sin(theta * 7.0 - indexValue * 0.34 + time * 0.11) * 4
        let adjustedRadius = radius + ripple
        let x = center.x + cos(theta) * (adjustedRadius + fine) * 1.42
        let y = center.y + sin(theta) * (adjustedRadius - fine) * 0.48
        return CGPoint(x: x, y: y)
    }
}

struct BrandProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = SustainColor.accent

    func makeBody(configuration: Configuration) -> some View {
        HoverableProminentButton(
            configuration: configuration,
            tint: tint,
            isEnabled: isEnabled
        )
    }
}

struct BrandBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = SustainColor.accent

    func makeBody(configuration: Configuration) -> some View {
        HoverableBorderedButton(
            configuration: configuration,
            tint: tint,
            isEnabled: isEnabled
        )
    }
}

private struct HoverableProminentButton: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.sustainNearBlack)
            .padding(.horizontal, SustainSpace.lg)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(configuration.isPressed ? 0.76 : isHovering ? 1.0 : 0.94),
                                tint.opacity(configuration.isPressed ? 0.56 : isHovering ? 0.86 : 0.72)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .stroke(Color.sustainIvory.opacity(isHovering ? 0.42 : 0.24), lineWidth: 1)
            )
            .shadow(color: tint.opacity(configuration.isPressed ? 0.12 : isHovering ? 0.38 : 0.24), radius: isHovering ? 14 : 9, y: isHovering ? 6 : 4)
            .scaleEffect(configuration.isPressed ? 0.982 : isHovering ? 1.018 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.smooth(duration: 0.18), value: isHovering)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

private struct HoverableBorderedButton: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, SustainSpace.md)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.20 : isHovering ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .stroke(tint.opacity(configuration.isPressed ? 0.42 : isHovering ? 0.38 : 0.20), lineWidth: 1)
            )
            .shadow(color: tint.opacity(isHovering ? 0.16 : 0), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : isHovering ? 1.01 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.smooth(duration: 0.18), value: isHovering)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func sustainScreenBackground(_ mood: SustainBackgroundMood = .standard) -> some View {
        background(SustainAppBackground(mood: mood))
    }

    func sustainProminentButton(tint: Color = SustainColor.accent) -> some View {
        buttonStyle(BrandProminentButtonStyle(tint: tint))
    }

    func sustainBorderedButton(tint: Color = SustainColor.accent) -> some View {
        buttonStyle(BrandBorderedButtonStyle(tint: tint))
    }
}

struct LitToggleButton: View {
    var title: String
    var systemImage: String
    var tint: Color = SustainColor.clickActive
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: SustainSpace.sm) {
                Circle()
                    .fill(isOn ? tint : SustainColor.textTertiary.opacity(0.42))
                    .frame(width: 9, height: 9)
                    .shadow(color: isOn ? tint.opacity(0.75) : .clear, radius: 7)

                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(isOn ? tint : SustainColor.textSecondary)
            .padding(.horizontal, SustainSpace.md)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .fill(tint.opacity(isOn ? 0.18 : isHovering ? 0.11 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .stroke(tint.opacity(isOn ? 0.48 : isHovering ? 0.28 : 0.14), lineWidth: 1)
            )
            .shadow(color: isOn ? tint.opacity(0.22) : .clear, radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.smooth(duration: 0.18), value: isHovering)
        .animation(.smooth(duration: 0.18), value: isOn)
    }
}
struct SustainScreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: SustainSpace.xxl) {
            VStack(alignment: .leading, spacing: SustainSpace.xs) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(SustainColor.textSecondary)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, SustainSpace.screen)
        .padding(.vertical, SustainSpace.xl)
    }
}

struct SustainSectionHeader: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = SustainColor.accent
    var isActive = false

    var body: some View {
        HStack(spacing: SustainSpace.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)

            Text(title)
                .font(SustainType.panelTitle)

            Spacer()

            SignalIndicator(label: value, tint: tint, isActive: isActive)
        }
    }
}

struct SignalIndicator: View {
    var label: String
    var tint: Color
    var isActive: Bool

    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            Circle()
                .fill(isActive ? tint : SustainColor.textTertiary.opacity(0.42))
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? tint.opacity(0.55) : .clear, radius: 5)

            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(isActive ? SustainColor.textPrimary : SustainColor.textSecondary)
        }
        .padding(.horizontal, SustainSpace.md)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }
}

struct MetadataChip: View {
    var label: String
    var value: String
    var tint: Color = SustainColor.accent

    var body: some View {
        HStack(spacing: SustainSpace.xs) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(SustainColor.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, SustainSpace.sm)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ChannelFader: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var isActive: Bool
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: SustainSpace.md) {
            HStack(spacing: SustainSpace.md) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SustainColor.textSecondary)
                }

                Spacer()

                SignalIndicator(
                    label: "\(Int((value * 100).rounded()))%",
                    tint: tint,
                    isActive: isActive
                )
            }

            HStack(spacing: SustainSpace.md) {
                LevelMeter(value: value, tint: tint, isActive: isActive)
                    .frame(width: 46, height: 18)

                Slider(value: $value, in: 0...1, step: 0.01)
                    .tint(tint)
                    .accessibilityLabel(Text("\(title) Volume"))
            }
        }
        .padding(SustainSpace.lg)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
    }
}

struct LevelMeter: View {
    var value: Double
    var tint: Color
    var isActive: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Double(index + 1) / 5.0
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(value >= threshold ? tint.opacity(isActive ? 0.95 : 0.62) : SustainColor.textTertiary.opacity(0.18))
                    .frame(width: 6, height: CGFloat(5 + index * 3))
            }
        }
        .accessibilityHidden(true)
    }
}

struct AudioPatternView: View {
    var tint: Color
    var isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let midY = size.height * 0.5
                let amplitude = isActive ? size.height * 0.16 : size.height * 0.06
                var path = Path()

                for x in stride(from: 0.0, through: size.width, by: 4.0) {
                    let progress = x / max(size.width, 1)
                    let wave = sin(progress * .pi * 3.0 + time * 0.9)
                    let drift = sin(progress * .pi * 1.4 + time * 0.36) * 0.45
                    let y = midY + (wave + drift) * amplitude
                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(path, with: .color(tint.opacity(isActive ? 0.36 : 0.16)), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }
}
