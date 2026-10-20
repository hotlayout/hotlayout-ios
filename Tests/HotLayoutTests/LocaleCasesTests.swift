import XCTest

@testable import HotLayout

/// The shared table of locale resolution (`fixtures/locale/locale-cases.json`).
final class LocaleCasesTests: XCTestCase {
    func testEveryRow() throws {
        let table = try Contract.json("fixtures/locale/locale-cases.json")
        let rows = Contract.rows(table, "cases")
        XCTAssertEqual(rows.count, 38)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let answer = resolveLocale(
                row["requested"]?.stringValue,
                available: (row["available"]?.arrayValue ?? []).compactMap(\.stringValue),
                source: row["source"]?.stringValue
            )
            XCTAssertEqual(answer.translation, row["translation"]?.stringValue, "translation: \(name)")
            XCTAssertEqual(answer.formatting, row["formatting"]?.stringValue, "formatting: \(name)")
            XCTAssertEqual(answer.directionLocale, row["directionLocale"]?.stringValue, "directionLocale: \(name)")
            XCTAssertEqual(answer.matched, row["matched"]?.boolValue, "matched: \(name)")
            if let direction = row["direction"]?.stringValue {
                let rtl = TextDirectionRule.isRightToLeft(answer.directionLocale) ?? false
                XCTAssertEqual(rtl ? "rtl" : "ltr", direction, "direction: \(name)")
            }
        }
    }
}
