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

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

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

    let rect = CGRect(x: 0, y: 0, width: scale, height: scale)
    let context = NSGraphicsContext.current!.cgContext

    // 1. Background Gradient
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            color(0.15, 0.78, 0.72).cgColor,
            color(0.27, 0.62, 0.96).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    // 2. Hair Silhouette (Dark Teal Bob)
    context.beginPath()
    context.move(to: CGPoint(x: scale * 0.50, y: scale * 0.76))
    context.addCurve(
        to: CGPoint(x: scale * 0.80, y: scale * 0.44),
        control1: CGPoint(x: scale * 0.68, y: scale * 0.76),
        control2: CGPoint(x: scale * 0.80, y: scale * 0.62)
    )
    context.addCurve(
        to: CGPoint(x: scale * 0.74, y: scale * 0.27),
        control1: CGPoint(x: scale * 0.80, y: scale * 0.34),
        control2: CGPoint(x: scale * 0.78, y: scale * 0.27)
    )
    context.addQuadCurve(
        to: CGPoint(x: scale * 0.50, y: scale * 0.25),
        control: CGPoint(x: scale * 0.62, y: scale * 0.25)
    )
    context.addQuadCurve(
        to: CGPoint(x: scale * 0.26, y: scale * 0.27),
        control: CGPoint(x: scale * 0.38, y: scale * 0.25)
    )
    context.addCurve(
        to: CGPoint(x: scale * 0.20, y: scale * 0.44),
        control1: CGPoint(x: scale * 0.22, y: scale * 0.27),
        control2: CGPoint(x: scale * 0.20, y: scale * 0.34)
    )
    context.addCurve(
        to: CGPoint(x: scale * 0.50, y: scale * 0.76),
        control1: CGPoint(x: scale * 0.20, y: scale * 0.62),
        control2: CGPoint(x: scale * 0.32, y: scale * 0.76)
    )
    context.closePath()
    color(0.10, 0.29, 0.34).setFill()
    context.fillPath()

    // 3. Subtle House-shaped Highlight at the Crown
    context.beginPath()
    context.move(to: CGPoint(x: scale * 0.50, y: scale * 0.75))
    context.addLine(to: CGPoint(x: scale * 0.60, y: scale * 0.66))
    context.addLine(to: CGPoint(x: scale * 0.57, y: scale * 0.58))
    context.addLine(to: CGPoint(x: scale * 0.43, y: scale * 0.58))
    context.addLine(to: CGPoint(x: scale * 0.40, y: scale * 0.66))
    context.closePath()
    color(1.0, 1.0, 1.0, 0.15).setFill()
    context.fillPath()

    // 4. Face Skin (with curved hairline)
    context.beginPath()
    context.move(to: CGPoint(x: scale * 0.32, y: scale * 0.50))
    context.addQuadCurve(
        to: CGPoint(x: scale * 0.68, y: scale * 0.50),
        control: CGPoint(x: scale * 0.50, y: scale * 0.62)
    )
    context.addCurve(
        to: CGPoint(x: scale * 0.50, y: scale * 0.23),
        control1: CGPoint(x: scale * 0.68, y: scale * 0.36),
        control2: CGPoint(x: scale * 0.62, y: scale * 0.23)
    )
    context.addCurve(
        to: CGPoint(x: scale * 0.32, y: scale * 0.50),
        control1: CGPoint(x: scale * 0.38, y: scale * 0.23),
        control2: CGPoint(x: scale * 0.32, y: scale * 0.36)
    )
    context.closePath()
    color(1.0, 0.98, 0.93).setFill()
    context.fillPath()

    // 5. Cheeks
    let cheekLeftRect = CGRect(x: scale * 0.31, y: scale * 0.3875, width: scale * 0.10, height: scale * 0.065)
    let cheekRightRect = CGRect(x: scale * 0.59, y: scale * 0.3875, width: scale * 0.10, height: scale * 0.065)
    let cheekLeft = NSBezierPath(ovalIn: cheekLeftRect)
    let cheekRight = NSBezierPath(ovalIn: cheekRightRect)
    color(0.98, 0.45, 0.38, 0.20).setFill()
    cheekLeft.fill()
    cheekRight.fill()

    // 6. Eyes
    let eyeSize = scale * 0.065
    color(0.12, 0.15, 0.18).setFill()
    NSBezierPath(ovalIn: CGRect(x: scale * 0.3875, y: scale * 0.4475, width: eyeSize, height: eyeSize)).fill()
    NSBezierPath(ovalIn: CGRect(x: scale * 0.5475, y: scale * 0.4475, width: eyeSize, height: eyeSize)).fill()

    // 7. Smiling Mouth
    context.beginPath()
    context.move(to: CGPoint(x: scale * 0.44, y: scale * 0.40))
    context.addQuadCurve(
        to: CGPoint(x: scale * 0.56, y: scale * 0.40),
        control: CGPoint(x: scale * 0.50, y: scale * 0.33)
    )
    context.setLineWidth(max(2.5, scale * 0.035))
    context.setLineCap(.round)
    color(0.98, 0.45, 0.38).setStroke()
    context.strokePath()

    // 8. Sparkle (Pinched 4-pointed Star)
    let sparkle = NSBezierPath()
    sparkle.move(to: CGPoint(x: scale * 0.652, y: scale * 0.688))
    sparkle.line(to: CGPoint(x: scale * 0.68, y: scale * 0.76))
    sparkle.line(to: CGPoint(x: scale * 0.708, y: scale * 0.688))
    sparkle.line(to: CGPoint(x: scale * 0.78, y: scale * 0.66))
    sparkle.line(to: CGPoint(x: scale * 0.708, y: scale * 0.632))
    sparkle.line(to: CGPoint(x: scale * 0.68, y: scale * 0.56))
    sparkle.line(to: CGPoint(x: scale * 0.652, y: scale * 0.632))
    sparkle.line(to: CGPoint(x: scale * 0.58, y: scale * 0.66))
    sparkle.close()
    color(1, 1, 1, 0.96).setFill()
    sparkle.fill()

    return rep.representation(using: .png, properties: [:])!
}

for slot in slots {
    let data = drawIcon(size: slot.pixels)
    try data.write(to: outputURL.appendingPathComponent(slot.filename), options: .atomic)
}

print("Generated \(slots.count) Nina app icon assets")
