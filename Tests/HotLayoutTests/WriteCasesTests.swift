import SwiftUI
import XCTest

@testable import HotLayout

/// Write actions (`setValue`, `toggleValue`) and the choice made of plain nodes
/// (`actions/action-cases.json`: `write…`, `haptic…`; `inputs/input-cases.json`: `choice…`,
/// `writeFormCases`).
final class WriteCasesTests: XCTestCase {
    static let actions = try! Contract.json("fixtures/actions/action-cases.json")
    static let inputs = try! Contract.json("fixtures/inputs/input-cases.json")

    /// Groups this file does not run, each with the reason; the test fails when a `write…` or
    /// `haptic…` group is neither run nor named, and when a name here is no longer a group.
    static let notRun: [String: String] = [
        "actions/writeSchemaCases": "the shape of the action against the JSON schema: the validator's side, not the reader's",
        "actions/writeDocumentCases": "rules of the validator (what may be published)",
        "actions/writeTreeCases": "rules of the validator (where a write action may stand)",
        "actions/hapticSchemaCases": "the shape of the action against the JSON schema: the validator's side, not the reader's",
    ]

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "actions/writeCases", "actions/writeControlCases", "actions/writePressCases", "actions/hapticCases",
            "inputs/choicePlaceCases", "inputs/choiceControlCases", "inputs/writeFormCases",
        ]
        var groups: Set<String> = []
        for (key, value) in Self.actions.objectValue ?? JSONObject() where (key.hasPrefix("write") || key.hasPrefix("haptic")) && key.hasSuffix("Cases") && value.arrayValue != nil {
            groups.insert("actions/\(key)")
        }
        for key in ["choicePlaceCases", "choiceControlCases", "writeFormCases"] where Self.inputs[key]?.arrayValue != nil { groups.insert("inputs/\(key)") }
        let known = run.union(Self.notRun.keys)
        XCTAssertEqual(groups.subtracting(known), [], "groups of the tables that are neither run nor named")
        XCTAssertEqual(known.subtracting(groups), [], "names that are no longer groups")
    }

    static func expand(_ value: JSONValue?) -> JSONValue { ActionCasesTests.expand(value ?? .null) }

    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    // MARK: Step

    func testWriteSteps() {
        let rows = Contract.rows(Self.actions, "writeCases")
        XCTAssertEqual(rows.count, 67)
        for row in rows {
            let action = Self.expand(row["action"]).objectValue ?? JSONObject()
            let data = Contract.scope(Self.expand(row["data"]))
            let step = WriteActions.step(of: action, read: { data[$0] })
            let name = Self.name(row)
            guard let expected = Self.expand(row["step"]).objectValue else {
                XCTAssertNil(step, "not a write: \(name)")
                continue
            }
            switch step {
            case .write(let path, let value)?:
                XCTAssertEqual(expected["kind"]?.stringValue, "write", name)
                XCTAssertEqual(path, expected["path"]?.stringValue, "path: \(name)")
                XCTAssertEqual(value, expected["value"], "value: \(name)")
            case .same(let path, let value)?:
                XCTAssertEqual(expected["kind"]?.stringValue, "same-value", name)
                XCTAssertEqual(path, expected["path"]?.stringValue, "path: \(name)")
                XCTAssertEqual(value, expected["value"], "value: \(name)")
            case .invalid(let problem)?:
                XCTAssertEqual(expected["kind"]?.stringValue, "invalid", name)
                XCTAssertEqual(problem.rawValue, expected["problem"]?.stringValue, "problem: \(name)")
            case nil:
                XCTFail("a write action was not recognised: \(name)")
            }
            // What the host gets: only a write that the gate lets through.
            var session: DataScope = [:]
            var host: [JSONValue]?
            if case .write(let path, let value)? = step, SessionWrite.apply(path: path, value: value, to: &session, gate: nil) {
                host = [.string(path), value]
            }
            let expectedHost = Self.expand(row["host"]).arrayValue
            XCTAssertEqual(host, expectedHost, "host: \(name)")
            if row["gate"]?.stringValue == "refused" {
                XCTAssertTrue(session.isEmpty, "a refused path reaches neither the session nor the host: \(name)")
            }
        }
    }

    func testControlOfAWriteNode() {
        let rows = Contract.rows(Self.actions, "writeControlCases")
        XCTAssertEqual(rows.count, 22)
        for row in rows {
            let action = Self.expand(row["action"]).objectValue ?? JSONObject()
            let data = Contract.scope(Self.expand(row["data"]))
            let control = WriteActions.control(of: action, read: { data[$0] })
            let name = Self.name(row)
            guard let expected = row["control"]?.objectValue else {
                XCTAssertNil(control, name)
                continue
            }
            XCTAssertEqual(control?.role.rawValue, expected["role"]?.stringValue, "role: \(name)")
            XCTAssertEqual(control?.path, expected["path"]?.stringValue, "path: \(name)")
            XCTAssertEqual(control?.on, expected["on"]?.boolValue, "on: \(name)")
        }
    }

    func testHapticRequest() {
        let rows = Contract.rows(Self.actions, "hapticCases")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let action = Self.expand(row["action"]).objectValue ?? JSONObject()
            XCTAssertEqual(PressRules.haptic(of: action, disabled: row["disabled"]?.boolValue == true)?.rawValue, row["expect"]?.stringValue, Self.name(row))
        }
    }

    // MARK: A press on the screen

    static func presses(_ row: JSONObject) -> [String] {
        (row["presses"]?.arrayValue ?? []).compactMap { $0.stringValue ?? $0["node"]?.stringValue }
    }

    func testPressesWriteInTheOrderTheHostSeesThem() {
        let rows = Contract.rows(Self.actions, "writePressCases")
        XCTAssertEqual(rows.count, 15)
        for row in rows {
            var sim = ScreenSim(nodes: row["nodes"]?.arrayValue ?? [])
            for id in Self.presses(row) { sim.press(id) }
            let name = Self.name(row)
            XCTAssertEqual(sim.log, (row["log"]?.arrayValue ?? []).map { $0.arrayValue ?? [] }, "log: \(name)")
            XCTAssertEqual(sim.session, Contract.scope(row["session"]), "session: \(name)")
        }
    }

    func testPlaceOfAnOptionInItsGroup() {
        let rows = Contract.rows(Self.inputs, "choicePlaceCases")
        XCTAssertEqual(rows.count, 11)
        for row in rows {
            let siblings = (row["siblings"]?.arrayValue ?? []).map(ScreenSim.node)
            let hidden = Set((row["hidden"]?.arrayValue ?? []).compactMap(\.stringValue))
            for (id, expected) in row["places"]?.objectValue ?? JSONObject() {
                guard let node = siblings.first(where: { $0.id == id }) else { return XCTFail("no node \(id)") }
                let place = WriteActions.place(of: node, in: siblings, isShown: { !hidden.contains($0.id) })
                let want = expected.arrayValue?.compactMap { $0.numberValue.map(Int.init) }
                XCTAssertEqual(place.map { [$0.position, $0.size] }, want, "\(id): \(Self.name(row))")
            }
        }
    }

    func testControlsOnTheFinishedScreen() {
        let rows = Contract.rows(Self.inputs, "choiceControlCases")
        XCTAssertEqual(rows.count, 15)
        for row in rows {
            var sim = ScreenSim(nodes: row["nodes"]?.arrayValue ?? [], layers: DataLayers(session: Contract.scope(row["session"])))
            let name = Self.name(row)
            for (id, expected) in row["expect"]?.objectValue ?? JSONObject() {
                XCTAssertEqual(sim.control(id), expected, "before \(id): \(name)")
            }
            guard row["presses"] != nil else { continue }
            for id in Self.presses(row) { sim.press(id) }
            for (id, expected) in row["after"]?.objectValue ?? JSONObject() {
                XCTAssertEqual(sim.control(id), expected, "after \(id): \(name)")
            }
        }
    }

    func testFormIsFilledAndEmptiedByWrites() {
        let rows = Contract.rows(Self.inputs, "writeFormCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            var sim = ScreenSim(nodes: row["nodes"]?.arrayValue ?? [])
            let name = Self.name(row)
            for (id, expected) in row["disabled"]?.objectValue ?? JSONObject() {
                let states = (expected.arrayValue ?? []).compactMap(\.boolValue)
                var seen = [sim.isDisabled(id)]
                for press in Self.presses(row) {
                    sim.press(press)
                    seen.append(sim.isDisabled(id))
                }
                XCTAssertEqual(seen, states, "\(id): \(name)")
            }
        }
    }

    // MARK: The real views

    /// The nodes of every row are drawn by the real views, with the session the presses left.
    @MainActor
    func testNodesOfTheTablesAreDrawn() throws {
        var drawn = 0
        for (table, group) in [(Self.inputs, "choiceControlCases"), (Self.inputs, "writeFormCases"), (Self.actions, "writePressCases")] {
            for row in Contract.rows(table, group) {
                let screen: JSONValue = [
                    "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": "a",
                    "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": row["nodes"] ?? []]]],
                ]
                let document = try loadDocument(screen)
                for locale in ["en", "ar"] {
                    let view = HotlayoutScreen(document: document, data: Contract.scope(row["session"]), locale: locale).frame(width: 360, height: 640)
                    XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(Self.name(row)) \(locale)")
                }
                drawn += 1
            }
        }
        XCTAssertEqual(drawn, 36)
    }
}
