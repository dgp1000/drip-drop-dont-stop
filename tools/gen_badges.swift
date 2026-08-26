// Generates the five 512x512 Game Center achievement badges for
// Drip Drop Dont Stop. GC masks these to a circle, so everything
// important stays well inside the center.
import AppKit
import CoreGraphics

let SIZE: CGFloat = 512

func ctx() -> CGContext {
    let c = CGContext(data: nil, width: Int(SIZE), height: Int(SIZE),
                      bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return c
}

func save(_ c: CGContext, _ name: String, dir: String) {
    let img = c.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    print(name)
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Deep cave background with a soft radial glow of the given tint.
func background(_ c: CGContext, tint: CGColor) {
    c.setFillColor(rgba(0.03, 0.05, 0.10))
    c.fill(CGRect(x: 0, y: 0, width: SIZE, height: SIZE))
    let colors = [tint.copy(alpha: 0.55)!, tint.copy(alpha: 0.0)!] as CFArray
    let grad = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
    c.drawRadialGradient(grad,
        startCenter: CGPoint(x: SIZE/2, y: SIZE/2), startRadius: 0,
        endCenter: CGPoint(x: SIZE/2, y: SIZE/2), endRadius: SIZE * 0.55,
        options: [])
}

/// Classic teardrop: round belly, curved point at the top.
func dropletPath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let tip = CGPoint(x: cx, y: cy + r * 1.75)
    p.move(to: tip)
    p.addCurve(to: CGPoint(x: cx + r, y: cy),
               control1: CGPoint(x: cx + r * 0.55, y: cy + r * 1.1),
               control2: CGPoint(x: cx + r, y: cy + r * 0.55))
    p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
             startAngle: 0, endAngle: .pi, clockwise: true)
    p.addCurve(to: tip,
               control1: CGPoint(x: cx - r, y: cy + r * 0.55),
               control2: CGPoint(x: cx - r * 0.55, y: cy + r * 1.1))
    return p
}

func fillDroplet(_ c: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat,
                 top: CGColor, bottom: CGColor, glow: CGColor) {
    c.saveGState()
    c.setShadow(offset: .zero, blur: 60, color: glow)
    c.addPath(dropletPath(cx: cx, cy: cy, r: r))
    c.clip()
    let grad = CGGradient(colorsSpace: nil,
                          colors: [bottom, top] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad,
        start: CGPoint(x: cx, y: cy - r), end: CGPoint(x: cx, y: cy + r * 1.75),
        options: [])
    c.restoreGState()
    // Specular highlight.
    c.setFillColor(rgba(1, 1, 1, 0.55))
    c.fillEllipse(in: CGRect(x: cx - r * 0.45, y: cy + r * 0.15,
                             width: r * 0.28, height: r * 0.42))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// ---- First Drop: the cyan droplet, plain and proud -------------------
var c = ctx()
background(c, tint: rgba(0.0, 0.75, 0.9))
fillDroplet(c, cx: 256, cy: 220, r: 105,
            top: rgba(0.55, 0.9, 1.0), bottom: rgba(0.05, 0.45, 0.85),
            glow: rgba(0.2, 0.8, 1.0, 0.9))
save(c, "first-drop", dir: dir)

// ---- Quickdrop: droplet leaning into speed lines ---------------------
c = ctx()
background(c, tint: rgba(1.0, 0.55, 0.1))
c.saveGState()
c.translateBy(x: 256, y: 235); c.rotate(by: -0.5); c.translateBy(x: -256, y: -235)
fillDroplet(c, cx: 256, cy: 225, r: 95,
            top: rgba(0.55, 0.9, 1.0), bottom: rgba(0.05, 0.45, 0.85),
            glow: rgba(0.2, 0.8, 1.0, 0.9))
c.restoreGState()
c.setStrokeColor(rgba(1.0, 0.7, 0.25, 0.9))
c.setLineCap(.round)
for (i, w) in [(0, 150), (1, 110), (2, 70)] {
    c.setLineWidth(14)
    let y = 160 + CGFloat(i) * 55
    c.move(to: CGPoint(x: 90, y: y))
    c.addLine(to: CGPoint(x: 90 + CGFloat(w), y: y))
    c.strokePath()
}
save(c, "quickdrop", dir: dir)

// ---- Dont Stop: a trail of drops climbing home -----------------------
c = ctx()
background(c, tint: rgba(1.0, 0.45, 0.15))
let stops: [(CGFloat, CGFloat, CGFloat)] = [(120, 130, 34), (210, 200, 44), (310, 280, 56)]
for (x, y, r) in stops {
    fillDroplet(c, cx: x, cy: y, r: r,
                top: rgba(1.0, 0.75, 0.35), bottom: rgba(0.9, 0.4, 0.1),
                glow: rgba(1.0, 0.6, 0.2, 0.8))
}
save(c, "dont-stop", dir: dir)

// ---- Midas Drip: the golden droplet ----------------------------------
c = ctx()
background(c, tint: rgba(1.0, 0.8, 0.2))
fillDroplet(c, cx: 256, cy: 220, r: 105,
            top: rgba(1.0, 0.92, 0.55), bottom: rgba(0.85, 0.6, 0.1),
            glow: rgba(1.0, 0.85, 0.3, 1.0))
// A little sparkle.
c.setFillColor(rgba(1, 1, 1, 0.95))
for (x, y, r) in [(150.0, 380.0, 7.0), (370, 350, 5), (330, 415, 4)] {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x, y: y + r * 3))
    path.addQuadCurve(to: CGPoint(x: x + r * 3, y: y), control: CGPoint(x: x + r * 0.4, y: y + r * 0.4))
    path.addQuadCurve(to: CGPoint(x: x, y: y - r * 3), control: CGPoint(x: x + r * 0.4, y: y - r * 0.4))
    path.addQuadCurve(to: CGPoint(x: x - r * 3, y: y), control: CGPoint(x: x - r * 0.4, y: y - r * 0.4))
    path.addQuadCurve(to: CGPoint(x: x, y: y + r * 3), control: CGPoint(x: x - r * 0.4, y: y + r * 0.4))
    c.addPath(path)
    c.fillPath()
}
save(c, "midas-drip", dir: dir)

