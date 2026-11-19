#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// When the appearance of a node plays, on a real screen (`momentCases` of `motion/motion-turn-cases.json`):
/// a first show, a screen pushed on top, a screen shown again by a step back and by a section switch play;
/// closing a layer above, a condition that starts to hold, a width class and a new record of a list do not.
/// Each node tells the tally whether it played or stood at once.
@MainActor
final class NodeAppearScreenTests: XCTestCase {
    private let appearing: JSONValue = ["kind": "fade", "duration": 400]

    private func card(_ id: String, extra: [(String, JSONValue)] = []) -> JSONValue {
        .object(JSONObject([
            ("id", .string(id)), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
            ("style", ["width": 40, "height": 40, "background": ["kind": "color", "color": ["value": "#ff0000"]]]),
            ("appear", appearing), ("children", []),
        ] + extra))
    }

    private func button(_ id: String, _ label: String, _ type: String, to screen: String? = nil) -> JSONValue {
        var action: JSONObject = ["type": .string(type)]
        if let screen { action["params"] = ["screenId": .string(screen)] }
        return ["id": .string(id), "type": "Button", "props": ["label": ["kind": "literal", "value": .string(label)], "variant": "ghost", "fullWidth": false, "action": .object(action)]]
    }

    private func screen(_ id: String, _ children: [JSONValue], modal: Bool = false) -> JSONValue {
        var entry: JSONObject = ["screenId": .string(id), "name": .string(id), "root": ["id": .string("root-\(id)"), "type": "Screen", "props": [:], "children": .array(children)]]
        if modal { entry["presentation"] = "modal" }
        return .object(entry)
    }

    private func flow() throws -> HotlayoutDocument {
        try HotlayoutDocument.load([
            "schemaVersion": .string(HotlayoutVersions.schema), "documentId": "d", "name": "n", "initialScreenId": "home",
            "screens": [
                screen("home", [card("home-card"), button("open", "Open", "navigate", to: "second"), button("sheet", "Sheet", "navigate", to: "layer"), button("section", "Section", "navigate.section", to: "third")]),
                screen("second", [card("second-card"), button("back", "Back", "navigate.back")]),
                screen("third", [card("third-card")]),
                screen("layer", [button("close", "Close", "navigate.back")], modal: true),
            ],
        ])
    }

    private func press(_ view: NSView, _ label: String) throws {
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: label), "no «\(label)»")))
        spin(0.3)
    }

    /// How many times the cards of these tests played their appearance and how many times they stood at once.
    private func tally() -> (played: Int, standing: Int) {
        let mine = AppearTally.decisions.filter { Self.cards.contains($0.id) }
        return (mine.filter(\.played).count, mine.filter { !$0.played }.count)
    }

    private static let cards: Set<String> = ["home-card", "second-card", "third-card", "conditional", "wide", "record"]

    func testTheMomentsOfAFlow() throws {
        let view = host(HotlayoutScreen(document: try flow(), locale: "en").environment(\.stackTransitionFreezeMs, 0))
        let first = tally()
        XCTAssertEqual(first.played, tallyBase.played + 1, "the first show plays")

        try press(view, "Open")
        XCTAssertEqual(tally().played, first.played + 1, "a screen pushed on top plays")
        try press(view, "Back")
        XCTAssertEqual(tally().played, first.played + 2, "a screen shown again by a step back plays")

        let before = tally()
        try press(view, "Sheet")
        try press(view, "Close")
        XCTAssertEqual(tally().played, before.played, "a layer opened and closed over a screen is not a show of the screen")
        XCTAssertEqual(tally().standing, before.standing)

        try press(view, "Section")
        XCTAssertEqual(tally().played, before.played + 1, "a section switch plays")
    }

    // MARK: Nodes that come later on a shown screen

    private final class Model: ObservableObject {
        @Published var data: DataScope = ["user.on": .bool(false), "items": .array([])]
    }

    private struct Host: View {
        let document: HotlayoutDocument
        @ObservedObject var model: Model
        var body: some View { HotlayoutScreen(document: document, data: model.data, locale: "en") }
    }

    func testANodeThatComesLaterStandsAtOnce() throws {
        let list: JSONValue = [
            "id": "list", "type": "Repeater", "props": ["source": "items", "item": "item"],
            "children": [card("record")],
        ]
        let document = try HotlayoutDocument.load([
            "schemaVersion": .string(HotlayoutVersions.schema), "documentId": "d", "name": "n", "initialScreenId": "home",
            "screens": [
                screen("home", [
                    card("conditional", extra: [("visibleIf", ["path": "user.on", "op": "eq", "value": true])]),
                    card("wide", extra: [("showOn", ["expanded"])]),
                    list,
                ])
            ],
        ])
        let model = Model()
        let view = host(Host(document: document, model: model))
        let shown = tally()
        XCTAssertEqual(shown.played, tallyBase.played, "nothing on the screen is built at its show: the cards are hidden or the list is empty")

        model.data = ["user.on": .bool(true), "items": .array([["name": "First"]])]
        spin(0.4)
        XCTAssertEqual(tally().played, shown.played, "a condition that starts to hold and a new record of a list do not play")
        XCTAssertEqual(tally().standing, shown.standing + 2, "they stand at once")

        view.frame = NSRect(x: 0, y: 0, width: 1400, height: 640)
        spin(0.4)
        XCTAssertEqual(tally().played, shown.played, "a width class that starts to show a node does not play")
        XCTAssertEqual(tally().standing, shown.standing + 3)
    }

    private var tallyBase: (played: Int, standing: Int) = (0, 0)

    override func setUp() {
        tallyBase = tally()
    }
}
#endif
