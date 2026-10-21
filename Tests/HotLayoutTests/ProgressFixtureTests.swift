import SwiftUI
import XCTest

@testable import HotLayout

/// The progress fixture drawn as a whole screen, with the theme the fixture ships with, and
/// the nodes that need the rest of the pipeline: the box of the ring, the label, a changing
/// value on a real screen.
@MainActor
final class ProgressFixtureTests: XCTestCase {
    private func json(_ object: Any) throws -> JSONValue {
        try JSONValue.parse(JSONSerialization.data(withJSONObject: object))
    }

    private func screen(_ children: [[String: Any]], scope: DataScope = [:], width: CGFloat = 393, height: CGFloat = 400, rtl: Bool = false) throws -> ProgressPixels.Image {
        let context = Body.context(scope: scope, rtl: rtl)
        return ProgressPixels.render(try Body.view(children, context: context).frame(width: width, height: height, alignment: .topLeading))
    }

    private func literal(_ value: Double) -> [String: Any] { ["kind": "literal", "value": value] }

    private func ring(style: [String: Any]? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var props: [String: Any] = ["value": literal(50), "max": literal(100), "color": "primary", "size": "md", "thickness": 8]
        props.merge(extra) { $1 }
        var node: [String: Any] = ["id": "n", "type": "CircularProgress", "props": props]
        if let style { node["style"] = style }
        return node
    }

    /// The columns of the image that hold any ink.
    private func ink(_ image: ProgressPixels.Image, rows: Range<Int>) -> (first: Int, last: Int)? {
        var columns: [Int] = []
        for x in 0..<image.width where rows.contains(where: { ProgressPixels.color(image, x: x, y: $0).alpha > 0.5 && !ProgressPixels.color(image, x: x, y: $0).isNear(RGBA(red: 1, green: 1, blue: 1)) }) { columns.append(x) }
        guard let first = columns.first, let last = columns.last else { return nil }
        return (first, last)
    }

    func testARingStandsAtTheStartOfAColumnAtItsSizeWord() throws {
        let image = try screen([ring()])
        let span = try XCTUnwrap(ink(image, rows: 0..<200))
        XCTAssertEqual(span.last - span.first + 1, 72, accuracy: 2, "size md is three units of xl: 72")
    }

    func testANamedBoxCentresTheRingInIt() throws {
        let style: [String: Any] = ["width": 200, "height": 120]
        let image = try screen([ring(style: style)])
        let span = try XCTUnwrap(ink(image, rows: 0..<200))
        XCTAssertEqual(span.last - span.first + 1, 120, accuracy: 2, "the diameter is the smaller side")
        XCTAssertEqual(Double(span.first), 40, accuracy: 2, "centred in the 200 wide box: 40 free on each side")
    }

    /// The rows that hold any ink.
    private func rowsWithInk(_ image: ProgressPixels.Image) -> (first: Int, last: Int)? {
        let rows = (0..<image.height).filter { y in (0..<image.width).contains { ProgressPixels.color(image, x: $0, y: y).alpha > 0.5 } }
        guard let first = rows.first, let last = rows.last else { return nil }
        return (first, last)
    }

    func testTheLabelDoesNotSizeTheRing() throws {
        let plain = try screen([ring()])
        let labelled = try screen([ring(extra: ["labelFormat": "valueOfMax", "labelTypography": "displayL"])])
        let a = try XCTUnwrap(rowsWithInk(plain))
        let b = try XCTUnwrap(rowsWithInk(labelled))
        XCTAssertEqual(a.last - a.first, b.last - b.first, "the label sits over the arc, the box stays 72 tall")
        let hole = (0..<20).flatMap { dy in (0..<30).map { dx in ProgressPixels.color(labelled, x: 25 + dx, y: 26 + dy).alpha } }.filter { $0 > 0.3 }.count
        XCTAssertGreaterThan(hole, 20, "ink in the middle of the ring: the label")
        let emptyHole = (0..<20).flatMap { dy in (0..<30).map { dx in ProgressPixels.color(plain, x: 25 + dx, y: 26 + dy).alpha } }.filter { $0 > 0.3 }.count
        XCTAssertEqual(emptyHole, 0, "without a label the middle is empty")
    }

    func testABarFillsTheRowAndGrowsFromTheLogicalStart() throws {
        let bar: [String: Any] = ["id": "b", "type": "ProgressBar", "props": ["value": literal(25), "max": literal(100), "color": "primary", "labelFormat": "none", "thickness": 8]]
        let ltr = try screen([bar])
        let rtl = try screen([bar], rtl: true)
        let row = 4
        // The fill is darker than the track, so the red channel tells them apart.
        XCTAssertLessThan(ProgressPixels.color(ltr, x: 10, y: row).red, ProgressPixels.color(ltr, x: 380, y: row).red - 0.1, "left to right: the fill is at the left")
        XCTAssertLessThan(ProgressPixels.color(rtl, x: 383, y: row).red, ProgressPixels.color(rtl, x: 10, y: row).red - 0.1, "right to left: the fill is at the right")
    }

    func testTheFixtureBodyDrawsWithBothWidgetsDrawn() throws {
        XCTAssertTrue(DocumentReader.knownWidgets.isSuperset(of: ["ProgressBar", "CircularProgress"]))
        let json = try Contract.json("fixtures/progress-screens.json")
        let document = try HotlayoutDocument.load(json)
        let root = try XCTUnwrap(document.screens.first?.root)
        let theme = HotlayoutThemeSet.builtIn.theme()
        let context = Body.context(theme: theme)
        let body = ColumnView(children: root.children, gap: 12, node: nil, context: context, depth: 0).padding(16).background(Color.white)
            .frame(width: 393, alignment: .topLeading)
        let image = ProgressPixels.render(body)
        XCTAssertGreaterThan(image.inked, 1000)
        if let directory = ProcessInfo.processInfo.environment["HL_SNAPSHOT_DIR"] { ProgressPixels.writePNG(body, to: URL(fileURLWithPath: directory).appendingPathComponent("progress-body.png")) }
    }
}