// ---- Nightfall: frozen droplet under a crescent moon -----------------
c = ctx()
background(c, tint: rgba(0.25, 0.35, 0.8))
// Stars.
c.setFillColor(rgba(1, 1, 1, 0.8))
for (x, y, r) in [(120.0, 420.0, 3.0), (200, 455, 2), (330, 440, 3), (400, 390, 2), (95, 330, 2)] {
    c.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
}
// Crescent moon built from two arcs (outer edge + inner "terminator"),
// so the sky shows through the bite with no overpainting.
// Geometry (relative to the moon center, bite center 30 pt along -x,
// both radius 65): intersections at angles ±103.4° on the outer circle
// and ±76.6° on the bite circle.
let moonR: CGFloat = 65
let crescent = CGMutablePath()
crescent.addArc(center: .zero, radius: moonR,
                startAngle: 1.805, endAngle: -1.805, clockwise: true)
crescent.addArc(center: CGPoint(x: -30, y: 0), radius: moonR,
                startAngle: -1.337, endAngle: 1.337, clockwise: false)
crescent.closeSubpath()
c.saveGState()
c.translateBy(x: 365, y: 365)
c.rotate(by: 2.2)      // horns toward the upper right
c.setShadow(offset: .zero, blur: 30, color: rgba(0.85, 0.9, 1.0, 0.8))
c.setFillColor(rgba(0.92, 0.94, 1.0))
c.addPath(crescent)
c.fillPath()
c.restoreGState()
// The frozen droplet: pale, faceted by a couple of crack lines
// (clipped to the silhouette so they can't poke out).
fillDroplet(c, cx: 210, cy: 185, r: 95,
            top: rgba(0.85, 0.95, 1.0), bottom: rgba(0.45, 0.65, 0.9),
            glow: rgba(0.6, 0.8, 1.0, 0.9))
c.saveGState()
c.addPath(dropletPath(cx: 210, cy: 185, r: 95))
c.clip()
c.setStrokeColor(rgba(1, 1, 1, 0.6))
c.setLineWidth(5)
c.move(to: CGPoint(x: 155, y: 235)); c.addLine(to: CGPoint(x: 262, y: 140)); c.strokePath()
c.move(to: CGPoint(x: 212, y: 188)); c.addLine(to: CGPoint(x: 250, y: 226)); c.strokePath()
c.restoreGState()
save(c, "nightfall", dir: dir)

// ---- 1.3 batch ------------------------------------------------------

// Twenty Basins: a green basin catching a steady drip.
c = ctx()
background(c, tint: rgba(0.1, 0.8, 0.5))
c.setFillColor(rgba(0.15, 0.75, 0.5))
c.fill(CGRect(x: 166, y: 120, width: 180, height: 110))
c.setFillColor(rgba(0.08, 0.45, 0.3))
c.fill(CGRect(x: 166, y: 200, width: 180, height: 30))
c.setStrokeColor(rgba(0.85, 1.0, 0.95, 0.9)); c.setLineWidth(8)
c.stroke(CGRect(x: 158, y: 112, width: 196, height: 126))
for (i, y) in [(0, 300.0), (1, 360.0), (2, 420.0)] {
    fillDroplet(c, cx: 256 + CGFloat(i % 2 == 0 ? -14 : 14), cy: y, r: 22,
                top: rgba(0.55, 0.9, 1.0), bottom: rgba(0.05, 0.45, 0.85),
                glow: rgba(0.2, 0.8, 1.0, 0.7))
}
save(c, "twenty-basins", dir: dir)

