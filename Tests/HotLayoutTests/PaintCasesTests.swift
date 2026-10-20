import XCTest

@testable import HotLayout

/// The colour of a shadow taken from the background (`shadow-color/…`) and the dashed border
/// (`border-dash/…`) against the shared tables.
final class PaintCasesTests: XCTestCase {
    static let shadow = try! Contract.json("fixtures/shadow-color/shadow-color-cases.json")
    static let dash = try! Contract.json("fixtures/border-dash/border-dash-cases.json")

    static let notRun: [String: String] = [
        "border-dash/schemaCases": "verdicts of the schema on the border style; the reader draws any document it can read",
    ]

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "shadow-color/middleStopCases", "shadow-color/tintCases", "shadow-color/ruleCases",
            "border-dash/lineCases", "border-dash/pathCases", "border-dash/styleCases", "border-dash/ruleCases",
        ]
        var groups: Set<String> = []
        for (name, table) in [("shadow-color", Self.shadow), ("border-dash", Self.dash)] {
            for (key, value) in table.objectValue ?? JSONObject() where key.hasSuffix("Cases") && value.arrayValue != nil { groups.insert("\(name)/\(key)") }
        }
        XCTAssertEqual(groups.subtracting(run).subtracting(Self.notRun.keys), [])
        XCTAssertEqual(run.union(Self.notRun.keys).subtracting(groups), [])
    }

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    // MARK: Shadow colour

    func testMiddleStop() {
        let rows = Contract.rows(Self.shadow, "middleStopCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let positions = (row["positions"]?.arrayValue ?? []).compactMap(\.numberValue)
            XCTAssertEqual(ShadowTint.middleStop(positions), row["expected"]?.numberValue.map(Int.init), name(row))
        }
    }

    func testTint() throws {
        let theme = try XCTUnwrap(HotlayoutThemeSet.read(.object(JSONObject([("themes", .object(JSONObject([("light", Self.shadow["theme"]!)])))]))))
        let resolver = StyleResolver(theme: theme.theme("light"))
        let rows = Contract.rows(Self.shadow, "tintCases")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let style = row["style"]?.objectValue ?? JSONObject()
            let layers = ShadowTint.apply(resolver.shadow(style["shadow"]) ?? [], style: style, resolver: resolver)
            guard let expected = row["expect"]?.arrayValue else {
                XCTAssertTrue(layers.isEmpty, name(row))
                continue
            }
            XCTAssertEqual(layers.count, expected.count, name(row))
            for (layer, want) in zip(layers, expected) {
                XCTAssertEqual(layer.offsetX, want["offsetX"]?.numberValue, name(row))
                XCTAssertEqual(layer.offsetY, want["offsetY"]?.numberValue, name(row))
                XCTAssertEqual(layer.blur, want["blur"]?.numberValue, name(row))
                XCTAssertEqual(layer.spread, want["spread"]?.numberValue, name(row))
                let color = try XCTUnwrap(want["color"]?.stringValue.flatMap(RGBA.init(hex:)))
                XCTAssertEqual(layer.color.red, color.red, accuracy: 1e-9, name(row))
                XCTAssertEqual(layer.color.green, color.green, accuracy: 1e-9, name(row))
                XCTAssertEqual(layer.color.blue, color.blue, accuracy: 1e-9, name(row))
                XCTAssertEqual(layer.color.alpha, want["opacity"]?.numberValue ?? .nan, accuracy: 1e-9, name(row))
            }
        }
    }

    func testShadowRules() throws {
        for row in Contract.rows(Self.shadow, "ruleCases") {
            switch row["rule"]?.stringValue {
            case "words": XCTAssertEqual(row["expect"]?.arrayValue?.compactMap(\.stringValue), [ShadowTint.word])
            case "inherited": XCTAssertEqual(row["expect"]?.boolValue, false)
            default: XCTFail(name(row))
            }
        }
        // `shadowColor` is not inherited: the text look a node passes down does not carry it.
        XCTAssertEqual(try Contract.json("screen-schema.json")["x-shadowColor"]?["words"]?.arrayValue?.compactMap(\.stringValue), [ShadowTint.word])
    }

    // MARK: Dashed border

    private func box(_ value: JSONValue?) -> DashedBorderRules.Box {
        func radii(_ r: JSONValue?) -> DashedBorderRules.Radii {
            .init(topStart: r?["topStart"]?.numberValue ?? 0, topEnd: r?["topEnd"]?.numberValue ?? 0, bottomEnd: r?["bottomEnd"]?.numberValue ?? 0, bottomStart: r?["bottomStart"]?.numberValue ?? 0)
        }
        return .init(width: value?["width"]?.numberValue ?? 0, height: value?["height"]?.numberValue ?? 0, border: value?["border"]?.numberValue ?? 0, radii: radii(value?["radii"]))
    }

    func testLines() {
        let rows = Contract.rows(Self.dash, "lineCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            let line = DashedBorderRules.line(box(row["box"]))
            let expect = row["expect"]
            XCTAssertEqual(line.perimeter, expect?["perimeter"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
            XCTAssertEqual(line.count, expect?["count"]?.numberValue.map(Int.init), name(row))
            XCTAssertEqual(line.dash, expect?["dash"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
            XCTAssertEqual(line.gap, expect?["gap"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
            let want = expect?["radii"]
            XCTAssertEqual(line.radii.topStart, want?["topStart"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
            XCTAssertEqual(line.radii.topEnd, want?["topEnd"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
            XCTAssertEqual(line.radii.bottomEnd, want?["bottomEnd"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
            XCTAssertEqual(line.radii.bottomStart, want?["bottomStart"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
        }
    }

    func testPaths() {
        let rows = Contract.rows(Self.dash, "pathCases")
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(DashedBorderRules.pathString(box(row["box"])), row["expect"]?.stringValue, name(row))
        }
    }

    func testStyleWords() {
        let rows = Contract.rows(Self.dash, "styleCases")
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            XCTAssertEqual(DashedBorderRules.isDashed(row["border"]), row["expect"]?.stringValue == "dashed", name(row))
        }
    }

    func testDashRules() throws {
        for row in Contract.rows(Self.dash, "ruleCases") {
            switch row["rule"]?.stringValue {
            case "dash": XCTAssertEqual(row["expect"]?.numberValue, DashedBorderRules.dash)
            case "gap": XCTAssertEqual(row["expect"]?.numberValue, DashedBorderRules.gap)
            default: XCTAssertNotNil(row["expect"], name(row))
            }
        }
        let block = try Contract.json("screen-schema.json")["x-style"]?["layout"]?["borderDash"]
        XCTAssertEqual(block?["dash"]?.numberValue, DashedBorderRules.dash)
        XCTAssertEqual(block?["gap"]?.numberValue, DashedBorderRules.gap)
        XCTAssertEqual(block?["words"]?.arrayValue?.compactMap(\.stringValue), [DashedBorderRules.word])
    }
}

extension DashedBorderRules {
    /// The path as the table writes it, from `frame` (the frame `DashedBorderShape` draws): from
    /// the inline start of the top straight edge toward the end.
    static func pathString(_ box: Box) -> String {
        let f = frame(box)
        func n(_ value: Double) -> String {
            let rounded = (value * 1000).rounded() / 1000
            return rounded == rounded.rounded(.towardZero) ? String(Int(rounded)) : String(rounded)
        }
        func arc(_ r: Double, _ x: Double, _ y: Double) -> String { r > 0 ? "A\(n(r)) \(n(r)) 0 0 1 \(n(x)) \(n(y))" : "L\(n(x)) \(n(y))" }
        let a = f.radii.topStart, b = f.radii.topEnd, c = f.radii.bottomEnd, d = f.radii.bottomStart
        return [
            "M\(n(f.left + a)) \(n(f.top))", "L\(n(f.right - b)) \(n(f.top))", arc(b, f.right, f.top + b),
            "L\(n(f.right)) \(n(f.bottom - c))", arc(c, f.right - c, f.bottom), "L\(n(f.left + d)) \(n(f.bottom))",
            arc(d, f.left, f.bottom - d), "L\(n(f.left)) \(n(f.top + a))", arc(a, f.left + a, f.top), "Z",
        ].joined(separator: " ")
    }
}
