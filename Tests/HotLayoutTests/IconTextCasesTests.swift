import XCTest

@testable import HotLayout

/// «An icon beside a text», the button sizes and the icon button against the shared table
/// (`icon-text/icon-text-cases.json`). `iconPathDocumentCases` are verdicts of the JSON Schema
/// and of the document validator, which this reader does not have.
final class IconTextCasesTests: XCTestCase {
    private let theme = HotlayoutThemeSet.builtIn.theme()
    private lazy var table = try! Contract.json("fixtures/icon-text/icon-text-cases.json")

    private func rtl(_ row: JSONObject) -> Bool { row["direction"]?.stringValue == "rtl" }

    private func parts(_ value: JSONValue?) -> [BesidePart] {
        (value?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(BesidePart.init(rawValue:)) }
    }

    /// The order of the parts of a node by the same rule for the three places.
    private func order(widget: String, props: JSONObject, rightToLeft: Bool, scope: DataScope = [:]) -> (icon: IconResolution, logical: [BesidePart], visual: [BesidePart]) {
        let icon = IconBesideTextRules.resolve(props: props, field: "icon", scope: scope)
        // A list row always puts the icon after the text.
        let position = widget == "ListTile" ? "end" : props["iconPosition"]?.stringValue
        let logical = IconBesideTextRules.logicalOrder(icon: icon, position: position)
        // `IconBesideText` puts the parts in an `HStack`, which SwiftUI lays out in reading direction.
        return (icon, logical, rightToLeft ? Array(logical.reversed()) : logical)
    }

