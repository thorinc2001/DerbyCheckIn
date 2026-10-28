// Draws the app icon: a pinewood derby car with a green checkbox on its side.
// Usage: swift Tools/make-icon.swift <output.png>   (1024×1024)
import AppKit

let size: CGFloat = 1024
// Pass --web to add a Wi-Fi symbol, for Derby Web Check In.
let args = CommandLine.arguments.dropFirst()
let web = args.contains("--web")
let out = args.first { $0 != "--web" } ?? "icon.png"

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
// Work top-down like a drawing program.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: nil)!
}

// MARK: Background tile (macOS icon grid: 824pt body, inset 100)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(color(0x1B4F9C)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
// Sky
ctx.drawLinearGradient(gradient([color(0x4FA3F7), color(0x1D5FC4)]),
                       start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 700), options: [])
// Track
let trackTop: CGFloat = 708
ctx.setFillColor(color(0x5B6472)); ctx.fill(CGRect(x: 0, y: trackTop, width: size, height: 300))
ctx.setFillColor(color(0x7A8494)); ctx.fill(CGRect(x: 0, y: trackTop, width: size, height: 16))
// Lane guide strip
ctx.setFillColor(color(0xFFFFFF, 0.85))
for x in stride(from: 110.0, to: 924.0, by: 120.0) {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 820, width: 70, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil))
}
ctx.fillPath()
// Speed lines behind the car
ctx.setStrokeColor(color(0xFFFFFF, 0.55)); ctx.setLineCap(.round); ctx.setLineWidth(14)
for (y, x0, x1) in [(460.0, 120.0, 172.0), (525.0, 100.0, 168.0), (590.0, 125.0, 172.0)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y))
}
ctx.strokePath()

// MARK: Car shadow
ctx.saveGState()
ctx.setFillColor(color(0x000000, 0.28))
ctx.fillEllipse(in: CGRect(x: 215, y: 700, width: 670, height: 26))
ctx.restoreGState()

// MARK: Car body (side view, nose to the right)
let body = CGMutablePath()
body.move(to: CGPoint(x: 200, y: 630))                                   // rear bottom
body.addLine(to: CGPoint(x: 200, y: 458))
body.addQuadCurve(to: CGPoint(x: 236, y: 424), control: CGPoint(x: 200, y: 424))   // rear top corner
body.addLine(to: CGPoint(x: 560, y: 418))
body.addQuadCurve(to: CGPoint(x: 618, y: 440), control: CGPoint(x: 595, y: 416))   // cockpit hump
body.addLine(to: CGPoint(x: 878, y: 578))                                 // wedge slope
body.addQuadCurve(to: CGPoint(x: 892, y: 612), control: CGPoint(x: 906, y: 590))   // nose
body.addLine(to: CGPoint(x: 880, y: 630))
body.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 10, color: color(0x000000, 0.3))
ctx.addPath(body); ctx.setFillColor(color(0xC98A4B)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(body); ctx.clip()
ctx.drawLinearGradient(gradient([color(0xF0C38A), color(0xD9A064), color(0xB27237)]),
                       start: CGPoint(x: 0, y: 418), end: CGPoint(x: 0, y: 630), options: [])
// Wood grain
ctx.setStrokeColor(color(0x8A5226, 0.28)); ctx.setLineWidth(5)
for (i, y) in stride(from: 452.0, to: 630.0, by: 36.0).enumerated() {
    let wobble: CGFloat = i % 2 == 0 ? 14 : -12
    ctx.move(to: CGPoint(x: 220, y: y))
    ctx.addCurve(to: CGPoint(x: 900, y: y + 6),
                 control1: CGPoint(x: 420, y: y + wobble), control2: CGPoint(x: 680, y: y - wobble))
}
ctx.strokePath()
// Top highlight
ctx.setStrokeColor(color(0xFFFFFF, 0.35)); ctx.setLineWidth(10)
ctx.move(to: CGPoint(x: 236, y: 432)); ctx.addLine(to: CGPoint(x: 555, y: 426))
ctx.strokePath()
ctx.restoreGState()
ctx.addPath(body); ctx.setStrokeColor(color(0x7A4518, 0.6)); ctx.setLineWidth(4); ctx.strokePath()

// MARK: Wheels
func wheel(_ c: CGPoint) {
    let r: CGFloat = 70
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 5), blur: 8, color: color(0x000000, 0.35))
    ctx.setFillColor(color(0x1E1F24)); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.restoreGState()
    ctx.setStrokeColor(color(0x3A3C44)); ctx.setLineWidth(8)
    ctx.strokeEllipse(in: CGRect(x: c.x - r + 13, y: c.y - r + 13, width: 2 * r - 26, height: 2 * r - 26))
    let h: CGFloat = 30
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h)); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xF2F4F7), color(0x9AA1AD)]),
                           start: CGPoint(x: c.x - h, y: c.y - h), end: CGPoint(x: c.x + h, y: c.y + h), options: [])
    ctx.restoreGState()
    ctx.setFillColor(color(0x55595F)); ctx.fillEllipse(in: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
}
wheel(CGPoint(x: 290, y: 638))
wheel(CGPoint(x: 790, y: 638))

// MARK: Green checkbox decal on the car's side
let box = CGRect(x: 380, y: 436, width: 172, height: 172)
let boxPath = CGPath(roundedRect: box, cornerWidth: 38, cornerHeight: 38, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 14, color: color(0x000000, 0.35))
ctx.addPath(boxPath); ctx.setFillColor(color(0x2FB54F)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(boxPath); ctx.clip()
ctx.drawLinearGradient(gradient([color(0x5EE07A), color(0x23A143)]),
                       start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY), options: [])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 5, dy: 5), cornerWidth: 34, cornerHeight: 34, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(10); ctx.strokePath()
// Check mark
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 4, color: color(0x0B5E22, 0.5))
ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(27); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: box.minX + 42, y: box.midY + 4))
ctx.addLine(to: CGPoint(x: box.minX + 76, y: box.maxY - 44))
ctx.addLine(to: CGPoint(x: box.maxX - 37, y: box.minY + 44))
ctx.strokePath()
ctx.restoreGState()


// MARK: Wi-Fi symbol (web version)
if web {
    let c = CGPoint(x: 735, y: 330)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: color(0x0B2E6B, 0.45))
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineCap(.round); ctx.setLineWidth(30)
    for r: CGFloat in [70, 130, 190] {
        ctx.addArc(center: c, radius: r, startAngle: -.pi * 3 / 4, endAngle: -.pi / 4, clockwise: false)
        ctx.strokePath()
    }
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: c.x - 24, y: c.y - 24, width: 48, height: 48))
    ctx.restoreGState()
}
ctx.restoreGState()  // tile clip

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
