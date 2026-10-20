#if canImport(AppKit)
import SwiftUI
import XCTest

@testable import HotLayout

/// The layouts `ListTileWidget` draws a row with, drawn off screen against the shared table: the
/// three columns (`rowCases`, both directions) and the trailing column (`trailingColumnCases`).
@MainActor
final class ListTileLayoutTests: XCTestCase {
    let table = try! Contract.json("fixtures/list-tile/list-tile-cases.json")

    private func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }

    /// The value, or `nil` for a missing or JSON `null` one.
    private func present(_ value: JSONValue?) -> JSONValue? {
        guard let value, !value.isNull else { return nil }
        return value
    }

    private func colour(_ index: Int) -> Color {
        let c = AdaptiveRender.colour(index)
        return Color(.sRGB, red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
    }

    func testRowColumnsAreWhereTheTableSays() throws {
        let rows = Contract.rows(table, "rowCases")
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let width = number(row["rowInline"])
            let rightToLeft = row["direction"]?.stringValue == "rtl"
            let leading = present(row["leading"])
            let trailing = present(row["trailing"])
            let view = ListTileRowLayout(gap: number(row["gap"])) {
                if let leading {
                    colour(0).frame(width: number(leading["inline"]), height: number(leading["block"])).layoutValue(key: ListTileColumnKey.self, value: .leading)
                }
                colour(1).frame(maxWidth: .infinity).frame(height: number(row["bodyBlock"])).layoutValue(key: ListTileColumnKey.self, value: .body)
                if let trailing {
                    colour(2).frame(width: number(trailing["inline"]), height: number(trailing["block"])).layoutValue(key: ListTileColumnKey.self, value: .trailing)
                }
            }
            .frame(width: width)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
            // The row stands at the left edge of a wider canvas: a column that does not shrink may
            // stand past the end of the row.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
            let pixels = try AdaptiveRender.draw(view, width: width + 100, height: 200)
            let boxes = AdaptiveRender.box(of: (0..<3).map(AdaptiveRender.colour), in: pixels)
            let expected = row["expected"]
            for (index, key) in ["leading", "body", "trailing"].enumerated() {
                guard let want = expected?[key], !want.isNull, number(want["width"]) > 0, number(want["height"]) > 0 else {
                    XCTAssertNil(boxes[index], "\(key): \(name)")
                    continue
                }
                let x = number(want["x"])
                let box = try XCTUnwrap(boxes[index], "\(key): \(name)")
                XCTAssertEqual(Double(box.minX), x, accuracy: 1, "\(key) x: \(name)")
                XCTAssertEqual(Double(box.minY), number(want["y"]), accuracy: 1, "\(key) y: \(name)")
                XCTAssertEqual(Double(box.width), number(want["width"]), accuracy: 1, "\(key) width: \(name)")
                XCTAssertEqual(Double(box.height), number(want["height"]), accuracy: 1, "\(key) height: \(name)")
            }
        }
    }

    func testTrailingColumnPushesBothLinesToTheEnd() throws {
        for row in Contract.rows(table, "trailingColumnCases") {
            let name = row["name"]?.stringValue ?? "?"
            let caption = present(row["caption"])
            let view = ListTileTrailingLayout {
                colour(0).frame(width: number(row["textInline"]), height: number(row["textLine"]))
                if let caption { colour(1).frame(width: number(caption["inline"]), height: number(caption["line"])) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
            let pixels = try AdaptiveRender.draw(view, width: 300, height: 120)
            let boxes = AdaptiveRender.box(of: [AdaptiveRender.colour(0), AdaptiveRender.colour(1)], in: pixels)
            let expected = row["expected"]
            let text = try XCTUnwrap(boxes[0], name)
            XCTAssertEqual(Double(text.minX), number(expected?["textStart"]), accuracy: 1, "text: \(name)")
            if let start = expected?["captionStart"], !start.isNull {
                let box = try XCTUnwrap(boxes[1], name)
                XCTAssertEqual(Double(box.minX), number(start), accuracy: 1, "caption: \(name)")
                XCTAssertEqual(Double(box.minY), number(row["textLine"]), accuracy: 1, "caption under the text: \(name)")
            }
            XCTAssertEqual(Double((boxes.compactMap { $0 }.map(\.maxX).max() ?? 0)), number(expected?["inline"]), accuracy: 1, "inline: \(name)")
        }
    }
}
#endif
