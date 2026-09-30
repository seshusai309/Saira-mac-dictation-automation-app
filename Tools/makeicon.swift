#!/usr/bin/env swift
import AppKit
import Foundation

// Renders AppIcon.icns from code — no design tool, no binary asset to keep in sync with
// the HUD palette. Run: swift Tools/makeicon.swift

// Matches `AppMark` in UI/Components.swift and the DS palette — Wispr Flow's brand colors.
// Change them together.
let charcoal = NSColor(srgbRed: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0, alpha: 1)
let cream = NSColor(srgbRed: 0xFF / 255.0, green: 0xFF / 255.0, blue: 0xEB / 255.0, alpha: 1)
let lavender = NSColor(srgbRed: 0xF0 / 255.0, green: 0xD7 / 255.0, blue: 0xFF / 255.0, alpha: 1)

/// Relative bar heights, center-weighted so the mark reads as a voice rather than a chart.
/// The middle bar is the lavender one.
let bars: [CGFloat] = [0.34, 0.62, 1.00, 0.70, 0.40]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: art occupies the middle ~82%, leaving the shadow gutter the system
    // expects.
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    // Apple's squircle is ~22.37% of the tile's edge.
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.035,
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    ctx.addPath(squircle)
    ctx.setFillColor(charcoal.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // A hairline bevel along the top edge — flat face, machined edge. No gradients.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bevel = CGPath(
        roundedRect: rect.insetBy(dx: size * 0.004, dy: size * 0.004),
        cornerWidth: radius, cornerHeight: radius, transform: nil
    )
    ctx.addPath(bevel)
    ctx.setStrokeColor(cream.withAlphaComponent(0.10).cgColor)
    ctx.setLineWidth(max(1, size * 0.008))
    ctx.strokePath()
    ctx.restoreGState()

    // A thin cream ring — the grille of a field recorder's microphone.
    let ringDiameter = rect.width * 0.66
    let ring = CGRect(
        x: rect.midX - ringDiameter / 2, y: rect.midY - ringDiameter / 2,
        width: ringDiameter, height: ringDiameter
    )
    ctx.setStrokeColor(cream.withAlphaComponent(0.22).cgColor)
    ctx.setLineWidth(max(1, size * 0.012))
    ctx.strokeEllipse(in: ring)

    // Waveform mark.
    let barWidth = rect.width * 0.066
    let gap = rect.width * 0.052
    let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    let maxHeight = rect.height * 0.40
    var x = rect.midX - totalWidth / 2

    for (index, bar) in bars.enumerated() {
        let height = max(barWidth, maxHeight * bar)
        let barRect = CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
        ctx.addPath(CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        ))
        ctx.setFillColor((index == bars.count / 2 ? lavender : cream).cgColor)
        ctx.fillPath()
        x += barWidth + gap
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Redraw at native pixel size rather than scaling a single render — keeps the small
    // sizes crisp instead of muddy.
    drawIcon(size: CGFloat(pixels)).draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .sourceOver, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) pairs iconutil expects.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    guard let data = png(NSImage(), pixels: pixels) else {
        print("failed at \(pixels)px"); exit(1)
    }
    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(points)x\(points)\(suffix).png"
    try data.write(to: iconset.appendingPathComponent(name))
}

print("wrote \(variants.count) PNGs to Resources/AppIcon.iconset")