    func testOrderOfParts() {
        let rows = Contract.rows(table, "orderCases")
        XCTAssertEqual(rows.count, 17)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let result = order(widget: row["widget"]?.stringValue ?? "", props: row["props"]?.objectValue ?? JSONObject(), rightToLeft: rtl(row))
            let expect = row["expect"]
            XCTAssertEqual(result.logical, parts(expect?["logical"]), "logical: \(name)")
            XCTAssertEqual(result.visual, parts(expect?["visual"]), "visual: \(name)")
            XCTAssertEqual(result.icon.box == .drawn, expect?["drawn"]?.boolValue, "drawn: \(name)")
            XCTAssertEqual(IconSet.isMirrored(result.icon.name, rightToLeft: rtl(row)), expect?["mirrored"]?.boolValue, "mirrored: \(name)")
        }
    }

    func testGlyphBoxBesideText() {
        let rows = Contract.rows(table, "glyphCases")
        XCTAssertEqual(rows.count, 5)
        let gap = theme.spacing[IconBesideTextRules.gapToken] ?? -1
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let typography = theme.typography[row["typography"]?.stringValue ?? ""]!
            let box = IconBesideTextRules.glyphBox(typography)
            let expect = row["expect"]
            XCTAssertEqual(box.glyph, expect?["glyph"]?.numberValue ?? -1, accuracy: 0.01, "glyph: \(name)")
            XCTAssertEqual(Double(box.box.width), expect?["boxInline"]?.numberValue ?? -1, accuracy: 0.01, "boxInline: \(name)")
            XCTAssertEqual(Double(box.box.height), expect?["boxBlock"]?.numberValue ?? -1, accuracy: 0.01, "boxBlock: \(name)")
            XCTAssertEqual(gap, expect?["gap"]?.numberValue ?? -2, accuracy: 0.01, "gap: \(name)")
            // The box and the gap of the `HStack` the icon stands in.
            XCTAssertEqual(Double(box.box.width) + gap, expect?["addsInline"]?.numberValue ?? -1, accuracy: 0.01, "addsInline: \(name)")
            // The box is as tall as the line of the text, so the icon never makes the widget taller.
            XCTAssertEqual(max(0, Double(box.box.height) - typography.lineBox), expect?["addsBlock"]?.numberValue ?? -1, accuracy: 0.01, "addsBlock: \(name)")
        }
    }

    func testButtonSizes() {
        let rows = Contract.rows(table, "buttonSizeCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let size = ButtonGeometry.size(row["size"]?.stringValue, theme: theme)
            let expect = row["expect"]
            XCTAssertEqual(size.paddingBlock, expect?["paddingBlock"]?.numberValue ?? -1, "paddingBlock: \(name)")
            XCTAssertEqual(size.paddingInline, expect?["paddingInline"]?.numberValue ?? -1, "paddingInline: \(name)")
            XCTAssertEqual(size.typography, expect?["typography"]?.stringValue, "typography: \(name)")
            let height = ButtonGeometry.height(size, theme: theme, border: row["border"]?.numberValue ?? 0)
            XCTAssertEqual(height, expect?["block"]?.numberValue ?? -1, accuracy: 0.01, "block: \(name)")
        }
    }

    func testIconButtons() {
        let rows = Contract.rows(table, "iconButtonCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let geometry = ButtonGeometry.iconButton(size: row["size"]?.stringValue, glyphSize: nil, theme: theme, border: row["border"]?.numberValue ?? 0)
            let expect = row["expect"]
            XCTAssertEqual(geometry.side, expect?["side"]?.numberValue ?? -1, accuracy: 0.01, "side: \(name)")
            XCTAssertEqual(geometry.glyph, expect?["glyph"]?.numberValue ?? -1, accuracy: 0.01, "glyph: \(name)")
            XCTAssertEqual(geometry.padding, expect?["padding"]?.numberValue ?? -1, accuracy: 0.01, "padding: \(name)")
        }
    }

    /// `glyphSize` names the glyph: the content box is its square and the button grows with it.
    func testIconButtonWithAnOwnGlyph() {
        let geometry = ButtonGeometry.iconButton(size: "md", glyphSize: 32, theme: theme, border: 0)
        XCTAssertEqual(geometry.glyph, 32)
        XCTAssertEqual(geometry.side, 32 + 2 * 8)
        XCTAssertEqual(ButtonGeometry.iconButton(size: "md", glyphSize: 500, theme: theme, border: 0).glyph, 128, "the number is clamped to 8…128")
        XCTAssertEqual(ButtonGeometry.iconButton(size: "md", glyphSize: 1, theme: theme, border: 0).glyph, 8)
    }

    func testAccessibleNames() {
        let rows = Contract.rows(table, "nameCases")
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            let name = ButtonGeometry.iconButtonName(label: row["label"]?.stringValue ?? "", iconName: row["icon"])
            XCTAssertEqual(name, row["expect"]?.stringValue, row["name"]?.stringValue ?? "?")
        }
    }

    func testSilentText() {
        for silent in ["", "   ", "\u{200B}", "\u{FE0F}", "\u{3164}", "\u{2800}", "\u{00A0}", "\u{200B} \u{200D}"] {
            XCTAssertTrue(TextHeard.isSilent(silent), "U+\(silent.unicodeScalars.first.map { String($0.value, radix: 16) } ?? "")")
        }
        for heard in ["a", "é", "e\u{0301}", "👍\u{FE0F}", "٣"] {
            XCTAssertFalse(TextHeard.isSilent(heard), heard)
        }
    }

    func testColorOfTheTrailingText() {
        let rows = Contract.rows(table, "colorCases")
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            let named = row["named"]
            let context = ListTileRules.NamedColor(ref: named ?? .null, named: named != nil && named?.isNull == false)
            let look = ListTileRules.trailingTextLook(["kind": "text"], context: context, isMet: { _ in false })
            // The icon beside the text takes the colour of the text: one value for both.
            XCTAssertEqual(look.color, row["expect"]?["text"], row["name"]?.stringValue ?? "?")
            XCTAssertEqual(look.color, row["expect"]?["icon"], row["name"]?.stringValue ?? "?")
        }
    }

    func testIconFromData() {
        let rows = Contract.rows(table, "iconPathCases")
        XCTAssertEqual(rows.count, 22)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let widget = row["widget"]?.stringValue ?? ""
            let props = row["props"]?.objectValue ?? JSONObject()
            let scope = Contract.scope(row["data"])
            let expect = row["expect"]
            let icon = IconBesideTextRules.resolve(props: props, field: widget == "Icon" ? "name" : "icon", scope: scope)
            // `null` in the table is «the node has no icon at all»: no value, not the value `null`.
            let resolved: JSONValue? = expect?["resolved"]?.isNull == true ? Optional<JSONValue>.none : expect?["resolved"]
            XCTAssertEqual(icon.resolved, resolved, "resolved: \(name)")
            XCTAssertEqual(icon.box.rawValue, expect?["box"]?.stringValue, "box: \(name)")
            // «mirrored» says whether the drawn icon is flipped on a right-to-left screen.
            XCTAssertEqual(IconSet.isMirrored(icon.name, rightToLeft: true), expect?["mirrored"]?.boolValue, "mirrored: \(name)")
            if let logical = expect?["logical"] {
                XCTAssertEqual(order(widget: widget, props: props, rightToLeft: false, scope: scope).logical, parts(logical), "logical: \(name)")
            }
        }
        XCTAssertEqual(Contract.rows(table, "iconPathDocumentCases").count, 9, "validator verdicts: not a reader's concern")
    }
}
