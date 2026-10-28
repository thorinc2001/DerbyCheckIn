// Draws the app icon: a clipboard with a ticked checklist and a wooden pinewood derby car.
// Usage: swift Tools/make-icon.swift [--web] <output.png>   (1024×1024)
// --web draws Derby Web Check In's version: a blue tile with a Wi-Fi badge.
import AppKit

let args = CommandLine.arguments.dropFirst()
let web = args.contains("--web")
let out = args.first { $0 != "--web" } ?? "icon.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Work top-down like a drawing program.
ctx.translateBy(x: 0, y: 1024)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}
/// Fills `path` with a top-to-bottom gradient, under a soft shadow.
func fill(_ path: CGPath, _ top: UInt32, _ bottom: UInt32, shadow: CGFloat = 0, base: UInt32? = nil) {
    let box = path.boundingBox
    if shadow > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: shadow * 0.55), blur: shadow, color: color(0x000000, 0.33))
        ctx.addPath(path); ctx.setFillColor(color(base ?? bottom)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient([color(top), color(bottom)]), start: CGPoint(x: 0, y: box.minY),
                           end: CGPoint(x: 0, y: box.maxY), options: [])
    ctx.restoreGState()
}
func checkMark(in box: CGRect, width: CGFloat) {
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: box.minX + box.width * 0.24, y: box.midY + box.height * 0.02))
    ctx.addLine(to: CGPoint(x: box.minX + box.width * 0.44, y: box.maxY - box.height * 0.25))
    ctx.addLine(to: CGPoint(x: box.maxX - box.width * 0.21, y: box.minY + box.height * 0.26))
    ctx.strokePath()
}

// MARK: Tile (macOS icon grid: 824 pt body, inset 100), with a soft glass light from the top

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
let (tileTop, tileBottom): (UInt32, UInt32) = web ? (0x63B6FF, 0x1D5BD3) : (0x5FD3A4, 0x168F78)
fill(tilePath, tileTop, tileBottom, shadow: 28)
ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
ctx.drawRadialGradient(gradient([color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)]),
                       startCenter: CGPoint(x: 400, y: 120), startRadius: 0,
                       endCenter: CGPoint(x: 400, y: 120), endRadius: 620, options: [])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 3, dy: 3), cornerWidth: 182, cornerHeight: 182, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.45)); ctx.setLineWidth(6); ctx.strokePath()

// MARK: Clipboard and paper

let board = CGPath(roundedRect: CGRect(x: 250, y: 176, width: 524, height: 720), cornerWidth: 44, cornerHeight: 44, transform: nil)
fill(board, 0xD9A060, 0xA9692D, shadow: 24, base: 0xB37436)
let paper = CGPath(roundedRect: CGRect(x: 292, y: 252, width: 440, height: 600), cornerWidth: 18, cornerHeight: 18, transform: nil)
fill(paper, 0xFFFFFF, 0xF4F6F8, shadow: 8)

// Checklist: two items done, one to go.
for (i, done) in [true, true, false].enumerated() {
    let y = 345 + CGFloat(i) * 110
    let dot = CGRect(x: 336, y: y - 36, width: 72, height: 72)
    if done {
        fill(CGPath(ellipseIn: dot, transform: nil), 0x5FE07D, 0x1E9E40)
        checkMark(in: dot.insetBy(dx: 8, dy: 8), width: 13)
    } else {
        ctx.setStrokeColor(color(0xC7CCD4)); ctx.setLineWidth(8); ctx.strokeEllipse(in: dot.insetBy(dx: 4, dy: 4))
    }
    let line = CGPath(roundedRect: CGRect(x: 440, y: y - 13, width: i == 2 ? 170 : 240, height: 26),
                      cornerWidth: 13, cornerHeight: 13, transform: nil)
    ctx.addPath(line); ctx.setFillColor(color(0xD5DAE1)); ctx.fillPath()
}

// MARK: The wooden wedge car, side view, nose right (local box about 720 × 300)

ctx.saveGState()
ctx.translateBy(x: 330, y: 650)
ctx.scaleBy(x: 0.52, y: 0.52)
let body = CGMutablePath()
body.move(to: CGPoint(x: 0, y: 220))
body.addLine(to: CGPoint(x: 0, y: 48))
body.addQuadCurve(to: CGPoint(x: 36, y: 14), control: CGPoint(x: 0, y: 14))
body.addLine(to: CGPoint(x: 360, y: 8))
body.addQuadCurve(to: CGPoint(x: 418, y: 30), control: CGPoint(x: 395, y: 6))
body.addLine(to: CGPoint(x: 678, y: 168))
body.addQuadCurve(to: CGPoint(x: 692, y: 202), control: CGPoint(x: 706, y: 180))
body.addLine(to: CGPoint(x: 680, y: 220))
body.closeSubpath()
ctx.setFillColor(color(0x000000, 0.22)); ctx.fillEllipse(in: CGRect(x: 10, y: 286, width: 680, height: 30))
fill(body, 0xF3C995, 0xB07034, shadow: 14, base: 0xC98A4B)
ctx.saveGState(); ctx.addPath(body); ctx.clip()
ctx.setStrokeColor(color(0x8A5226, 0.28)); ctx.setLineWidth(5)
for (i, y) in stride(from: 40.0, to: 220.0, by: 38.0).enumerated() {   // wood grain
    let w: CGFloat = i % 2 == 0 ? 12 : -10
    ctx.move(to: CGPoint(x: -10, y: y))
    ctx.addCurve(to: CGPoint(x: 720, y: y + 6), control1: CGPoint(x: 220, y: y + w), control2: CGPoint(x: 480, y: y - w))
}
ctx.strokePath()
ctx.restoreGState()
ctx.addPath(body); ctx.setStrokeColor(color(0x7A4518, 0.55)); ctx.setLineWidth(4); ctx.strokePath()
for cx in [90.0, 590.0] {
    let c = CGPoint(x: cx, y: 228), r: CGFloat = 70, h: CGFloat = 30
    fill(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil), 0x2A2B31, 0x16171B, shadow: 8)
    fill(CGPath(ellipseIn: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h), transform: nil), 0xF4F6F9, 0x9AA1AD)
}
ctx.restoreGState()

// MARK: Metal clip

let clip = CGPath(roundedRect: CGRect(x: 402, y: 132, width: 220, height: 120), cornerWidth: 34, cornerHeight: 34, transform: nil)
fill(clip, 0xF1F3F6, 0x8D96A3, shadow: 10, base: 0x9AA3AF)
ctx.setFillColor(color(0x5D6672)); ctx.fillEllipse(in: CGRect(x: 487, y: 160, width: 50, height: 50))

// MARK: Wi-Fi badge (web version)

if web {
    let c = CGPoint(x: 772, y: 306), r: CGFloat = 112
    let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    fill(CGPath(ellipseIn: disc.insetBy(dx: -12, dy: -12), transform: nil), 0xFFFFFF, 0xFFFFFF, shadow: 18)
    fill(CGPath(ellipseIn: disc, transform: nil), 0x4DA3FF, 0x1E5FD6)
    let o = CGPoint(x: c.x, y: c.y + 52)
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineCap(.round); ctx.setLineWidth(22)
    for arc: CGFloat in [42, 82, 122] where arc < r {
        ctx.addArc(center: o, radius: arc, startAngle: -.pi * 3 / 4, endAngle: -.pi / 4, clockwise: false)
        ctx.strokePath()
    }
    ctx.setFillColor(color(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: o.x - 17, y: o.y - 17, width: 34, height: 34))
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
