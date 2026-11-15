// Draws the modern official Widmut app icon as a 1024px PNG
// Renders a high-end geometric W monogram squircle on obsidian dark with electric cyan accents.
// Usage: swift scripts/make-icon.swift <output.png> [small]
import AppKit
import ImageIO
import SwiftUI

let small = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "small"
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: body).cgPath

// Subtle drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 32, color: rgb(0x000000, 0.50))
ctx.addPath(shape)
ctx.setFillColor(rgb(0x07090E))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()

// Deep Obsidian background
ctx.drawLinearGradient(gradient([rgb(0x161C28), rgb(0x0D1118), rgb(0x07090E)], [0, 0.55, 1]),
                       start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])

// Ambient electric cyan & violet core glow
ctx.drawRadialGradient(gradient([rgb(0x0EA5E9, 0.35), rgb(0x6366F1, 0.12), rgb(0x07090E, 0)], [0, 0.45, 1]),
                       startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 420, options: [])

// Draw modern geometric "W" monogram
let wPath = CGMutablePath()
let wSize: CGFloat = small ? 560 : 500
let left = 512 - wSize / 2
let top: CGFloat = 512 + wSize / 2.3
let bottom: CGFloat = 512 - wSize / 2.3
let strokeW: CGFloat = small ? 82 : 72

// Left slant
wPath.move(to: CGPoint(x: left, y: top))
wPath.addLine(to: CGPoint(x: left + wSize * 0.28, y: bottom))
wPath.addLine(to: CGPoint(x: 512, y: top - wSize * 0.28))
wPath.addLine(to: CGPoint(x: left + wSize * 0.72, y: bottom))
wPath.addLine(to: CGPoint(x: left + wSize, y: top))

ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(strokeW)
ctx.addPath(wPath)
ctx.replacePathWithStrokedPath()
ctx.clip()

// Gradient inside the "W"
ctx.drawLinearGradient(gradient([rgb(0x38BDF8), rgb(0x818CF8), rgb(0xC084FC)], [0, 0.55, 1]),
                       start: CGPoint(x: left, y: top), end: CGPoint(x: left + wSize, y: bottom), options: [])
ctx.restoreGState()

// Subtle inner rim glow along the top border
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)]),
                       start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.maxY - 140), options: [])

ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
