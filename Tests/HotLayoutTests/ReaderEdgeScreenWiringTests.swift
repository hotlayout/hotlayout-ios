import SwiftUI
import XCTest

@testable import HotLayout

/// Schema 9.28.0 on the real screen, through the public entry: the list budget cuts what a screen
/// draws and says it once, a number of a theme outside its bounds is drawn as the contract says, and a
/// text that paints nothing is not part of the name of a card.
@MainActor
final class ReaderEdgeScreenWiringTests: XCTestCase {
    final class Recorder {
        var reports: [HotlayoutReport] = []
    }

    // MARK: Theme numbers

    private func box(_ id: String, padding: JSONValue) -> JSONValue {
        [
            "id": .string(id), "type": "Container", "props": ["direction": "column", "gap": "none"],
            "style": ["padding": padding, "background": ["kind": "color", "color": ["value": "#ff0000"]], "width": 160],
            "children": [Harness.box("\(id)-blue", width: 20, height: 20, color: "#0000ff")],
        ]
    }

    private func themeJSON(spacing: [(String, JSONValue)]) throws -> JSONValue {
        var contract = try XCTUnwrap(Contract.json("theme.json")["contract"])
        guard case .object(var root) = contract, case .object(var themes)? = root["themes"], case .object(var light)? = themes["light"],
            case .object(var current)? = light["spacing"]
        else { throw XCTSkip("shape of theme.json") }
        for (name, value) in spacing { current[name] = value }
        light["spacing"] = .object(current)
        themes["light"] = .object(light)
        root["themes"] = .object(themes)
        contract = .object(root)
        return contract
    }

    /// The pixels of the real screen drawn with the theme; the same document every time.
    private func pixels(_ spacing: [(String, JSONValue)], padding: JSONValue) throws -> Data {
        let theme = try HotlayoutThemeSet.load(try themeJSON(spacing: spacing))
        let document = try screenDocument([("a", [box("card", padding: padding)])])
        let (image, bytes) = try screenPixels(HotlayoutScreen(document: document, theme: theme, locale: "en"))
        // The screen is drawn: the red box is on it (a blank picture would make every comparison pass).
        let seen = Pixels(image)
        let red = { (x: Int, y: Int) -> Bool in seen.rgb(x, y).map { $0.r > 200 && $0.g < 90 && $0.b < 90 } ?? false }
        XCTAssertTrue((0..<seen.width).contains { x in (0..<seen.height).contains { y in red(x, y) } }, "the box is drawn")
        return bytes
    }

    func testANumberOutsideTheBoundsIsDrawnAsTheBuiltInValueOfTheSameToken() throws {
        let builtIn = try pixels([("md", 12)], padding: "md")
        XCTAssertEqual(try pixels([("md", 1_000_000_000)], padding: "md"), builtIn, "a billion is the 12 of the built-in `md`")
        XCTAssertEqual(try pixels([("md", -4)], padding: "md"), builtIn)
        XCTAssertEqual(try pixels([("md", .number(.infinity))], padding: "md"), builtIn, "infinity too")
        XCTAssertNotEqual(try pixels([("md", 40)], padding: "md"), builtIn, "a number inside the bounds is drawn as it is")
    }

    func testACustomTokenOutsideTheBoundsIsDrawnAtTheNearestBound() throws {
        let bound = try pixels([("hero", 128)], padding: "hero")
        XCTAssertEqual(try pixels([("hero", 500)], padding: "hero"), bound)
        XCTAssertEqual(try pixels([("hero", .number(.infinity))], padding: "hero"), bound)
        XCTAssertNotEqual(try pixels([("hero", 0)], padding: "hero"), bound)
        XCTAssertEqual(try pixels([("hero", -1)], padding: "hero"), try pixels([("hero", 0)], padding: "hero"), "below zero is the lower bound")
    }

    func testTheReplacementReachesTheHostThroughOnReport() throws {
        let recorder = Recorder()
        let theme = try HotlayoutThemeSet.load(try themeJSON(spacing: [("md", 1_000_000_000), ("hero", 500)]))
        let document = try screenDocument([("a", [box("card", padding: "md")])])
        let held = showScreen(HotlayoutScreen(document: document, theme: theme, locale: "en", onReport: { recorder.reports += $0 }))
        withExtendedLifetime(held) {}
        let said = recorder.reports.map { $0.location + " " + $0.reason }
        XCTAssertTrue(said.contains { $0.contains("spacing.md") && $0.contains("the built-in value") }, "\(said)")
        XCTAssertTrue(said.contains { $0.contains("spacing.hero") && $0.contains("the nearest bound") }, "\(said)")
    }

