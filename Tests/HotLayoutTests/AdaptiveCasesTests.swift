import SwiftUI
import XCTest

@testable import HotLayout

/// The adaptive table by width (`fixtures/adaptive/adaptive-cases.json`, schema 9.18 and 9.19) as
/// functions of the rules: the class of a width, the layers of a class, the style and the props of
/// a node in a class, who is shown, who is drawn and counted, the zones, the form, the data block of
/// the artifact, and the explicit «nothing» of a layer (`unset`). The rows about geometry run again
/// through the real views in `AdaptiveLayoutTests`; the wide places are in `AdaptiveWideCasesTests`.
final class AdaptiveCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/adaptive/adaptive-cases.json")
    static let schema = ScreenAnatomyCasesTests.schema

    // MARK: Helpers

    static func rows(_ group: String) -> [JSONObject] { Contract.rows(table, group) }
    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    static func widthClass(_ value: JSONValue?) -> WidthClass { value?.stringValue.flatMap(WidthClass.init(rawValue:)) ?? .compact }

    /// The data in which every listed path holds (`isTrue`), as the tables say «met».
    static func met(_ value: JSONValue?) -> DataScope {
        var scope: DataScope = [:]
        for path in (value?.arrayValue ?? []).compactMap(\.stringValue) { scope[path] = true }
        return scope
    }

    /// A node of a row: the type and the id are given when the row does not name them.
    static func node(_ value: JSONValue?, type: String = "Container", id: String = "node") -> DocumentNode {
        var object = value?.objectValue ?? JSONObject()
        if object["id"] == nil { object["id"] = .string(id) }
        if object["type"] == nil { object["type"] = .string(type) }
        return ScreenSim.node(.object(object))
    }

    static func json(_ object: JSONObject?) -> JSONValue { object.map(JSONValue.object) ?? .null }

    // MARK: The shape of the table

    func testTableShape() {
        let counts: [String: Int] = [
            "classCases": 20, "layerCases": 3, "styleCases": 22, "propsCases": 27, "showCases": 22, "drawnCases": 7, "numberCases": 5, "tabCases": 4,
            "weightCases": 5, "zoneCases": 5, "formCases": 6, "validityCases": 39, "contentCases": 22, "gridCases": 12, "boxCases": 12, "ruleCases": 20,
            "chromeCases": 35, "wideNavItemCases": 7, "wideNavHeightCases": 3, "wideAppBarCases": 23, "wideNavBarCases": 7, "wideZoneCases": 27,
            "wideModalCases": 14, "wideModalRadiusCases": 9, "wideSectionCases": 10, "wideModalContentCases": 10, "olderReaderShowOnCases": 10,
            "wideRuleCases": 21, "unsetStyleCases": 14, "unsetStateCases": 3, "unsetPropsCases": 7, "unsetDocumentCases": 12, "unsetScreenCases": 5,
        ]
        for (group, count) in counts { XCTAssertEqual(Self.rows(group).count, count, group) }
        XCTAssertEqual(counts.values.reduce(0, +), 448)
        for group in counts.keys { XCTAssertEqual(Set(Self.rows(group).map(Self.name)).count, Self.rows(group).count, "\(group): names repeat") }
    }

    /// Every group of the table is run by a reader test or named here with the reason.
    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "classCases", "layerCases", "styleCases", "propsCases", "showCases", "drawnCases", "numberCases", "tabCases", "weightCases", "zoneCases",
            "formCases", "validityCases", "contentCases", "gridCases", "boxCases", "ruleCases", "chromeCases", "wideNavItemCases", "wideNavHeightCases",
            "wideAppBarCases", "wideNavBarCases", "wideZoneCases", "wideModalCases", "wideModalRadiusCases", "wideModalContentCases", "wideRuleCases",
            "unsetStyleCases", "unsetStateCases", "unsetPropsCases",
        ]
        let notRun: [String: String] = [
            "wideSectionCases": "validator rule: sections of a document that name different places for the bar",
            "olderReaderShowOnCases": "advice of the editor about an older reader; this reader is not older",
            "unsetDocumentCases": "validator rule: which documents are published",
            "unsetScreenCases": "validator rule: which screen roots are published; what a reader does with a field is run by unsetPropsCases",
        ]
        let groups = Contract.groups(Self.table)
        XCTAssertEqual(groups, run.union(notRun.keys))
        XCTAssertTrue(run.isDisjoint(with: notRun.keys))
    }

    // MARK: Class and cascade

    func testClassCases() {
        for row in Self.rows("classCases") {
            // A string, `null` and a missing width are «unknown».
            XCTAssertEqual(WidthClass.of(width: row["width"]?.numberValue).rawValue, row["expect"]?.stringValue, Self.name(row))
        }
        for width in WidthClass.allCases {
            XCTAssertEqual(WidthClass.of(width: width.from), width)
            if width.from > 0 { XCTAssertNotEqual(WidthClass.of(width: width.from - 0.001), width) }
        }
        XCTAssertEqual(WidthClass.of(width: .nan), .compact)
        XCTAssertEqual(WidthClass.of(width: .infinity), .compact)
        XCTAssertEqual(WidthClass.of(width: -1), .compact)
    }

    func testLayerCases() {
        for row in Self.rows("layerCases") {
            XCTAssertEqual(Self.widthClass(row["widthClass"]).layers.map(\.rawValue), (row["expect"]?.arrayValue ?? []).compactMap(\.stringValue), Self.name(row))
        }
    }

    // MARK: Style and props

    func testStyleCases() {
        for row in Self.rows("styleCases") {
            let node = Self.node(row["node"]).inWidthClass(Self.widthClass(row["widthClass"]))
            let style = NodeStyle.effective(node, scope: Self.met(row["met"]))
            let expected = row["expect"]?.objectValue ?? JSONObject()
            XCTAssertEqual(style, expected, Self.name(row))
        }
    }

    func testPropsCases() {
        for row in Self.rows("propsCases") {
            let node = Self.node(row["node"]).inWidthClass(Self.widthClass(row["widthClass"]))
            XCTAssertEqual(node.props, row["expect"]?.objectValue, Self.name(row))
        }
    }

    /// The tree is resolved: no override is left in a resolved node, and a document without any
    /// override is the same tree in every class.
    func testResolvedTreeCarriesNoOverrides() {
        let node = Self.node(.object(JSONObject([
            ("type", "Grid"), ("props", ["columns": 2]), ("propsOn", ["expanded": ["columns": 4]]), ("style", ["padding": "md"]), ("styleOn", ["expanded": ["padding": "xl"]]),
            ("children", [.object(JSONObject([("id", "k"), ("type", "Column"), ("props", ["gap": "sm"]), ("propsOn", ["medium": ["gap": "lg"]])]))]),
        ])))
        let wide = node.inWidthClass(.expanded)
        XCTAssertNil(wide.fields["propsOn"])
        XCTAssertNil(wide.fields["styleOn"])
        XCTAssertNil(wide.children[0].fields["propsOn"])
        XCTAssertEqual(wide.props["columns"], 4)
        XCTAssertEqual(wide.children[0].props["gap"], "lg")
        XCTAssertTrue(wide.columnsFromOverride)
        XCTAssertEqual(node.inWidthClass(.compact), node)
        let plain = Self.node(.object(JSONObject([("type", "Column"), ("props", ["gap": "sm"]), ("style", ["padding": "md"])])))
        for widthClass in WidthClass.allCases {
            XCTAssertEqual(plain.inWidthClass(widthClass).props, plain.props)
            XCTAssertEqual(plain.inWidthClass(widthClass).style, plain.style)
        }
    }

    /// The columns of the base keep their bounds 2…4, a number of a layer is read as 1…6.
    func testColumnsBounds() {
        func columns(_ spec: JSONValue, _ widthClass: WidthClass) -> Int? {
            let node = Self.node(spec, type: "Grid").inWidthClass(widthClass)
            return gridColumns(node.props["columns"], overridden: node.columnsFromOverride)
        }
        let base = JSONValue.object(JSONObject([("type", "Grid"), ("props", ["columns": 9])]))
        XCTAssertEqual(columns(base, .expanded), 4)
        XCTAssertEqual(columns(.object(JSONObject([("type", "Grid"), ("props", ["columns": 1])])), .compact), 2)
        let layered = JSONValue.object(JSONObject([("type", "Grid"), ("props", ["columns": 2]), ("propsOn", ["medium": ["columns": 1], "expanded": ["columns": 99]])]))
        XCTAssertEqual(columns(layered, .compact), 2)
        XCTAssertEqual(columns(layered, .medium), 1)
        XCTAssertEqual(columns(layered, .expanded), 6)
    }

    func testScreenContentWidth() {
        let screen = JSONValue.object(JSONObject([("type", "Screen"), ("props", ["gap": "sm"]), ("propsOn", ["expanded": ["contentMaxWidth": 1120]])]))
        XCTAssertNil(Self.node(screen, type: "Screen").inWidthClass(.medium).props["contentMaxWidth"])
        XCTAssertEqual(Self.node(screen, type: "Screen").inWidthClass(.expanded).props["contentMaxWidth"], 1120)
        // Outside the bounds it is clamped, not a whole number it is no field.
        let cases: [(JSONValue?, Double?)] = [(100, 320), (5000, 1920), (900.5, nil), ("900", nil), (nil, nil), (.null, nil), (1120, 1120)]
        for (value, want) in cases { XCTAssertEqual(WidthRules.contentMaxWidth(value), want, "\(String(describing: value))") }
    }

    // MARK: Visibility

    func testShowCases() {
        for row in Self.rows("showCases") {
            let node = Self.node(row["node"])
            let widthClass = Self.widthClass(row["widthClass"])
            XCTAssertEqual(WidthRules.isShown(node, widthClass, scope: Self.met(row["met"])), row["expect"]?.boolValue, Self.name(row))
            // The two halves are independent: a class never shows what a condition hid, and vice versa.
            let byClass = WidthRules.showOn(node.fields)?.contains(widthClass) ?? true
            let byData = Conditions.isVisible(node.visibleIf, scope: Self.met(row["met"]))
            XCTAssertEqual(row["expect"]?.boolValue, byClass && byData, Self.name(row))
        }
    }

    func testDrawnCases() {
        for row in Self.rows("drawnCases") {
            let widthClass = Self.widthClass(row["widthClass"])
            let scope = Self.met(row["met"])
            let visible = (row["items"]?.arrayValue ?? []).map { WidthRules.isShown(Self.node($0), widthClass, scope: scope) }
            let drawn = row["kind"]?.stringValue == "appBarActions" ? AppBarRules.drawn(visible: visible) : NavBarRules.drawn(visible: visible)
            XCTAssertEqual(drawn.map(JSONValue.bool), row["expect"]?.arrayValue, Self.name(row))
        }
    }

    func testNumberCases() {
        for row in Self.rows("numberCases") {
            let widthClass = Self.widthClass(row["widthClass"])
            let items = (row["items"]?.arrayValue ?? []).map { value -> DocumentNode in
                var object = value.objectValue ?? JSONObject()
                let marker = object["marker"]
                object["marker"] = nil
                object["props"] = ["content": ["kind": "literal", "value": "x"], "marker": marker ?? .null]
                return Self.node(.object(object), type: "Text")
            }
            let siblings = ListSiblings(children: items, scope: Self.met(row["met"]), widthClass: widthClass)
            let numbers = items.indices.map { ListMarkerRules.number(siblings.markers, at: $0, visible: siblings.visible) }
            XCTAssertEqual(numbers.map { $0.map { JSONValue.number(Double($0)) } ?? .null }, row["expect"]?.arrayValue, Self.name(row))
        }
    }

    func testTabCases() {
        for row in Self.rows("tabCases") {
            let widthClass = Self.widthClass(row["widthClass"])
            let scope = Self.met(row["met"])
            let visible = (row["tabs"]?.arrayValue ?? []).map { WidthRules.isShown(Self.node($0, type: "Tab"), widthClass, scope: scope) }
            let open = TabsRules.openTabIndex(initialTab: row["initialTab"], visible: visible)
            XCTAssertEqual(open.map { JSONValue.number(Double($0)) } ?? .null, row["expect"], Self.name(row))
        }
    }

    func testZoneCases() {
        for row in Self.rows("zoneCases") {
            let widthClass = Self.widthClass(row["widthClass"])
            let scope = Self.met(row["met"])
            let children = (row["children"]?.arrayValue ?? []).map { Self.node($0) }
            let zones = ScreenAnatomy.childrenByZone(children)
            func id(_ node: DocumentNode?) -> JSONValue { node.map { .string($0.id) } ?? .null }
            func shown(_ node: DocumentNode?) -> JSONValue { node.map { .bool(WidthRules.isShown($0, widthClass, scope: scope)) } ?? .null }
            let actual: JSONValue = .object(JSONObject([
                ("appBar", id(zones.appBar)), ("pinned", id(zones.pinned)), ("navBar", id(zones.navBar)), ("body", .array(zones.body.map { .string($0.id) })),
                ("shown", .object(JSONObject([
                    ("appBar", shown(zones.appBar)), ("pinned", shown(zones.pinned)), ("navBar", shown(zones.navBar)), ("body", .array(zones.body.map { shown($0) })),
                ]))),
            ]))
            XCTAssertEqual(actual, row["expect"], Self.name(row))
        }
    }

    func testFormCases() {
        for row in Self.rows("formCases") {
            let widthClass = Self.widthClass(row["widthClass"])
            var values = Self.met(row["met"])
            for (path, value) in row["values"]?.objectValue ?? JSONObject() { values[path] = value }
            let fields = (row["fields"]?.arrayValue ?? []).map { value -> JSONValue in
                var object = value.objectValue ?? JSONObject()
                let id = object["id"] ?? "?", path = object["path"] ?? "?", under = object["under"]
                object["path"] = nil
                object["under"] = nil
                object["type"] = "TextField"
                object["props"] = ["label": ["kind": "literal", "value": "x"], "value": ["kind": "binding", "path": path], "required": true]
                guard let under else { return .object(object) }
                var wrapper = under.objectValue ?? JSONObject()
                wrapper["id"] = .string((id.stringValue ?? "") + "-wrap")
                wrapper["type"] = "Column"
                wrapper["props"] = .object(JSONObject())
                wrapper["children"] = [.object(object)]
                return .object(wrapper)
            }
            let root = ScreenSim(nodes: fields).root
            let counted = FormRules.requiredFields(of: root, widthClass: widthClass).filter { !$0.hiddenByClass }.map(\.nodeId)
            let expected = row["expect"]
            XCTAssertEqual(counted.map(JSONValue.string), expected?["required"]?.arrayValue, Self.name(row))
            XCTAssertEqual(FormRules.isFormFilled(root: root, scope: values, widthClass: widthClass), expected?["filled"]?.boolValue, Self.name(row))
        }
    }

    // MARK: The data block of the artifact

    private func widthBlock(_ path: String) -> JSONValue? {
        var value = Self.schema["x-style"]?["layout"]?["widthClass"]
        for part in path.split(separator: ".") {
            if let index = Int(part) { value = value?.arrayValue.flatMap { $0.indices.contains(index) ? $0[index] : nil } } else { value = value?[String(part)] }
        }
        return value
    }

    func testRuleCases() {
        for row in Self.rows("ruleCases") {
            XCTAssertEqual(widthBlock(row["rule"]?.stringValue ?? ""), row["expect"], Self.name(row))
        }
        // The numbers of the reader are the numbers of the artifact.
        for entry in widthBlock("classes")?.arrayValue ?? [] {
            XCTAssertEqual(WidthClass(rawValue: entry["class"]?.stringValue ?? "")?.from, entry["from"]?.numberValue)
        }
        XCTAssertEqual(widthBlock("contentMaxWidth.min")?.numberValue, WidthRules.contentMaxWidthRange.lowerBound)
        XCTAssertEqual(widthBlock("contentMaxWidth.max")?.numberValue, WidthRules.contentMaxWidthRange.upperBound)
        XCTAssertEqual(widthBlock("props.columns.min")?.numberValue, 1)
        XCTAssertEqual(widthBlock("props.columns.max")?.numberValue, 6)
        let byWidget = (widthBlock("props.byWidget")?.arrayValue ?? []).compactMap(\.objectValue)
        var listed: [String: [String]] = [:]
        for entry in byWidget { listed[entry["type"]?.stringValue ?? ""] = (entry["props"]?.arrayValue ?? []).compactMap(\.stringValue) }
        XCTAssertEqual(listed, WidthRules.responsiveProps)
        XCTAssertEqual(widthBlock("cascade.order")?.arrayValue?.compactMap(\.stringValue), ["base"] + WidthClass.allCases.dropFirst().map(\.rawValue))
        let features = Self.schema["x-compatibility"]?["features"]
        for key in ["widthClassVisibility", "widthClassStyle", "widthClassProps", "screenContentMaxWidth"] {
            XCTAssertEqual(features?[key]?.stringValue, "9.18.0", key)
        }
    }

    // MARK: Explicit «nothing» in a layer (9.19.0)

    func testUnsetStyleCases() {
        for row in Self.rows("unsetStyleCases") {
            let node = Self.node(row["node"])
            for widthClass in WidthClass.allCases {
                // `null` in the table is «no style».
                XCTAssertEqual(node.inWidthClass(widthClass).style ?? .null, row["expected"]?[widthClass.rawValue] ?? .null, "\(Self.name(row)): \(widthClass)")
            }
        }
    }

    func testUnsetStateCases() {
        for row in Self.rows("unsetStateCases") {
            let node = Self.node(row["node"]).inWidthClass(Self.widthClass(row["widthClass"]))
            let scope: DataScope = row["met"]?.boolValue == true ? ["task.completed": true] : [:]
            XCTAssertEqual(NodeStyle.effective(node, scope: scope), row["expected"]?.objectValue, Self.name(row))
        }
    }

    func testUnsetPropsCases() {
        for row in Self.rows("unsetPropsCases") {
            let node = Self.node(row["node"], type: row["node"]?["type"]?.stringValue ?? "Screen")
            let prop = row["prop"]?.stringValue ?? ""
            for widthClass in WidthClass.allCases {
                let value = node.inWidthClass(widthClass).props[prop]
                let want = row["expected"]?[widthClass.rawValue]
                XCTAssertEqual(value ?? .null, want ?? .null, "\(Self.name(row)): \(widthClass)")
            }
        }
    }

    // MARK: Hostile shapes

    /// A field of the wrong shape is read as a missing field and never stops the tree.
    func testHostileShapesDoNotBreakTheResolution() {
        let hostile: [JSONObject] = [
            ["showOn": "expanded"], ["showOn": [1, .null, [:]]], ["showOn": []], ["styleOn": 5],
            ["styleOn": ["expanded": "x", "medium": .null, "huge": ["padding": "xl"]]], ["propsOn": "wide"], ["propsOn": ["expanded": 7]],
            ["propsOn": ["expanded": ["gap": ["a": 1], "columns": "many", "direction": 3]]],
            ["propsOn": ["unset": 3]], ["propsOn": ["unset": ["expanded": "gap"]]], ["styleOn": ["unset": ["expanded": [1, .null, "padding"]]]],
        ]
        for fields in hostile {
            var object = JSONObject([("id", "g"), ("type", "Grid"), ("props", ["columns": 2])])
            for (key, value) in fields { object[key] = value }
            let node = ScreenSim.node(.object(object))
            for widthClass in WidthClass.allCases {
                let resolved = node.inWidthClass(widthClass)
                XCTAssertNotNil(gridColumns(resolved.props["columns"], overridden: resolved.columnsFromOverride), "\(fields)")
            }
        }
    }

    /// The names of `unset` are read as the reader reads them: not strings are skipped, the removed
    /// field is the one named, a field outside the closed list of the widget is not removed.
    func testUnsetReading() {
        let carrier: JSONValue = ["unset": ["expanded": ["padding", 3, .null, "background"], "medium": "padding"]]
        XCTAssertEqual(WidthRules.unsetNames(carrier, layer: .expanded), ["padding", "background"])
        XCTAssertEqual(WidthRules.unsetNames(carrier, layer: .medium), [])
        XCTAssertEqual(WidthRules.unsetNames(nil, layer: .expanded), [])
        let removed = WidthRules.effectiveProps(type: "Column", props: ["gap": "sm"], propsOn: ["unset": ["expanded": ["gap"]]], widthClass: .expanded)
        XCTAssertEqual(removed.props["gap"], "sm", "a property of a widget that cannot be removed stays")
    }
}
