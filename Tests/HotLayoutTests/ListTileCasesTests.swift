import XCTest

@testable import HotLayout

/// The parts of a list row against the shared table (`list-tile/list-tile-cases.json`).
/// `documentCases` are verdicts of the JSON Schema and of the document validator, which this
/// reader does not have.
final class ListTileCasesTests: XCTestCase {
    private lazy var table = try! Contract.json("fixtures/list-tile/list-tile-cases.json")

    /// Equality of two values of the document with a tolerance for the numbers.
    private func same(_ left: JSONValue?, _ right: JSONValue?) -> Bool {
        switch (left, right) {
        case (.number(let a)?, .number(let b)?): return abs(a - b) < 1e-9
        case (.object(let a)?, .object(let b)?):
            return Set(a.keys) == Set(b.keys) && a.keys.allSatisfy { same(a[$0], b[$0]) }
        default: return left == right
        }
    }

    private func number(_ value: JSONValue?) -> Double { value?.numberValue ?? .nan }

    func testLineLimits() {
        let rows = Contract.rows(table, "lineCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            // The widget hands `lineLimit` to the text as its line limit; the text cuts what is over it.
            let natural = Int(number(row["natural"]))
            let limit = ListTileRules.lineLimit(row["limit"])
            XCTAssertEqual(limit.map { min(natural, $0) } ?? natural, Int(number(row["expected"]?["lines"])), row["name"]?.stringValue ?? "?")
            XCTAssertEqual(limit.map { natural > $0 } ?? false, row["expected"]?["cut"]?.boolValue, row["name"]?.stringValue ?? "?")
        }
    }

    func testTileUnderTheLeadingIcon() {
        let rows = Contract.rows(table, "tileCases")
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let tile = ListTileRules.tile(of: row["leading"])
            guard let expected = row["expected"], !expected.isNull else {
                XCTAssertNil(tile, name)
                continue
            }
            XCTAssertNotNil(tile, name)
            XCTAssert(same(tile?.color, expected["color"]), "color: \(name)")
            XCTAssert(same(tile?.radius, expected["radius"]), "radius: \(name)")
            XCTAssertEqual(tile?.size, number(expected["size"]), "size: \(name)")
        }
    }

    func testBoxOfTheLeadingIcon() {
        let rows = Contract.rows(table, "leadingBoxCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let glyph = (inline: number(row["glyph"]?["inline"]), block: number(row["glyph"]?["block"]))
            let box = ListTileRules.leadingBox(leading: row["leading"], glyph: glyph)
            let expected = row["expected"]
            XCTAssertEqual(box.inline, number(expected?["inline"]), name)
            XCTAssertEqual(box.block, number(expected?["block"]), name)
            XCTAssertEqual(box.glyphInline, number(expected?["glyphInline"]), name)
            XCTAssertEqual(box.glyphBlock, number(expected?["glyphBlock"]), name)
        }
    }

    func testTrailingColumn() {
        let rows = Contract.rows(table, "trailingColumnCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let caption = row["caption"].flatMap { $0.isNull ? nil : (inline: number($0["inline"]), line: number($0["line"])) }
            let column = ListTileRules.trailingColumn(textInline: number(row["textInline"]), textLine: number(row["textLine"]), caption: caption)
            let expected = row["expected"]
            XCTAssertEqual(column.inline, number(expected?["inline"]), name)
            XCTAssertEqual(column.block, number(expected?["block"]), name)
            XCTAssertEqual(column.textStart, number(expected?["textStart"]), name)
            if expected?["captionStart"]?.isNull == true {
                XCTAssertNil(column.captionStart, name)
            } else {
                XCTAssertEqual(column.captionStart, number(expected?["captionStart"]), name)
            }
        }
    }

    func testThreeColumnsOfTheRow() {
        let rows = Contract.rows(table, "rowCases")
        XCTAssertEqual(rows.count, 11)
        func column(_ value: JSONValue?) -> (inline: Double, block: Double)? {
            guard let value, !value.isNull else { return nil }
            return (number(value["inline"]), number(value["block"]))
        }
        func check(_ rect: ListTileRules.Rect?, _ expected: JSONValue?, _ label: String) {
            guard let expected, !expected.isNull else { return XCTAssertNil(rect, label) }
            XCTAssertEqual(rect?.x, number(expected["x"]), label)
            XCTAssertEqual(rect?.y, number(expected["y"]), label)
            XCTAssertEqual(rect?.width, number(expected["width"]), label)
            XCTAssertEqual(rect?.height, number(expected["height"]), label)
        }
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let rects = ListTileRules.rowRects(
                rowInline: number(row["rowInline"]), gap: number(row["gap"]), leading: column(row["leading"]), trailing: column(row["trailing"]),
                bodyBlock: number(row["bodyBlock"]), rightToLeft: row["direction"]?.stringValue == "rtl"
            )
            let expected = row["expected"]
            XCTAssertEqual(rects.block, number(expected?["block"]), name)
            check(rects.leading, expected?["leading"], "leading: \(name)")
            check(rects.body, expected?["body"], "body: \(name)")
            check(rects.trailing, expected?["trailing"], "trailing: \(name)")
        }
    }

    private func named(_ context: JSONValue?) -> ListTileRules.NamedColor {
        ListTileRules.NamedColor(ref: context?["color"] ?? .null, named: context?["colorNamed"]?.boolValue == true)
    }

    func testLooksOfTheParts() {
        let rows = Contract.rows(table, "lookCases")
        XCTAssertEqual(rows.count, 17)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let met = Set((row["met"]?.arrayValue ?? []).compactMap(\.stringValue))
            let isMet: (JSONValue) -> Bool = { met.contains($0["path"]?.stringValue ?? "") }
            let context = named(row["context"])
            let text = ListTileRules.trailingTextLook(row["trailing"], context: context, isMet: isMet)
            let caption = ListTileRules.captionLook(row["trailing"], context: context, isMet: isMet)
            let expected = row["expected"]
            XCTAssert(same(text.color, expected?["text"]?["color"]), "text colour: \(name): \(text.color)")
            XCTAssert(same(text.typography, expected?["text"]?["typography"]), "text typography: \(name)")
            XCTAssert(same(caption.color, expected?["caption"]?["color"]), "caption colour: \(name): \(caption.color)")
            XCTAssert(same(caption.typography, expected?["caption"]?["typography"]), "caption typography: \(name)")
        }
    }

    func testColourOfTheLeadingIcon() {
        let rows = Contract.rows(table, "leadingColorCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            let color = ListTileRules.leadingIconColor(row["leading"], context: named(row["context"]))
            XCTAssert(same(color, row["expected"]), row["name"]?.stringValue ?? "?")
        }
    }

    func testDocumentVerdictsAreNotAReadersConcern() {
        XCTAssertEqual(Contract.rows(table, "documentCases").count, 21)
    }
}
