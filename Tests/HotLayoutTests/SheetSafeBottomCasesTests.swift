import SwiftUI
import XCTest

@testable import HotLayout

/// The bottom safe inset of a modal sheet against the shared table: where the reader adds it
/// (inside the box of the sheet under the content, or under the content of the bottom zone, never
/// both), the box of the sheet with the inset in it, and the data of the block in the artifact.
/// The last tests draw real sheets and look at the pixels.
@MainActor
final class SheetSafeBottomCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/sheet-safe-bottom/sheet-safe-bottom-cases.json")

    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }
    static func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }

    func testEveryGroupIsRun() {
        let groups = (Self.table.objectValue ?? JSONObject()).filter { $0.key.hasSuffix("Cases") && $0.value.arrayValue != nil }.map(\.key)
        XCTAssertEqual(Set(groups), ["placementCases", "geometryCases", "ruleCases"], "a group of the table that this reader does not run")
    }

    func testPlacementCases() {
        let rows = Contract.rows(Self.table, "placementCases")
        XCTAssertEqual(rows.count, 19)
        for row in rows {
            let input = row["input"]?.objectValue ?? JSONObject()
            let place = SheetSafeBottom.place(
                presentation: input["presentation"]?.stringValue, placement: input["modalPlacement"], areaWidth: Self.number(input["areaWidth"]),
                safeBottom: input["safeBottom"], bottomZone: input["bottomZone"]?.boolValue ?? false)
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(place, SheetSafeBottom.Place(root: Self.number(expect["root"]), zone: Self.number(expect["zone"])), Self.name(row))
            XCTAssertTrue(place.root == 0 || place.zone == 0, "once: \(Self.name(row))")
        }
    }

    func testGeometryCases() {
        let rows = Contract.rows(Self.table, "geometryCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            let input = row["input"]?.objectValue ?? JSONObject()
            let box = SheetSafeBottom.box(areaHeight: Self.number(input["areaHeight"]), contentHeight: Self.number(input["contentHeight"]), safeBottom: input["safeBottom"])
            let expect = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(
                box,
                SheetSafeBottom.Box(
                    y: Self.number(expect["y"]), height: Self.number(expect["height"]), contentBottom: Self.number(expect["contentBottom"]),
                    scrolls: expect["scrolls"]?.boolValue ?? false),
                Self.name(row))
        }
    }

    func testRuleCases() {
        let block = (try? Contract.json("screen-schema.json"))?["x-style"]?["layout"]?["sheetSafeBottom"]
        XCTAssertNotNil(block)
        let rows = Contract.rows(Self.table, "ruleCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            var value = block
            for part in (row["rule"]?.stringValue ?? "").split(separator: ".") { value = value?[String(part)] }
            XCTAssertEqual(value, row["expect"], "artifact: \(Self.name(row))")
        }
        // What the reader does with a window and a sheet shown as a window follows the same words.
        XCTAssertEqual(block?["window"]?.stringValue, "none")
        XCTAssertEqual(block?["sheetWindow"]?.stringValue, "none-as-a-window")
    }

    // MARK: Real sheets

    private func box(_ id: String, height: Double, color: String, pin: Bool = false) -> JSONValue {
        var node = JSONObject([
            ("id", .string(id)), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
            ("style", .object(JSONObject([
                ("width", .number(300)), ("height", .number(height)),
                ("background", .object(JSONObject([("kind", "color"), ("color", .object(JSONObject([("value", .string(color))])))]))),
            ]))),
            ("children", []),
        ])
        if pin { node["pin"] = "bottom" }
        return .object(node)
    }

    /// A blue-rooted sheet over a red page: a green box 176 high, and a yellow pinned block 50 high when `pinned`.
    private func render(inset: Double, pinned: Bool = false, window: Bool = false, content: Double = 176, areaHeight: CGFloat = 852) throws -> Pixels {
        var children = [box("body", height: content, color: "#00ff00")]
        if pinned { children.append(box("pin", height: 50, color: "#ffff00", pin: true)) }
        let root: JSONValue = .object(JSONObject([
            ("id", "m"), ("type", "Screen"), ("props", .object(JSONObject())),
            ("style", .object(JSONObject([("background", .object(JSONObject([("kind", "color"), ("color", .object(JSONObject([("value", "#0000ff")])))])))]))),
            ("children", .array(children)),
        ]))
        let page = ModalCasesTests.pageScreen
        let sheet = JSONValue.object(JSONObject([("screenId", "m"), ("name", "M"), ("presentation", "modal"), ("root", root)]))
        let document = try ModalCasesTests.document([page, sheet])
        let entry = try XCTUnwrap(document.screen("m"))
        let context = Harness.context(rightToLeft: false)
        let layer = ModalStackLayer(id: 1, shape: window ? .window : .sheet, placement: window ? "center" : nil, blur: nil, dismissible: true)
        // As HotlayoutScreen lays it: a sheet holds the inset the host gave, a window none.
        let held = ScreenInsets(top: 0, bottom: window ? 0 : inset)
        let view = ModalStack(
            layers: [layer], margin: 24, insets: ScreenInsets(top: 0, bottom: inset), dismiss: { _ in }, page: { Color(red: 1, green: 0, blue: 0) },
            layer: { _ in ScreenRootView(root: entry.root, context: context, shrinks: true, insets: held) }
        )
        .frame(width: 393, height: areaHeight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return Pixels(try XCTUnwrap(renderer.cgImage))
    }

    // An `ImageRenderer` does not draw the inside of a scroll view, so the body shows as the root
    // colour and the tests read the box of the sheet (the top row of the root colour) and the pinned
    // block, which lies outside the scroll.

    func testSheetWithoutZoneHoldsTheInsetUnderItsContent() throws {
        let bare = try XCTUnwrap(sheetTop(try render(inset: 0)))
        let pixels = try render(inset: 34)
        XCTAssertEqual(bare, 852 - 176, "without an inset the sheet is its content")
        XCTAssertEqual(sheetTop(pixels), bare - 34, "content plus the inset")
        XCTAssertTrue(pixels.isColor(350, 851, "#0000ff"), "the background goes under the inset")
    }

    func testSheetWithPinnedBlockHoldsTheInsetOnce() throws {
        let bare = try XCTUnwrap(sheetTop(try render(inset: 0, pinned: true)))
        let pixels = try render(inset: 34, pinned: true)
        // The block ends 34 above the bottom; the inset is under the zone, not under the root as well.
        XCTAssertTrue(pixels.isColor(100, 852 - 34 - 5, "#ffff00"), "the pinned block stands above the inset")
        XCTAssertFalse(pixels.isColor(100, 852 - 34 + 5, "#ffff00"), "and ends there")
        XCTAssertTrue(pixels.isColor(100, 852 - 10, "#0000ff"), "the inset under the zone")
        XCTAssertEqual(sheetTop(pixels), bare - 34, "the inset is added once, not twice")
        XCTAssertTrue(pixels.isColor(350, 851, "#0000ff"))
        XCTAssertTrue(try render(inset: 0, pinned: true).isColor(100, 851, "#ffff00"), "without an inset the block reaches the bottom")
    }

    func testTallContentScrollsAboveTheInset() throws {
        let pixels = try render(inset: 34, pinned: true, content: 1200)
        XCTAssertEqual(sheetTop(pixels), 0, "the sheet is as tall as the area")
        XCTAssertTrue(pixels.isColor(100, 852 - 34 - 5, "#ffff00"), "the block stays above the inset")
        XCTAssertTrue(pixels.isColor(350, 851, "#0000ff"), "the inset stays under it")
    }

    /// The first row from the top where the root colour shows outside the boxes: the top of the sheet.
    private func sheetTop(_ pixels: Pixels) -> Int? { (0..<852).first { pixels.isColor(350, $0, "#0000ff") } }

    func testWindowGetsNoInset() throws {
        let pixels = try render(inset: 34, window: true)
        // Centred 176 high: its box is the same as without an inset.
        // A window of 176 is 176 high with an inset of 34 as with none.
        let bare = try render(inset: 0, window: true)
        let rows = { (p: Pixels) in (0..<852).filter { p.isColor(196, $0, "#0000ff") } }
        XCTAssertFalse(rows(pixels).isEmpty)
        // The window is laid above the bottom inset of the host (as before), and holds none inside: the same height.
        XCTAssertEqual(rows(pixels).count, rows(bare).count)
        XCTAssertEqual(rows(bare).count, 176)
    }

    func testHostThatGaveZeroGetsNoInsetOnABadValue() {
        XCTAssertEqual(SheetSafeBottom.inset(.number(.infinity)), 0)
        XCTAssertEqual(SheetSafeBottom.inset(.number(-3)), 0)
        XCTAssertEqual(SheetSafeBottom.inset(.string("34")), 0)
        XCTAssertEqual(SheetSafeBottom.inset(nil), 0)
        XCTAssertEqual(SheetSafeBottom.inset(.number(20.5)), 20.5)
    }
}
