import SwiftUI
import XCTest

@testable import HotLayout

/// The shared table of overlays and pulled children (`fixtures/offset/offset-cases.json`),
/// through the rules, the geometry and the real node drawn off screen.
@MainActor
final class OffsetCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/offset/offset-cases.json")
    static let spacing: [String: Double] = (table["tokens"]?["spacing"]?.objectValue ?? JSONObject()).reduce(into: [:]) { $0[$1.key] = $1.value.numberValue }

    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func resolver() -> StyleResolver { StyleResolver(theme: HotlayoutThemeSet.builtIn.theme(nil)) }

    // MARK: the theme steps used by the table

    func testTableSpacingIsTheBuiltInTheme() {
        let resolver = resolver()
        for (token, value) in Self.spacing {
            XCTAssertEqual(resolver.spacing(.string(token)), value, token)
        }
    }

    // MARK: reading `layer`

    func testLayerReadCases() {
        let rows = Contract.rows(Self.table, "layerReadCases")
        XCTAssertEqual(rows.count, 21)
        for row in rows {
            let read = LayerRead.read(row["value"])
            let expect = row["expect"]
            guard let expected = expect?.objectValue else {
                XCTAssertNil(read, Self.name(row))
                continue
            }
            guard let read else { XCTFail("\(Self.name(row)): not read"); continue }
            func word(_ key: String) -> String? { expected[key]?.stringValue }
            func axis(_ key: String) -> (String, JSONValue)? {
                guard let object = expected[key]?.objectValue, let toward = object["toward"]?.stringValue, let by = object["by"] else { return nil }
                return (toward, by)
            }
            XCTAssertEqual(read.alignHorizontal?.rawValue, word("alignHorizontal"), "alignHorizontal: \(Self.name(row))")
            XCTAssertEqual(read.alignVertical?.rawValue, word("alignVertical"), "alignVertical: \(Self.name(row))")
            XCTAssertEqual(read.offsetX?.toward, axis("offsetX")?.0, "offsetX toward: \(Self.name(row))")
            XCTAssertEqual(read.offsetX?.by.json, axis("offsetX")?.1, "offsetX by: \(Self.name(row))")
            XCTAssertEqual(read.offsetY?.toward, axis("offsetY")?.0, "offsetY toward: \(Self.name(row))")
            XCTAssertEqual(read.offsetY?.by.json, axis("offsetY")?.1, "offsetY by: \(Self.name(row))")
            XCTAssertEqual(read.rotate, Int(expected["rotate"]?.numberValue ?? 0), "rotate: \(Self.name(row))")
        }
    }

    // MARK: who is an overlay, who sizes the stack

    func testLayerPlaceCases() {
        let rows = Contract.rows(Self.table, "layerPlaceCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            let children = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue)
            let kinds = LayerRules.kinds(parentType: row["parent"]?.stringValue ?? "", children: children)
            XCTAssertEqual(kinds.map(\.isOverlay), (row["overlays"]?.arrayValue ?? []).map { $0.boolValue ?? false }, "overlays: \(Self.name(row))")
            XCTAssertEqual(kinds.map(\.sizesStack), (row["sizesStack"]?.arrayValue ?? []).map { $0.boolValue ?? false }, "sizesStack: \(Self.name(row))")
            if let expected = row["visibleSizers"]?.numberValue {
                let hidden = (row["hidden"]?.arrayValue ?? []).map { $0.boolValue ?? false }
                // The kinds `StackView` draws with; a hidden sizing layer measures nothing.
                let acting = LayerRules.acting(kinds, visible: hidden.map { !$0 })
                let drawn = zip(acting, hidden).filter { $0.sizesStack && !$1 }.count
                XCTAssertEqual(drawn, Int(expected), "visibleSizers: \(Self.name(row))")
            }
        }
    }

    /// The reader's side of the document table: what it does with a document the validator
    /// refuses. (The refusal itself — `schema`, `issues` — belongs to the builder.)
    func testLayerDocumentCasesReaderOutcome() {
        let rows = Contract.rows(Self.table, "layerDocumentCases")
        XCTAssertEqual(rows.count, 16)
        for row in rows {
            let children = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue)
            let kinds = LayerRules.kinds(parentType: row["parent"]?.stringValue ?? "", children: children)
            let issues = (row["issues"]?.arrayValue ?? []).compactMap(\.stringValue)
            let name = Self.name(row)
            if issues.contains("v.layerOutsideStack") { XCTAssertEqual(kinds, [.sizing, .sizing], name) }
            if issues.contains("v.layerOnFill") { XCTAssertEqual(kinds, [.sizing, .fill], name) }
            if issues.contains("v.noSizingLayer") { XCTAssertFalse(kinds.contains { $0.isOverlay }, name) }
            if issues.contains("v.allLayersFilled") {
                XCTAssertEqual(kinds, [.fill, .fill], name)
                XCTAssertEqual(LayerRules.acting(kinds, visible: [true, true]), [.sizing, .sizing], name)
            }
            if issues.contains("v.unknownToken") {
                let read = LayerRead.read(children[1]["layer"])
                XCTAssertNotNil(read?.offsetX, name)
                XCTAssertNil(resolver().spacing(read?.offsetX?.by.json), name)
            }
            if row["schema"]?.boolValue == false, let layer = children.last?["layer"] {
                // Zod refuses the form; a reader that gets it anyway reads what it can and never fails.
                _ = LayerRead.read(layer)
            }
        }
    }

    // MARK: the geometry

    private func input(_ row: JSONObject, rightToLeft: Bool) -> LayerGeometry.Input {
        func size(_ key: String) -> CGSize {
            CGSize(width: row[key]?["width"]?.numberValue ?? 0, height: row[key]?["height"]?.numberValue ?? 0)
        }
        let read = LayerRead.read(row["layer"]) ?? LayerRead()
        let stackH = AlignWord(row["stackAlign"]?["horizontal"]) ?? .center
        let stackV = AlignWord(row["stackAlign"]?["vertical"]) ?? .center
        func pixels(_ axis: LayerAxisOffset?) -> (toward: String, by: Double)? {
            guard let axis, let by = resolver().spacing(axis.by.json) else { return nil }
            return (axis.toward, by)
        }
        return LayerGeometry.Input(
            stack: size("stack"), layer: size("size"), alignHorizontal: read.alignHorizontal ?? stackH, alignVertical: read.alignVertical ?? stackV,
            offsetX: pixels(read.offsetX), offsetY: pixels(read.offsetY), rotate: read.rotate, rightToLeft: rightToLeft
        )
    }

    func testLayerGeometryCases() {
        let rows = Contract.rows(Self.table, "layerCases")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            for (direction, rtl) in [("ltr", false), ("rtl", true)] {
                let name = "\(Self.name(row)) [\(direction)]"
                let expected = row[direction]
                let result = LayerGeometry.place(input(row, rightToLeft: rtl))
                let rect = expected?["rect"]
                XCTAssertEqual(Double(result.rect.minX), rect?["x"]?.numberValue ?? .nan, accuracy: 1e-9, "x: \(name)")
                XCTAssertEqual(Double(result.rect.minY), rect?["y"]?.numberValue ?? .nan, accuracy: 1e-9, "y: \(name)")
                XCTAssertEqual(Double(result.rect.width), rect?["width"]?.numberValue ?? .nan, accuracy: 1e-9, "width: \(name)")
                XCTAssertEqual(Double(result.rect.height), rect?["height"]?.numberValue ?? .nan, accuracy: 1e-9, "height: \(name)")
                XCTAssertEqual(result.angle, expected?["angle"]?.numberValue ?? .nan, accuracy: 1e-9, "angle: \(name)")
                XCTAssertEqual(result.protrudes, row["protrudes"]?.boolValue, "protrudes: \(name)")
                for tap in (expected?["taps"]?.arrayValue ?? []).compactMap(\.objectValue) {
                    let point = CGPoint(x: tap["x"]?.numberValue ?? 0, y: tap["y"]?.numberValue ?? 0)
                    XCTAssertEqual(LayerGeometry.contains(result, point), tap["hits"]?.boolValue, "tap \(point): \(name)")
                }
            }
        }
    }

    // MARK: the real node, drawn

    /// A stack whose sizing layer is white and fills `stack`, with one red overlay of `size`
    /// and the `layer` of the row: the pixels must be red exactly where the table says a tap
    /// hits, and the stack must keep its size.
    func testOverlaysAreDrawnWhereTheTableSays() throws {
        let rows = Contract.rows(Self.table, "layerCases")
        let margin: CGFloat = 80
        for row in rows {
            for (direction, rtl) in [("ltr", false), ("rtl", true)] {
                let name = "\(Self.name(row)) [\(direction)]"
                let stack = CGSize(width: row["stack"]?["width"]?.numberValue ?? 0, height: row["stack"]?["height"]?.numberValue ?? 0)
                let size = CGSize(width: row["size"]?["width"]?.numberValue ?? 0, height: row["size"]?["height"]?.numberValue ?? 0)
                let node = try Harness.node(.object(JSONObject([
                    ("id", "stack"), ("type", "Stack"),
                    ("props", ["alignHorizontal": row["stackAlign"]?["horizontal"] ?? "center", "alignVertical": row["stackAlign"]?["vertical"] ?? "center"]),
                    ("children", [
                        Harness.box("base", width: stack.width, height: stack.height, color: "#ffffff"),
                        Harness.box("layer", width: size.width, height: size.height, color: "#ff0000", fields: [("layer", row["layer"] ?? [:])]),
                    ]),
                ])))
                let pixels = try Harness.render(node, rightToLeft: rtl, margin: margin)
                XCTAssertEqual(pixels.width, Int(stack.width + 2 * margin), "the overlay must not change the stack: \(name)")
                XCTAssertEqual(pixels.height, Int(stack.height + 2 * margin), "the overlay must not change the stack: \(name)")
                let expected = row[direction]
                let center = (x: Int(margin) + Int((expected?["rect"]?["x"]?.numberValue ?? 0) + size.width / 2), y: Int(margin) + Int((expected?["rect"]?["y"]?.numberValue ?? 0) + size.height / 2))
                XCTAssertTrue(pixels.isColor(center.x, center.y, "#ff0000"), "centre of the layer: \(name)")
                for tap in (expected?["taps"]?.arrayValue ?? []).compactMap(\.objectValue) {
                    let x = Int(margin) + Int(tap["x"]?.numberValue ?? 0), y = Int(margin) + Int(tap["y"]?.numberValue ?? 0)
                    let hit = pixels.isColor(x, y, "#ff0000")
                    XCTAssertEqual(hit, tap["hits"]?.boolValue, "pixel at tap (\(x - Int(margin)), \(y - Int(margin))): \(name)")
                    if tap["hits"]?.boolValue == false { XCTAssertTrue(pixels.isColor(x, y, "#ffffff"), "the stack is white under a miss at (\(x - Int(margin)), \(y - Int(margin))): \(name)") }
                }
            }
        }
    }

    // MARK: fill

    /// A layer on the whole stack takes the size of the stack, whatever size it names itself; the
    /// layer above it stands where it stands.
    func testFillLayerTakesTheWholeStack() throws {
        let node = try Harness.node(.object(JSONObject([
            ("id", "stack"), ("type", "Stack"), ("props", ["alignHorizontal": "center", "alignVertical": "center"]),
            ("children", [
                Harness.box("base", width: 100, height: 60, color: "#ffffff"),
                Harness.box("fill", width: 10, height: 10, color: "#00ff00", fields: [("fill", true)]),
                Harness.box("dot", width: 10, height: 10, color: "#ff0000", fields: [("layer", ["alignHorizontal": "start", "alignVertical": "start"])]),
            ]),
        ])))
        for rtl in [false, true] {
            let pixels = try Harness.render(node, rightToLeft: rtl, margin: 20)
            XCTAssertEqual(pixels.width, 140)
            XCTAssertEqual(pixels.height, 100)
            for (x, y) in [(21, 21), (118, 21), (21, 78), (118, 78), (70, 50)] where !(rtl ? (x >= 110 && y < 31) : (x < 31 && y < 31)) {
                XCTAssertTrue(pixels.isColor(x, y, "#00ff00"), "the fill layer covers (\(x), \(y)), rtl: \(rtl)")
            }
            XCTAssertTrue(pixels.isColor(rtl ? 115 : 25, 25, "#ff0000"), "the overlay lies over the fill layer, rtl: \(rtl)")
        }
    }

    /// The sizing layer hidden by a condition: the overlay stays an overlay and the stack has no
    /// size now (the document is counted, not visibility).
    func testHiddenSizingLayerLeavesAZeroStackNotAJumpingOverlay() throws {
        let node = try Harness.node(.object(JSONObject([
            ("id", "stack"), ("type", "Stack"), ("props", ["alignHorizontal": "center", "alignVertical": "center"]),
            ("children", [
                Harness.box("base", width: 100, height: 60, color: "#ffffff", fields: [("visibleIf", ["path": "user.isPremium", "op": "isTrue"])]),
                Harness.box("dot", width: 10, height: 10, color: "#ff0000", fields: [("layer", ["alignHorizontal": "end"])]),
            ]),
        ])))
        let pixels = try Harness.render(node, rightToLeft: false, margin: 30)
        XCTAssertEqual(pixels.width, 60)
        XCTAssertEqual(pixels.height, 60)
        // Zero stack at (30, 30): an overlay of 10 at the end of nothing stands at x = -10.
        XCTAssertTrue(pixels.isColor(25, 30, "#ff0000"))
    }

    // MARK: pull

    func testPullFlowCases() {
        let rows = Contract.rows(Self.table, "pullCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            let gap = row["gap"]?.numberValue ?? 0
            let children = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue).map {
                FlowPull.Child(size: CGFloat($0["size"]?.numberValue ?? 0), pull: CGFloat($0["pull"]?.numberValue ?? 0))
            }
            let result = FlowPull.flow(children, gap: CGFloat(gap))
            XCTAssertEqual(result.starts.map(Double.init), (row["starts"]?.arrayValue ?? []).compactMap(\.numberValue), "starts: \(Self.name(row))")
            XCTAssertEqual(Double(result.size), row["size"]?.numberValue ?? .nan, "size: \(Self.name(row))")
        }
    }

    func testPullReadCases() {
        let rows = Contract.rows(Self.table, "pullReadCases")
        XCTAssertEqual(rows.count, 20)
        for row in rows {
            let fields = row["node"]?.objectValue ?? JSONObject()
            let node = DocumentNode(id: "n", type: row["nodeType"]?.stringValue ?? "Text", fields: fields)
            let read = FlowPull.read(node: node, parentType: row["parent"]?.stringValue ?? "", parentProps: row["parentProps"]?.objectValue ?? JSONObject())
            if let expected = row["expect"]?.objectValue {
                XCTAssertEqual(read?.by.json, expected["by"], "by: \(Self.name(row))")
                XCTAssertEqual(read?.axis == .row ? "row" : "column", expected["axis"]?.stringValue, "axis: \(Self.name(row))")
            } else {
                XCTAssertNil(read, Self.name(row))
            }
        }
    }

    func testPullDocumentCasesReaderOutcome() {
        let rows = Contract.rows(Self.table, "pullDocumentCases")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            let node = DocumentNode(id: "n", type: row["nodeType"]?.stringValue ?? "Text", fields: row["node"]?.objectValue ?? JSONObject())
            let read = FlowPull.read(node: node, parentType: row["parent"]?.stringValue ?? "", parentProps: row["parentProps"]?.objectValue ?? JSONObject())
            let issues = (row["issues"]?.arrayValue ?? []).compactMap(\.stringValue)
            let name = Self.name(row)
            if issues.contains(where: { ["v.pullOutsideFlow", "v.pullWithWeight", "v.pullOnAppBar"].contains($0) }) { XCTAssertNil(read, name) }
            if row["schema"]?.boolValue == false { XCTAssertNil(read, "unreadable: \(name)") }
            if row["schema"]?.boolValue == true, issues.isEmpty { XCTAssertNotNil(read, name) }
            if issues.contains("v.unknownToken") { XCTAssertNil(resolver().spacing(read?.by.json), name) }
        }
    }

    /// The strip of a column or a row drawn from the table: each child has its own colour, the
    /// later one lies over the earlier one, and the container is as long as the table says.
    func testPulledFlowsAreDrawnWhereTheTableSays() throws {
        let colors = ["#ff0000", "#00ff00", "#0000ff", "#ffff00"]
        let margin = 60
        for row in Contract.rows(Self.table, "pullCases") {
            let gap = row["gap"]?.numberValue ?? 0
            let items = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue)
            let starts = (row["starts"]?.arrayValue ?? []).compactMap(\.numberValue)
            let total = Int(row["size"]?.numberValue ?? 0)
            for axis in ["column", "row"] {
                for rtl in axis == "row" ? [false, true] : [false] {
                    let name = "\(Self.name(row)) [\(axis)\(rtl ? ", rtl" : "")]"
                    let crossSize = 20.0
                    let children: [JSONValue] = items.enumerated().map { index, item in
                        let size = item["size"]?.numberValue ?? 0
                        let fields: [(String, JSONValue)] = item["pull"].map { [("pull", $0)] } ?? []
                        return Harness.box("c\(index)", width: axis == "row" ? size : crossSize, height: axis == "row" ? crossSize : size, color: colors[index % colors.count], fields: fields)
                    }
                    let container: JSONValue = axis == "row"
                        ? .object(JSONObject([("id", "flow"), ("type", "Row"), ("props", ["gap": .number(gap), "align": "start", "justify": "start", "wrap": false, "scrollable": false]), ("children", .array(children))]))
                        : .object(JSONObject([("id", "flow"), ("type", "Column"), ("props", ["gap": .number(gap)]), ("children", .array(children))]))
                    let pixels = try Harness.render(try Harness.node(container), rightToLeft: rtl, margin: CGFloat(margin))
                    XCTAssertEqual(axis == "row" ? pixels.width : pixels.height, total + 2 * margin, "length of the content: \(name)")
                    // Walk the main axis: the colour at each step is that of the LAST child that covers it.
                    for position in Int(starts.min() ?? 0)..<Int(starts.indices.map { starts[$0] + (items[$0]["size"]?.numberValue ?? 0) }.max() ?? 0) {
                        let covering = items.indices.last { Double(position) >= starts[$0] && Double(position) < starts[$0] + (items[$0]["size"]?.numberValue ?? 0) }
                        // Logical start → physical: from the left in LTR, from the right in right-to-left text.
                        let physical = rtl ? total - position - 1 : position
                        let x = axis == "row" ? margin + physical : margin + 10
                        let y = axis == "row" ? margin + 10 : margin + position
                        guard let covering else { continue }
                        XCTAssertTrue(pixels.isColor(x, y, colors[covering % colors.count]), "colour at \(position): \(name)")
                    }
                }
            }
        }
    }

    // MARK: weights in a row (adaptive table, hidden children removed)

    func testRowWeightCasesAreTheSameArithmetic() throws {
        let table = try Contract.json("fixtures/adaptive/adaptive-cases.json")
        let rows = Contract.rows(table, "weightCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let widthClass = row["widthClass"]?.stringValue ?? "compact"
            let met = Set((row["met"]?.arrayValue ?? []).compactMap(\.stringValue))
            let inline = CGFloat(row["inline"]?.numberValue ?? 0)
            let gap = CGFloat(row["gap"]?.numberValue ?? 0)
            let children = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue)
            // A child is drawn when its class is listed (or none is) and its condition holds.
            let shown = children.map { child -> Bool in
                if let classes = child["showOn"]?.arrayValue?.compactMap(\.stringValue), !classes.contains(widthClass) { return false }
                if let path = child["visibleIf"]?["path"]?.stringValue { return met.contains(path) }
                return true
            }
            let drawn = children.indices.filter { shown[$0] }
            let widths = RowLayout.widths(
                natural: drawn.map { CGFloat(children[$0]["width"]?.numberValue ?? 0) },
                weights: drawn.map { children[$0]["weight"]?.numberValue },
                gap: gap, available: inline
            )
            var expected: [Double?] = []
            for value in row["expect"]?.arrayValue ?? [] { expected.append(value.numberValue) }
            var got: [Double?] = Array(repeating: nil, count: children.count)
            for (slot, index) in drawn.enumerated() { got[index] = Double(widths[slot]) }
            for index in children.indices {
                if let want = expected[index] {
                    XCTAssertEqual(got[index] ?? .nan, want, accuracy: 1e-6, "child \(index): \(Self.name(row))")
                } else {
                    XCTAssertNil(got[index], "child \(index) is not drawn: \(Self.name(row))")
                }
            }
        }
    }
}
