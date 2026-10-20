import XCTest

/// Reads one pixel of a screenshot (points, scaled to the screenshot's pixels).
func pixel(_ shot: XCUIScreenshot, x: CGFloat, y: CGFloat) -> (r: Int, g: Int, b: Int) {
    let image = shot.image
    guard let cg = image.cgImage else { return (0, 0, 0) }
    let scale = CGFloat(cg.width) / image.size.width
    let px = Int(x * scale), py = Int(y * scale)
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(cg, in: CGRect(x: -px, y: py - cg.height + 1, width: cg.width, height: cg.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
}

func colourDistance(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Int {
    abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
}
