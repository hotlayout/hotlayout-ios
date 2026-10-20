import SwiftUI
import XCTest

@testable import HotLayout

/// The picture groups of `media-chrome-cases.json`: the proportion of a box, the box, where the
/// file lies in it, the radius that clips it and the circle. Every row runs through the rule
/// functions; the box and radius rows run once more through the real node drawn off screen.
@MainActor
final class ImageCasesTests: XCTestCase {
    static let table = ScreenAnatomyCasesTests.chrome

    private func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }
    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testRatioCases() {
        let rows = Contract.rows(Self.table, "ratioCases")
        XCTAssertEqual(rows.count, 20)
        for row in rows {
            let expected = number(row["expect"]?["width"]) / number(row["expect"]?["height"])
            XCTAssertEqual(ImageRules.ratio(of: row["aspectRatio"]), expected, accuracy: 1e-9, name(row))
        }
    }

    private func box(_ row: JSONObject) -> ImageRules.Box {
        let style = row["style"]?.objectValue ?? JSONObject()
        return ImageRules.box(
            aspectRatio: row["aspectRatio"], width: number(row["width"]), height: style["height"]?.numberValue,
            minHeight: style["minHeight"]?.numberValue, maxHeight: style["maxHeight"]?.numberValue
        )
    }

    func testImageBoxCases() {
        let rows = Contract.rows(Self.table, "imageBoxCases")
        XCTAssertEqual(rows.count, 18)
        for row in rows {
            let expect = row["expect"]?.objectValue ?? JSONObject()
            let actual = box(row)
            XCTAssertEqual(actual.width, number(expect["width"]), accuracy: 0.001, name(row))
            XCTAssertEqual(actual.height, number(expect["height"]), accuracy: 0.001, name(row))
            XCTAssertEqual(actual.byRatio, expect["byRatio"]?.boolValue, name(row))
        }
    }

    /// The same rows through the real node: the box the layout gives is the box of the table.
    func testImageBoxCasesThroughTheRealNode() throws {
        for row in Contract.rows(Self.table, "imageBoxCases") {
            let width = number(row["width"])
            guard width > 0 else { continue }
            var style = row["style"]?.objectValue ?? JSONObject()
            style["width"] = .number(width)
            let node = try Harness.node(.object(JSONObject([
                ("id", "img"), ("type", "Image"), ("props", .object(JSONObject(row["aspectRatio"].map { [("aspectRatio", $0)] } ?? []))), ("style", .object(style)),
            ])))
            let view = NodeView(node: node, context: Harness.context(rightToLeft: false), placement: .natural).fixedSize()
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage, name(row))
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(Double(image.width), number(expect["width"]).rounded(), accuracy: 1, name(row))
            XCTAssertEqual(Double(image.height), number(expect["height"]).rounded(), accuracy: 1, name(row))
        }
    }

    func testPaintCases() {
        let rows = Contract.rows(Self.table, "paintCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            let box = row["box"]?.objectValue ?? JSONObject()
            let rect = ImageRules.paintRect(boxWidth: number(box["width"]), boxHeight: number(box["height"]), natural: number(row["natural"]), fit: row["fit"]?.stringValue)
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(rect.x, number(expect["x"]), accuracy: 0.001, name(row))
            XCTAssertEqual(rect.y, number(expect["y"]), accuracy: 0.001, name(row))
            XCTAssertEqual(rect.width, number(expect["width"]), accuracy: 0.001, name(row))
            XCTAssertEqual(rect.height, number(expect["height"]), accuracy: 0.001, name(row))
        }
    }

    func testRadiusCases() {
        let rows = Contract.rows(Self.table, "radiusCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            let box = row["box"]?.objectValue ?? JSONObject()
            let (width, height, radius) = (number(box["width"]), number(box["height"]), number(row["radius"]))
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(ImageRules.effectiveRadius(boxWidth: width, boxHeight: height, radius: radius), number(expect["radius"]), name(row))
            // A circle: a square box whose corners the radius rounds to the half of its side.
            let rounded = ImageRules.effectiveRadius(boxWidth: width, boxHeight: height, radius: radius)
            XCTAssertEqual(width == height && rounded == width / 2, expect["circle"]?.boolValue, name(row))
        }
    }

    /// The circle rows: the style the panel writes (`pill` is the theme's number, 72) makes a circle
    /// of the side, and the node box clips it so: the corner is empty and the centre is painted.
    func testCircleCases() throws {
        let pill = try XCTUnwrap(HotlayoutThemeSet.builtIn.theme(nil).radius["pill"])
        XCTAssertEqual(pill, 72)
        for row in Contract.rows(Self.table, "circleCases") {
            let expect = row["expect"]?.objectValue ?? JSONObject()
            let side = number(row["side"])
            XCTAssertEqual(number(expect["width"]), side, name(row))
            XCTAssertEqual(number(expect["height"]), side, name(row))
            let radius = expect["radius"]?.stringValue == "pill" ? pill : number(expect["radius"])
            XCTAssertEqual(ImageRules.effectiveRadius(boxWidth: side, boxHeight: side, radius: radius), side / 2, name(row))
        }
    }

    private func circleNode(_ side: Double, radius: JSONValue) throws -> DocumentNode {
        try Harness.node(.object(JSONObject([
            ("id", "img"), ("type", "Image"), ("props", ["aspectRatio": "16:9"]),
            ("style", ["width": .number(side), "height": .number(side), "radius": radius, "background": ["kind": "color", "color": ["value": "#ff0000"]]]),
        ])))
    }

    func testCircleIsClippedByTheNode() throws {
        for rtl in [false, true] {
            let pixels = try Harness.render(try circleNode(56, radius: "pill"), rightToLeft: rtl, margin: 0)
            XCTAssertEqual(pixels.width, 56)
            XCTAssertEqual(pixels.height, 56)
            XCTAssertEqual(pixels.rgb(1, 1)?.r, 0, "corner is cut, rtl=\(rtl)")
            XCTAssertEqual(pixels.rgb(54, 54)?.r, 0)
            XCTAssertGreaterThan(pixels.rgb(28, 28)?.r ?? 0, 30, "centre is painted")
            XCTAssertGreaterThan(pixels.rgb(28, 3)?.r ?? 0, 30, "edge middle is painted")
        }
    }

    /// 160 with `pill` is a rounded square, not a circle: the corner is cut by 72, so (2, 65) is
    /// painted; a circle of radius 80 would cut it.
    func testPillOnALargeSquareIsNotACircle() throws {
        let pixels = try Harness.render(try circleNode(160, radius: "pill"), rightToLeft: false, margin: 0)
        XCTAssertEqual(pixels.rgb(4, 4)?.r, 0)
        XCTAssertGreaterThan(pixels.rgb(2, 65)?.r ?? 0, 30)
    }

    func testAltReachesTheAccessibilityLabel() throws {
        let context = Harness.context(rightToLeft: false)
        func alt(_ value: JSONValue?) throws -> String {
            let props: JSONObject = JSONObject(value.map { [("alt", $0)] } ?? [])
            let node = try Harness.node(.object(JSONObject([("id", "i"), ("type", "Image"), ("props", .object(props))])))
            return ImageWidget(node: node, context: context, look: BoxLook()).altText
        }
        XCTAssertEqual(try alt("Maya in a red coat"), "Maya in a red coat")
        XCTAssertEqual(try alt(nil), "")
        XCTAssertEqual(try alt(["kind": "template", "template": "Photo of {name}", "values": ["name": ["kind": "literal", "value": "Maya"]]]).isEmpty, false)
    }

    func testOnlyHttpsIsLoadedByDefault() {
        let policy = ImagePolicy()
        XCTAssertNotNil(policy.resolve("https://example.com/a.png"))
        for address in ["http://example.com/a.png", "data:image/png;base64,AAAA", "file:///etc/passwd", "/a.png", "javascript:alert(1)", "https://"] {
            XCTAssertNil(policy.resolve(address), address)
        }
    }
}
