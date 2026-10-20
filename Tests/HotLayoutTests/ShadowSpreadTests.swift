import SwiftUI
import XCTest

@testable import HotLayout

/// The spread of a shadow layer grows its shape on every side, as CSS grows `box-shadow`; the
/// halo of a small circle (a ring around a check mark) is made of it alone.
@MainActor
final class ShadowSpreadTests: XCTestCase {
    private let ring = "#ee4422"

    private func pixels(radius: JSONValue?, spread: Double, blur: Double = 0) throws -> (Pixels, CGRect) {
        var style = JSONObject([
            ("width", 26), ("height", 26), ("background", AdaptiveRender.background(0)),
            ("shadow", .array([["offsetX": 0, "offsetY": 0, "blur": .number(blur), "spread": .number(spread), "color": ["value": .string(ring)]]])),
        ])
        if let radius { style["radius"] = radius }
        let box = JSONValue.object(JSONObject([("id", "c"), ("type", "Container"), ("props", ["direction": "column"]), ("style", .object(style))]))
        let root = AdaptiveRender.screenRoot([box], style: ["padding": ["top": 60, "bottom": 60, "start": 60, "end": 60]])
        let document = try AdaptiveRender.document(root: root)
        let drawn = try AdaptiveRender.render(document, width: 200, height: 200)
        let found = try XCTUnwrap(AdaptiveRender.box(of: [AdaptiveRender.colour(0)], in: drawn)[0])
        return (drawn, found)
    }

    func testSpreadMakesARingAroundACircle() throws {
        let (drawn, box) = try pixels(radius: "pill", spread: 6)
        let midY = Int(box.midY), midX = Int(box.midX)
        XCTAssertTrue(drawn.isColor(Int(box.maxX) + 2, midY, ring), "the ring stands just outside the circle")
        XCTAssertTrue(drawn.isColor(midX, Int(box.minY) - 3, ring))
        XCTAssertFalse(drawn.isColor(Int(box.maxX) + 9, midY, ring), "and ends at the spread")
        // The corner of the grown rect is not covered: the grown shape is round, not a square.
        XCTAssertFalse(drawn.isColor(Int(box.minX) - 4, Int(box.minY) - 4, ring))
    }

    func testSquareBoxKeepsSquareCorners() throws {
        let (drawn, box) = try pixels(radius: nil, spread: 6)
        XCTAssertTrue(drawn.isColor(Int(box.minX) - 4, Int(box.minY) - 4, ring))
    }

    func testNegativeSpreadDrawsNothingOutside() throws {
        let (drawn, box) = try pixels(radius: "pill", spread: -4, blur: 0)
        XCTAssertFalse(drawn.isColor(Int(box.maxX) + 2, Int(box.midY), ring))
    }
}
