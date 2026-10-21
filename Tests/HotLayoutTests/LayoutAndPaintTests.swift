import SwiftUI
import XCTest

@testable import HotLayout

/// Layout and paint the contract states and a drawing shows: the layer of a stack takes its own
/// size, a named side makes the box of an icon, a gradient lies over the
/// role of a button, and the glass of a node.
@MainActor
final class LayoutAndPaintTests: XCTestCase {
    static let chrome = try! Contract.json("fixtures/media-chrome/media-chrome-cases.json")

    // MARK: the own glyph size (`x-style.layout.ownGlyphSize`)

    func testGlyphCases() {
        let rows = Contract.rows(Self.chrome, "glyphCases")
        XCTAssertEqual(rows.count, 32)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let typography = row["typography"]
            let pad = row["padding"]?.numberValue ?? 0
            let border = row["border"]?.numberValue ?? 0
            let fontSize = typography?["fontSize"]?.numberValue ?? 0
            let line = fontSize * (typography?["lineHeight"]?.numberValue ?? 1)
            let isButton = row["widget"]?.stringValue == "IconButton"
            let result = GlyphGeometry.of(.init(
                glyphSize: row["glyphSize"]?.numberValue, fontSize: fontSize, paddingInline: 2 * pad, paddingBlock: 2 * pad, borderWidth: border,
                width: row["style"]?["width"]?.numberValue, height: row["style"]?["height"]?.numberValue,
                word: isButton ? CGSize(width: line, height: line) : CGSize(width: fontSize, height: line)
            ))
            let expect = row["expect"]
            XCTAssertEqual(result.glyph, expect?["glyph"]?.numberValue ?? -1, accuracy: 0.01, "glyph: \(name)")
            XCTAssertEqual(result.content.width, expect?["content"]?["inline"]?.numberValue ?? -1, accuracy: 0.01, "content inline: \(name)")
            XCTAssertEqual(result.content.height, expect?["content"]?["block"]?.numberValue ?? -1, accuracy: 0.01, "content block: \(name)")
            XCTAssertEqual(result.box.width, expect?["box"]?["inline"]?.numberValue ?? -1, accuracy: 0.01, "box inline: \(name)")
            XCTAssertEqual(result.box.height, expect?["box"]?["block"]?.numberValue ?? -1, accuracy: 0.01, "box block: \(name)")
        }
    }

    private func render(_ json: JSONValue, rightToLeft: Bool = false, margin: CGFloat = 10) throws -> Pixels {
        try Harness.render(Harness.node(json), rightToLeft: rightToLeft, margin: margin)
    }

    private func object(_ pairs: [(String, JSONValue)]) -> JSONValue { .object(JSONObject(pairs)) }

    /// An `Icon` with named sides stands in the CENTRE of its box and is clamped to it.
    func testNamedIconIsCentredAndClamped() throws {
        let node = object([
            ("id", "i"), ("type", "Icon"), ("props", ["name": "star", "size": "md", "glyphSize": 64]),
            ("style", ["width": 48, "height": 48, "color": ["value": "#ff0000"]]),
        ])
        let pixels = try render(node, margin: 10)
        XCTAssertEqual(pixels.width, 68)
        XCTAssertEqual(pixels.height, 68)
        // The glyph is clamped to 48 and centred: the red marks lie symmetric about the middle of
        // the box (34, 34) and inside it, none outside the box and none against its corner only.
        let red = redBounds(pixels)
        XCTAssertNotNil(red)
        guard let red else { return }
        XCTAssertGreaterThanOrEqual(red.minX, 10); XCTAssertLessThanOrEqual(red.maxX, 58)
        XCTAssertGreaterThanOrEqual(red.minY, 10); XCTAssertLessThanOrEqual(red.maxY, 58)
        XCTAssertEqual(Double(red.minX + red.maxX) / 2, 34, accuracy: 1.5)
        XCTAssertEqual(Double(red.minY + red.maxY) / 2, 34, accuracy: 1.5)
        XCTAssertGreaterThan(red.maxX - red.minX, 30, "drawn at the clamped size, not smaller")
    }

    private func redBounds(_ pixels: Pixels) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var found: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.rgb(x, y).map({ $0.r > 200 && $0.g < 60 && $0.b < 60 }) == true {
                found = (min(found?.minX ?? x, x), max(found?.maxX ?? x, x), min(found?.minY ?? y, y), max(found?.maxY ?? y, y))
            }
        }
        return found
    }

    /// An `IconButton` with a named side is that box, drawn whole; the glyph is clamped to the
    /// content box (56 − 2 × 8 = 40) and centred.
    func testNamedIconButtonFillsItsBox() throws {
        let node = object([
            ("id", "b"), ("type", "IconButton"), ("props", ["icon": "star", "size": "md", "glyphSize": 48, "label": "x", "variant": "primary"]),
            ("style", ["width": 56, "height": 56, "background": ["kind": "color", "color": ["value": "#0000ff"]]]),
        ])
        let pixels = try render(node, margin: 10)
        XCTAssertEqual(pixels.width, 76)
        XCTAssertEqual(pixels.height, 76)
        // The round surface covers the named 56 × 56, not a smaller natural button.
        XCTAssertTrue(pixels.isColor(38, 14, "#0000ff") || pixels.isColor(38, 13, "#0000ff"), "the top of the circle")
        XCTAssertTrue(pixels.isColor(38, 62, "#0000ff") || pixels.isColor(38, 63, "#0000ff"), "the bottom of the circle")
    }

    // MARK: a layer of a stack takes its own size

    /// A column in a stack is as wide as its widest child, not as the stack: its stretching
    /// child must not reach the left edge of the stack.
    func testColumnLayerOfAStackTakesItsOwnWidth() throws {
        let node = object([
            ("id", "s"), ("type", "Stack"), ("props", ["alignHorizontal": "center", "alignVertical": "center"]),
            ("children", [
                Harness.box("base", width: 200, height: 100, color: "#ffffff"),
                object([
                    ("id", "col"), ("type", "Column"), ("props", ["gap": "none", "align": "center"]),
                    ("children", [
                        object([
                            ("id", "stretching"), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
                            ("style", ["background": ["kind": "color", "color": ["value": "#ff0000"]]]),
                            ("children", [Harness.box("known", width: 40, height: 20, color: "#00ff00")]),
                        ]),
                    ]),
                ]),
            ]),
        ])
        for rtl in [false, true] {
            let pixels = try render(node, rightToLeft: rtl, margin: 10)
            XCTAssertEqual(pixels.width, 220)
            // The column is 40 wide and centred: x 90…130 of the stack, so 100…140 on the canvas.
            XCTAssertTrue(pixels.isColor(120, 60, "#00ff00"), "the child stands in the middle, rtl: \(rtl)")
            XCTAssertTrue(pixels.isColor(30, 60, "#ffffff"), "the stack is white far from the column, rtl: \(rtl)")
            XCTAssertTrue(pixels.isColor(195, 60, "#ffffff"), "and on the other side, rtl: \(rtl)")
        }
    }

    // MARK: gradient on a button

    func testButtonGradientBackground() throws {
        let node = object([
            ("id", "b"), ("type", "Button"), ("props", ["label": "", "variant": "primary", "fullWidth": true]),
            ("style", [
                "width": 100,
                "background": ["kind": "gradient", "gradient": ["angle": 90, "stops": [
                    ["color": ["value": "#ff0000"], "position": 0], ["color": ["value": "#0000ff"], "position": 1],
                ]]],
            ]),
        ])
        let pixels = try render(node, margin: 10)
        XCTAssertTrue(pixels.rgb(12, 18).map { $0.r > 200 && $0.b < 60 } ?? false, "the start of the gradient is red")
        XCTAssertTrue(pixels.rgb(108, 18).map { $0.b > 200 && $0.r < 60 } ?? false, "the end of the gradient is blue")
    }
}
