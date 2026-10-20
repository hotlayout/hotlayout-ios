import Foundation
import XCTest

@testable import HotLayout

/// The shared table of a list item (`fixtures/list-marker/list-marker-cases.json`): the column of the
/// marker, what it says, the number among the siblings and the boxes of the item.
final class ListMarkerCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/list-marker/list-marker-cases.json")

    static let runGroups: Set<String> = ["geometryCases", "textCases", "numberCases", "instanceCases", "layoutCases", "naturalCases"]

    func testEveryGroupIsRun() {
        let groups = Set((Self.table.objectValue ?? JSONObject()).keys.filter { (Self.table[$0]?.arrayValue) != nil })
        XCTAssertEqual(groups, Self.runGroups)
    }

    func testTableShape() {
        XCTAssertEqual(Contract.rows(Self.table, "geometryCases").count, 18)
        XCTAssertEqual(Contract.rows(Self.table, "textCases").count, 10)
        XCTAssertEqual(Contract.rows(Self.table, "numberCases").count, 17)
        XCTAssertEqual(Contract.rows(Self.table, "instanceCases").count, 5)
        XCTAssertEqual(Contract.rows(Self.table, "layoutCases").count, 16)
        XCTAssertEqual(Contract.rows(Self.table, "naturalCases").count, 3)
    }

    private func marker(_ row: JSONObject) -> DrawnMarker {
        ListMarkerRules.drawn(row["marker"]) ?? .bullet
    }

    func testGeometryCases() {
        for row in Contract.rows(Self.table, "geometryCases") {
            let name = row["name"]?.stringValue ?? "?"
            let geometry = ListMarkerRules.geometry(marker(row), fontSize: row["fontSize"]?.numberValue ?? 0, groupSize: Int(row["groupSize"]?.numberValue ?? 1))
            XCTAssertEqual(geometry.column, row["expect"]?["column"]?.numberValue ?? -1, accuracy: 1e-9, "column: \(name)")
            XCTAssertEqual(geometry.gap, row["expect"]?["gap"]?.numberValue ?? -1, accuracy: 1e-9, "gap: \(name)")
            XCTAssertEqual(geometry.indent, row["expect"]?["indent"]?.numberValue ?? -1, accuracy: 1e-9, "indent: \(name)")
        }
    }

    func testTextCases() {
        for row in Contract.rows(Self.table, "textCases") {
            let name = row["name"]?.stringValue ?? "?"
            let text = ListMarkerRules.text(marker(row), number: Int(row["number"]?.numberValue ?? 1), formattingLocale: row["formattingLocale"]?.stringValue)
            XCTAssertEqual(text, row["expect"]?.stringValue, name)
        }
    }

    func testNumberCases() {
        for row in Contract.rows(Self.table, "numberCases") {
            let name = row["name"]?.stringValue ?? "?"
            let siblings = (row["siblings"]?.arrayValue ?? []).compactMap(\.objectValue)
            let markers: [DrawnMarker?] = siblings.map { $0["type"]?.stringValue == "Text" ? ListMarkerRules.drawn($0["marker"]) : nil }
            let visible = siblings.map { $0["visible"]?.boolValue != false }
            let numbers = markers.indices.map { ListMarkerRules.number(markers, at: $0, visible: visible) }
            let sizes = markers.indices.map { ListMarkerRules.groupSize(markers, at: $0) }
            XCTAssertEqual(numbers, (row["expect"]?["numbers"]?.arrayValue ?? []).map { $0.numberValue.map { Int($0) } }, "numbers: \(name)")
            XCTAssertEqual(sizes, (row["expect"]?["groupSizes"]?.arrayValue ?? []).map { $0.numberValue.map { Int($0) } }, "group sizes: \(name)")
        }
    }

    func testInstanceCases() {
        for row in Contract.rows(Self.table, "instanceCases") {
            let name = row["name"]?.stringValue ?? "?"
            let templateVisible = (row["templateVisible"]?.arrayValue ?? []).map { $0.boolValue ?? false }
            XCTAssertEqual(templateVisible.count, Int(row["records"]?.numberValue ?? -1), name)
            XCTAssertEqual(RepeaterPlan.numbers(shown: templateVisible), (row["expect"]?["numbers"]?.arrayValue ?? []).map { $0.numberValue.map { Int($0) } }, "numbers: \(name)")
            // The column follows the drawn instances: the group size of the item is the table's.
            XCTAssertEqual(templateVisible.count, Int(row["expect"]?["groupSize"]?.numberValue ?? -1), "group size: \(name)")
        }
    }

    func testLayoutCases() {
        for row in Contract.rows(Self.table, "layoutCases") {
            let name = row["name"]?.stringValue ?? "?"
            let layout = ListMarkerRules.layout(
                marker(row), fontSize: row["fontSize"]?.numberValue ?? 0, groupSize: Int(row["groupSize"]?.numberValue ?? 1),
                placeInline: row["placeInline"]?.numberValue ?? 0, rightToLeft: row["direction"]?.stringValue == "rtl",
                lines: row["lines"]?.numberValue.map { Int($0) }, maxLines: row["maxLines"]?.numberValue.map { Int($0) }, lineBlock: row["lineBlock"]?.numberValue
            )
            let expect = row["expect"]
            XCTAssertEqual(layout.markerFrom, expect?["markerBox"]?["from"]?.numberValue ?? -1, accuracy: 1e-9, "marker from: \(name)")
            XCTAssertEqual(layout.markerTo, expect?["markerBox"]?["to"]?.numberValue ?? -1, accuracy: 1e-9, "marker to: \(name)")
            XCTAssertEqual(layout.textFrom, expect?["textBox"]?["from"]?.numberValue ?? -1, accuracy: 1e-9, "text from: \(name)")
            XCTAssertEqual(layout.textTo, expect?["textBox"]?["to"]?.numberValue ?? -1, accuracy: 1e-9, "text to: \(name)")
            XCTAssertEqual(layout.textInline, expect?["textInline"]?.numberValue ?? -1, accuracy: 1e-9, "text width: \(name)")
            XCTAssertEqual(layout.markerOnRight ? "right" : "left", expect?["markerEdge"]?.stringValue, "marker edge: \(name)")
            XCTAssertEqual(layout.textFrom, expect?["secondLineFrom"]?.numberValue ?? -1, accuracy: 1e-9, "hanging indent: \(name)")
            if let block = expect?["block"]?.numberValue { XCTAssertEqual(layout.block ?? -1, block, accuracy: 1e-9, "block: \(name)") }
            if let drawn = expect?["markerDrawn"]?.boolValue { XCTAssertEqual(layout.markerDrawn, drawn, "marker drawn: \(name)") }
        }
    }

    func testNaturalCases() {
        for row in Contract.rows(Self.table, "naturalCases") {
            let name = row["name"]?.stringValue ?? "?"
            let natural = ListMarkerRules.naturalInline(marker(row), fontSize: row["fontSize"]?.numberValue ?? 0, groupSize: Int(row["groupSize"]?.numberValue ?? 1), textNaturalInline: row["textNaturalInline"]?.numberValue ?? 0)
            XCTAssertEqual(natural, row["expect"]?["naturalInline"]?.numberValue ?? -1, accuracy: 1e-9, name)
        }
    }
}
