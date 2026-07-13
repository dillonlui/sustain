import SwiftUI

struct BrandMarkView: View {
    var body: some View {
        // Just the clean sustain wave — matches the app icon's central mark. The old
        // topographic ripple strokes behind it read as visual noise at this size.
        SustainWaveShape()
            .fill(
                LinearGradient(
                    colors: [.sustainIvory, .sustainSage, .sustainIvory],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: .sustainSage.opacity(0.42), radius: 12)
            .drawingGroup()
    }
}

struct SustainWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 1024
        let scaleY = rect.height / 1024

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        path.move(to: point(196, 535))
        path.addCurve(to: point(424, 466), control1: point(256, 446), control2: point(345, 422))
        path.addCurve(to: point(636, 579), control1: point(505, 510), control2: point(548, 575))
        path.addCurve(to: point(835, 478), control1: point(718, 583), control2: point(781, 531))
        path.addCurve(to: point(604, 624), control1: point(779, 563), control2: point(705, 621))
        path.addCurve(to: point(374, 520), control1: point(512, 627), control2: point(450, 562))
        path.addCurve(to: point(196, 535), control1: point(310, 485), control2: point(253, 494))
        path.closeSubpath()
        return path
    }
}

extension Color {
    static let sustainNearBlack = Color(red: 0.055, green: 0.059, blue: 0.063)
    static let sustainCharcoal = Color(red: 0.090, green: 0.098, blue: 0.090)
    static let sustainDeepOlive = Color(red: 0.118, green: 0.137, blue: 0.118)
    static let sustainMoss = Color(red: 0.227, green: 0.290, blue: 0.224)
    static let sustainSage = Color(red: 0.659, green: 0.745, blue: 0.604)
    static let sustainIvory = Color(red: 0.945, green: 0.937, blue: 0.902)
    static let sustainMutedGold = Color(red: 0.863, green: 0.796, blue: 0.541)
}
