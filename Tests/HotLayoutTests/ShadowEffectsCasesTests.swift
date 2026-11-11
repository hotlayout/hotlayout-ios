import SwiftUI
import XCTest

@testable import HotLayout

/// The inner shadow and the shadow of a text against the shared table (`shadow-effects/shadow-effects-cases.json`):
/// how a layer is read, the geometry of an inner layer, the order of the layers of a text, and what is drawn.
@MainActor
final class ShadowEffectsCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/shadow-effects/shadow-effects-cases.json")
    private static let inset = Table(group: "insetCases", table: table)
    private static let text = Table(group: "textShadowCases", table: table)

    /// The rows of one block of the table (`insetCases.css`, `textShadowCases.document`, …).
    struct Table {
        let group: String
        let table: JSONValue
        func rows(_ name: String) -> [JSONObject] { (table[group]?[name]?.arrayValue ?? []).compactMap(\.objectValue) }
    }

    private let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme(nil))
    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testEveryBlockIsRun() {
        XCTAssertEqual(Set((Self.table["insetCases"]?.objectValue ?? JSONObject()).keys), ["css", "geometry", "document", "themeElevation"])
        XCTAssertEqual(Set((Self.table["textShadowCases"]?.objectValue ?? JSONObject()).keys), ["css", "document"])
    }

    // MARK: Inner layers

    /// The layers of a row as the reader reads them: the numbers as written, and the flag only for the word `true`.
    func testInsetLayersAreRead() throws {
        let rows = Self.inset.rows("css")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let written = row["layers"]?.arrayValue ?? []
            let read = try XCTUnwrap(resolver.shadow(.array(written)), name(row))
            XCTAssertEqual(read.count, written.count, name(row))
            for (layer, source) in zip(read, written) {
                XCTAssertEqual(layer.inset, source["inset"]?.boolValue == true, name(row))
                XCTAssertEqual(layer.offsetX, source["offsetX"]?.numberValue ?? .nan, name(row))
                XCTAssertEqual(layer.offsetY, source["offsetY"]?.numberValue ?? .nan, name(row))
                XCTAssertEqual(layer.blur, source["blur"]?.numberValue ?? .nan, name(row))
                XCTAssertEqual(layer.spread, source["spread"]?.numberValue ?? .nan, name(row))
            }
        }
    }

    func testInsetGeometry() throws {
        let rows = Self.inset.rows("geometry")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            let box = row["box"], layer = row["layer"]
            let radius = box?["radius"]?.numberValue ?? .nan
            let clip = InsetShadowGeometry.clip(
                width: box?["width"]?.numberValue ?? .nan, height: box?["height"]?.numberValue ?? .nan, border: box?["borderWidth"]?.numberValue ?? .nan,
                corners: Corners(topStart: radius, topEnd: radius, bottomEnd: radius, bottomStart: radius))
            let hole = InsetShadowGeometry.hole(
                clip: clip, offsetX: layer?["offsetX"]?.numberValue ?? .nan, offsetY: layer?["offsetY"]?.numberValue ?? .nan, spread: layer?["spread"]?.numberValue ?? .nan)
            for (got, key) in [(clip, "clip"), (hole, "hole")] {
                let want = row[key]
                XCTAssertEqual(got.x, want?["x"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)) \(key).x")
                XCTAssertEqual(got.y, want?["y"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)) \(key).y")
                XCTAssertEqual(got.width, want?["width"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)) \(key).width")
                XCTAssertEqual(got.height, want?["height"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)) \(key).height")
                XCTAssertEqual(got.corners.topStart, want?["radius"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)) \(key).radius")
                XCTAssertEqual(got.corners.bottomEnd, want?["radius"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)) \(key).radius")
            }
        }
    }

    /// A reader keeps a layer whose `inset` is anything but `true` as an outer one, brings numbers to their bounds, and
    /// reads no list of more than four layers.
    func testInsetDocuments() {
        let rows = Self.inset.rows("document")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let read = resolver.shadow(row["shadow"])
            let layers = row["shadow"]?.arrayValue ?? []
            if layers.count > 4 {
                XCTAssertNil(read, name(row))
                continue
            }
            XCTAssertEqual(read?.count, layers.count, name(row))
            XCTAssertEqual(read?.map(\.inset), layers.map { $0["inset"]?.boolValue == true }, name(row))
            for layer in read ?? [] {
                XCTAssertTrue((-64...64).contains(layer.offsetX) && (-64...64).contains(layer.offsetY) && (0...128).contains(layer.blur), name(row))
            }
        }
    }

    /// The theme has no inner shadow: a layer of an elevation token is an outer one whatever it says.
    func testThemeElevationHasNoInnerLayer() throws {
        let rows = Self.inset.rows("themeElevation")
        XCTAssertEqual(rows.count, 2)
        var theme = try Contract.json("theme.json")["contract"] ?? .null
        for row in rows {
            var object = theme.objectValue ?? JSONObject()
            var themes = object["themes"]?.objectValue ?? JSONObject()
            var light = themes["light"]?.objectValue ?? JSONObject()
            light["elevation"] = ["probe": [row["layer"] ?? .null]]
            themes["light"] = .object(light)
            object["themes"] = .object(themes)
            theme = .object(object)
            let layers = try HotlayoutThemeSet.load(theme).theme("light").elevation["probe"] ?? []
            XCTAssertEqual(layers.map(\.inset), [false], name(row))
        }
    }

    private func box(shadow: [JSONValue], fields: [(String, JSONValue)] = []) throws -> DocumentNode {
        try Harness.node(
            .object(JSONObject([
                ("id", "b"), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
                ("style", .object(JSONObject([
                    ("width", 200), ("height", 80), ("background", ["kind": "color", "color": ["value": "#ffffff"]]), ("shadow", .array(shadow)),
                ] + fields))),
                ("children", []),
            ])))
    }

    private func layer(_ x: Double, _ y: Double, blur: Double, spread: Double = 0, color: String, inset: Bool) -> JSONValue {
        var object: JSONObject = ["offsetX": .number(x), "offsetY": .number(y), "blur": .number(blur), "spread": .number(spread), "color": ["value": .string(color)]]
        if inset { object["inset"] = true }
        return .object(object)
    }

    /// An inner layer lies INSIDE the box, over the background: a band at the top edge and nothing outside.
    func testInnerLayerIsPaintedInsideTheBox() throws {
        let node = try box(shadow: [layer(0, 3, blur: 0, color: "#ff0000", inset: true)])
        let pixels = try Harness.render(node, rightToLeft: false, margin: 10)
        XCTAssertTrue(pixels.isColor(110, 10 + 1, "#ff0000"), "the band under the top edge")
        XCTAssertTrue(pixels.isColor(110, 10 + 2, "#ff0000"))
        XCTAssertTrue(pixels.isColor(110, 10 + 40, "#ffffff"), "the middle is the background")
        XCTAssertTrue(pixels.isColor(110, 10 + 78, "#ffffff"), "the bottom edge is not shaded by a layer that moves down")
        XCTAssertTrue(pixels.isColor(110, 5, "#000000"), "nothing outside the box, above it")
        XCTAssertTrue(pixels.isColor(110, 10 + 80 + 5, "#000000"), "nothing outside the box, below it")
    }

    /// An outer layer is drawn behind the box as before, and a mixed list keeps both.
    func testOuterLayerStaysOutside() throws {
        let node = try box(shadow: [layer(0, 6, blur: 0, color: "#00ff00", inset: false), layer(0, 3, blur: 0, color: "#ff0000", inset: true)])
        let pixels = try Harness.render(node, rightToLeft: false, margin: 12)
        XCTAssertTrue(pixels.isColor(112, 12 + 80 + 3, "#00ff00"), "the drop under the box")
        XCTAssertTrue(pixels.isColor(112, 12 + 1, "#ff0000"), "the inner band")
        XCTAssertTrue(pixels.isColor(112, 12 + 40, "#ffffff"))
    }

    /// The first layer lies on top of the next one.
    func testFirstInnerLayerIsOnTop() throws {
        let node = try box(shadow: [layer(0, 4, blur: 0, color: "#ff0000", inset: true), layer(0, 4, blur: 0, color: "#0000ff", inset: true)])
        let pixels = try Harness.render(node, rightToLeft: false, margin: 4)
        XCTAssertTrue(pixels.isColor(104, 4 + 1, "#ff0000"))
    }

    /// The layer is cut to the box inside the border: the border stays free of it.
    func testInnerLayerStopsAtTheBorder() throws {
        let node = try box(
            shadow: [layer(0, 0, blur: 0, spread: 6, color: "#ff0000", inset: true)],
            fields: [("border", ["width": 4, "color": ["value": "#00ff00"]])])
        let pixels = try Harness.render(node, rightToLeft: false, margin: 4)
        XCTAssertTrue(pixels.isColor(104, 4 + 1, "#00ff00"), "the border is over the layer")
        XCTAssertTrue(pixels.isColor(104, 4 + 6, "#ff0000"), "the thick edge inside the border")
        XCTAssertTrue(pixels.isColor(104, 4 + 40, "#ffffff"))
    }

    // MARK: The shadow of a text

    func testTextShadowOrder() {
        let rows = Self.text.rows("css")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let layers = resolver.textShadow(row["layers"])
            XCTAssertEqual(layers?.count, row["layers"]?.arrayValue?.count, name(row))
            let order = TextShadowRules.bottomFirst(layers ?? [])
            let expected = (row["bottomFirst"]?.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) }
            XCTAssertEqual(order, expected.map { layers![$0] }, name(row))
        }
    }

    /// Only `Text` reads the field; one or two layers; numbers are brought to their bounds; an unknown extra field is
    /// not read.
    func testTextShadowDocuments() {
        let rows = Self.text.rows("document")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            let type = row["type"]?.stringValue ?? ""
            let layers = TextShadowRules.layers(type: type, style: ["textShadow": row["textShadow"] ?? .null], resolver: resolver)
            let count = row["textShadow"]?.arrayValue?.count ?? 0
            if type != "Text" || count == 0 || count > 2 {
                XCTAssertNil(layers, name(row))
            } else {
                XCTAssertEqual(layers?.count, count, name(row))
                for layer in layers ?? [] { XCTAssertTrue((0...128).contains(layer.blur) && (-64...64).contains(layer.offsetY), name(row)) }
            }
        }
    }

    private func text(shadow: [JSONValue]?, gradient: Bool = false) throws -> DocumentNode {
        var style: JSONObject = ["color": ["value": "#ffffff"], "typography": ["token": "displayL", "fontSize": 60]]
        if let shadow { style["textShadow"] = .array(shadow) }
        if gradient {
            style["textGradient"] = ["angle": 180, "stops": [["color": ["value": "#ffffff"], "position": 0], ["color": ["value": "#ffffff"], "position": 1]]]
        }
        return try Harness.node(
            .object(JSONObject([
                ("id", "t"), ("type", "Text"), ("props", ["content": ["kind": "literal", "value": "HI"]]), ("style", .object(style)),
            ])))
    }

    private func textLayer(_ x: Double, _ y: Double, color: String) -> JSONValue {
        ["offsetX": .number(x), "offsetY": .number(y), "blur": 0, "color": ["value": .string(color)]]
    }

    private func count(_ pixels: Pixels, where test: (Int, Int, Int) -> Bool) -> Int {
        var found = 0
        for y in 0..<pixels.height { for x in 0..<pixels.width { if let c = pixels.rgb(x, y), test(c.r, c.g, c.b) { found += 1 } } }
        return found
    }

    private func isRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 200 && g < 60 && b < 60 }

    /// The shadow is a copy of the text in the colour of the layer: it shows past the glyphs, and it takes no room.
    func testTextShadowShowsBesideTheGlyphsAndTakesNoRoom() throws {
        let plain = try Harness.render(text(shadow: nil), rightToLeft: false, margin: 30)
        let shadowed = try Harness.render(text(shadow: [textLayer(0, 12, color: "#ff0000")]), rightToLeft: false, margin: 30)
        XCTAssertGreaterThan(count(shadowed, where: isRed), 40)
        XCTAssertEqual(shadowed.width, plain.width, "the shadow does not widen the text")
        let flat = try Harness.render(text(shadow: [textLayer(40, 40, color: "#ff0000")]), rightToLeft: false, margin: 30)
        XCTAssertEqual(flat.height, shadowed.height, "the offset does not change the height")
    }

    /// An opaque gradient on the glyphs hides the shadow under it as a solid colour would.
    func testTextShadowDoesNotShineThroughAGradientOnTheGlyphs() throws {
        let hidden = try Harness.render(text(shadow: [textLayer(0, 0, color: "#ff0000")], gradient: true), rightToLeft: false, margin: 30)
        XCTAssertEqual(count(hidden, where: isRed), 0)
        let moved = try Harness.render(text(shadow: [textLayer(0, 12, color: "#ff0000")], gradient: true), rightToLeft: false, margin: 30)
        XCTAssertGreaterThan(count(moved, where: isRed), 40)
    }

    func testFirstTextLayerIsOnTop() throws {
        let both = try Harness.render(text(shadow: [textLayer(0, 12, color: "#ff0000"), textLayer(0, 12, color: "#0000ff")]), rightToLeft: false, margin: 30)
        XCTAssertGreaterThan(count(both, where: isRed), 40)
        XCTAssertEqual(count(both, where: { r, g, b in b > 200 && r < 60 && g < 60 }), 0)
    }
}
