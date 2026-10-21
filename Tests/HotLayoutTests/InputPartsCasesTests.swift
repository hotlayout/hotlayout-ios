import SwiftUI
import XCTest

@testable import HotLayout

/// The parts of a text field (`inputPartsNote` of `fixtures/inputs/input-cases.json`): the box of the
/// field itself, a mark at each end, the counter and the row under the box. The rows run against the
/// pure rules the view calls; the documents that pass the schema are drawn by the real views.
final class InputPartsCasesTests: XCTestCase {
    static let table = InputCasesTests.table

    static func name(_ row: JSONObject) -> String { InputCasesTests.name(row) }

    func testBoxOfTheField() {
        let rows = Contract.rows(Self.table, "fieldBoxCases")
        XCTAssertEqual(rows.count, 16)
        for row in rows {
            let metrics = row["metrics"]
            let height = InputPartsRules.boxHeight(
                textLine: metrics?["textLine"]?.numberValue ?? 0, paddingBlock: metrics?["paddingBlock"]?.numberValue ?? 0,
                lines: Int(row["lines"]?.numberValue ?? 1), height: row["height"], borderWidth: row["borderWidth"]
            )
            XCTAssertEqual(height, row["expect"]?.numberValue, Self.name(row))
        }
    }

    func testRowInsideTheBox() {
        let rows = Contract.rows(Self.table, "affixRowCases")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let name = Self.name(row)
            let box = row["boxInline"]?.numberValue ?? 0
            let result = InputPartsRules.affixRow(
                boxInline: box, border: row["border"]?.numberValue ?? 0, paddingInline: row["paddingInline"]?.numberValue ?? 0,
                gap: row["gap"]?.numberValue ?? 0, prefix: row["prefix"]?.numberValue, suffix: row["suffix"]?.numberValue
            )
            let expect = row["expect"]
            XCTAssertEqual(result.prefixStart, expect?["prefixStart"]?.numberValue, name)
            XCTAssertEqual(result.textStart, expect?["textStart"]?.numberValue, name)
            XCTAssertEqual(result.textInline, expect?["textInline"]?.numberValue, name)
            XCTAssertEqual(result.suffixStart, expect?["suffixStart"]?.numberValue, name)
            // Right to left: the left edge is «box − start − width».
            if let rtl = row["rtl"] {
                XCTAssertEqual(box - (result.prefixStart ?? 0) - (row["prefix"]?.numberValue ?? 0), rtl["prefixX"]?.numberValue, "rtl prefix: \(name)")
                XCTAssertEqual(box - result.textStart - result.textInline, rtl["textX"]?.numberValue, "rtl text: \(name)")
                XCTAssertEqual(box - (result.suffixStart ?? 0) - (row["suffix"]?.numberValue ?? 0), rtl["suffixX"]?.numberValue, "rtl suffix: \(name)")
            }
        }
    }

    func testCounterText() {
        let rows = Contract.rows(Self.table, "counterCases")
        XCTAssertEqual(rows.count, 16)
        for row in rows {
            let props = row["props"]
            let text = InputPartsRules.counterText(counter: props?["counter"], maxLength: props?["maxLength"], shown: row["shown"]?.stringValue ?? "")
            XCTAssertEqual(text, row["expect"]?.stringValue, Self.name(row))
        }
    }

    func testRowUnderTheBox() {
        let rows = Contract.rows(Self.table, "noteRowCases")
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            let name = Self.name(row)
            let row_ = row["rowInline"]?.numberValue ?? 0
            let result = InputPartsRules.noteRow(rowInline: row_, gap: row["gap"]?.numberValue ?? 0, counter: row["counter"]?.numberValue)
            XCTAssertEqual(result.noteInline, row["expect"]?["noteInline"]?.numberValue, name)
            XCTAssertEqual(result.counterStart, row["expect"]?["counterStart"]?.numberValue, name)
            if let rtl = row["rtl"] {
                XCTAssertEqual(row_ - (result.counterStart ?? 0) - (row["counter"]?.numberValue ?? 0), rtl["counterX"]?.numberValue, "rtl: \(name)")
            }
        }
    }

    func testMarkTextIsCutToEightCodePoints() {
        XCTAssertEqual(InputPartsRules.affixText("12345678"), "12345678")
        XCTAssertEqual(InputPartsRules.affixText("123456789"), "12345678")
        // A surrogate pair is one code point and is never split.
        XCTAssertEqual(InputPartsRules.affixText(String(repeating: "😀", count: 9)), String(repeating: "😀", count: 8))
        XCTAssertEqual(InputPartsRules.affix(["kind": "text"]), nil)
        XCTAssertEqual(InputPartsRules.affix("₴"), nil)
        XCTAssertEqual(InputPartsRules.affix(["kind": "icon", "icon": "mail"]), .icon("mail"))
    }

    /// The documents of the table the schema accepts are drawn by the real views, in both directions.
    @MainActor
    func testDocumentsOfTheTableAreDrawn() throws {
        var drawn = 0
        for row in Contract.rows(Self.table, "partsDocumentCases") where row["schema"]?.boolValue == true {
            var props: JSONObject = ["label": ["kind": "literal", "value": "Field"], "value": ["kind": "binding", "path": "form.name"]]
            for (key, value) in row["props"]?.objectValue ?? JSONObject() { props[key] = value }
            let screen: JSONValue = [
                "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": "a",
                "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": [["id": "f", "type": "TextField", "props": .object(props)]]]]],
            ]
            guard let document = try? HotlayoutDocument.load(screen) else { XCTFail("not loaded: \(Self.name(row))"); continue }
            for locale in ["en", "ar"] {
                let view = HotlayoutScreen(document: document, data: ["form.name": "Alex"], locale: locale).frame(width: 320, height: 480)
                XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(Self.name(row)) \(locale)")
            }
            drawn += 1
        }
        XCTAssertGreaterThanOrEqual(drawn, 10)
    }
}
