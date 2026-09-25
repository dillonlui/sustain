import SwiftUI

enum FutureSignalSongRole {
    case now
    case next

    var label: String {
        switch self {
        case .now: "NOW"
        case .next: "NEXT"
        }
    }

    var emptyTitle: String {
        switch self {
        case .now: "No song playing"
        case .next: "Nothing cued"
        }
    }
}

/// One song's operational readout. Layout and type express NOW/NEXT hierarchy;
/// the parent performance surface supplies the only enclosing frame.
struct FutureSignalSongReadout: View {
    var role: FutureSignalSongRole
    var title: String?
    var key: String? = nil
    var padDescription: String? = nil
    var bpm: Int? = nil
    var timeSignature: String? = nil
    var clickDescription: String? = nil
    var stateLabel: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    private var isNow: Bool { role == .now }

    var body: some View {
        VStack(alignment: .leading, spacing: isNow ? 14 : 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(role.label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(palette.activeSignal)

                Spacer(minLength: 12)

                if let stateLabel, !stateLabel.isEmpty {
                    Text(stateLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isNow ? palette.activeSignal : palette.cuedEdge)
                        .lineLimit(1)
                }
            }

            Text(title ?? role.emptyTitle)
                .font(.system(size: isNow ? 38 : 25, weight: .semibold))
                .foregroundStyle(title == nil ? palette.textSecondary : palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .help(title ?? role.emptyTitle)

            if title != nil {
                HStack(spacing: 10) {
                    if let key {
                        Text(key)
                    }
                    if let padDescription {
                        Text(padDescription).lineLimit(1)
                    }
                    if let bpm {
                        Text("\(bpm) BPM")
                            .monospacedDigit()
                    }
                    if let timeSignature {
                        Text(timeSignature)
                            .monospacedDigit()
                    }
                }
                .font(isNow ? .title3 : .callout)
                .foregroundStyle(palette.textSecondary)

                if let clickDescription, !clickDescription.isEmpty {
                    Text(clickDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .help(clickDescription)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Signal Grid · song readouts") {
    VStack(alignment: .leading, spacing: 24) {
        FutureSignalSongReadout(
            role: .now,
            title: "Build My Life",
            key: "D",
            bpm: 72,
            timeSignature: "4/4",
            clickDescription: "Click: Beat",
            stateLabel: "Playing"
        )
        Divider()
        FutureSignalSongReadout(
            role: .next,
            title: "Goodness of God",
            key: "G",
            bpm: 68,
            timeSignature: "4/4",
            clickDescription: "Click: 2 per beat",
            stateLabel: "Cued"
        )
    }
    .padding(24)
    .frame(width: 580)
    .background(FutureSignalColor(colorScheme: .dark, contrast: .standard).performanceSurface)
    .preferredColorScheme(.dark)
}
