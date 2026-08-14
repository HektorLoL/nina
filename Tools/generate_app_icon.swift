import AppKit
import CoreGraphics
import Foundation

let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Nina/Assets.xcassets/AppIcon.appiconset")

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

struct IconSlot {
    let filename: String
    let pixels: Int
}

let slots: [IconSlot] = [
    .init(filename: "AppIcon-20x20@1x.png", pixels: 20),
    .init(filename: "AppIcon-20x20@2x.png", pixels: 40),
    .init(filename: "AppIcon-20x20@3x.png", pixels: 60),
    .init(filename: "AppIcon-29x29@1x.png", pixels: 29),
    .init(filename: "AppIcon-29x29@2x.png", pixels: 58),
    .init(filename: "AppIcon-29x29@3x.png", pixels: 87),
    .init(filename: "AppIcon-40x40@1x.png", pixels: 40),
    .init(filename: "AppIcon-40x40@2x.png", pixels: 80),
    .init(filename: "AppIcon-40x40@3x.png", pixels: 120),
    .init(filename: "AppIcon-60x60@2x.png", pixels: 120),
    .init(filename: "AppIcon-60x60@3x.png", pixels: 180),
    .init(filename: "AppIcon-76x76@1x.png", pixels: 76),
    .init(filename: "AppIcon-76x76@2x.png", pixels: 152),
    .init(filename: "AppIcon-83.5x83.5@2x.png", pixels: 167),
    .init(filename: "AppIcon-1024x1024@1x.png", pixels: 1024)
]

// Azulejo reserva: cobalt floods the tile edge to edge and the mark is left in
// bare glaze. Inside the app cobalt is rationed; the icon spends the whole
// ration at once, on the outside.
let cobalt = NSColor(srgbRed: 27 / 255, green: 79 / 255, blue: 216 / 255, alpha: 1)
let glaze = NSColor(srgbRed: 251 / 255, green: 252 / 255, blue: 253 / 255, alpha: 1)

// The mark is drawn from `Nina/NinaMark.swift`'s 64-grid large master, placed so
// its drawn extent is 65.8% of the frame and optically lifted, because a
// bottom-heavy mass centred by its box reads as sinking.
private let markBoxOrigin = CGPoint(x: 118.9, y: 112.0)
private let markUnit: CGFloat = 12.255
private let arcCenter = CGPoint(x: 32, y: 23.8)
private let arcRadius: CGFloat = 22.5
private let bandWidth: CGFloat = 10
private let discCenter = CGPoint(x: 32, y: 27.8)
private let discRadius: CGFloat = 8.4

func drawIcon(size: Int) -> Data {
    let scale = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = NSGraphicsContext.current!.cgContext
    let unit = scale / 1024

    cobalt.setFill()
    context.fill(CGRect(x: 0, y: 0, width: scale, height: scale))

    // The bitmap context is y-up and the mark is authored y-down, so every y is
    // mirrored and the 220° sweep runs clockwise instead of counter-clockwise.
    func place(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (markBoxOrigin.x + point.x * markUnit) * unit,
            y: scale - (markBoxOrigin.y + point.y * markUnit) * unit
        )
    }

    context.setStrokeColor(glaze.cgColor)
    context.setLineWidth(bandWidth * markUnit * unit)
    context.setLineCap(.round)
    context.beginPath()
    context.addArc(
        center: place(arcCenter),
        radius: arcRadius * markUnit * unit,
        startAngle: .pi / 9,
        endAngle: .pi * 8 / 9,
        clockwise: true
    )
    context.strokePath()

    // The disc is never concentric with the cup: concentric reads as an iris.
    let disc = place(discCenter)
    let r = discRadius * markUnit * unit
    glaze.setFill()
    NSBezierPath(
        ovalIn: CGRect(x: disc.x - r, y: disc.y - r, width: r * 2, height: r * 2)
    ).fill()

    return rep.representation(using: .png, properties: [:])!
}

for slot in slots {
    let data = drawIcon(size: slot.pixels)
    try data.write(to: outputURL.appendingPathComponent(slot.filename), options: .atomic)
}

print("Generated \(slots.count) Nina app icon assets")
