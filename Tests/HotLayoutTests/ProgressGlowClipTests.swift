import SwiftUI
import XCTest

@testable import HotLayout

/// A scale with a `glow` is not clipped by the box of its own node: the glow is a blurred copy that
/// lies outside the scale by its blur, and only an ancestor that clips may cut it, as it cuts a
/// shadow. A node without a glow keeps the clip of its radius.
@MainActor
final class ProgressGlowClipTests: XCTestCase {
    private func literal(_ value: Double) -> [String: Any] { ["kind": "literal", "value": value] }

    /// A scale in a padded column, so there is room around it for the glow to show; the rows above the
    /// scale hold ink only where the glow reaches.
    private func ink(above type: String, glow: String?, border: Bool = false) throws -> Int {
        var props: [String: Any] = ["value": literal(60), "max": literal(100), "color": "primary", "labelFormat": "none"]
        if let glow { props["glow"] = glow }
        var style: [String: Any] = ["radius": "lg", "width": 120, "height": type == "ProgressBar" ? 8 : 120]
        if border { style["border"] = ["color": "primary", "width": 2] }
        let scale: [String: Any] = ["id": "scale", "type": type, "props": props, "style": style]
        let holder: [String: Any] = [
            "id": "holder", "type": "Container", "props": ["direction": "column", "gap": "none"], "style": ["padding": 40], "children": [scale],
        ]
        let context = Body.context()
        let image = ProgressPixels.render(try Body.view([holder], context: context).frame(width: 300, height: 260, alignment: .topLeading))
        var count = 0
        for y in 0..<30 { for x in 0..<image.width where ProgressPixels.color(image, x: x, y: y).alpha > 0.02 { count += 1 } }
        return count
    }

    func testTheGlowOfABarReachesPastItsBox() throws {
        XCTAssertEqual(try ink(above: "ProgressBar", glow: nil), 0, "without a glow nothing lies above the scale")
        XCTAssertGreaterThan(try ink(above: "ProgressBar", glow: "strong"), 0, "the glow lies above the bar, past its box")
        XCTAssertGreaterThan(try ink(above: "ProgressBar", glow: "strong", border: true), 0, "with a border as well")
    }

    func testTheGlowOfARingReachesPastItsBox() throws {
        XCTAssertEqual(try ink(above: "CircularProgress", glow: nil), 0)
        XCTAssertGreaterThan(try ink(above: "CircularProgress", glow: "strong"), 0)
    }

    func testAnUnknownWordIsNoGlow() throws {
        XCTAssertEqual(try ink(above: "ProgressBar", glow: "huge"), 0, "the clip stays")
    }

    func testTheContentOfAnOrdinaryNodeWithARadiusIsStillClipped() throws {
        let inner: [String: Any] = ["id": "inner", "type": "Container", "props": ["direction": "column", "gap": "none"], "style": ["width": 200, "height": 60, "background": ["kind": "color", "color": "primary"]]]
        let card: [String: Any] = [
            "id": "card", "type": "Container", "props": ["direction": "column", "gap": "none"],
            "style": ["radius": "lg", "width": 100, "height": 60, "background": ["kind": "color", "color": "surface"]], "children": [inner],
        ]
        let image = ProgressPixels.render(try Body.view([card], context: Body.context()).frame(width: 300, height: 100, alignment: .topLeading))
        XCTAssertEqual(ProgressPixels.color(image, x: 150, y: 30).alpha, 0, accuracy: 0.01, "the wide child does not leave the card")
    }
}
