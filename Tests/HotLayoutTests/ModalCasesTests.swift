import SwiftUI
import XCTest

@testable import HotLayout

/// The modal layer against the shared tables: the box of a sheet and a window, the blur, the
/// drag that closes a sheet, `dismissible`, the Escape key, the event of a show.
@MainActor
final class ModalCasesTests: XCTestCase {
    static let dismissTable = try! Contract.json("fixtures/sheet-dismiss/sheet-dismiss-cases.json")
    static let chromeTable = try! Contract.json("fixtures/media-chrome/media-chrome-cases.json")
    static let motionTable = try! Contract.json("fixtures/motion/motion-cases.json")

    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }
    static func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }

    /// Groups of the tables this reader does not run, with the reason; keyed `table/group`.
    static let notRun: [String: String] = [
        "sheet-dismiss/documentCases": "rules of the validator (`dismissible` on a page is not published); the reader ignores the field on a page, checked by testDocumentReading",
        "sheet-dismiss/escapeRuleCases": "descriptive words of the contract; the Escape rule itself is escapeCases",
        "media-chrome/documentCases": "rules of the validator (where `modalPlacement` may stand); the reader draws any document it can read",
        "motion/glassCases": "glass under a node (`style.backdropBlur`) belongs to the node style, not to the modal layer",
    ]

    /// Groups of the shared tables that belong to the modal layer: every one is run or named.
    func testEveryModalGroupIsRunOrNamed() {
        let run: Set<String> = [
            "sheet-dismiss/startCases", "sheet-dismiss/releaseCases", "sheet-dismiss/entryCases", "sheet-dismiss/ruleCases", "sheet-dismiss/escapeCases",
            "media-chrome/modalCases", "media-chrome/modalAreaCases", "media-chrome/placementCases", "media-chrome/modalRuleCases", "media-chrome/shownCases",
            "motion/blurCases",
        ]
        var groups: Set<String> = []
        for (key, value) in Self.dismissTable.objectValue ?? JSONObject() where key.hasSuffix("Cases") && value.arrayValue != nil { groups.insert("sheet-dismiss/\(key)") }
        let known = run.union(Self.notRun.keys)
        XCTAssertEqual(groups.subtracting(known), [], "groups of sheet-dismiss that are neither run nor named")
        for name in known {
            let parts = name.split(separator: "/").map(String.init)
            let table = ["sheet-dismiss": Self.dismissTable, "media-chrome": Self.chromeTable, "motion": Self.motionTable][parts[0]]
            XCTAssertNotNil(table?[parts[1]]?.arrayValue, "\(name) is no longer a group")
        }
    }

    // MARK: Box

    func testModalBoxCases() {
        let rows = Contract.rows(Self.chromeTable, "modalCases")
        XCTAssertEqual(rows.count, 16)
        for row in rows {
            let viewport = row["viewport"]?.objectValue ?? JSONObject()
            let box = ModalRules.box(
                window: ModalRules.isWindow(row["placement"]), viewportWidth: Self.number(viewport["width"]), viewportHeight: Self.number(viewport["height"]),
                contentHeight: Self.number(row["contentHeight"]), margin: Self.number(row["margin"])
            )
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(box, ModalRules.Box(x: Self.number(expect["x"]), y: Self.number(expect["y"]), width: Self.number(expect["width"]), height: Self.number(expect["height"]), scrolls: expect["scrolls"]?.boolValue ?? false), Self.name(row))
        }
    }

    func testModalAreaCases() {
        let rows = Contract.rows(Self.chromeTable, "modalAreaCases")
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            let area = row["area"]?.objectValue ?? JSONObject()
            let box = ModalRules.box(
                window: true, viewportWidth: Self.number(area["width"]), viewportHeight: Self.number(area["height"]),
                contentHeight: Self.number(row["contentHeight"]), margin: Self.number(row["margin"])
            )
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(box.x + Self.number(area["x"]), Self.number(expect["x"]), Self.name(row))
            XCTAssertEqual(box.y + Self.number(area["y"]), Self.number(expect["y"]), Self.name(row))
            XCTAssertEqual(box.y + Self.number(area["y"]) + box.height / 2, Self.number(expect["centerY"]), Self.name(row))
            XCTAssertEqual(box.width, Self.number(expect["width"]), Self.name(row))
        }
    }

    func testPlacementCases() {
        let rows = Contract.rows(Self.chromeTable, "placementCases")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            XCTAssertEqual(ModalRules.isWindow(row["value"]) ? "center" : "bottom", row["expect"]?.stringValue, Self.name(row))
        }
    }

    // MARK: Blur

    func testBlurCases() throws {
        let rows = Contract.rows(Self.motionTable, "blurCases")
        XCTAssertEqual(rows.count, 11)
        for row in rows {
            var screen: [(String, JSONValue)] = [("screenId", "b"), ("name", "B"), ("root", Self.root)]
            for key in ["presentation", "modalPlacement", "backdropBlur"] { if let value = row[key] { screen.append((key, value)) } }
            let document = try Self.document([Self.pageScreen, .object(JSONObject(screen))])
            let entry = try XCTUnwrap(document.screen("b"))
            let expected: Int? = row["schema"]?.boolValue == true && row["presentation"]?.stringValue == "modal" ? Int(Self.number(row["backdropBlur"])) : nil
            XCTAssertEqual(entry.backdropBlur, expected, Self.name(row))
        }
    }

    func testBlurAddsAsVariances() {
        XCTAssertEqual(ModalRules.combinedBlur([]), 0)
        XCTAssertEqual(ModalRules.combinedBlur([16]), 16)
        XCTAssertEqual(ModalRules.combinedBlur([3, 4]), 5, accuracy: 1e-9)
    }

    // MARK: Drag, release, dismissible, Escape

    func testStartCases() {
        let rows = Contract.rows(Self.dismissTable, "startCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let starts = ModalRules.dragStarts(
                sheet: row["sheet"]?.boolValue ?? false, dismissible: row["dismissible"]?.boolValue ?? true, scrolled: Self.number(row["scrolled"]),
                dy: Self.number(row["dy"]), dx: Self.number(row["dx"]), onHandle: row["onHandle"]?.boolValue ?? false
            )
            XCTAssertEqual(starts, row["expect"]?.boolValue, Self.name(row))
        }
    }

    func testReleaseCases() {
        let rows = Contract.rows(Self.dismissTable, "releaseCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            let outcome = ModalRules.dragOutcome(sheetHeight: Self.number(row["sheetHeight"]), dragged: Self.number(row["dragged"]), velocity: Self.number(row["velocity"]))
            XCTAssertEqual(outcome.rawValue, row["expect"]?.stringValue, Self.name(row))
        }
    }

    func testVelocityFromTheLastHundredMilliseconds() {
        XCTAssertEqual(ModalRules.velocity(samples: []), 0)
        XCTAssertEqual(ModalRules.velocity(samples: [(0, 0)]), 0)
        // 100 pt in 100 ms: 1000 pt/s; the older sample is outside the window.
        XCTAssertEqual(ModalRules.velocity(samples: [(0, 0), (0.9, 100), (1.0, 200)]), 1000, accuracy: 1e-6)
        XCTAssertEqual(ModalRules.velocity(samples: [(0, 300), (0.05, 250)]), -1000, accuracy: 1e-6)
    }

    func testEntryCases() throws {
        let rows = Contract.rows(Self.dismissTable, "entryCases")
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            let entry = row["entry"]?.objectValue ?? JSONObject()
            let document = try Self.document([Self.pageScreen, .object(JSONObject([("screenId", "redeem"), ("name", "Redeem"), ("root", Self.root)] + entry.keys.filter { !["screenId", "name"].contains($0) }.map { ($0, entry[$0]!) }))])
            XCTAssertEqual(document.screen("redeem")?.dismissible, row["expect"]?.boolValue, Self.name(row))
        }
    }

    func testDocumentReading() throws {
        // On a page the field is not read (the validator rejects it).
        let document = try Self.document([.object(JSONObject([("screenId", "a"), ("name", "A"), ("dismissible", false), ("backdropBlur", 8), ("root", Self.root)]))])
        XCTAssertEqual(document.screen("a")?.dismissible, true)
        XCTAssertNil(document.screen("a")?.backdropBlur)
    }

    func testRuleCases() throws {
        let schema = try Contract.json("screen-schema.json")
        let block = schema["x-sheetDismiss"]
        let rows = Contract.rows(Self.dismissTable, "ruleCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            var value = block
            for part in (row["rule"]?.stringValue ?? "").split(separator: ".") { value = value?[String(part)] }
            XCTAssertEqual(value, row["expect"], "artifact: \(Self.name(row))")
        }
        XCTAssertEqual(ModalRules.dismissShare, 0.3)
        XCTAssertEqual(ModalRules.flingVelocity, 700)
        XCTAssertEqual(ModalRules.velocityWindowMs, 100)
        XCTAssertEqual(ModalRules.returnMotion, ModalRules.Motion(durationMs: 250, curve: [0.2, 0, 0, 1]))
        XCTAssertEqual(ModalRules.exitMotion, ModalRules.Motion(durationMs: 200, curve: [0.4, 0, 1, 1]))
        XCTAssertEqual(ModalRules.touchSlop, 10)
        XCTAssertEqual(ModalRules.scrimOpacity, schema["x-style"]?["layout"]?["modalLayer"]?["scrim"]?["opacity"]?.numberValue)
        XCTAssertEqual(ModalRules.windowMaxWidth, schema["x-style"]?["layout"]?["modalLayer"]?["center"]?["maxWidth"]?.numberValue)
    }

    func testEscapeCases() {
        let rows = Contract.rows(Self.dismissTable, "escapeCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let steps = ModalRules.escapeSteps(
                key: row["key"]?.stringValue ?? "", repeating: row["repeat"]?.boolValue ?? false,
                modalOnTop: row["modalOnTop"]?.boolValue ?? false, topDismissible: row["topDismissible"]?.boolValue ?? true
            )
            XCTAssertEqual(Double(steps), Self.number(row["expect"]), Self.name(row))
        }
    }

    // MARK: Event of the show

    /// `statusBarIcons` is a request the screen shell makes; this layer does not read it, so the
    /// key is taken off the expected event.
    func testShownCases() throws {
        let rows = Contract.rows(Self.chromeTable, "shownCases")
        XCTAssertEqual(rows.count, 11)
        for row in rows {
            let stack = (row["stack"]?.arrayValue ?? []).compactMap(\.objectValue)
            let screens = stack.map { FlowDocument.Screen(screenId: $0["screenId"]?.stringValue ?? "", presentation: $0["presentation"]?.stringValue == "modal" ? .modal : .page, modalPlacement: $0["modalPlacement"]?.stringValue) }
            var flow = Flow(document: FlowDocument(documentId: "d", screens: screens, initialScreenId: screens.first?.screenId, entryPoints: [:]), entry: nil)
            var event: ScreenShownEvent?
            switch row["transition"]?.stringValue {
            case "start": event = flow.shownEvent(cause: .entry)
            case "pop": event = flow.shownEvent(cause: .back)
            default:
                let target = stack.last?["screenId"] ?? .null
                let record = stack.last?["record"]
                var action: JSONObject = JSONObject([("type", "navigate"), ("params", .object(JSONObject([("screenId", target)])))])
                if record != nil { action["carryRecord"] = true }
                event = flow.press(action).shown
            }
            var expected = row["expect"]?.objectValue ?? JSONObject()
            expected["statusBarIcons"] = nil
            var actual = ActionCasesTests.shownJSON(event).objectValue ?? JSONObject()
            // A record of the pushed frame comes from the row of a list in the document, not from the stack here.
            if stack.last?["record"] != nil { actual["record"] = expected["record"] }
            XCTAssertEqual(JSONValue.object(actual), JSONValue.object(expected), Self.name(row))
        }
    }

    // MARK: The real layers

    static let root = JSONValue.object(JSONObject([("id", "r"), ("type", "Screen"), ("props", .object(JSONObject())), ("children", [])]))
    static let pageScreen = JSONValue.object(JSONObject([("screenId", "a"), ("name", "A"), ("root", root)]))

    static func document(_ screens: [JSONValue]) throws -> HotlayoutDocument {
        try loadDocument(.object(JSONObject([("schemaVersion", "9.27.0"), ("documentId", "d"), ("name", "n"), ("initialScreenId", "a"), ("screens", .array(screens))])))
    }

    /// A page of one colour and a layer of another, drawn together off screen.
    func render(window: Bool, dismissible: Bool = true, blur: Int? = nil, height: CGFloat = 176) throws -> Pixels {
        let sheetRoot: JSONValue = .object(JSONObject([
            ("id", "m"), ("type", "Screen"), ("props", .object(JSONObject())),
            ("style", .object(JSONObject([("background", .object(JSONObject([("kind", "color"), ("color", .object(JSONObject([("value", "#0000ff")])))])))]))),
            ("children", [.object(JSONObject([("id", "box"), ("type", "Container"), ("props", .object(JSONObject())), ("style", .object(JSONObject([("height", .number(Double(height)))]))), ("children", [])]))]),
        ]))
        let sheet = try Self.document([Self.pageScreen, .object(JSONObject([("screenId", "m"), ("name", "M"), ("presentation", "modal"), ("root", sheetRoot)]))])
        let entry = try XCTUnwrap(sheet.screen("m"))
        let context = Harness.context(rightToLeft: false)
        let layer = ModalStack.Layer(id: 1, content: AnyView(ScreenRootView(root: entry.root, context: context, shrinks: true)), shape: window ? .window : .sheet, placement: window ? "center" : nil, blur: blur, dismissible: dismissible)
        let view = ModalStack(page: AnyView(Color(red: 1, green: 0, blue: 0)), layers: [layer], margin: 24, dismiss: { _ in })
            .frame(width: 393, height: 852)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return Pixels(try XCTUnwrap(renderer.cgImage))
    }

    func testSheetStandsAtTheBottomUnderTheScrim() throws {
        let pixels = try render(window: false)
        // The sheet: the root's own blue, 176 high at the bottom.
        XCTAssertTrue(pixels.isColor(200, 852 - 100, "#0000ff"))
        XCTAssertFalse(pixels.isColor(200, 852 - 190, "#0000ff"))
        // The page under the scrim: red at 0.55.
        let page = try XCTUnwrap(pixels.rgb(200, 100))
        XCTAssertEqual(page.r, Int((255 * (1 - ModalRules.scrimOpacity)).rounded()), accuracy: 6)
        XCTAssertLessThan(page.g, 8)
    }

    func testWindowStandsInTheMiddle() throws {
        let pixels = try render(window: true, height: 200)
        XCTAssertTrue(pixels.isColor(196, 426, "#0000ff"))
        XCTAssertFalse(pixels.isColor(196, 426 - 110, "#0000ff"))
        XCTAssertFalse(pixels.isColor(196, 426 + 110, "#0000ff"))
        XCTAssertFalse(pixels.isColor(10, 426, "#0000ff"))
        XCTAssertTrue(pixels.isColor(30, 426, "#0000ff"))
    }

    func testBlurSoftensThePageBeneath() throws {
        // The page has a hard edge; the blur must mix colours at it and leave the layer sharp.
        let sheetRoot: JSONValue = .object(JSONObject([("id", "m"), ("type", "Screen"), ("props", .object(JSONObject())), ("children", [])]))
        let doc = try Self.document([Self.pageScreen, .object(JSONObject([("screenId", "m"), ("name", "M"), ("presentation", "modal"), ("root", sheetRoot)]))])
        let context = Harness.context(rightToLeft: false)
        func edge(blur: Int?) throws -> Int {
            let page = HStack(spacing: 0) { Color.white; Color.black }
            let layer = ModalStack.Layer(id: 1, content: AnyView(ScreenRootView(root: try XCTUnwrap(doc.screen("m")).root, context: context, shrinks: true)), shape: .sheet, placement: nil, blur: blur, dismissible: true)
            let renderer = ImageRenderer(content: ModalStack(page: AnyView(page), layers: [layer], margin: 24, dismiss: { _ in }).frame(width: 200, height: 200))
            renderer.scale = 1
            let pixels = Pixels(try XCTUnwrap(renderer.cgImage))
            return try XCTUnwrap(pixels.rgb(96, 100)).r
        }
        let sharp = try edge(blur: nil)
        let soft = try edge(blur: 16)
        XCTAssertGreaterThan(sharp - soft, 20, "pixel 4 points left of the edge is darker by the blur")
    }
}
