import SwiftUI
import XCTest

@testable import HotLayout

/// Lists from data against the shared tables: the filter and the grid, the numbers, groups
/// (`repeater-filter/…`, `repeater-group/…`) and the live record (`scope/…`, 9.27.0).
final class ListsCasesTests: XCTestCase {
    static let filterTable = try! Contract.json("fixtures/repeater-filter/repeater-filter-cases.json")
    static let groupTable = try! Contract.json("fixtures/repeater-group/repeater-group-cases.json")
    static let scopeTable = try! Contract.json("fixtures/scope/record-scope-cases.json")

    /// Groups of rows this reader does not run, each with the reason. The test fails when a
    /// group of a table is neither run nor named here, and when a name here is no longer a group.
    static let notRun: [String: String] = [
        "repeater-filter/carouselCases": "run by CarouselCasesTests.testStopsOfTheCardsDrawn",
        "repeater-filter/documentCases": "rules of the validator (what may be published); the reader draws any document it can read",
        "repeater-filter/filterCases": "run by ConditionCasesTests.testListFilter",
        "repeater-filter/limitCases": "run by ConditionCasesTests.testListFilter",
        "repeater-filter/emptinessCases": "run by ConditionCasesTests.testFilteredEmptiness",
        "repeater-group/documentCases": "rules of the validator (where `groupBy` may stand); the reader draws any document it can read",
    ]

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "repeater-filter/gridCases", "repeater-filter/numberCases",
            "repeater-group/sameCases", "repeater-group/groupCases", "repeater-group/listCases", "repeater-group/ruleCases",
            "scope/entitySourceCases", "scope/liveRecordCases", "scope/liveFlowCases",
        ]
        var groups: Set<String> = []
        for (name, table) in [("repeater-filter", Self.filterTable), ("repeater-group", Self.groupTable), ("scope", Self.scopeTable)] {
            for (key, value) in table.objectValue ?? JSONObject() where key.hasSuffix("Cases") && value.arrayValue != nil {
                groups.insert("\(name)/\(key)")
            }
        }
        let known = run.union(Self.notRun.keys)
        // The 9.2.0 tables of `scope/` are run by RecordScopeCasesTests.
        let scope9_2: Set<String> = ["scope/readCases", "scope/recordCases", "scope/flowCases"]
        XCTAssertEqual(groups.subtracting(scope9_2).subtracting(known), [], "groups of the tables that are neither run nor named")
        XCTAssertEqual(known.subtracting(groups), [], "names that are no longer groups")
    }

    // MARK: Grid and numbers

    func testGridCells() {
        let records = Self.filterTable["records"]?.arrayValue ?? []
        let rows = Contract.rows(Self.filterTable, "gridCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let drawn = RepeaterPlan.drawnIndexes(records: records, item: "reward", filter: row["where"], outer: Contract.scope(row["outer"]), limit: nil)
            let columns = gridColumns(row["columns"]) ?? 0
            let cells = GridGeometry.cells(count: drawn.count, columns: columns)
            XCTAssertEqual(cells, (row["cells"]?.arrayValue ?? []).map { ($0.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) } }, row["name"]?.stringValue ?? "?")
        }
    }

    func testCellWidthIsTheSameFormula() {
        XCTAssertEqual(GridGeometry.cellWidth(total: 361, columns: 2, gap: 8), 176.5)
        XCTAssertEqual(GridGeometry.cellWidth(total: 361, columns: 3, gap: 0), 361.0 / 3)
        XCTAssertEqual(GridGeometry.cellWidth(total: 320, columns: 4, gap: 8), 74)
    }

    func testColumnsReading() {
        XCTAssertNil(gridColumns(nil))
        XCTAssertNil(gridColumns(.null))
        XCTAssertEqual(gridColumns(.string("x")), 2)
        XCTAssertEqual(gridColumns(3), 3)
        XCTAssertEqual(gridColumns(9), 6)
        XCTAssertEqual(gridColumns(0), 1)
    }

    func testNumbersCountTheRecordsDrawn() {
        let records = Self.filterTable["records"]?.arrayValue ?? []
        let rows = Contract.rows(Self.filterTable, "numberCases")
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            let drawn = RepeaterPlan.drawnIndexes(records: records, item: "reward", filter: row["where"], outer: Contract.scope(row["outer"]), limit: nil)
            let numbers = RepeaterPlan.numbers(shown: drawn.map { _ in true })
            XCTAssertEqual(numbers, (row["numbers"]?.arrayValue ?? []).map { $0.numberValue.map(Int.init) }, row["name"]?.stringValue ?? "?")
        }
    }

    func testHiddenTemplateTakesNoNumber() {
        XCTAssertEqual(RepeaterPlan.numbers(shown: [true, false, true, true]), [1, nil, 2, 3])
    }

    func testLimitIsBoundedAndTheCeilingHolds() {
        XCTAssertEqual(RepeaterPlan.limit(["limit": 0]), 1)
        XCTAssertEqual(RepeaterPlan.limit(["limit": "x"]), 1)
        XCTAssertEqual(RepeaterPlan.limit(["limit": 80]), 50)
        XCTAssertEqual(RepeaterPlan.limit(["limit": .null]), nil)
        XCTAssertNil(RepeaterPlan.limit([:]))
        let many = (0..<80).map { JSONValue.object(["id": .number(Double($0))]) }
        XCTAssertEqual(RepeaterPlan.drawnIndexes(records: many, item: "x", filter: nil, outer: [:], limit: nil).count, 50)
    }

    func testTemplateVisibilityIsJudgedPerRecord() {
        let template = DocumentNode(id: "t", type: "Text", fields: ["visibleIf": ["path": "task.done", "op": "isTrue"]])
        let node = DocumentNode(id: "r", type: "Repeater", props: ["source": "tasks", "item": "task"], children: [template])
        let scope: DataScope = ["tasks": [["done": true], ["done": false], ["done": true]]]
        let plan = RepeaterPlan(node: node, scope: scope)
        XCTAssertEqual(plan.instances.map(\.shown), [true, false, true])
        XCTAssertEqual(plan.instances.map(\.number), [1, nil, 2])
    }

    // MARK: Groups

    func testSameGroupValue() {
        let rows = Contract.rows(Self.groupTable, "sameCases")
        XCTAssertEqual(rows.count, 11)
        for row in rows {
            XCTAssertEqual(RecordGroups.isSame(row["left"], row["right"]), row["expect"]?.boolValue, row["name"]?.stringValue ?? "?")
        }
    }

    func testGroupsOfValues() {
        let rows = Contract.rows(Self.groupTable, "groupCases")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let groups = RecordGroups.groups(of: (row["values"]?.arrayValue ?? []).map { $0 })
            let expected = Contract.rows(row.asValue, "expect").map { ($0["start"]?.numberValue.map(Int.init) ?? -1, $0["size"]?.numberValue.map(Int.init) ?? -1) }
            XCTAssertEqual(groups.map { [$0.start, $0.size] }, expected.map { [$0.0, $0.1] }, row["name"]?.stringValue ?? "?")
        }
    }

    func testGroupedLists() {
        let rows = Contract.rows(Self.groupTable, "listCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            var props: JSONObject = ["source": "activities", "item": "activity", "groupBy": "activity.day"]
            if let filter = row["where"] { props["where"] = filter }
            if let limit = row["limit"] { props["limit"] = limit }
            let node = DocumentNode(
                id: "list", type: "Repeater", props: props,
                children: [DocumentNode(id: "record", type: "Text"), DocumentNode(id: "header", type: "Text")]
            )
            let plan = RepeaterPlan(node: node, scope: ["activities": row["records"] ?? .array([])])
            var drawn: [String] = []
            for instance in plan.instances {
                if instance.headerBefore { drawn.append("header:\(instance.scope["activity.day"]?.stringValue ?? "")") }
                if instance.shown { drawn.append("record:\(instance.scope["activity.title"]?.stringValue ?? "")") }
            }
            XCTAssertEqual(drawn, (row["expect"]?.arrayValue ?? []).compactMap(\.stringValue), row["name"]?.stringValue ?? "?")
        }
    }

    func testGroupRulesMirrorTheArtifact() throws {
        let schema = try Contract.json("screen-schema.json")
        let block = schema["x-repeaterGroup"]
        XCTAssertEqual(block?["prop"]?.stringValue, "groupBy")
        XCTAssertEqual(block?["header"]?["child"]?.numberValue.map(Int.init) ?? RecordGroups.headerChild, RecordGroups.headerChild)
        for row in Contract.rows(Self.groupTable, "ruleCases") where row["rule"]?.stringValue == "header.child" {
            XCTAssertEqual(row["expect"]?.numberValue.map(Int.init), RecordGroups.headerChild)
        }
    }

    // MARK: Live record (9.27.0)

    func testEntitySources() {
        let rows = Contract.rows(Self.scopeTable, "entitySourceCases")
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            let roots = (row["screens"]?.arrayValue ?? []).map(Self.node)
            let found = LiveRecord.entitySources(roots: roots)
            var expected: EntitySources = [:]
            for (entity, sources) in row["expected"]?.objectValue ?? JSONObject() { expected[entity] = (sources.arrayValue ?? []).compactMap(\.stringValue) }
            XCTAssertEqual(found, expected, row["name"]?.stringValue ?? "?")
        }
    }

    /// A node of a table row (`type`, `props`, `children`) as the reader holds it.
    static func node(_ json: JSONValue) -> DocumentNode {
        let object = json.objectValue ?? JSONObject()
        return DocumentNode(
            id: "n", type: object["type"]?.stringValue ?? "", props: object["props"]?.objectValue ?? JSONObject(),
            children: (object["children"]?.arrayValue ?? []).map(node)
        )
    }

    static func links(_ value: JSONValue?) -> [RecordLink] {
        (value?.arrayValue ?? []).compactMap(\.objectValue).map {
            RecordLink(source: $0["source"]?.stringValue ?? "", item: $0["item"]?.stringValue ?? "", fields: $0["fields"]?.objectValue ?? JSONObject())
        }
    }

    static func listsOf(_ row: JSONObject) -> EntitySources {
        LiveRecord.entitySources(lists: (row["lists"]?.arrayValue ?? []).compactMap(\.objectValue).map {
            (source: $0["source"]?.stringValue ?? "", item: $0["item"]?.stringValue ?? "")
        })
    }

    func testLiveRecordCases() {
        let rows = Contract.rows(Self.scopeTable, "liveRecordCases")
        XCTAssertEqual(rows.count, 23)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let sources = Self.listsOf(row)
            var chain = Self.links(row["chain"])
            for (index, update) in (row["updates"]?.arrayValue ?? []).compactMap(\.objectValue).enumerated() {
                let label = "\(name) — update \(index + 1)"
                let collections = update["collections"]?.objectValue ?? JSONObject()
                let next = LiveRecord.refresh(chain, collections: { collections[$0] }, sources: sources)
                let same = update["same"]?.boolValue == true
                XCTAssertEqual(next == chain, same, "same: \(label)")
                chain = next
                let record = LiveRecord.record(of: chain)
                XCTAssertEqual(record.map(ActionCasesTests.recordJSON) ?? .null, update["record"] ?? .null, "record: \(label)")
                if let read = update["read"]?.objectValue {
                    let session = Contract.scope(read["session"])
                    let answer = RecordScope.read(DataLayers(record: record, session: session), path: read["path"]?.stringValue ?? "")
                    XCTAssertEqual(answer?.value, read["value"], "read value: \(label)")
                    XCTAssertEqual(answer?.layer.rawValue, read["layer"]?.stringValue, "read layer: \(label)")
                }
            }
        }
    }

    func testLiveFlowCases() {
        let rows = Contract.rows(Self.scopeTable, "liveFlowCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let screens = (row["screens"]?.objectValue ?? JSONObject()).map { id, presentation in
                FlowDocument.Screen(screenId: id, presentation: presentation.stringValue == "modal" ? .modal : .page)
            }
            let document = FlowDocument(documentId: "live", screens: screens, initialScreenId: row["start"]?.stringValue, entryPoints: [:], entitySources: Self.listsOf(row))
            var flow = Flow(document: document, entry: nil)
            for (index, step) in (row["steps"]?.arrayValue ?? []).compactMap(\.objectValue).enumerated() {
                let label = "\(name) — step \(index + 1)"
                switch step["do"]?.stringValue {
                case "navigate":
                    var action: JSONObject = ["type": "navigate", "params": ["screenId": step["to"] ?? .null]]
                    if step["carryRecord"]?.boolValue == true { action["carryRecord"] = true }
                    _ = flow.press(action, instances: ActionCasesTests.instances(step["instances"]))
                case "back":
                    _ = flow.press(["type": "navigate.back"])
                case "data":
                    let collections = step["collections"]?.objectValue ?? JSONObject()
                    let shownBefore = flow.stack.map(\.screenId)
                    flow.refresh(collections: { collections[$0] })
                    XCTAssertEqual(flow.stack.map(\.screenId), shownBefore, "a data step is not a show: \(label)")
                default:
                    XCTFail("unknown step: \(label)")
                }
                let expect = step["expect"]?.objectValue
                XCTAssertEqual(flow.stack.map(\.screenId), (expect?["stack"]?.arrayValue ?? []).compactMap(\.stringValue), "stack: \(label)")
                let records = flow.stack.map { $0.record.map(ActionCasesTests.recordJSON) ?? .null }
                XCTAssertEqual(records, expect?["records"]?.arrayValue ?? [], "records: \(label)")
            }
        }
    }

    // MARK: Drawing

    /// A list, a grid and a grouped list with data are drawn without a crash, and a press in a
    /// row hands over the record of THAT row.
    @MainActor
    func testListsWithDataDraw() throws {
        let json: JSONValue = [
            "schemaVersion": "9.27.0", "documentId": "lists", "name": "Lists", "initialScreenId": "a",
            "screens": [
                [
                    "screenId": "a", "name": "A",
                    "root": [
                        "id": "root", "type": "Screen", "props": ["gap": "sm"],
                        "children": [
                            [
                                "id": "list", "type": "Repeater",
                                "props": ["source": "items", "item": "item", "direction": "column", "gap": "xs", "groupBy": "item.day"],
                                "children": [
                                    ["id": "row", "type": "Text", "props": ["content": ["kind": "binding", "path": "item.name", "fallback": ""]]],
                                    ["id": "head", "type": "Text", "props": ["content": ["kind": "binding", "path": "item.day", "fallback": ""]]],
                                ],
                            ],
                            [
                                "id": "tiles", "type": "Repeater",
                                "props": ["source": "items", "item": "item", "direction": "column", "gap": "xs", "columns": 2],
                                "children": [["id": "tile", "type": "Text", "props": ["content": ["kind": "binding", "path": "item.name", "fallback": ""]]]],
                            ],
                            [
                                "id": "grid", "type": "Grid", "props": ["columns": 3, "gap": "xs"],
                                "children": [
                                    ["id": "g1", "type": "Text", "props": ["content": ["kind": "literal", "value": "One"]]],
                                    ["id": "g2", "type": "Text", "props": ["content": ["kind": "literal", "value": "Two"]]],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let document = try HotlayoutDocument.load(json)
        let data: DataScope = ["items": [["name": "Alpha", "day": "Today"], ["name": "Beta", "day": "Today"], ["name": "Gamma", "day": "Mon"]]]
        let view = HotlayoutScreen(document: document, data: data, locale: "en").frame(width: 393, height: 852)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }
}

private extension JSONObject {
    var asValue: JSONValue { .object(self) }
}
