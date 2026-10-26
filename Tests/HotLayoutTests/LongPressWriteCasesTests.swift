import SwiftUI
import XCTest

@testable import HotLayout

/// A write action on a long press, against the shared table (`long-press/long-press-write-cases.json`),
/// and a node that carries the editor's `name`.
@MainActor
final class LongPressWriteCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/long-press/long-press-write-cases.json")

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    /// A long press as the card runs it: the haptic request and the event, then the action; a
    /// write goes through the same function as the press of a node.
    private func hold(_ sim: inout ScreenSim, _ id: String) {
        guard let path = sim.find(id), let actor = PressTarget.receiver(chain: path), let action = PressTarget.longPress(actor) else { return }
        sim.run(action)
    }

    func testRunCases() {
        let rows = Contract.rows(Self.table, "runCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            var sim = ScreenSim(nodes: row["nodes"]?.arrayValue ?? [])
            let node = row["node"]?.stringValue ?? ""
            for gesture in (row["gestures"]?.arrayValue ?? []).compactMap(\.stringValue) {
                switch gesture {
                case "tap": sim.press(node)
                case "hold": hold(&sim, node)
                case "key":
                    XCTAssertTrue(LongPressRules.isLongPressKey("F10", shift: true), name(row))
                    hold(&sim, node)
                default: XCTFail("unknown gesture \(gesture)")
                }
            }
            let writes = sim.log.filter { $0.first?.stringValue != "action" }
            XCTAssertEqual(writes, (row["log"]?.arrayValue ?? []).map { $0.arrayValue ?? [] }, "log: \(name(row))")
            let handed = sim.log.filter { $0.first?.stringValue == "action" }.compactMap { $0.last?.stringValue }
            XCTAssertEqual(handed, (row["handed"]?.arrayValue ?? []).compactMap(\.stringValue), "handed: \(name(row))")
            XCTAssertEqual(sim.session, Contract.scope(row["session"]), "session: \(name(row))")
            let shown = (row["watch"]?.arrayValue ?? []).compactMap(\.stringValue).filter { sim.isShown($0) }
            XCTAssertEqual(shown, (row["shown"]?.arrayValue ?? []).compactMap(\.stringValue), "shown: \(name(row))")
            // The role comes from `action` alone: a button without a state.
            if let path = sim.find(node), let card = path.last {
                XCTAssertEqual(PressTarget.actsOnPress(card), true, name(row))
                let own = card.props["action"]?.objectValue
                XCTAssertNil(own.flatMap { WriteActions.control(of: $0, read: { sim.scope[$0] }) }, "role: \(name(row))")
            }
        }
    }

    func testNodesOfTheTablesAreDrawn() throws {
        for row in Contract.rows(Self.table, "runCases") {
            let screen: JSONValue = [
                "schemaVersion": "9.30.0", "documentId": "d", "name": "n", "initialScreenId": "a",
                "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": row["nodes"] ?? []]]],
            ]
            let document = try loadDocument(screen)
            let view = HotlayoutScreen(document: document, locale: "en").frame(width: 360, height: 640)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage, name(row))
        }
    }

    /// The field `name` of a node is for the editor: the reader draws and names the node as without it.
    func testNodeNameChangesNothing() throws {
        func screen(named: Bool) -> JSONValue {
            var card: JSONObject = [
                "id": "card", "type": "Container",
                "props": ["direction": "column", "gap": "none", "action": ["type": "share"]],
                "children": [["id": "t", "type": "Text", "props": ["content": ["kind": "literal", "value": "Coffee"]]]],
            ]
            if named { card["name"] = "Mission card" }
            return [
                "schemaVersion": "9.29.0", "documentId": "d", "name": "n", "initialScreenId": "a",
                "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": [.object(card)]]]],
            ]
        }
        let plain = try loadDocument(screen(named: false))
        let named = try loadDocument(screen(named: true))
        XCTAssertEqual(
            PressTarget.name(of: named.screens[0].root.children[0], shown: { _ in true }, paintOf: { _ in nil }) { Harness.context(rightToLeft: false).text($0, field: $1) },
            PressTarget.name(of: plain.screens[0].root.children[0], shown: { _ in true }, paintOf: { _ in nil }) { Harness.context(rightToLeft: false).text($0, field: $1) }
        )
        func pixels(_ document: HotlayoutDocument) -> Data? {
            let view = HotlayoutScreen(document: document, locale: "en").frame(width: 360, height: 640)
            return ImageRenderer(content: view).cgImage?.dataProvider?.data as Data?
        }
        XCTAssertEqual(pixels(named), pixels(plain))
    }
}
