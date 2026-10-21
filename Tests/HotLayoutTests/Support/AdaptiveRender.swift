import SwiftUI
import XCTest
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@testable import HotLayout

/// Draws a whole document at a width the way a host does, off screen, and finds the boxes of the
/// table by their colours. A box has a colour of its own (`colour(i)`), so the pixels say where it stands.
@MainActor
enum AdaptiveRender {
    static let hostColor = (r: 238, g: 68, b: 34)

    /// The colour of the i-th box: red 0x11, blue 0xcc, green stepped by eight so that two are never close.
    static func hex(_ index: Int) -> String { String(format: "#11%02xcc", 40 + 8 * index) }
    static func background(_ index: Int) -> JSONValue { ["kind": "color", "color": ["value": .string(hex(index))]] }
    static let hostBackground: JSONValue = ["kind": "color", "color": ["value": "#ee4422"]]

    static func document(root: JSONValue, screens extra: [JSONValue] = [], localization: JSONValue? = nil) throws -> HotlayoutDocument {
        var object = JSONObject([
            ("schemaVersion", "9.27.0"), ("documentId", "adaptive"), ("name", "adaptive"), ("initialScreenId", "s"),
            ("screens", .array([.object(JSONObject([("screenId", "s"), ("name", "s"), ("root", root)]))] + extra)),
        ])
        if let localization { object["localization"] = localization }
        return try HotlayoutDocument.load(.object(object))
    }

    static func screenRoot(_ children: [JSONValue], props: JSONObject = JSONObject(), style: JSONValue? = nil, propsOn: JSONValue? = nil, fields: JSONObject = JSONObject()) -> JSONValue {
        var allProps: JSONObject = ["gap": "none"]
        for (key, value) in props { allProps[key] = value }
        var object = JSONObject([("id", "root"), ("type", "Screen"), ("props", .object(allProps)), ("children", .array(children))])
        if let style { object["style"] = style }
        if let propsOn { object["propsOn"] = propsOn }
        for (key, value) in fields { object[key] = value }
        return .object(object)
    }

    /// A column container of the height the table names, with the colour of its index.
    static func cell(_ index: Int, _ spec: JSONObject) -> JSONValue {
        var style = JSONObject([("background", background(index)), ("height", spec["height"] ?? 10)])
        if let width = spec["width"] { style["width"] = width }
        var object = JSONObject([("id", .string("c\(index)")), ("type", "Container"), ("props", ["direction": "column"]), ("style", .object(style))])
        for key in ["weight", "showOn", "visibleIf"] { if let value = spec[key] { object[key] = value } }
        return .object(object)
    }

    /// The screen drawn by the platform view in a window of this size, one pixel to a point. A
    /// screen is drawn this way and not by `ImageRenderer`, which leaves out what stands in a scroll view
    /// (on iOS too: the screen's body is a scroll view, and `ImageRenderer` drew it empty there).
    static func render(
        _ document: HotlayoutDocument, width: Double, height: Double, rightToLeft: Bool = false, data: DataScope = [:], safe: (top: Double, bottom: Double) = (0, 0)
    ) throws -> Pixels {
        let view = HotlayoutScreen(document: document, data: data, locale: rightToLeft ? "ar" : "en", now: Date(timeIntervalSince1970: 1_791_000_000))
        return try draw(view, width: width, height: height)
    }

    static func draw<V: View>(_ screen: V, width: Double, height: Double) throws -> Pixels {
        #if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.accessory)
        let hosting = NSHostingView(rootView: screen)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // Off screen, transparent and never in front: the window is for the layout only.
        window.setFrame(NSRect(x: -20000, y: -20000, width: width, height: height), display: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
        ))
        rep.size = NSSize(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        return Pixels(try XCTUnwrap(rep.cgImage))
        #else
        // A window of the size, as a host gives one; the system's safe area is left out, as on macOS.
        let controller = UIHostingController(rootView: screen)
        if #available(iOS 16.4, *) { controller.safeAreaRegions = [] }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let window = UIWindow(frame: bounds)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = bounds
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        // The layers drawn into bytes in the order `Pixels` reads them (red, green, blue, alpha, sRGB).
        // `drawHierarchy` gives an empty picture in a test process of no application.
        let context = try XCTUnwrap(CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        controller.view.layer.render(in: context)
        window.isHidden = true
        return Pixels(try XCTUnwrap(context.makeImage()))
        #endif
    }

    /// The bounding box of a colour in the picture, or `nil` when it is not there.
    static func box(of colors: [(Int, Int, Int)], in pixels: Pixels) -> [CGRect?] {
        var minX = [Int](repeating: Int.max, count: colors.count), minY = minX, maxX = [Int](repeating: -1, count: colors.count), maxY = maxX
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                guard let c = pixels.rgb(x, y) else { continue }
                // The paper of the picture is by far the most of it.
                if c.r > 245 && c.g > 245 && c.b > 245 { continue }
                for (index, want) in colors.enumerated() where abs(c.r - want.0) <= 3 && abs(c.g - want.1) <= 3 && abs(c.b - want.2) <= 3 {
                    minX[index] = min(minX[index], x); maxX[index] = max(maxX[index], x)
                    minY[index] = min(minY[index], y); maxY[index] = max(maxY[index], y)
                }
            }
        }
        return colors.indices.map { maxX[$0] < 0 ? nil : CGRect(x: minX[$0], y: minY[$0], width: maxX[$0] - minX[$0] + 1, height: maxY[$0] - minY[$0] + 1) }
    }

    /// The colour of the i-th box as it is in the picture.
    static func colour(_ index: Int) -> (Int, Int, Int) { (0x11, 40 + 8 * index, 0xcc) }
}

extension AdaptiveRender {
    /// Writes a picture to a file, for looking at it.
    static func save(_ image: CGImage, to path: String) {
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
