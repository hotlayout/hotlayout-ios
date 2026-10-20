import SwiftUI
import XCTest

@testable import HotLayout

/// The geometry rows of the adaptive table through the real views: the document is drawn at a width,
/// the class comes from the box, and the boxes stand where the table says. The picture is the one the
/// platform draws, one pixel to a point, so a box that stands at a fraction of a point is found within two.
@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    static func rows(_ group: String) -> [JSONObject] { AdaptiveCasesTests.rows(group) }
    static func name(_ row: JSONObject) -> String { AdaptiveCasesTests.name(row) }
    static func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }

    /// A rectangle found in a picture stands within two points of the one the table gives (the edge pixels
    /// of a box at a fraction of a point mix two colours and are not counted).
    func assertRect(_ found: CGRect?, x: Double, y: Double? = nil, width: Double, height: Double? = nil, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let found else { return XCTFail("\(label): the box is not drawn", file: file, line: line) }
        XCTAssertEqual(Double(found.minX), x, accuracy: 2.01, "\(label): x", file: file, line: line)
        XCTAssertEqual(Double(found.width), width, accuracy: 2.01, "\(label): width", file: file, line: line)
        if let y { XCTAssertEqual(Double(found.minY), y, accuracy: 2.01, "\(label): y", file: file, line: line) }
        if let height { XCTAssertEqual(Double(found.height), height, accuracy: 2.01, "\(label): height", file: file, line: line) }
    }

    // MARK: Grid and container

    /// A host of the row with the children of the table; the screen root has 16 of padding on every side.
    func hostRows(group: String, children key: String) throws {
        for row in Self.rows(group) {
            let frame = Self.number(row["frame"])
            let expected = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(WidthClass.of(width: frame).rawValue, expected["widthClass"]?.stringValue, Self.name(row))
            let specs = (row[key]?.arrayValue ?? []).compactMap(\.objectValue)
            var host = row["node"]?.objectValue ?? JSONObject()
            host["id"] = "host"
            host["style"] = ["background": AdaptiveRender.hostBackground]
            host["children"] = .array(specs.enumerated().map { AdaptiveRender.cell($0.offset, $0.element) })
            let document = try AdaptiveRender.document(root: AdaptiveRender.screenRoot([.object(host)], style: ["padding": 16]))
            let pixels = try AdaptiveRender.render(document, width: frame, height: 640, rightToLeft: row["rtl"]?.boolValue == true)
            // The host stands at the padding of the root; its own colour is mostly under the cells.
            let boxes = AdaptiveRender.box(of: [AdaptiveRender.hostColor] + specs.indices.map(AdaptiveRender.colour), in: pixels)
            let hostBox = CGRect(x: 16, y: 16, width: frame - 32, height: 0)
            let rects = expected["rects"]?.arrayValue ?? []
            for (index, rect) in rects.enumerated() {
                let found = boxes[index + 1]
                if rect.isNull { XCTAssertNil(found, "\(Self.name(row)): cell \(index) is hidden"); continue }
                assertRect(
                    found.map { $0.offsetBy(dx: -hostBox.minX, dy: -hostBox.minY) }, x: Self.number(rect["x"]), y: Self.number(rect["y"]),
                    width: Self.number(rect["width"]), height: Self.number(rect["height"]), "\(Self.name(row)): cell \(index)"
                )
            }
        }
    }

    func testGridCases() throws { try hostRows(group: "gridCases", children: "cells") }
    func testBoxCases() throws { try hostRows(group: "boxCases", children: "children") }

    // MARK: Weights of a row

    func testWeightCasesThroughTheRealRow() throws {
        for row in Self.rows("weightCases") {
            let inline = Self.number(row["inline"])
            XCTAssertEqual(WidthClass.of(width: inline + 32), AdaptiveCasesTests.widthClass(row["widthClass"]), Self.name(row))
            let specs = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue)
            let host: JSONValue = .object(JSONObject([
                ("id", "host"), ("type", "Row"), ("props", .object(JSONObject([("gap", row["gap"] ?? 0), ("align", "start"), ("justify", "start"), ("wrap", false)]))),
                ("children", .array(specs.enumerated().map { AdaptiveRender.cell($0.offset, $0.element) })),
            ]))
            let document = try AdaptiveRender.document(root: AdaptiveRender.screenRoot([host], style: ["padding": 16]))
            let pixels = try AdaptiveRender.render(document, width: inline + 32, height: 80, data: AdaptiveCasesTests.met(row["met"]))
            let boxes = AdaptiveRender.box(of: specs.indices.map(AdaptiveRender.colour), in: pixels)
            for (index, want) in (row["expect"]?.arrayValue ?? []).enumerated() {
                if want.isNull { XCTAssertNil(boxes[index], "\(Self.name(row)): child \(index) is hidden"); continue }
                assertRect(boxes[index], x: Double(boxes[index]?.minX ?? 0), width: Self.number(want), "\(Self.name(row)): child \(index)")
            }
        }
    }

    // MARK: Content column

    func testContentCasesThroughTheRealScreen() throws {
        for row in Self.rows("contentCases") {
            let rtl = row["rtl"]?.boolValue == true
            let width = Self.number(row["width"])
            let padding = row["padding"] ?? .object(JSONObject())
            // The bar is drawn with a button at each end of its content, in colours of their own.
            var bar = JSONObject([
                ("id", "bar"), ("type", "AppBar"), ("props", ["title": ["kind": "literal", "value": "T"], "showBack": false]),
                ("children", [
                    .object(JSONObject([
                        ("id", "lead"), ("type", "Button"), ("zone", "leading"),
                        ("props", ["label": ["kind": "literal", "value": "L"], "fullWidth": false, "action": ["type": "none"]]), ("style", ["background": AdaptiveRender.background(3)]),
                    ])),
                    .object(JSONObject([
                        ("id", "act"), ("type", "IconButton"),
                        ("props", ["icon": "house", "label": ["kind": "literal", "value": "A"], "action": ["type": "none"]]), ("style", ["background": AdaptiveRender.background(4)]),
                    ])),
                ]),
            ])
            if let inset = row["appBarInset"] { bar["style"] = ["padding": inset] }
            var nav = JSONObject([
                ("id", "nav"), ("type", "NavBar"), ("props", ["widePlacement": "bottom"]),
                ("children", .array(["a", "b", "c"].enumerated().map { index, id in
                    .object(JSONObject([
                        ("id", .string(id)), ("type", "NavItem"),
                        ("props", ["icon": "house", "label": ["kind": "literal", "value": .string(id)], "action": ["type": "navigate.section", "params": ["screenId": .string(id)]]]),
                        ("style", ["background": AdaptiveRender.background(5 + index)]),
                    ]))
                })),
            ])
            if let inset = row["navBarInset"] { nav["style"] = ["padding": inset] }
            let children: [JSONValue] = [
                .object(bar), AdaptiveRender.cell(1, ["height": 60]),
                .object(JSONObject([("id", "pin"), ("type", "Container"), ("props", ["direction": "column"]), ("style", ["background": AdaptiveRender.background(2), "height": 40]), ("pin", "bottom")])),
                .object(nav),
            ]
            var props = JSONObject()
            if let max = row["contentMaxWidth"] { props["contentMaxWidth"] = max }
            let document = try AdaptiveRender.document(root: AdaptiveRender.screenRoot(children, props: props, style: ["padding": padding]))
            let pixels = try AdaptiveRender.render(document, width: width, height: 700, rightToLeft: rtl)
            let boxes = AdaptiveRender.box(of: (1...7).map(AdaptiveRender.colour), in: pixels)
            let expected = row["expect"]
            func check(_ zone: String, _ left: Double, _ right: Double) {
                let want = expected?[zone]
                XCTAssertEqual(left, Self.number(want?["x"]), accuracy: 2.01, "\(Self.name(row)): \(zone): x")
                XCTAssertEqual(right - left, Self.number(want?["width"]), accuracy: 2.01, "\(Self.name(row)): \(zone): width")
            }
            if let body = boxes[0] { check("body", Double(body.minX), Double(body.maxX)) } else { XCTFail("\(Self.name(row)): body") }
            if let pinned = boxes[1] { check("pinned", Double(pinned.minX), Double(pinned.maxX)) } else { XCTFail("\(Self.name(row)): pinned") }
            // The content of the bar: from the edge of the node at its start to the edge of the one at its end.
            if let lead = boxes[2], let act = boxes[3] {
                check("appBar", Double(rtl ? act.minX : lead.minX), Double(rtl ? lead.maxX : act.maxX))
            } else { XCTFail("\(Self.name(row)): app bar") }
            // The shares of the items of the bar: from the start of the first to the end of the last.
            let items = [boxes[4], boxes[5], boxes[6]].compactMap { $0 }
            XCTAssertEqual(items.count, 3, Self.name(row))
            if let first = items.map(\.minX).min(), let last = items.map(\.maxX).max() { check("navBar", Double(first), Double(last)) }
        }
    }

    /// The background of the root runs edge to edge, whatever the column of the content.
    func testBackgroundsRunEdgeToEdge() throws {
        let root = AdaptiveRender.screenRoot(
            [AdaptiveRender.cell(1, ["height": 60])], props: ["contentMaxWidth": 600],
            style: ["background": AdaptiveRender.hostBackground]
        )
        let pixels = try AdaptiveRender.render(try AdaptiveRender.document(root: root), width: 1280, height: 300)
        let boxes = AdaptiveRender.box(of: [AdaptiveRender.hostColor, AdaptiveRender.colour(1)], in: pixels)
        XCTAssertEqual(boxes[0]?.width, 1280)
        assertRect(boxes[1], x: 340, width: 600, "the column")
    }

    // MARK: A class is of the box, not of the window

    func testClassFollowsTheBox() throws {
        let wide = AdaptiveRender.cell(1, ["height": 20, "showOn": ["expanded"]])
        let phone = AdaptiveRender.cell(2, ["height": 20, "showOn": ["compact"]])
        let document = try AdaptiveRender.document(root: AdaptiveRender.screenRoot([wide, phone]))
        for (width, shown) in [(400.0, 2), (1100.0, 1), (700.0, 0), (320.0, 2)] {
            let pixels = try AdaptiveRender.render(document, width: width, height: 100)
            let boxes = AdaptiveRender.box(of: [AdaptiveRender.colour(1), AdaptiveRender.colour(2)], in: pixels)
            XCTAssertEqual(boxes[0] != nil, shown == 1, "wide cell at \(width)")
            XCTAssertEqual(boxes[1] != nil, shown == 2, "phone cell at \(width)")
        }
    }

    /// A hidden child takes no place and no gap, whether the class or the data hid it.
    func testHiddenChildTakesNoRoomInAColumnAndARow() throws {
        for type in ["Column", "Row"] {
            var specs: [JSONObject] = [["height": 10, "width": 20], ["height": 10, "width": 20], ["height": 10, "width": 20]]
            specs[1]["showOn"] = ["expanded"]
            let host: JSONValue = .object(JSONObject([
                ("id", "host"), ("type", .string(type)), ("props", ["gap": 10, "align": "start"]),
                ("children", .array(specs.enumerated().map { AdaptiveRender.cell($0.offset, $0.element) })),
            ]))
            let document = try AdaptiveRender.document(root: AdaptiveRender.screenRoot([host]))
            let pixels = try AdaptiveRender.render(document, width: 393, height: 120)
            let boxes = AdaptiveRender.box(of: (0...2).map(AdaptiveRender.colour), in: pixels)
            XCTAssertNil(boxes[1], type)
            let first = try XCTUnwrap(boxes[0]), third = try XCTUnwrap(boxes[2])
            // One gap between the two that are drawn, not two.
            XCTAssertEqual(Double(type == "Column" ? third.minY - first.maxY : third.minX - first.maxX), 10, accuracy: 2.01, type)
        }
    }

    // MARK: A document of the table is drawn at every width

    private static func withDefaults(_ spec: JSONObject, id: String) -> JSONValue {
        let type = spec["type"]?.stringValue ?? ""
        var props: JSONObject
        switch type {
        case "Grid": props = ["columns": 2, "gap": "sm"]
        case "Container": props = ["direction": "column", "gap": "sm"]
        case "Column": props = ["gap": "sm", "align": "start"]
        case "Row": props = ["gap": "sm", "align": "center", "justify": "start", "wrap": false]
        case "Repeater": props = ["source": "tasks", "item": "task", "gap": "sm"]
        case "Divider": props = ["orientation": "horizontal"]
        case "Text": props = ["content": ["kind": "literal", "value": "x"]]
        default: props = JSONObject()
        }
        for (key, value) in spec["props"]?.objectValue ?? JSONObject() { props[key] = value }
        var object = spec
        object["id"] = .string(id)
        object["props"] = .object(props)
        if let children = spec["children"]?.arrayValue {
            object["children"] = .array(children.enumerated().map { withDefaults($0.element.objectValue ?? JSONObject(), id: "\(id)-\($0.offset)") })
        }
        return .object(object)
    }

    /// The reader has no validator: a document the validator would refuse is still read, and drawn at
    /// every width (`x-compatibility`: the document comes from a network).
    func testValidityCasesDrawAtEveryWidth() throws {
        var drawn = 0
        for row in Self.rows("validityCases") {
            let rootFields = row["root"]?.objectValue ?? JSONObject()
            var props: JSONObject = ["gap": "none"]
            for (key, value) in rootFields["props"]?.objectValue ?? JSONObject() { props[key] = value }
            let children = (row["children"]?.arrayValue ?? []).enumerated().map { Self.withDefaults($0.element.objectValue ?? JSONObject(), id: "n\($0.offset)") }
            var rootObject = AdaptiveRender.screenRoot(children, props: props).objectValue ?? JSONObject()
            for (key, value) in rootFields where key != "props" { rootObject[key] = value }
            let document = try AdaptiveRender.document(root: .object(rootObject))
            for width in [393.0, 768.0, 1280.0] {
                let view = HotlayoutScreen(document: document, locale: "en").frame(width: CGFloat(width), height: 600)
                XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(Self.name(row)) at \(width)")
                drawn += 1
            }
        }
        XCTAssertEqual(drawn, 39 * 3)
    }

    /// A field of the wrong shape does not stop the screen: drawn at every width.
    func testHostileShapesDrawAtEveryWidth() throws {
        let hostile: [JSONObject] = [
            ["showOn": "expanded"], ["showOn": [1, .null, [:]]], ["showOn": []], ["styleOn": 5], ["propsOn": "wide"], ["propsOn": ["expanded": 7]],
            ["propsOn": ["expanded": ["gap": ["a": 1], "columns": "many", "direction": 3]]], ["propsOn": ["__proto__": ["gap": "xl"], "constructor": ["gap": "xl"]]],
            ["propsOn": ["unset": ["expanded": "columns"]]],
        ]
        for fields in hostile {
            var grid = JSONObject([("id", "g"), ("type", "Grid"), ("props", ["columns": 2]), ("children", [AdaptiveRender.cell(0, ["height": 10])])])
            for (key, value) in fields { grid[key] = value }
            let document = try AdaptiveRender.document(root: AdaptiveRender.screenRoot([.object(grid)]))
            for width in [393.0, 768.0, 1280.0] {
                let view = HotlayoutScreen(document: document, locale: "en").frame(width: CGFloat(width), height: 300)
                XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(fields) at \(width)")
            }
        }
    }
}
