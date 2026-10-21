import SwiftUI
import XCTest

@testable import HotLayout

/// The border of a rounded node: drawn over the background, and the content is clipped by the
/// inner edge of the border, so the background shows in the corner as it does along the straight
/// edges (a picture inside a card leaves a thin rim of the card's colour all the way round).
@MainActor
final class BorderCornerTests: XCTestCase {
    private let rim = "#ee22aa"
    private let line = "#2244ee"
    private let content = "#22ee44"

    private func draw(border: JSONValue) throws -> (Pixels, CGRect) {
        let child = JSONValue.object(
            JSONObject([
                ("id", "in"), ("type", "Container"), ("props", ["direction": "column"]),
                ("style", ["height": 54, "background": ["kind": "color", "color": ["value": .string(content)]]]),
            ]))
        let box = JSONValue.object(
            JSONObject([
                ("id", "c"), ("type", "Container"), ("props", ["direction": "column"]), ("children", .array([child])),
                (
                    "style",
                    [
                        "width": 60, "height": 60, "radius": 20, "border": border,
                        "background": ["kind": "color", "color": ["value": .string(rim)]],
                    ]
                ),
            ]))
        let root = AdaptiveRender.screenRoot([box], style: ["padding": ["top": 60, "bottom": 60, "start": 60, "end": 60]])
        let drawn = try AdaptiveRender.render(try AdaptiveRender.document(root: root), width: 200, height: 200)
        let found = try XCTUnwrap(AdaptiveRender.box(of: [(0x22, 0xee, 0x44)], in: drawn)[0])
        // The content is inset by the border (2) on every side.
        return (drawn, found.insetBy(dx: -2, dy: -2))
    }

    func testBorderIsDrawnOverTheBackground() throws {
        let (drawn, box) = try draw(border: ["width": 2, "color": ["value": .string(line)]])
        let y = Int(box.midY)
        XCTAssertTrue(drawn.isColor(Int(box.minX), y, line), "the left edge is the line, not the background")
        XCTAssertTrue(drawn.isColor(Int(box.minX) + 3, y, content))
        // Along the arc of the corner the line is there too.
        let c = 20.0 - 19.0 * 0.7071
        XCTAssertTrue(drawn.isColor(Int(box.minX + c), Int(box.minY + c), line), "and round the corner")
    }

    func testContentDoesNotCoverTheCornerRim() throws {
        // A faint line over the background: what shows in the corner arc is the background, not the content.
        let (drawn, box) = try draw(border: ["width": 2, "color": ["value": "#ffffff10"]])
        let c = 20.0 - 19.0 * 0.7071
        let x = Int(box.minX + c), y = Int(box.minY + c)
        XCTAssertFalse(drawn.isColor(x, y, content), "the content is clipped by the inner edge of the border")
        let pixel = try XCTUnwrap(drawn.rgb(x, y))
        XCTAssertGreaterThan(pixel.r, 180, "the rim is the background of the card")
        XCTAssertLessThan(pixel.g, 110)
    }
}
