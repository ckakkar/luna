// Renders the background of Luna.dmg's window (run by scripts/make-dmg.sh).
//
//   swift scripts/dmg-background.swift <background.png> <scale>
//
// 660×400 points: dusk, from indigo at the top to warm light at the bottom, with Luna's moon glowing
// above an arrow from the app (left) to Applications (right). Finder draws the icon labels in white in
// dark mode and black in light mode, so the band behind them (y ≈ 265) is a mid-tone that reads with
// both. Keep the icon positions in sync with scripts/dmg-settings.py.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: swift scripts/dmg-background.swift <out.png> <scale>\n".utf8))
    exit(2)
}

let width: CGFloat = 660
let height: CGFloat = 400
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin in points, like Finder's icon positions.
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: height)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha,
    ])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// Dusk. The band at 0.66 (the labels' row) has a relative luminance of about 0.18.
ctx.drawLinearGradient(
    gradient(
        [color(0x1B1E52), color(0x3A3880), color(0x7A6FA8), color(0xC98F9A), color(0xF2C3A0)],
        [0, 0.33, 0.66, 0.86, 1]),
    start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: height), options: [])

// Moonlight in the sky.
let moon = CGPoint(x: 330, y: 70)
ctx.drawRadialGradient(
    gradient([color(0xFFF1D6, 0.55), color(0xB9B4FF, 0.18), color(0xB9B4FF, 0)], [0, 0.35, 1]),
    startCenter: moon, startRadius: 0, endCenter: moon, endRadius: 210, options: [])

// Stars, fading towards the horizon.
let stars: [(CGFloat, CGFloat, CGFloat)] = [
    (48, 34, 1.4), (112, 70, 1), (190, 26, 1.2), (250, 96, 0.8), (430, 30, 1), (505, 84, 1.3), (590, 40, 1),
    (626, 112, 0.8), (78, 128, 0.8), (560, 140, 0.7), (150, 150, 0.6), (300, 18, 0.8),
]
for (x, y, r) in stars {
    ctx.setFillColor(color(0xFFFFFF, 0.75 - y / 300))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

// A crescent moon.
let r: CGFloat = 17
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 18, color: color(0xFFE6AE, 0.8))
// Everything but the shadow disc, then the moon's disc inside that.
let outside = CGMutablePath()
outside.addRect(CGRect(x: 0, y: 0, width: width, height: height))
outside.addEllipse(in: CGRect(x: moon.x - r - 12, y: moon.y - r - 7, width: 2 * r, height: 2 * r))
ctx.addPath(outside)
ctx.clip(using: .evenOdd)
ctx.addEllipse(in: CGRect(x: moon.x - r, y: moon.y - r, width: 2 * r, height: 2 * r))
ctx.setFillColor(color(0xFFF4DC))
ctx.fillPath()
ctx.restoreGState()

// The arrow from the app to Applications: a gentle arc, white warming to gold, ending in a solid head
// pointed along the curve.
let start = CGPoint(x: 252, y: 196)
let control = CGPoint(x: 330, y: 152)
let end = CGPoint(x: 398, y: 186)
let tangent = CGPoint(x: end.x - control.x, y: end.y - control.y)
let length = (tangent.x * tangent.x + tangent.y * tangent.y).squareRoot()
let direction = CGPoint(x: tangent.x / length, y: tangent.y / length)
let normal = CGPoint(x: -direction.y, y: direction.x)
let tip = CGPoint(x: end.x + direction.x * 14, y: end.y + direction.y * 14)

let arc = CGMutablePath()
arc.move(to: start)
arc.addQuadCurve(to: end, control: control)
let head = CGMutablePath()
head.move(to: tip)
head.addLine(to: CGPoint(x: end.x - direction.x * 3 + normal.x * 9, y: end.y - direction.y * 3 + normal.y * 9))
head.addLine(to: CGPoint(x: end.x - direction.x * 3 - normal.x * 9, y: end.y - direction.y * 3 - normal.y * 9))
head.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 10, color: color(0xFFE2A0, 0.65))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.saveGState()
ctx.addPath(arc.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 4))
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0xFFFFFF, 0.95), color(0xFFD58A)], [0, 1]), start: start, end: end, options: [.drawsAfterEndLocation])
ctx.restoreGState()
// The head: filled, with rounded corners from a stroke of the same colour.
ctx.addPath(head)
ctx.setFillColor(color(0xFFD58A))
ctx.setStrokeColor(color(0xFFD58A))
ctx.setLineWidth(3)
ctx.setLineJoin(.round)
ctx.drawPath(using: .fillStroke)
ctx.endTransparencyLayer()
ctx.restoreGState()

// Words, on the warm part of the sky.
func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let attributed = NSAttributedString(
        string: string,
        attributes: [.font: font, .foregroundColor: NSColor(cgColor: color(0x2A1F4A, alpha))!])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.saveGState()
    // Core Text draws upright in a bottom-left coordinate space.
    ctx.translateBy(x: (width - bounds.width) / 2, y: y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}
text("Drag Luna into Applications", size: 17, weight: .semibold, alpha: 0.9, y: 336)
text("First launch: System Settings › Privacy & Security › Open Anyway", size: 11, weight: .medium, alpha: 0.7, y: 362)

let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[1]))
