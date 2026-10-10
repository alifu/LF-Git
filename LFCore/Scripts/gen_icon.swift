#!/usr/bin/env swift
// Draws the LF-Git app icon (a merge: Current and Incoming lanes joining into one) and writes every size of the
// macOS AppIcon set, with the matching Contents.json.
//
//   swift LFCore/Scripts/gen_icon.swift            # writes LF-Git/Assets.xcassets/AppIcon.appiconset
//   swift LFCore/Scripts/gen_icon.swift out.png    # one 1024 px preview instead
//
// Colors come from the Atlassian palette used by Design/theme.json: Teal = Current, Blue = Incoming, Green = result.
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

let backgroundTop = color(0x216E4E)      // Green800
let backgroundBottom = color(0x1C3329)   // Green1000
let current = color(0x42B2D7)            // Teal500
let incoming = color(0x669DF1)           // Blue400
let result = color(0x7EE2B8)             // Green300
let ink = color(0xF8F8F8)                // Neutral100

/// Draws the icon on a 1024 x 1024 canvas, scaled to `pixels`.
func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // Tile: 824 px squircle inside the 1024 canvas, as in Apple's macOS icon grid.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
    if pixels >= 128 {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        color(0x000000).setFill()
        shape.fill()
        context.restoreGState()
    }
    context.saveGState()
    shape.addClip()
    NSGradient(starting: backgroundTop, ending: backgroundBottom)!.draw(in: tile, angle: -90)
    // A soft light from the top edge.
    NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    context.restoreGState()
    color(0xFFFFFF, 0.18).setStroke()
    shape.lineWidth = 3
    shape.stroke()

    // The merge: two lanes (Current, Incoming) curve into one lane that continues down.
    let left = CGPoint(x: 340, y: 740), right = CGPoint(x: 684, y: 740)
    let join = CGPoint(x: 512, y: 470), bottom = CGPoint(x: 512, y: 284)
    func lane(from start: CGPoint, _ tint: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.curve(to: join, controlPoint1: CGPoint(x: start.x, y: 580), controlPoint2: CGPoint(x: join.x, y: 640))
        path.lineWidth = 62
        path.lineCapStyle = .round
        tint.setStroke()
        path.stroke()
    }
    let trunk = NSBezierPath()
    trunk.move(to: join)
    trunk.line(to: bottom)
    trunk.lineWidth = 62
    trunk.lineCapStyle = .round
    result.setStroke()
    trunk.stroke()


    lane(from: left, current)
    lane(from: right, incoming)

    // Commit nodes: a ring with the lane's color around a dark center.
    func node(_ center: CGPoint, _ tint: NSColor, radius: CGFloat = 70) {
        let outer = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        tint.setFill()
        outer.fill()
        let inner = NSBezierPath(ovalIn: NSRect(x: center.x - radius * 0.46, y: center.y - radius * 0.46,
                                                width: radius * 0.92, height: radius * 0.92))
        backgroundBottom.setFill()
        inner.fill()
    }
    node(left, current)
    node(right, incoming)
    node(bottom, result)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let arguments = CommandLine.arguments.dropFirst()
if let preview = arguments.first {
    try write(render(pixels: 1024), to: URL(fileURLWithPath: preview))
    exit(0)
}

let directory = URL(fileURLWithPath: "LF-Git/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try write(render(pixels: points * scale), to: directory.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("Contents.json"))
print("wrote \(sizes.count) icons to \(directory.path)")