    // MARK: Modal layers

    #if canImport(AppKit)
    private func text(_ id: String, _ value: String) -> JSONValue {
        ["id": .string(id), "type": "Text", "props": ["content": ["kind": "literal", "value": .string(value)], "variant": "bodyM"]]
    }

    private func labels(_ view: NSView) -> [String] {
        // A static text carries its text as the value, a control as the label.
        elements(view).flatMap { [text($0, "accessibilityLabel"), text($0, "accessibilityValue")].compactMap { $0 } }
    }

    /// A layer that cannot be dismissed (`dismissible: false`) uses the modal semantics of the platform like any other: what
    /// is under it is out of reach of the screen reader, and the layer itself is not hidden; the reader adds no trap of its own.
    func testALayerThatCannotBeDismissedKeepsThePlatformModalSemantics() throws {
        for dismissible in [true, false] {
            let button: JSONValue = [
                "id": "open", "type": "Button",
                "props": ["label": ["kind": "literal", "value": "Open layer"], "variant": "ghost", "fullWidth": false, "action": ["type": "navigate", "params": ["screenId": "layer"]]],
            ]
            let document = try HotlayoutDocument.load([
                "schemaVersion": "9.28.0", "documentId": "d", "name": "n", "initialScreenId": "a",
                "screens": [
                    ["screenId": "a", "name": "A", "root": ["id": "ra", "type": "Screen", "props": [:], "children": [button, text("under", "Page text")]]],
                    [
                        "screenId": "layer", "name": "Layer", "presentation": "modal", "dismissible": .bool(dismissible),
                        "root": ["id": "rl", "type": "Screen", "props": [:], "children": [text("inside", "Layer text")]],
                    ],
                ],
            ])
            XCTAssertEqual(document.screen("layer")?.dismissible, dismissible)
            let view = host(HotlayoutScreen(document: document, locale: "en"))
            XCTAssertTrue(labels(view).contains("Page text"), "the page is reachable before the layer")
            XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Open layer"))))
            spin(0.6)
            let said = labels(view)
            XCTAssertTrue(said.contains("Layer text"), "the layer is exposed (dismissible \(dismissible)): \(said)")
            XCTAssertFalse(said.contains("Page text"), "the page under the layer is out of reach (dismissible \(dismissible)): \(said)")
        }
    }

    // MARK: The name of a card

    private func nameOfCard(_ row: JSONObject) throws -> (view: NSView, heard: [String], silent: [String], labels: [String]) {
        let card: JSONValue = [
            "id": "card", "type": "Container",
            "props": ["direction": "column", "gap": "none", "action": ["type": "navigate", "params": ["screenId": "details"]]],
            "children": row["children"] ?? [],
        ]
        let document = try screenDocument([("a", [card]), ("details", [text("d", "Details")])])
        let view = host(HotlayoutScreen(document: document, data: Contract.scope(row["data"]), locale: "en"))
        let heard = (row["heard"]?.arrayValue ?? []).compactMap(\.stringValue)
        let silent = (row["silent"]?.arrayValue ?? []).compactMap(\.stringValue)
        return (view, heard, silent, labels(view))
    }

