import SwiftUI

// MARK: - Tokens

/// Semantic colors. Everything resolves to native system colors so the app follows
/// light/dark automatically and honors the user's System Settings accent. Status
/// colors (green/amber/red) carry *meaning*; the single interaction accent is the
/// system accent. No custom palette drives the chrome.
enum SustainColor {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let panelElevated = Color(nsColor: .controlBackgroundColor)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    /// Sustain's brand accent — a refined sage, slightly brighter on dark and deeper on
    /// light so it reads as a selection/active color in both appearances. Applied as the
    /// app-wide tint so native controls adopt it. Restraint comes from using it rarely.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        // Both variants keep ≥4.5:1 contrast against white so white text on the accent
        // (e.g. the prominent transport button) passes WCAG AA. Dark is a touch lighter
        // to lift off a dark background; light is deeper for presence on white.
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.37, green: 0.48, blue: 0.34, alpha: 1)
            : NSColor(srgbRed: 0.31, green: 0.42, blue: 0.29, alpha: 1)
    })
    static let accentSoft = accent.opacity(0.14)

    /// A single interaction accent carries all "active/selected" state — pad, click, and
    /// ready all resolve to it, so on/off reads as accent-vs-neutral rather than as
    /// competing hues. Warning/destructive stay distinct because they signal danger.
    static let padActive = accent
    static let clickActive = accent
    static let ready = accent
    static let warning = Color(nsColor: .systemOrange)
    static let destructive = Color(nsColor: .systemRed)

    static let separator = Color(nsColor: .separatorColor)
    static let focusRing = Color.accentColor.opacity(0.55)

    // Retained for source compatibility; kept subtle/native rather than glassy.
    static let glassFill = Color.clear
    static let glassTint = Color.clear
    static let glassHighlight = Color(nsColor: .separatorColor)
    static let glassShadow = Color.black.opacity(0.12)
}

enum SustainSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let screen: CGFloat = 24
    static let section: CGFloat = 32
}

enum SustainRadius {
    static let panel: CGFloat = 10
    static let elevated: CGFloat = 12
    static let control: CGFloat = 6
    static let capsule: CGFloat = 999
}

enum SustainType {
    static let display = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    static let metric = Font.system(.title, design: .rounded).weight(.semibold).monospacedDigit()
    static let panelTitle = Font.headline
    static let label = Font.caption.weight(.medium)
}

// MARK: - Surfaces

/// A restrained native card: a control-background (or supplied material) fill with a
/// single hairline border. No gradient, sheen, or shadow stack.
struct SustainPanel<Content: View>: View {
    var material: Material? = nil
    var isActive = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(SustainSpace.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
                    .stroke(isActive ? SustainColor.accent.opacity(0.5) : SustainColor.separator, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous)
        if let material {
            shape.fill(material)
        } else {
            shape.fill(SustainColor.panel)
        }
    }
}

/// Plain native window background. The decorative gradient/topographic layers are gone;
/// the mood parameter is retained for source compatibility and no longer draws anything.
struct SustainAppBackground: View {
    var mood: SustainBackgroundMood = .standard

    var body: some View {
        SustainColor.background.ignoresSafeArea()
    }
}

enum SustainBackgroundMood {
    case standard
    case live
    case rehearse
    case audio
    case system
}

/// Retained for source compatibility. Ambient decoration has been removed in favor of
/// native calm; renders nothing. A tasteful, motion-respecting pad visualization will be
/// reintroduced only on the active-playback surface.
struct TopographicFieldView: View {
    var tint: Color
    var animated = false

    var body: some View {
        Color.clear
    }
}

/// Retained for source compatibility; renders nothing for now.
struct AudioPatternView: View {
    var tint: Color
    var isActive: Bool

    var body: some View {
        Color.clear
    }
}

// MARK: - Buttons

extension View {
    func sustainScreenBackground(_ mood: SustainBackgroundMood = .standard) -> some View {
        background(SustainAppBackground(mood: mood))
    }

    func sustainProminentButton(tint: Color = SustainColor.accent) -> some View {
        buttonStyle(.borderedProminent).tint(tint)
    }

