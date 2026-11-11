import SwiftUI
import XCTest

@testable import HotLayout

/// The shared chart table (`fixtures/chart/chart-cases.json`): how a record becomes a point, the scale, the highlighted
/// point, the bars, the line, the monotone curve and the label boxes; and the chart drawn as a real node.
@MainActor
final class ChartCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/chart/chart-cases.json")
    private let tolerance = 1e-6

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    private func rows(_ group: String, _ count: Int) -> [JSONObject] {
        let list = Contract.rows(Self.table, group)
        XCTAssertEqual(list.count, count, "\(group): the table has \(list.count) rows")
        return list
    }

    private func numbers(_ value: JSONValue?) -> [Double] { (value?.arrayValue ?? []).compactMap(\.numberValue) }

    func testEveryGroupIsRun() {
        let groups = Set((Self.table.objectValue ?? JSONObject()).filter { $0.key.hasSuffix("Cases") && $0.value.arrayValue != nil }.map(\.key))
        XCTAssertEqual(
            groups, ["pointCases", "highlightCases", "barCases", "lineCases", "smoothCases", "labelCases", "plotHeightCases"],
            "a group of the table this test does not run, or a name that is no group")
    }

    func testPointCases() {
        for row in rows("pointCases", 7) {
            let collections = row["collections"]?.objectValue ?? JSONObject()
            let points = ChartRules.points(row["data"], collection: { collections[$0]?.arrayValue })
            let expected = (row["expect"]?.arrayValue ?? []).compactMap(\.objectValue).map {
                ChartRules.Point(value: $0["value"]?.numberValue ?? -1, label: $0["label"]?.stringValue ?? "?")
            }
            XCTAssertEqual(points, expected, name(row))
        }
    }

    func testHighlightCases() {
        for row in rows("highlightCases", 6) {
            let values = numbers(row["values"])
            let label = "\(values) \(row["highlight"]?.stringValue ?? "")"
            XCTAssertEqual(ChartRules.highlightIndex(values, row["highlight"]?.stringValue), row["expect"]?.numberValue.map { Int($0) }, label)
            let ratios = ChartRules.ratios(values)
            let expected = numbers(row["ratios"])
            XCTAssertEqual(ratios.count, expected.count, label)
            for (got, want) in zip(ratios, expected) { XCTAssertEqual(got, want, accuracy: tolerance, label) }
        }
    }

    func testBarCases() {
        for row in rows("barCases", 5) {
            let values = numbers(row["values"])
            let highlight = ChartRules.highlightIndex(values, row["highlight"]?.stringValue)
            let bars = ChartRules.bars(
                ratios: ChartRules.ratios(values, shown: row["shown"]?.numberValue ?? 1), width: row["width"]?.numberValue ?? 0,
                height: row["height"]?.numberValue ?? 0, gap: row["gap"]?.numberValue ?? 0, radius: row["radius"]?.numberValue ?? 0, highlight: highlight)
            let expected = (row["expect"]?.arrayValue ?? []).compactMap(\.objectValue)
            XCTAssertEqual(bars.count, expected.count, name(row))
            for (bar, want) in zip(bars, expected) {
                XCTAssertEqual(bar.x, want["x"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(bar.y, want["y"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(bar.width, want["width"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(bar.height, want["height"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(bar.radius, want["radius"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(bar.highlighted, want["highlighted"]?.boolValue, name(row))
            }
        }
    }

    func testLineCases() {
        for row in rows("lineCases", 3) {
            let values = numbers(row["values"])
            let line = ChartRules.line(
                ratios: ChartRules.ratios(values), width: row["width"]?.numberValue ?? 0, height: row["height"]?.numberValue ?? 0,
                lineWidth: row["lineWidth"]?.numberValue ?? 0, highlight: ChartRules.highlightIndex(values, row["highlight"]?.stringValue))
            let expected = row["expect"]?.objectValue ?? JSONObject()
            let points = (expected["points"]?.arrayValue ?? []).compactMap(\.objectValue)
            XCTAssertEqual(line.points.count, points.count, name(row))
            for (point, want) in zip(line.points, points) {
                XCTAssertEqual(point.x, want["x"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(point.y, want["y"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
            }
            XCTAssertEqual(line.inset, expected["inset"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
            XCTAssertEqual(line.baseline, expected["baseline"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
            if let dot = expected["dot"]?.objectValue {
                XCTAssertEqual(line.dot?.x ?? .nan, dot["x"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(line.dot?.y ?? .nan, dot["y"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(line.dot?.radius ?? .nan, dot["radius"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
            } else {
                XCTAssertNil(line.dot, name(row))
            }
        }
    }

    func testSmoothCases() {
        for row in rows("smoothCases", 4) {
            let points = (row["points"]?.arrayValue ?? []).compactMap(\.objectValue).map {
                ChartRules.XY(x: $0["x"]?.numberValue ?? 0, y: $0["y"]?.numberValue ?? 0)
            }
            let tangents = ChartRules.tangents(points)
            let expected = numbers(row["expectTangents"])
            XCTAssertEqual(tangents.count, expected.count, name(row))
            for (got, want) in zip(tangents, expected) { XCTAssertEqual(got, want, accuracy: tolerance, name(row)) }
            // The curve never leaves the values of its neighbours: between two points it stays between their heights.
            let segments = ChartRules.smoothSegments(points)
            XCTAssertEqual(segments.count, max(0, points.count - 1), name(row))
            for (index, segment) in segments.enumerated() {
                let from = points[index]
                let low = min(from.y, segment.to.y) - tolerance
                let high = max(from.y, segment.to.y) + tolerance
                for step in 0...20 {
                    let t = Double(step) / 20
                    let u = 1 - t
                    let y = u * u * u * from.y + 3 * u * u * t * segment.c1.y + 3 * u * t * t * segment.c2.y + t * t * t * segment.to.y
                    XCTAssertTrue(y >= low && y <= high, "\(name(row)): segment \(index) at \(t)")
                }
            }
        }
    }

    func testLabelCases() {
        for row in rows("labelCases", 3) {
            let boxes = ChartRules.labelBoxes(centers: numbers(row["centers"]), width: row["width"]?.numberValue ?? 0)
            let expected = (row["expect"]?.arrayValue ?? []).compactMap(\.objectValue)
            XCTAssertEqual(boxes.count, expected.count, name(row))
            for (box, want) in zip(boxes, expected) {
                XCTAssertEqual(box.index, Int(want["index"]?.numberValue ?? -1), name(row))
                XCTAssertEqual(box.left, want["left"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
                XCTAssertEqual(box.width, want["width"]?.numberValue ?? .nan, accuracy: tolerance, name(row))
            }
        }
    }

    func testPlotHeightCases() {
        for row in rows("plotHeightCases", 3) {
            let height = ChartRules.plotHeight(
                height: row["height"]?.numberValue ?? 0, labels: row["labels"]?.boolValue == true, labelLine: row["labelLine"]?.numberValue ?? 0,
                labelGap: row["labelGap"]?.numberValue ?? 0)
            XCTAssertEqual(height, row["expect"]?.numberValue ?? .nan, accuracy: tolerance, "\(row)")
        }
    }

    func testFieldReaders() {
        XCTAssertEqual(ChartRules.readHighlight("last"), "last")
        XCTAssertEqual(ChartRules.readHighlight("middle"), "none")
        XCTAssertEqual(ChartRules.readHighlight(nil), "none")
        XCTAssertTrue(ChartRules.readSmooth("smooth"))
        XCTAssertFalse(ChartRules.readSmooth("straight"))
        XCTAssertEqual(ChartRules.readLineWidth(nil), 2)
        XCTAssertEqual(ChartRules.readLineWidth(0), 1)
        XCTAssertEqual(ChartRules.readLineWidth(99), 8)
        XCTAssertEqual(ChartRules.readLineWidth("3"), 2)
    }

    func testFewerThanTwoPointsIsAnEmptyChartAndOver31AreCut() {
        let one = JSONValue.object(JSONObject([("kind", "literal"), ("points", [["value": 3]])]))
        XCTAssertEqual(ChartRules.points(one, collection: { _ in nil }), [])
        let many = JSONValue.object(JSONObject([("kind", "literal"), ("points", .array((0..<40).map { ["value": .number(Double($0))] }))]))
        XCTAssertEqual(ChartRules.points(many, collection: { _ in nil }).count, 31)
        XCTAssertEqual(ChartRules.points(["kind": "table"], collection: { _ in nil }), [])
        XCTAssertEqual(ChartRules.points(nil, collection: { _ in nil }), [])
    }

    // MARK: The chart as a real node

    private func chart(_ props: JSONObject, style: JSONObject = JSONObject()) throws -> DocumentNode {
        try Harness.node(.object(JSONObject([("id", "c"), ("type", "Chart"), ("props", .object(props)), ("style", .object(style))])))
    }

    private func render(_ node: DocumentNode, width: CGFloat, rightToLeft: Bool = false, scope: DataScope = [:]) throws -> Pixels {
        var context = Harness.context(rightToLeft: rightToLeft)
        context.scope = scope
        let view = NodeView(node: node, context: context, placement: .stretched)
            .frame(width: width)
            .background(Color.black)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return Pixels(try XCTUnwrap(renderer.cgImage))
    }

    private let bars: JSONObject = [
        "variant": "bars", "color": ["value": "#00ff00"], "barGap": 0, "barRadius": 0,
        "data": ["kind": "literal", "points": [["value": 10], ["value": 1]]],
    ]

    func testTheChartFillsTheWidthAndIsAsHighAsTheStyleOrOneHundredTwenty() throws {
        let plain = try render(try chart(bars), width: 200)
        XCTAssertEqual(plain.width, 200)
        XCTAssertEqual(plain.height, 120)
        let named = try render(try chart(bars, style: ["height": 64]), width: 200)
        XCTAssertEqual(named.height, 64)
    }

    func testBarsStandOnTheBottomAndTheFirstPointIsAtTheStart() throws {
        let node = try chart(bars)
        let pixels = try render(node, width: 200)
        // The first bar is the tall one, at the start; the second one is a tenth as high.
        XCTAssertTrue(pixels.isColor(50, 100, "#00ff00"))
        XCTAssertTrue(pixels.isColor(50, 10, "#00ff00"))
        XCTAssertTrue(pixels.isColor(150, 118, "#00ff00"))
        XCTAssertFalse(pixels.isColor(150, 60, "#00ff00"))
        let mirrored = try render(node, width: 200, rightToLeft: true)
        XCTAssertTrue(mirrored.isColor(150, 100, "#00ff00"))
        XCTAssertFalse(mirrored.isColor(50, 60, "#00ff00"))
    }

    func testAnEmptyChartKeepsItsBoxAndDrawsNothing() throws {
        var props = bars
        props["data"] = ["kind": "literal", "points": [["value": 5]]]
        let pixels = try render(try chart(props), width: 200)
        XCTAssertEqual(pixels.height, 120)
        for point in [(50, 100), (150, 118), (100, 60)] { XCTAssertFalse(pixels.isColor(point.0, point.1, "#00ff00")) }
    }

    func testPointsFromACollectionOfTheData() throws {
        var props = bars
        props["data"] = ["kind": "collection", "source": "spend", "item": "s", "valueField": "s.amount"]
        let scope: DataScope = ["spend": [["s.amount": 10], ["amount": 1]]]
        let pixels = try render(try chart(props), width: 200, scope: scope)
        XCTAssertTrue(pixels.isColor(50, 10, "#00ff00"))
        XCTAssertFalse(pixels.isColor(150, 60, "#00ff00"))
    }

    func testTheAppearanceGrowsFromZeroAndTheTopOfTheScaleStandsAtOnce() throws {
        var props = bars
        props["animateIn"] = true
        let node = try chart(props)
        func pixels(at milliseconds: Double) throws -> Pixels {
            let view = NodeView(node: node, context: Harness.context(rightToLeft: false), placement: .stretched)
                .frame(width: 200).background(Color.black).environment(\.valueTransitionElapsedMs, milliseconds)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return Pixels(try XCTUnwrap(renderer.cgImage))
        }
        let start = try pixels(at: 0)
        XCTAssertFalse(start.isColor(50, 100, "#00ff00"), "nothing has grown yet")
        let end = try pixels(at: ValueTransition.durationMs)
        XCTAssertTrue(end.isColor(50, 10, "#00ff00"))
    }

    func testTheChartScreenFixtureReadsWithoutAnUnknownWidget() throws {
        let data = try Data(contentsOf: Contract.root.appendingPathComponent("fixtures/chart-screens.json"))
        let document = try HotlayoutDocument.load(data)
        XCTAssertFalse(document.reports.contains { $0.kind == .unknownWidget })
    }
}
