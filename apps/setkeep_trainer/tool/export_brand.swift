// Run from apps/setkeep_trainer: swift tool/export_brand.swift
// Native size/mask export only; artwork is supplied by image_gen.
import AppKit
import ImageIO
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = CGImageSourceCreateWithURL(root.appendingPathComponent("assets/brand/trainer_symbol_source.png") as CFURL, nil)!
let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let dark = CGColor(red: 15/255, green: 23/255, blue: 32/255, alpha: 1)
func export(_ path: String, _ size: Int, inset: CGFloat = 0, round: Bool = false) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: round ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    if round { ctx.addEllipse(in: bounds); ctx.clip() }
    ctx.setFillColor(dark); ctx.fill(bounds)
    ctx.interpolationQuality = .high
    ctx.draw(artwork, in: bounds.insetBy(dx: CGFloat(size)*inset, dy: CGFloat(size)*inset))
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(out))
}
export("assets/brand/trainer_icon.png", 1024)
let ios = "ios/Runner/Assets.xcassets"
let data = try! Data(contentsOf: root.appendingPathComponent("\(ios)/AppIcon.appiconset/Contents.json"))
let catalog = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
for item in catalog["images"] as! [[String: String]] {
    let point = Double(item["size"]!.split(separator: "x")[0])!
    let scale = Double(item["scale"]!.dropLast())!
    export("\(ios)/AppIcon.appiconset/\(item["filename"]!)", Int(point*scale))
}
let res = "android/app/src/main/res"
for (density, scale) in [("mdpi",1.0),("hdpi",1.5),("xhdpi",2.0),("xxhdpi",3.0),("xxxhdpi",4.0)] {
    export("\(res)/mipmap-\(density)/ic_launcher.png", Int(48*scale))
    export("\(res)/mipmap-\(density)/ic_launcher_round.png", Int(48*scale), round: true)
    // Symbol width 80%; 0.75 scale => 65dp; outer plates fit the safe circle.
    export("\(res)/drawable-\(density)/trainer_foreground.png", Int(108*scale), inset: 0.125)
}
print("Exported TRAINER native icons; use tool/export_native_splash.swift for splash assets")