    func testSilentCases() throws {
        let rows = Contract.rows(ReaderEdgeCasesTests.silent, "silentCases")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            let name = ReaderEdgeCasesTests.name(row)
            let card = try nameOfCard(row)
            // The card is one element named by what is heard, in document order, and nothing that paints nothing.
            XCTAssertNotNil(find(card.view, label: card.heard.joined(separator: ", ")), "\(name): the name of the card is the heard texts; labels: \(card.labels)")
            for quiet in card.silent {
                XCTAssertFalse(card.labels.contains { $0.contains(quiet) }, "«\(quiet)» is silent: \(name): \(card.labels)")
            }
            spin(0.05)
        }
    }

    func testASilentTextDoesNotTakeTheNameAwayFromTheVisibleOne() throws {
        let transparent: JSONValue = [
            "id": "b", "type": "Text", "props": ["content": ["kind": "literal", "value": "Confirm transfer"]], "style": ["opacity": 0],
        ]
        let card: JSONValue = [
            "id": "card", "type": "Container", "props": ["direction": "column", "gap": "none", "action": ["type": "none", "track": ["event": "x"]]],
            "children": [text("a", "Show offer"), transparent],
        ]
        let view = host(HotlayoutScreen(document: try screenDocument([("a", [card])]), locale: "en"))
        XCTAssertNotNil(find(view, label: "Show offer"))
        XCTAssertNil(find(view, label: "Show offer, Confirm transfer"))
    }

    // MARK: The list budget

    private func list(_ id: String, source: String, item: String, template: JSONValue) -> JSONValue {
        ["id": .string(id), "type": "Repeater", "props": ["source": .string(source), "item": .string(item), "gap": "none"], "children": [template]]
    }

    private func records(_ count: Int, _ label: String) -> JSONValue {
        .array((0..<count).map { .object(JSONObject([("id", .number(Double($0))), ("name", .string("\(label) \($0)"))])) })
    }

    private func rowText(_ id: String, _ path: String) -> JSONValue {
        ["id": .string(id), "type": "Text", "props": ["content": ["kind": "binding", "path": .string(path)]]]
    }

    private func drawn(_ view: NSView, prefix: String) -> Int { labels(view).filter { $0.hasPrefix(prefix) }.count }

    private func budgetReports(_ recorder: Recorder) -> [HotlayoutReport] { recorder.reports.filter { $0.reason.contains("list budget") } }

    private func showList(_ children: [JSONValue], data: DataScope, recorder: Recorder) throws -> NSView {
        let document = try screenDocument([("a", children)])
        let view = host(HotlayoutScreen(document: document, data: data, locale: "en", onReport: { recorder.reports += $0 }))
        spin(1.5)
        return view
    }

    func testAScreenAtExactlyTheBudgetIsDrawnWhole() throws {
        let recorder = Recorder()
        let inner = list("inner", source: "rows", item: "row", template: rowText("t", "row.name"))
        let view = try showList([list("outer", source: "rows", item: "outer", template: inner)], data: ["rows": records(50, "Row")], recorder: recorder)
        XCTAssertEqual(drawn(view, prefix: "Row "), 2500)
        XCTAssertEqual(budgetReports(recorder), [])
    }

    func testOneInstanceOverTheBudgetIsNotDrawnAndIsReportedOnce() throws {
        let recorder = Recorder()
        let inner = list("inner", source: "rows", item: "row", template: rowText("t", "row.name"))
        let extra = list("extra", source: "more", item: "more", template: rowText("e", "more.name"))
        let view = try showList(
            [list("outer", source: "rows", item: "outer", template: inner), extra], data: ["rows": records(50, "Row"), "more": records(1, "Extra")], recorder: recorder)
        XCTAssertEqual(drawn(view, prefix: "Row "), 2500)
        XCTAssertEqual(drawn(view, prefix: "Extra"), 0, "the list after the cut draws nothing")
        XCTAssertEqual(budgetReports(recorder).count, 1, "\(budgetReports(recorder))")
        XCTAssertTrue(budgetReports(recorder).first?.reason.contains("1 instances") == true, "\(budgetReports(recorder))")
        XCTAssertEqual(budgetReports(recorder).first?.location, "screen “a”")
    }

    func testAListHiddenByItsConditionStillCostsItsInstances() throws {
        let recorder = Recorder()
        let hidden: JSONValue = [
            "id": "hidden", "type": "Column", "props": [:], "visibleIf": ["path": "flag.on", "op": "isTrue"],
            "children": [list("h", source: "rows", item: "h", template: rowText("ht", "h.name"))],
        ]
        let big = list("big", source: "rows", item: "big", template: list("inner", source: "rows", item: "row", template: rowText("t", "row.name")))
        // The hidden list comes first in the document: it takes 50 of the 2550, so the last inner instances of the big list are cut.
        let view = try showList([hidden, big], data: ["rows": records(50, "Row"), "flag.on": false], recorder: recorder)
        XCTAssertEqual(drawn(view, prefix: "Row "), 2500 - 50)
        XCTAssertEqual(budgetReports(recorder).count, 1)
    }

    func testThreeNestedListsStopInsideTheFirstOuterInstance() throws {
        let recorder = Recorder()
        let inner = list("inner", source: "rows", item: "row", template: rowText("t", "row.name"))
        let middle = list("middle", source: "rows", item: "mid", template: inner)
        let view = try showList([list("outer", source: "rows", item: "outer", template: middle)], data: ["rows": records(15, "Row")], recorder: recorder)
        // 15 × 15 × 15 would be 3375 rows: the budget counts the outer and the middle instances too.
        let rows = drawn(view, prefix: "Row ")
        XCTAssertLessThan(rows, 3375)
        XCTAssertGreaterThan(rows, 0)
        XCTAssertEqual(budgetReports(recorder).count, 1)
    }
    #endif
}
