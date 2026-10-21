import SwiftUI
import XCTest

@testable import HotLayout

/// A drawing read back pixel by pixel: the views are rendered off screen at scale 1.
@MainActor
enum ProgressPixels {
    struct Image {
        let width: Int
        let height: Int
        let data: [UInt8]
    }

    static func render<V: View>(_ view: V, scale: CGFloat = 1) -> Image {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return Image(width: 0, height: 0, data: []) }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Image(width: width, height: height, data: data)
    }

    /// Saves a drawing as a PNG (for looking at, not for asserting).
    static func writePNG<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage, let data = CFDataCreateMutable(nil, 0), let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, cg, nil)
        CGImageDestinationFinalize(destination)
        try? (data as Data).write(to: url)
    }

    /// The colour at a pixel, the origin at the top left, un-premultiplied.
    static func color(_ image: Image, x: Int, y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        let base = (y * image.width + x) * 4
        let alpha = Double(image.data[base + 3]) / 255
        guard alpha > 0 else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        return RGBA(red: Double(image.data[base]) / 255 / alpha, green: Double(image.data[base + 1]) / 255 / alpha, blue: Double(image.data[base + 2]) / 255 / alpha, alpha: alpha)
    }
}

extension RGBA {
    /// The same colour within a few levels of 255, over a fully opaque pixel.
    func isNear(_ other: RGBA, tolerance: Double = 0.03) -> Bool {
        abs(red - other.red) < tolerance && abs(green - other.green) < tolerance && abs(blue - other.blue) < tolerance && abs(alpha - other.alpha) < tolerance
    }
}

extension ProgressPixels.Image {
    /// The number of pixels that are not fully transparent.
    var inked: Int { stride(from: 3, to: data.count, by: 4).filter { data[$0] > 0 }.count }
}

/// A screen body drawn without the scroll view (`ImageRenderer` leaves a `ScrollView` blank):
/// the children of the root in a column, in a context the test builds.
@MainActor
enum Body {
    static func context(theme: HotlayoutTheme = HotlayoutThemeSet.builtIn.theme(), scope: DataScope = [:], rtl: Bool = false, locale: String = "en", sink: ReportSink = ReportSink()) -> RenderContext {
        let resolver = StyleResolver(theme: theme)
        return RenderContext(
            resolver: resolver, screenId: "s", localization: nil, locale: Localization.resolve(nil, requested: locale), scope: scope, timeZone: nil,
            now: 1_791_000_000_000, rightToLeft: rtl, inherited: NodeStyle.root(resolver), sink: sink, images: ImagePolicy(), pressHandler: { _, _, _ in PressRun(runner: .none, task: nil) }
        )
    }

    static func document(_ children: [[String: Any]]) throws -> DocumentNode {
        let root: [String: Any] = ["id": "root", "type": "Screen", "props": ["gap": "sm"], "children": children]
        let object: [String: Any] = ["schemaVersion": HotlayoutVersions.schema, "documentId": "t", "name": "t", "initialScreenId": "s", "screens": [["screenId": "s", "name": "s", "root": root]]]
        return try HotlayoutDocument.load(JSONValue.parse(JSONSerialization.data(withJSONObject: object))).screens[0].root
    }

    static func view(_ children: [[String: Any]], context: RenderContext) throws -> some View {
        let root = try document(children)
        return ColumnView(children: root.children, gap: 8, node: nil, context: context, depth: 0)
            .environment(\.layoutDirection, context.rightToLeft ? .rightToLeft : .leftToRight)
    }
}
