// Draws the default app icon (original artwork: a planet under a distant sun,
// with "PSO" in Baloo 2) as a 1024x1024 PNG.
//   swift scripts/make-icon.swift <font.ttf> <out.png>
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count == 3 else {
  FileHandle.standardError.write("usage: make-icon.swift <font.ttf> <out.png>\n".data(using: .utf8)!)
  exit(1)
}
let fontURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let S = CGFloat(size)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ stops: [CGFloat]? = nil) -> CGGradient {
  CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: stops)!
}
func glow(_ c: CGPoint, _ r: CGFloat, _ inner: CGColor, _ outer: CGColor) {
  ctx.drawRadialGradient(gradient([inner, outer]), startCenter: c, startRadius: 0, endCenter: c, endRadius: r,
                         options: [])
}

// CoreGraphics' origin is bottom-left.
ctx.drawLinearGradient(gradient([rgb(28, 56, 120), rgb(14, 26, 74), rgb(6, 9, 30)], [0, 0.5, 1]),
                       start: CGPoint(x: S, y: 0), end: CGPoint(x: 0, y: S), options: [])
glow(CGPoint(x: S * 0.3, y: S * 0.75), S * 0.7, rgb(70, 40, 140, 0.35), rgb(70, 40, 140, 0))

srand48(1337)
for _ in 0..<140 {
  let x = drand48() * Double(S), y = Double(S) * (0.35 + drand48() * 0.65)
  let r = 1.0 + pow(drand48(), 3) * 4
  ctx.setFillColor(rgb(220, 230, 255, 0.3 + drand48() * 0.6))
  ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

// Sun, upper right.
glow(CGPoint(x: S * 0.80, y: S * 0.82), S * 0.45, rgb(255, 220, 160, 0.55), rgb(255, 200, 120, 0))
glow(CGPoint(x: S * 0.80, y: S * 0.82), S * 0.06, rgb(255, 250, 235), rgb(255, 240, 200, 0))

// Planet, lower half.
let pc = CGPoint(x: S * 0.5, y: -S * 0.42)
let pr = S * 0.82
glow(pc, pr * 1.12, rgb(90, 190, 255, 0.55), rgb(90, 190, 255, 0))
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: pc.x - pr, y: pc.y - pr, width: 2 * pr, height: 2 * pr))
ctx.clip()
ctx.drawRadialGradient(gradient([rgb(110, 200, 185), rgb(36, 96, 110), rgb(8, 22, 40)], [0, 0.45, 1]),
                       startCenter: CGPoint(x: pc.x + pr * 0.3, y: pc.y + pr * 0.85), startRadius: 0,
                       endCenter: pc, endRadius: pr * 1.05, options: [.drawsAfterEndLocation])
srand48(7)
for _ in 0..<10 {
  let y = pc.y + pr * (0.55 + drand48() * 0.45)
  let bw = pr * (0.6 + drand48() * 0.9), bh = pr * (0.02 + drand48() * 0.035)
  let x = pc.x - bw / 2 + (drand48() - 0.5) * pr * 0.8
  ctx.setFillColor(rgb(255, 255, 255, 0.06 + drand48() * 0.08))
  ctx.fillEllipse(in: CGRect(x: x, y: y, width: bw, height: bh))
}
ctx.restoreGState()
ctx.setStrokeColor(rgb(170, 230, 255, 0.7))
ctx.setLineWidth(5)
ctx.strokeEllipse(in: CGRect(x: pc.x - pr, y: pc.y - pr, width: 2 * pr, height: 2 * pr))

// "PSO": gold gradient with a soft shadow.
let font = CTFontCreateWithName("Baloo2-SemiBold" as CFString, S * 0.36, nil)
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "PSO", attributes: [
  NSAttributedString.Key(kCTFontAttributeName as String): font,
  NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(255, 255, 255),
]))
let bounds = CTLineGetImageBounds(line, ctx)
let origin = CGPoint(x: (S - bounds.width) / 2 - bounds.minX, y: S * 0.47)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.025, color: rgb(4, 8, 30, 0.8))
ctx.textPosition = origin
CTLineDraw(line, ctx)
ctx.restoreGState()
// Fill the glyphs with the gradient: clip to the text drawing mode.
ctx.saveGState()
ctx.setTextDrawingMode(.clip)
ctx.textPosition = origin
CTLineDraw(line, ctx)
let top = origin.y + bounds.maxY, bottom = origin.y + bounds.minY
ctx.drawLinearGradient(gradient([rgb(255, 232, 120), rgb(255, 138, 48)]), start: CGPoint(x: 0, y: top),
                       end: CGPoint(x: 0, y: bottom), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("Wrote \(outURL.path)")
