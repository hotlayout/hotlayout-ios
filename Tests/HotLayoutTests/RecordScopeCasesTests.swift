import XCTest

@testable import HotLayout

/// The shared table of data layers and the record scope (`fixtures/scope/record-scope-cases.json`).
final class RecordScopeCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/scope/record-scope-cases.json")

    func testLayerOrderMirrorsTheArtifact() throws {
        let order = (Self.table["layerOrder"]?.arrayValue ?? []).compactMap(\.stringValue)
        XCTAssertEqual(order, DataLayer.allCases.map(\.rawValue))
        let schema = try Contract.json("screen-schema.json")
        XCTAssertEqual((schema["x-dataScope"]?["layers"]?.arrayValue ?? []).compactMap(\.stringValue), DataLayer.allCases.map(\.rawValue))
    }

    func testReadCases() {
        let rows = Contract.rows(Self.table, "readCases")
        XCTAssertEqual(rows.count, 17)
        for row in rows {
            let layers = row["layers"]?.objectValue ?? JSONObject()
            func layer(_ name: String) -> DataScope? {
                guard let value = layers[name] else { return nil }
                var scope: DataScope = [:]
                for (key, item) in value.objectValue ?? JSONObject() { scope[key] = item }
                return scope
            }
            let read = RecordScope.read(DataLayers(record: layer("record"), session: layer("session"), host: layer("host"), data: layer("data")), path: row["path"]?.stringValue ?? "")
            XCTAssertEqual(read?.value ?? .null, row["value"] ?? .null, "value: \(row["name"]?.stringValue ?? "?")")
            XCTAssertEqual(read?.layer.rawValue, row["layer"]?.stringValue, "layer: \(row["name"]?.stringValue ?? "?")")
        }
    }

    func testRecordCases() {
        let rows = Contract.rows(Self.table, "recordCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            var record: DataScope? = nil
            if let screen = row["screenRecord"]?.objectValue {
                var scope: DataScope = [:]
                for (key, item) in screen { scope[key] = item }
                record = scope
            }
            for instance in ActionCasesTests.instances(row["instances"]) {
                record = RecordScope.overlay(record, RecordScope.instanceRecord(item: instance.item, fields: instance.fields))
            }
            XCTAssertEqual(record.map(ActionCasesTests.recordJSON) ?? .null, row["expected"] ?? .null, row["name"]?.stringValue ?? "?")
        }
    }

    func testFlowCases() {
        let rows = Contract.rows(Self.table, "flowCases")
        XCTAssertEqual(rows.count, 20)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            var flow = Flow(document: ActionCasesTests.flowDocument(row, documentId: "flow"), entry: nil)
            XCTAssertEqual(flow.stack.map(\.screenId), [row["start"]?.stringValue ?? ""], "start: \(name)")
            for (index, step) in (row["steps"]?.arrayValue ?? []).compactMap(\.objectValue).enumerated() {
                let label = "\(name) — step \(index + 1)"
                var action = JSONObject()
                switch step["do"]?.stringValue {
                case "navigate":
                    action = ["type": "navigate", "params": ["screenId": step["to"] ?? .null]]
                    if step["carryRecord"]?.boolValue == true { action["carryRecord"] = true }
                case "back":
                    action = ["type": "navigate.back"]
                case "host":
                    action = ["type": step["type"] ?? "submit"]
                default:
                    XCTFail("unknown step: \(label)")
                }
                let outcome = flow.press(action, instances: ActionCasesTests.instances(step["instances"]))
                let expect = step["expect"]?.objectValue
                XCTAssertEqual(flow.stack.map(\.screenId), (expect?["stack"]?.arrayValue ?? []).compactMap(\.stringValue), "stack: \(label)")
                XCTAssertEqual(flow.top?.record.map(ActionCasesTests.recordJSON) ?? .null, expect?["record"] ?? .null, "record: \(label)")
                if let hostRecord = expect?["hostRecord"] {
                    XCTAssertEqual(outcome.hostRecord.map(ActionCasesTests.recordJSON) ?? .null, hostRecord, "host record: \(label)")
                }
            }
        }
    }
}
