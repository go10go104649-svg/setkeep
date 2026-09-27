import AppKit
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: swift extract_thumbnails.swift VIDEO_DIR THUMBNAIL_DIR")
}
let videos = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let files = try FileManager.default.contentsOfDirectory(at: videos, includingPropertiesForKeys: nil)
for file in files where file.pathExtension.lowercased() == "mp4" {
  let destination = output.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".png")
  if FileManager.default.fileExists(atPath: destination.path) { continue }
  let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
  generator.appliesPreferredTrackTransform = true
  let frame = try generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
  let side = 256
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
  )!
  let context = NSGraphicsContext(bitmapImageRep: bitmap)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  NSColor.white.setFill()
  NSRect(x: 0, y: 0, width: side, height: side).fill()
  let scale = min(CGFloat(side) / CGFloat(frame.width), CGFloat(side) / CGFloat(frame.height))
  let width = CGFloat(frame.width) * scale
  let height = CGFloat(frame.height) * scale
  let image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
  image.draw(in: NSRect(x: (CGFloat(side) - width) / 2,
                        y: (CGFloat(side) - height) / 2,
                        width: width, height: height))
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
  print("THUMBNAIL \(file.deletingPathExtension().lastPathComponent)")
}
