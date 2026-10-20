import XCTest

@testable import HotLayout

/// Conditions against the shared tables: emptiness (`inputs/input-cases.json`,
/// `emptinessCases`) and the list filter (`repeater-filter/repeater-filter-cases.json`).
final class ConditionCasesTests: XCTestCase {
    func testEmptiness() throws {
        let rows = Contract.rows(try Contract.json("fixtures/inputs/input-cases.json"), "emptinessCases")
        XCTAssertEqual(rows.count, 14)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            var scope: DataScope = [:]
            if let value = row["value"] { scope["x"] = value }
            XCTAssertEqual(Conditions.holds(["path": "x", "op": "isEmpty"], scope: scope), row["isEmpty"]?.boolValue, "isEmpty: \(name)")
            XCTAssertEqual(Conditions.holds(["path": "x", "op": "isNotEmpty"], scope: scope), row["isNotEmpty"]?.boolValue, "isNotEmpty: \(name)")
        }
    }

    func testListFilter() throws {
        let table = try Contract.json("fixtures/repeater-filter/repeater-filter-cases.json")
        let records = table["records"]?.arrayValue ?? []
        let filterRows = Contract.rows(table, "filterCases")
        let limitRows = Contract.rows(table, "limitCases")
        XCTAssertEqual(filterRows.count, 21)
        XCTAssertEqual(limitRows.count, 4)
        for row in filterRows {
            let passed = ListFilter.passedIndexes(records: row["records"]?.arrayValue ?? records, item: "reward", filter: row["where"], outer: Contract.scope(row["outer"]))
            XCTAssertEqual(passed, (row["passed"]?.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) }, row["name"]?.stringValue ?? "?")
        }
        for row in limitRows {
            let drawn = ListFilter.passedIndexes(records: records, item: "reward", filter: row["where"], outer: Contract.scope(row["outer"]), limit: row["limit"]?.numberValue.map(Int.init))
            XCTAssertEqual(drawn, (row["drawn"]?.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) }, row["name"]?.stringValue ?? "?")
        }
    }

    func testFilteredEmptiness() throws {
        let table = try Contract.json("fixtures/repeater-filter/repeater-filter-cases.json")
        let rows = Contract.rows(table, "emptinessCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            var scope = Contract.scope(row["outer"])
            if row["noList"]?.boolValue == true {
                scope["rewards"] = nil
            } else if row["emptyList"]?.boolValue == true {
                scope["rewards"] = .array([])
            } else {
                scope["rewards"] = row["records"] ?? table["records"]
            }
            XCTAssertEqual(Conditions.isVisible(row["condition"], scope: scope), row["holds"]?.boolValue, row["name"]?.stringValue ?? "?")
        }
    }
}
