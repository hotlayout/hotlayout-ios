import SwiftUI
import XCTest

@testable import HotLayout

/// Diagonal gradients follow CSS `to <corner>` on the laid-out box, not a corner-to-corner line.
@MainActor
final class DiagonalGradientTests: XCTestCase {
    private func points(_ angle: Double, _ w: Double, _ h: Double) -> (UnitPoint, UnitPoint) {
        gradientPoints(angle: angle, size: CGSize(width: w, height: h))
    }

    private func assertPoints(_ angle: Double, _ w: Double, _ h: Double, _ sx: Double, _ sy: Double, file: StaticString = #filePath, line: UInt = #line) {
        let squares = w * w + h * h
        let dx = sx * h * h / squares, dy = sy * w * w / squares
        let result = points(angle, w, h)
        XCTAssertEqual(result.1.x, 0.5 + dx, accuracy: 1e-9, "end.x \(angle) \(w)x\(h)", file: file, line: line)
        XCTAssertEqual(result.1.y, 0.5 + dy, accuracy: 1e-9, "end.y \(angle) \(w)x\(h)", file: file, line: line)
        XCTAssertEqual(result.0.x, 0.5 - dx, accuracy: 1e-9, "start.x \(angle) \(w)x\(h)", file: file, line: line)
        XCTAssertEqual(result.0.y, 0.5 - dy, accuracy: 1e-9, "start.y \(angle) \(w)x\(h)", file: file, line: line)
    }

    func testDiagonalsFollowTheFormula() {
        for (w, h) in [(360.0, 56.0), (56.0, 360.0), (100.0, 100.0)] {
            assertPoints(45, w, h, 1, -1)
            assertPoints(135, w, h, 1, 1)
            assertPoints(225, w, h, -1, 1)
            assertPoints(315, w, h, -1, -1)
        }
    }

    func testNumbersOnTheWideBox() {
        let r = points(135, 360, 56)
        let squares = 360.0 * 360 + 56 * 56
        XCTAssertEqual(r.1.x, 0.5 + 56 * 56 / squares, accuracy: 1e-9)
        XCTAssertEqual(r.1.y, 0.5 + 360 * 360 / squares, accuracy: 1e-9)
        XCTAssertGreaterThan(r.1.y, 1)  // the line leaves the box vertically: the corner sits at position 1
        let square = points(135, 80, 80)
        XCTAssertEqual(square.0.x, 0, accuracy: 1e-9); XCTAssertEqual(square.1.y, 1, accuracy: 1e-9)
    }

    func testAxesAreCssDegrees() {
        for (w, h) in [(360.0, 56.0), (56.0, 360.0), (100.0, 100.0)] {
            let up = points(0, w, h), right = points(90, w, h), down = points(180, w, h), left = points(270, w, h)
            XCTAssertEqual(up.0.x, 0.5, accuracy: 1e-9); XCTAssertEqual(up.0.y, 1, accuracy: 1e-9); XCTAssertEqual(up.1.y, 0, accuracy: 1e-9)
            XCTAssertEqual(right.0.x, 0, accuracy: 1e-9); XCTAssertEqual(right.1.x, 1, accuracy: 1e-9); XCTAssertEqual(right.0.y, 0.5, accuracy: 1e-9)
            XCTAssertEqual(down.0.y, 0, accuracy: 1e-9); XCTAssertEqual(down.1.y, 1, accuracy: 1e-9)
            XCTAssertEqual(left.0.x, 1, accuracy: 1e-9); XCTAssertEqual(left.1.x, 0, accuracy: 1e-9)
        }
    }

    func testOtherAnglesUseCssLineLength() {
        // 30° on 200x100: the line is |200 sin 30| + |100 cos 30| long, centred.
        let r = points(30, 200, 100)
        let length = 200 * 0.5 + 100 * (3.0).squareRoot() / 2
        XCTAssertEqual((r.1.x - r.0.x) * 200, 0.5 * length, accuracy: 1e-6)
        XCTAssertEqual((r.0.y - r.1.y) * 100, (3.0).squareRoot() / 2 * length, accuracy: 1e-6)
    }

    private func gradientNode(angle: Double) -> JSONValue {
        .object(JSONObject([
            ("id", "g"), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
            ("style", [
                "width": 360, "height": 56,
                "background": [
                    "kind": "gradient",
                    "gradient": ["angle": .number(angle), "stops": [["color": ["value": "#000000"], "position": 0], ["color": ["value": "#ffffff"], "position": 1]]],
                ],
            ]),
            ("children", []),
        ]))
    }

    private func luma(_ pixels: Pixels, _ x: Int, _ y: Int) throws -> Int {
        let c = try XCTUnwrap(pixels.rgb(x, y))
        return (c.r + c.g + c.b) / 3
    }

    func testDiagonalIsNotHorizontalOnAWideBox() throws {
        let pixels = try Harness.render(Harness.node(gradientNode(angle: 135)), rightToLeft: false, margin: 0)
        XCTAssertEqual(pixels.width, 360)
        XCTAssertEqual(pixels.height, 56)
        XCTAssertLessThan(try luma(pixels, 2, 2), 25)
        XCTAssertGreaterThan(try luma(pixels, 357, 53), 230)
        // A left-to-right gradient would give the same colour above and below the middle.
        let top = try luma(pixels, 180, 2), bottom = try luma(pixels, 180, 53)
        XCTAssertGreaterThan(bottom - top, 60)
        // Physical: right-to-left does not mirror it.
        let rtl = try Harness.render(Harness.node(gradientNode(angle: 135)), rightToLeft: true, margin: 0)
        XCTAssertLessThan(try luma(rtl, 2, 2), 25)
        XCTAssertGreaterThan(try luma(rtl, 357, 53), 230)
    }
}
