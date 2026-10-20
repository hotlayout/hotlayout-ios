import SwiftUI
import XCTest

@testable import HotLayout

/// Draws one node of a document off screen, as the reader draws it, and reads pixels back.
struct Pixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let bytesPerPixel: Int
    private let bytesPerRow: Int

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytesPerPixel = image.bitsPerPixel / 8
        bytesPerRow = image.bytesPerRow
        bytes = Array((image.dataProvider?.data as Data?) ?? Data())
    }

    /// The colour at a pixel as red, green, blue.
    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = y * bytesPerRow + x * bytesPerPixel
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    /// Whether the pixel is the colour, within the tolerance of colour management.
    func isColor(_ x: Int, _ y: Int, _ hex: String) -> Bool {
        guard let c = rgb(x, y), let want = RGBA(hex: hex) else { return false }
        return abs(c.r - Int((want.red * 255).rounded())) <= 12 && abs(c.g - Int((want.green * 255).rounded())) <= 12 && abs(c.b - Int((want.blue * 255).rounded())) <= 12
    }
}

@MainActor
enum Harness {
    /// A node of a document: `json` is wrapped into a screen and read by the document reader.
    static func node(_ json: JSONValue) throws -> DocumentNode {
        let document = try loadDocument(.object(JSONObject([
            ("schemaVersion", "9.27.0"), ("documentId", "d"), ("name", "n"), ("initialScreenId", "a"),
            ("screens", [.object(JSONObject([
                ("screenId", "a"), ("name", "A"),
                ("root", .object(JSONObject([("id", "r"), ("type", "Screen"), ("props", .object(JSONObject())), ("children", [json])]))),
            ]))]),
        ])))
        return try XCTUnwrap(document.screens.first?.root.children.first)
    }

    static func context(rightToLeft: Bool) -> RenderContext {
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme(nil))
        return RenderContext(
            resolver: resolver, screenId: "a", localization: nil,
            locale: Localization.resolve(nil, requested: "en"), scope: [:], timeZone: nil, now: 0,
            rightToLeft: rightToLeft, inherited: NodeStyle.root(resolver), sink: ReportSink(), images: ImagePolicy(), pressHandler: { _, _, _ in PressRun(runner: .none, task: nil) }
        )
    }

    /// The node drawn at its natural size with `margin` of empty space around it.
    static func render(_ node: DocumentNode, rightToLeft: Bool, margin: CGFloat) throws -> Pixels {
        let view = NodeView(node: node, context: context(rightToLeft: rightToLeft), placement: .natural)
            .padding(margin)
            .background(Color.black)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return Pixels(try XCTUnwrap(renderer.cgImage))
    }

    static func box(_ id: String, width: Double, height: Double, color: String, fields: [(String, JSONValue)] = []) -> JSONValue {
        .object(JSONObject([
            ("id", .string(id)), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
            ("style", ["width": .number(width), "height": .number(height), "background": ["kind": "color", "color": ["value": .string(color)]]]),
            ("children", []),
        ] + fields))
    }
}
