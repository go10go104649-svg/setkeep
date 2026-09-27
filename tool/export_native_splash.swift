// Regenerate only the native launch artwork, never the launcher icons.
// Run from the repository root: swift tool/export_native_splash.swift
import AppKit
import CoreText
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let trainerRoot = root.appendingPathComponent("apps/setkeep_trainer")

func symbol(at path: String, trainer: Bool) -> CGImage {
    let data = try! Data(contentsOf: root.appendingPathComponent(path))
    let original = NSBitmapImageRep(data: data)!
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: original.pixelsWide,
        pixelsHigh: original.pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: original.pixelsWide * 4,
        bitsPerPixel: 32
    )!
    var minX = original.pixelsWide
    var minY = original.pixelsHigh
    var maxX = 0
    var maxY = 0
    for y in 0..<original.pixelsHigh {
        for x in 0..<original.pixelsWide {
            let pixel = original.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let red = pixel.redComponent
            let green = pixel.greenComponent
            let blue = pixel.blueComponent
            let alpha: CGFloat
            let output: NSColor
            if trainer {
                // The existing TRAINER source has a dark icon background. Keep
                // its exact SK silhouette, but put it on the native light splash.
                alpha = min(1, max(0, (max(red, green, blue) - 0.32) / 0.34))
                let cyan = blue > red * 1.2 && blue > green * 1.08
                output = cyan
                    ? NSColor(calibratedRed: 56/255, green: 198/255, blue: 1, alpha: alpha)
                    : NSColor(calibratedRed: 15/255, green: 23/255, blue: 32/255, alpha: alpha)
            } else {
                alpha = pixel.alphaComponent
                output = NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
            }
            bitmap.setColor(output, atX: x, y: y)
            if alpha > 0.12 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }
    precondition(maxX > minX && maxY > minY)
    return bitmap.cgImage!.cropping(to: CGRect(
        x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1
    ))!
}

// Cropped directly from the approved SETKEEP brand board: mark, wordmark,
// and the splash tagline are one lockup so their geometry stays unchanged.
let generalSymbol = symbol(at: "assets/brand/setkeep_splash_lockup_source.png", trainer: false)
let trainerSymbol = symbol(
    at: "apps/setkeep_trainer/assets/brand/trainer_symbol_source.png",
    trainer: true
)

func drawWord(_ value: String, baseline: CGFloat, size: CGFloat, color: CGColor, in context: CGContext) {
    let font = CTFontCreateWithName("HelveticaNeue-CondensedBlack" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(x: (180 - width) / 2, y: baseline)
    CTLineDraw(line, context)
}

func export(_ path: URL, scale: Double, trainer: Bool, ios: Bool) {
    let logicalSize = ios && !trainer ? 240 : 180
    let size = Int(Double(logicalSize) * scale)
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.interpolationQuality = .high
    let mark = trainer ? trainerSymbol : generalSymbol
    if trainer {
        context.draw(mark, in: CGRect(x: 35, y: 84, width: 110, height: 52))
        let ink = CGColor(red: 16/255, green: 24/255, blue: 32/255, alpha: 1)
        drawWord("SETKEEP", baseline: 57, size: 19, color: ink, in: context)
        drawWord("TRAINER", baseline: 43, size: 9,
                 color: CGColor(red: 56/255, green: 198/255, blue: 1, alpha: 1),
                 in: context)
    } else if ios {
        context.draw(mark, in: CGRect(x: 17, y: 59, width: 206, height: 121))
    } else {
        // Android 12+ applies a circular system mask to the splash icon.
        context.draw(mark, in: CGRect(x: 40, y: 60, width: 100, height: 59))
    }
    try! FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

func exportProgress(_ path: URL, scale: Double) {
    let context = CGContext(
        data: nil, width: Int(200 * scale), height: Int(80 * scale),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setFillColor(CGColor(red: 0.86, green: 0.88, blue: 0.87, alpha: 1))
    context.fill(CGRect(x: 14, y: 38, width: 172, height: 4))
    context.setFillColor(CGColor(red: 0, green: 208/255, blue: 132/255, alpha: 1))
    context.fill(CGRect(x: 14, y: 38, width: 43, height: 4))
    let destination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}

for (app, trainer) in [(root, false), (trainerRoot, true)] {
    let ios = app.appendingPathComponent("ios/Runner/Assets.xcassets/LaunchImage.imageset")
    for scale in 1...3 {
        export(ios.appendingPathComponent("LaunchImage\(scale == 1 ? "" : "@\(scale)x").png"),
               scale: Double(scale), trainer: trainer, ios: true)
    }
    let android = app.appendingPathComponent("android/app/src/main/res")
    for (density, scale) in [("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0), ("xxhdpi", 3.0), ("xxxhdpi", 4.0)] {
        export(android.appendingPathComponent("drawable-\(density)/launch_logo.png"),
               scale: scale, trainer: trainer, ios: false)
        if !trainer {
            exportProgress(android.appendingPathComponent("drawable-\(density)/launch_progress.png"),
                           scale: scale)
        }
    }
}
print("Exported SETKEEP and SETKEEP TRAINER native splash lockups")
