import SwiftUI
import XCTest

@testable import HotLayout

/// A text or a bar label whose value runs is written in figures of equal width ALWAYS
/// (`value-transition/value-transition-cases.json`, `figureCases`): at rest, between values and in the place that is held.
@MainActor
final class TabularFiguresCasesTests: XCTestCase {
    private static let table: JSONValue = { try! Contract.json("fixtures/value-transition/value-transition-cases.json") }()

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testRows() {
        let rows = Contract.rows(Self.table, "figureCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let tabular = ValueTransition.tabularFigures(type: row["type"]?.stringValue ?? "", props: row["props"]?.objectValue ?? JSONObject())
            XCTAssertEqual(tabular, row["expected"]?["tabular"]?.boolValue, name(row))
        }
        // The label of a ring is tabular whatever its fields say: it is not asked here.
        XCTAssertFalse(ValueTransition.tabularFigures(type: "Container", props: ["animateIn": true]))
    }

    private func width(_ props: JSONObject, content: String) throws -> Int {
        var all = props
        all["content"] = ["kind": "literal", "value": .string(content)]
        let node = try Harness.node(.object(JSONObject([("id", "t"), ("type", "Text"), ("props", .object(all))])))
        let pixels = try Harness.render(node, rightToLeft: false, margin: 0)
        return pixels.width
    }

    /// The text that holds the place measures the same for any figures: "1111" is as wide as "8888" at rest.
    func testTextWithAFieldKeepsOneWidthAtRest() throws {
        for props: JSONObject in [["animateIn": true], ["animateChanges": true]] {
            XCTAssertEqual(try width(props, content: "1111"), try width(props, content: "8888"), "\(props)")
        }
    }
}
