// Renders Luna's app icon (run via `make icons`).
//
//   swift scripts/app-icon.swift <icon.png>
//
// 1024×1024 on Apple's icon grid (824 px tile, 100 px margins): a twilight tile with a glowing gibbous moon,
// a few stars, and beneath it a Control Center brightness slider filled to the moon's phase.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/app-icon.swift <icon.png>\n".utf8))
    exit(2)
}

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, like the coordinates below.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha,
        ])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// A rounded rectangle with continuous (squircle) corners, like Apple's icon tiles.
func continuousRect(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let e = radius * 1.528665
    let c = radius * 0.43
    p.move(to: CGPoint(x: r.minX + e, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY))
    p.addCurve(
        to: CGPoint(x: r.maxX, y: r.minY + e), control1: CGPoint(x: r.maxX - c, y: r.minY),
        control2: CGPoint(x: r.maxX, y: r.minY + c))
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - e))
    p.addCurve(
        to: CGPoint(x: r.maxX - e, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - c),
        control2: CGPoint(x: r.maxX - c, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY))
    p.addCurve(
        to: CGPoint(x: r.minX, y: r.maxY - e), control1: CGPoint(x: r.minX + c, y: r.maxY),
        control2: CGPoint(x: r.minX, y: r.maxY - c))
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + e))
    p.addCurve(
        to: CGPoint(x: r.minX + e, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + c),
        control2: CGPoint(x: r.minX + c, y: r.minY))
    p.closeSubpath()
    return p
}

let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = continuousRect(tileRect, radius: 120)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tile)
ctx.setFillColor(color(0x101330))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile)
ctx.clip()

// Twilight: indigo above, near-black navy below.
ctx.drawLinearGradient(
    gradient([color(0x343A8C), color(0x1B1F55), color(0x0A0C24)], [0, 0.5, 1]),
    start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

let moonCenter = CGPoint(x: 512, y: 452)
let moonRadius: CGFloat = 214

// The moon lights the sky around it.
ctx.drawRadialGradient(
    gradient([color(0x8E8CFF, 0.55), color(0x6A6FE0, 0.18), color(0x6A6FE0, 0)], [0, 0.45, 1]),
    startCenter: moonCenter, startRadius: moonRadius * 0.6, endCenter: moonCenter, endRadius: moonRadius * 2.3,
    options: [])

// Stars.
let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (228, 236, 5, 0.9), (318, 178, 3, 0.6), (790, 214, 4, 0.8), (742, 318, 2.5, 0.55), (206, 420, 2.5, 0.5),
    (836, 470, 3, 0.6), (270, 604, 2, 0.45), (770, 620, 2.5, 0.5), (412, 150, 2, 0.5),
]
for (x, y, r, a) in stars {
    ctx.setFillColor(color(0xFFFFFF, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

// The moon's dark side, faintly lit by the earth.
let disc = CGPath(
    ellipseIn: CGRect(
        x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius, width: 2 * moonRadius, height: 2 * moonRadius),
    transform: nil)
ctx.addPath(disc)
ctx.setFillColor(color(0x262B66))
ctx.fillPath()

// The lit part, gibbous, lit from the right.
let phase: CGFloat = 0.7
let lit = CGMutablePath()
lit.move(to: CGPoint(x: moonCenter.x, y: moonCenter.y - moonRadius))
lit.addArc(center: moonCenter, radius: moonRadius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
let terminator = moonRadius * abs(1 - 2 * phase)
for i in 0...64 {
    let angle = .pi / 2 - .pi * CGFloat(i) / 64
    lit.addLine(to: CGPoint(x: moonCenter.x - terminator * cos(angle), y: moonCenter.y + moonRadius * sin(angle)))
}
lit.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: color(0xFFE6AE, 0.65))
ctx.addPath(lit)
ctx.setFillColor(color(0xFFF4DC))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(lit)
ctx.clip()
ctx.drawRadialGradient(
    gradient([color(0xFFFFFF), color(0xFFF3D6), color(0xF2D49A)], [0, 0.55, 1]),
    startCenter: CGPoint(x: moonCenter.x + 70, y: moonCenter.y - 80), startRadius: 0,
    endCenter: moonCenter, endRadius: moonRadius * 1.05, options: [.drawsAfterEndLocation])
// A few soft maria.
for (dx, dy, r, a) in [(60.0, -40.0, 46.0, 0.10), (120.0, 60.0, 30.0, 0.08), (20.0, 90.0, 36.0, 0.07)]
    as [(CGFloat, CGFloat, CGFloat, CGFloat)]
{
    ctx.setFillColor(color(0x9C8150, a))
    ctx.fillEllipse(in: CGRect(x: moonCenter.x + dx - r, y: moonCenter.y + dy - r, width: 2 * r, height: 2 * r))
}
ctx.restoreGState()

// A brightness slider, filled to the moon's phase.
let track = CGRect(x: 262, y: 752, width: 500, height: 70)
let trackPath = CGPath(roundedRect: track, cornerWidth: 35, cornerHeight: 35, transform: nil)
ctx.addPath(trackPath)
ctx.setFillColor(color(0xFFFFFF, 0.13))
ctx.fillPath()
let fill = CGRect(
    x: track.minX, y: track.minY, width: track.height + (track.width - track.height) * phase, height: track.height)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 24, color: color(0xFFE2A0, 0.45))
ctx.addPath(CGPath(roundedRect: fill, cornerWidth: 35, cornerHeight: 35, transform: nil))
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0xFFFFFF), color(0xFFE9BD)], [0, 1]), start: CGPoint(x: fill.minX, y: 0),
    end: CGPoint(x: fill.maxX, y: 0), options: [])
ctx.restoreGState()
// A small sun inside the fill.
let sun = CGPoint(x: track.minX + 35, y: track.midY)
ctx.setFillColor(color(0x2A2F6E, 0.75))
ctx.fillEllipse(in: CGRect(x: sun.x - 9, y: sun.y - 9, width: 18, height: 18))
ctx.setStrokeColor(color(0x2A2F6E, 0.75))
ctx.setLineWidth(4.5)
ctx.setLineCap(.round)
for i in 0..<8 {
    let angle = CGFloat(i) * .pi / 4
    ctx.move(to: CGPoint(x: sun.x + 15 * cos(angle), y: sun.y + 15 * sin(angle)))
    ctx.addLine(to: CGPoint(x: sun.x + 21 * cos(angle), y: sun.y + 21 * sin(angle)))
}
ctx.strokePath()

// Glass: a soft sheen over the top half, and a fine edge.
ctx.drawLinearGradient(
    gradient([color(0xFFFFFF, 0.13), color(0xFFFFFF, 0)], [0, 1]),
    start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
ctx.restoreGState()

ctx.addPath(tile)
ctx.setStrokeColor(color(0xFFFFFF, 0.14))
ctx.setLineWidth(3)
ctx.strokePath()

let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[1]))
