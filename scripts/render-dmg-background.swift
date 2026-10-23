import AppKit

// Render at 2x; the TIFF retains a 720x460 point size for Retina Finder windows.
let size = NSSize(width: 720, height: 460)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 920,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let ink = NSColor(srgbRed: 0.12, green: 0.23, blue: 0.20, alpha: 1)
let green = NSColor(srgbRed: 0.23, green: 0.42, blue: 0.34, alpha: 1)
let muted = NSColor(srgbRed: 0.39, green: 0.44, blue: 0.40, alpha: 1)
NSColor(srgbRed: 0.97, green: 0.97, blue: 0.94, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
func centered(_ text: String, y: CGFloat, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (text as NSString).draw(in: NSRect(x: 30, y: y, width: 660, height: 50), withAttributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: style, .kern: tracking
    ])
}
centered("SUSTAIN", y: 382, font: .systemFont(ofSize: 12, weight: .semibold), color: green, tracking: 4)
centered("Install Sustain", y: 329, font: .systemFont(ofSize: 34, weight: .semibold), color: ink)
centered("Drag Sustain into Applications to get started.", y: 291,
         font: .systemFont(ofSize: 16), color: muted)
// Finder coordinates start at the top. The two real, draggable icons sit on these halos.
for x: CGFloat in [180, 540] {
    green.withAlphaComponent(0.055).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 120, y: 80, width: 240, height: 240)).fill()
}
green.withAlphaComponent(0.7).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 321, y: 210))
arrow.line(to: NSPoint(x: 399, y: 210))
arrow.move(to: NSPoint(x: 387, y: 222))
arrow.line(to: NSPoint(x: 399, y: 210))
arrow.line(to: NSPoint(x: 387, y: 198))
arrow.stroke()
centered("Then open Sustain from Applications.", y: 34,
         font: .systemFont(ofSize: 13), color: muted)
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .tiff, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