    func sustainBorderedButton(tint: Color = SustainColor.accent) -> some View {
        buttonStyle(.bordered).tint(tint)
    }
}

/// A native button-styled toggle with a small state dot, used for arm/enable controls.
struct LitToggleButton: View {
    var title: String
    var systemImage: String
    var tint: Color = SustainColor.clickActive
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .tint(tint)
    }
}

// MARK: - Headers

struct SustainScreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SustainSpace.xxl) {
            VStack(alignment: .leading, spacing: SustainSpace.xs) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, SustainSpace.screen)
        .padding(.vertical, SustainSpace.lg)
    }
}

struct SustainSectionHeader: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = SustainColor.accent
    var isActive = false

    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Spacer()
            SignalIndicator(label: value, tint: tint, isActive: isActive)
        }
    }
}

// MARK: - Indicators

struct SignalIndicator: View {
    var label: String
    var tint: Color
    var isActive: Bool

    var body: some View {
        HStack(spacing: SustainSpace.xs) {
            Circle()
                .fill(isActive ? tint : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, SustainSpace.sm)
        .padding(.vertical, 4)
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
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, SustainSpace.sm)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

// MARK: - Notices

/// Inline caution/error banner following the native pattern: the color lives on the
/// icon, the message text stays at full (primary) contrast, on a subtle tinted chip.
struct SustainInlineNotice: View {
    enum Kind {
        case warning
        case error

        var tint: Color {
            switch self {
            case .warning: SustainColor.warning
            case .error: SustainColor.destructive
            }
        }

        var systemImage: String {
            switch self {
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }
    }

    var message: String
    var kind: Kind = .warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SustainSpace.sm) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tint)
            Text(message)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(SustainSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: SustainRadius.panel, style: .continuous))
    }
}

// MARK: - Layout

/// Lays two panels side by side, falling back to a vertical stack when the container is
/// too narrow to fit them horizontally. The basis of responsive two-column screens.
struct PanelPair<First: View, Second: View>: View {
    var spacing: CGFloat = SustainSpace.xxl
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                first
                second
            }
            VStack(spacing: spacing) {
                first
                second
            }
        }
    }
}

// MARK: - Count-in

/// Large, glanceable count-in. Shows the current beat as a big monospaced numeral with
/// the total beats as pips, matching the spoken "one, two, three…". Occupies a stable
/// footprint whether or not it is counting so the performance layout never jumps.
struct CountoffIndicator: View {
    var beat: Int?
    var total: Int?

    var body: some View {
        VStack(spacing: SustainSpace.sm) {
            Text("COUNT IN")
                .font(.caption2.weight(.semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(isCounting ? 1 : 0)

            Text(beat.map(String.init) ?? "–")
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isCounting ? SustainColor.accent : .secondary.opacity(0.35))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.12), value: beat)

            HStack(spacing: SustainSpace.xs) {
                ForEach(0..<max(total ?? 0, 0), id: \.self) { index in
                    Circle()
                        .fill((beat ?? 0) > index ? SustainColor.accent : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 6)
            .opacity(isCounting ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(isCounting ? "Count in, beat \(beat ?? 0) of \(total ?? 0)" : "")
    }

    private var isCounting: Bool {
        beat != nil
    }
}

// MARK: - Level controls

struct ChannelFader: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var isActive: Bool
    @Binding var value: Double
    var onCommit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: SustainSpace.sm) {
            HStack(spacing: SustainSpace.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? .primary : .secondary)
            }

            HStack(spacing: SustainSpace.sm) {
                LevelMeter(value: value, tint: tint, isActive: isActive)
                    .frame(width: 44, height: 16)
                Slider(value: $value, in: 0...1) { editing in
                    if !editing { onCommit() }
                }
                .tint(tint)
                .accessibilityLabel(Text("\(title) Volume"))
            }
        }
        .padding(SustainSpace.md)
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
                    .fill(value >= threshold ? tint.opacity(isActive ? 0.95 : 0.6) : Color.secondary.opacity(0.2))
                    .frame(width: 6, height: CGFloat(5 + index * 3))
            }
        }
        .accessibilityHidden(true)
    }
}
