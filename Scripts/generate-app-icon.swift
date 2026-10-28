#!/usr/bin/env swift
// Generates the AppIcon PNG set (dark rounded square with a notch/island glyph).
// Usage: swift Scripts/generate-app-icon.swift MacIsland/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MacIsland/Resources/Assets.xcassets/AppIcon.appiconset"
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let s = CGFloat(px)
    let inset = s * 0.095
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.05, alpha: 1)])!.draw(in: squircle, angle: -90)

    // Screen top edge highlight
    let edge = NSRect(x: rect.minX, y: rect.maxY - rect.height * 0.055, width: rect.width, height: rect.height * 0.055)
    let edgePath = NSBezierPath(rect: edge)
    edgePath.append(squircle)
    edgePath.windingRule = .evenOdd
    NSColor(white: 0.32, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    NSBezierPath(rect: edge).fill()

    // Expanded island
    let islandW = rect.width * 0.66
    let islandH = rect.height * 0.30
    let island = NSRect(x: rect.midX - islandW / 2, y: rect.maxY - islandH, width: islandW, height: islandH)
    let islandPath = NSBezierPath()
    let r = islandH * 0.42
    islandPath.move(to: NSPoint(x: island.minX, y: island.maxY))
    islandPath.line(to: NSPoint(x: island.minX, y: island.minY + r))
    islandPath.appendArc(withCenter: NSPoint(x: island.minX + r, y: island.minY + r), radius: r, startAngle: 180, endAngle: 270)
    islandPath.line(to: NSPoint(x: island.maxX - r, y: island.minY))
    islandPath.appendArc(withCenter: NSPoint(x: island.maxX - r, y: island.minY + r), radius: r, startAngle: 270, endAngle: 360)
    islandPath.line(to: NSPoint(x: island.maxX, y: island.maxY))
    islandPath.close()
    NSColor.black.setFill()
    islandPath.fill()

    // Content glyphs: artwork square + three bars
    let pad = islandH * 0.26
    let art = NSRect(x: island.minX + pad, y: island.minY + pad, width: islandH - 2 * pad, height: islandH - 2 * pad)
    NSColor(white: 0.92, alpha: 1).setFill()
    NSBezierPath(roundedRect: art, xRadius: art.width * 0.22, yRadius: art.width * 0.22).fill()
    let barW = islandH * 0.085
    let gap = barW * 0.9
    let heights: [CGFloat] = [0.45, 0.9, 0.65]
    for (i, h) in heights.enumerated() {
        let x = island.maxX - pad - CGFloat(heights.count - i) * (barW + gap) + gap
        let bh = (islandH - 2 * pad) * h
        let bar = NSRect(x: x, y: island.minY + pad, width: barW, height: bh)
        NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(name).png")
    try! render(px).write(to: url)
}
print("wrote \(sizes.count) icons to \(outputDir)")