// Every Basin: the golden basin, collection complete.
c = ctx()
background(c, tint: rgba(1.0, 0.8, 0.2))
c.setFillColor(rgba(1.0, 0.8, 0.25))
c.fill(CGRect(x: 146, y: 140, width: 220, height: 130))
c.setFillColor(rgba(0.7, 0.5, 0.1))
c.fill(CGRect(x: 146, y: 240, width: 220, height: 30))
c.setStrokeColor(rgba(1.0, 0.95, 0.7, 1)); c.setLineWidth(10)
c.stroke(CGRect(x: 136, y: 130, width: 240, height: 150))
fillDroplet(c, cx: 256, cy: 330, r: 55,
            top: rgba(1.0, 0.92, 0.55), bottom: rgba(0.85, 0.6, 0.1),
            glow: rgba(1.0, 0.85, 0.3, 1.0))
save(c, "every-basin", dir: dir)

// Into the Depths: a droplet descending past depth chevrons.
c = ctx()
background(c, tint: rgba(0.15, 0.35, 0.85))
c.setStrokeColor(rgba(0.5, 0.75, 1.0, 0.75)); c.setLineWidth(14)
c.setLineCap(.round)
for (i, y) in [(0, 400.0), (1, 330.0), (2, 260.0)] {
    let inset = CGFloat(i) * 26
    c.move(to: CGPoint(x: 150 + inset, y: y + 34))
    c.addLine(to: CGPoint(x: 256, y: y))
    c.addLine(to: CGPoint(x: 362 - inset, y: y + 34))
    c.strokePath()
}
fillDroplet(c, cx: 256, cy: 130, r: 58,
            top: rgba(0.55, 0.9, 1.0), bottom: rgba(0.05, 0.35, 0.75),
            glow: rgba(0.2, 0.6, 1.0, 0.9))
save(c, "into-the-depths", dir: dir)

// Storm Chaser: the droplet leaning into layered gale streaks.
c = ctx()
background(c, tint: rgba(0.2, 0.75, 0.75))
c.setStrokeColor(rgba(0.7, 1.0, 0.95, 0.85)); c.setLineCap(.round)
for (i, y) in [(0, 380.0), (1, 320.0), (2, 260.0), (3, 200.0)] {
    c.setLineWidth(i % 2 == 0 ? 12 : 8)
    c.move(to: CGPoint(x: 90, y: y))
    c.addLine(to: CGPoint(x: 90 + CGFloat(140 - i * 18), y: y))
    c.strokePath()
}
c.saveGState()
c.translateBy(x: 290, y: 280); c.rotate(by: -0.45); c.translateBy(x: -290, y: -280)
fillDroplet(c, cx: 290, cy: 270, r: 78,
            top: rgba(0.75, 1.0, 0.95), bottom: rgba(0.1, 0.55, 0.6),
            glow: rgba(0.4, 0.95, 0.9, 0.9))
c.restoreGState()
save(c, "storm-chaser", dir: dir)

// Flash Flood: the droplet mid-burst, speed spikes radiating.
c = ctx()
background(c, tint: rgba(1.0, 0.6, 0.1))
c.setStrokeColor(rgba(1.0, 0.85, 0.4, 0.95)); c.setLineCap(.round)
for a in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 4) {
    c.setLineWidth(9)
    let r1: CGFloat = 150, r2: CGFloat = 205
    c.move(to: CGPoint(x: 256 + cos(a) * r1, y: 256 + sin(a) * r1))
    c.addLine(to: CGPoint(x: 256 + cos(a) * r2, y: 256 + sin(a) * r2))
    c.strokePath()
}
fillDroplet(c, cx: 256, cy: 215, r: 80,
            top: rgba(1.0, 0.95, 0.7), bottom: rgba(0.95, 0.55, 0.1),
            glow: rgba(1.0, 0.75, 0.2, 1.0))
save(c, "flash-flood", dir: dir)

// Stubborn: the droplet re-forming inside impact rings.
c = ctx()
background(c, tint: rgba(0.85, 0.4, 0.55))
c.setStrokeColor(rgba(1.0, 0.75, 0.85, 0.6))
for (r, w) in [(200.0, 6.0), (160.0, 8.0), (120.0, 10.0)] {
    c.setLineWidth(w)
    c.strokeEllipse(in: CGRect(x: 256 - r, y: 256 - r, width: r * 2, height: r * 2))
}
fillDroplet(c, cx: 256, cy: 215, r: 62,
            top: rgba(1.0, 0.8, 0.9), bottom: rgba(0.7, 0.25, 0.45),
            glow: rgba(1.0, 0.55, 0.7, 0.9))
save(c, "stubborn", dir: dir)
