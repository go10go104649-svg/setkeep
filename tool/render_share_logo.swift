import AppKit
import Foundation

// Derive a small transparent lockup from the approved splash artwork.
// Source top: SK symbol; middle: SETKEEP wordmark. The tagline is excluded.
let source = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "assets/brand/setkeep_splash_lockup_source.png")))!
let width = 320, height = 174
let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4,
                              bitsPerPixel: 32)!
for y in 0..<height { for x in 0..<width { output.setColor(NSColor(calibratedWhite: 0, alpha: 0), atX: x, y: y) } }
func drawCrop(srcX: Int, srcY: Int, srcWidth: Int, srcHeight: Int,
              dstX: Int, dstY: Int, dstWidth: Int, dstHeight: Int) {
  for y in 0..<dstHeight {
    for x in 0..<dstWidth {
      let sx = srcX + x * srcWidth / dstWidth
      let sy = srcY + y * srcHeight / dstHeight
      guard let color = source.colorAt(x: sx, y: sy)?.usingColorSpace(.deviceRGB),
            color.alphaComponent > 0.01 else { continue }
      let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
      let isGreen = g > r * 1.25 && g > b * 1.10 && g > 0.2
      // The source has a dark wordmark that vanishes on the SNS image's dark overlay.
      // Keep the approved green stroke and render dark artwork white.
      let result = isGreen
        ? NSColor(calibratedRed: r, green: g, blue: b, alpha: color.alphaComponent)
        : NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: color.alphaComponent)
      output.setColor(result, atX: dstX + x, y: dstY + y)
    }
  }
}
// Image coordinates here are top-origin. Crops stop before the source tagline.
drawCrop(srcX: 90, srcY: 5, srcWidth: 280, srcHeight: 135,
         dstX: 48, dstY: 4, dstWidth: 224, dstHeight: 108)
drawCrop(srcX: 5, srcY: 170, srcWidth: 450, srcHeight: 56,
         dstX: 16, dstY: 130, dstWidth: 288, dstHeight: 36)
let png = output.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "assets/brand/setkeep_share_lockup.png"))
