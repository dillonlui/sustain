import SwiftUI

/// Semantic colors for the Signal Grid direction. Views resolve this from their environment
/// so previews and the app's System / Light / Dark setting share the same source of truth.
struct FutureSignalColor {
    let canvas: Color
    let sidebar: Color
    let performanceSurface: Color
    let panel: Color
    let panelElevated: Color
    let surfaceEdge: Color
    let divider: Color
    let activeSignal: Color
    let cuedEdge: Color
    let focus: Color
    let textPrimary: Color
    let textSecondary: Color
    let warning: Color
    let blocked: Color

    init(colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        let dark = colorScheme == .dark
        let highContrast = contrast == .increased

        canvas = dark ? Self.rgb(14, 16, 15) : Self.rgb(242, 241, 235)
        sidebar = dark ? Self.rgb(17, 22, 19) : Self.rgb(233, 236, 229)
        performanceSurface = dark ? Self.rgb(18, 23, 21) : Self.rgb(250, 250, 246)
        panel = dark ? Self.rgb(23, 28, 25) : Self.rgb(255, 255, 255)
        panelElevated = dark ? Self.rgb(30, 37, 32) : Self.rgb(244, 247, 241)
        surfaceEdge = dark
            ? Self.rgb(highContrast ? 127 : 68, highContrast ? 157 : 92, highContrast ? 136 : 80)
            : Self.rgb(highContrast ? 68 : 151, highContrast ? 98 : 170, highContrast ? 75 : 154)
        divider = dark
            ? Self.rgb(highContrast ? 127 : 54, highContrast ? 157 : 72, highContrast ? 136 : 62)
            : Self.rgb(highContrast ? 68 : 178, highContrast ? 98 : 190, highContrast ? 75 : 175)
        activeSignal = dark
            ? Self.rgb(highContrast ? 183 : 157, highContrast ? 255 : 226, highContrast ? 194 : 173)
            : Self.rgb(highContrast ? 19 : 37, highContrast ? 89 : 120, highContrast ? 48 : 65)
        cuedEdge = dark ? Self.rgb(135, 191, 149) : Self.rgb(50, 118, 68)
        focus = dark ? Self.rgb(196, 255, 207) : Self.rgb(21, 99, 47)
        textPrimary = dark ? Self.rgb(247, 249, 245) : Self.rgb(24, 33, 27)
        textSecondary = dark
            ? Self.rgb(highContrast ? 213 : 174, highContrast ? 225 : 190, highContrast ? 214 : 181)
            : Self.rgb(highContrast ? 58 : 92, highContrast ? 71 : 104, highContrast ? 62 : 94)
        warning = dark ? Self.rgb(255, 198, 116) : Self.rgb(134, 73, 17)
        blocked = dark ? Self.rgb(255, 151, 145) : Self.rgb(161, 46, 43)
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: 1)
    }
}

enum FutureSignalEffects {
    static let surfaceRadius: CGFloat = 8
    static let edgeWidth: CGFloat = 1
    static let cornerLength: CGFloat = 14
    static let cornerInset: CGFloat = 12
    static let cornerWidth: CGFloat = 1.5
    static let activeGlowRadius: CGFloat = 16
    static let activeGlowOpacity = 0.16
    static let surfacePadding: CGFloat = 24
}
