import SwiftUI
import XCTest

@testable import HotLayout

/// The radial gradient against the shared table (`radial-gradient/radial-gradient-cases.json`): the radius in points,
/// the readings of a gradient of a node and of a theme token, and the circle on the pixels.
@MainActor
final class RadialGradientCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/radial-gradient/radial-gradient-cases.json")

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testEveryGroupIsRun() {
        XCTAssertEqual(Contract.groups(Self.table), ["geometryCases", "documentCases"])
    }

    func testRadiusInPoints() {
        let rows = Contract.rows(Self.table, "geometryCases")
        XCTAssertEqual(rows.count, 48)
        for row in rows {
            let width = row["box"]?["width"]?.numberValue ?? .nan, height = row["box"]?["height"]?.numberValue ?? .nan
            let center = row["center"]
            let radial = GradientValue.Radial(centerX: center?["x"]?.numberValue ?? .nan, centerY: center?["y"]?.numberValue ?? .nan, radius: row["radius"]?.numberValue ?? .nan)
            let radius = radial.radiusPoints(width: width, height: height)
            XCTAssertEqual(radius, row["radiusPx"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
            // The share of the shorter side that Flutter's own gradient takes.
            XCTAssertEqual(radius / min(width, height), row["flutterRadius"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
            let far = radial.radiusPoints(width: width, height: height) / radial.radius
            XCTAssertEqual(far, row["farthestCornerPx"]?.numberValue ?? .nan, accuracy: 1e-5, name(row))
        }
    }

    /// What the reader does with a row the schema refuses: a form that does not resolve is no gradient, a number outside
    /// its bounds is brought to them.
    private static let notDrawn: Set<String> = [
        "radial with an angle", "linear with a shape field", "shape without center", "shape without radius", "radial without shape", "unknown shape",
        "linear with a center", "radial with one stop",
    ]

    func testOwnGradient() {
        let rows = Contract.rows(Self.table, "documentCases")
        XCTAssertEqual(rows.count, 20)
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme(nil))
        for row in rows {
            let raw = row["gradient"] ?? .null
            let gradient = resolver.gradient(raw)
            if row["valid"]?.boolValue == true {
                XCTAssertNotNil(gradient, name(row))
                XCTAssertEqual(gradient?.radial != nil, raw["shape"]?.stringValue == "radial", name(row))
            } else if Self.notDrawn.contains(name(row)) {
                XCTAssertNil(gradient, name(row))
            } else if let radial = gradient?.radial {
                XCTAssertTrue((0...1).contains(radial.centerX) && (0...1).contains(radial.centerY), name(row))
                XCTAssertTrue((0.05...2).contains(radial.radius), name(row))
            } else {
                XCTFail("\(name(row)): a number outside its bounds is brought to them, the gradient stays")
            }
        }
    }

    private func themeWith(gradient: JSONValue) throws -> HotlayoutThemeSet {
        var theme = try Contract.json("theme.json")["contract"] ?? .null
        var object = theme.objectValue ?? JSONObject()
        var themes = object["themes"]?.objectValue ?? JSONObject()
        var light = themes["light"]?.objectValue ?? JSONObject()
        var gradients = light["gradient"]?.objectValue ?? JSONObject()
        gradients["probeGradient"] = gradient
        light["gradient"] = .object(gradients)
        themes["light"] = .object(light)
        object["themes"] = .object(themes)
        theme = .object(object)
        return try HotlayoutThemeSet.load(theme)
    }

    func testThemeToken() throws {
        let colors = ["#336699", "#cc9966"]
        for row in Contract.rows(Self.table, "documentCases") {
            var raw = row["gradient"]?.objectValue ?? JSONObject()
            let stops = (raw["stops"]?.arrayValue ?? []).enumerated().map { index, stop in
                JSONValue.object(["color": .string(colors[index % 2]), "position": stop["position"] ?? .null])
            }
            raw["stops"] = .array(stops)
            let token = try themeWith(gradient: .object(raw)).theme("light").gradient["probeGradient"]
            if row["valid"]?.boolValue == true {
                XCTAssertNotNil(token, name(row))
                XCTAssertEqual(token?.radial != nil, raw["shape"]?.stringValue == "radial", name(row))
                if let radial = token?.radial, let center = raw["center"] {
                    XCTAssertEqual([radial.centerX, radial.centerY, radial.radius], [center["x"]?.numberValue, center["y"]?.numberValue, raw["radius"]?.numberValue].compactMap { $0 }, name(row))
                }
            } else if Self.notDrawn.contains(name(row)) {
                // An entry of the wrong form is dropped: the theme has no such gradient.
                XCTAssertNil(token, name(row))
            } else if let radial = token?.radial {
                XCTAssertTrue((0...1).contains(radial.centerX) && (0...1).contains(radial.centerY) && (0.05...2).contains(radial.radius), name(row))
            } else {
                XCTFail("\(name(row)): a number outside its bounds is brought to them")
            }
        }
    }

    /// A box filled by a radial gradient, read back: the first colour at the centre, the last one past the circle, and
    /// the same colour at the same distance along both axes (a circle, never an ellipse).
    private func fill(width: Double, height: Double, x: Double, y: Double, radius: Double) throws -> Pixels {
        let gradient: JSONValue = [
            "shape": "radial", "center": ["x": .number(x), "y": .number(y)], "radius": .number(radius),
            "stops": [["color": ["value": "#ff0000"], "position": 0], ["color": ["value": "#0000ff"], "position": 1]],
        ]
        let node = try Harness.node(
            .object(JSONObject([
                ("id", "g"), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
                ("style", ["width": .number(width), "height": .number(height), "background": ["kind": "gradient", "gradient": gradient]]),
                ("children", []),
            ])))
        return try Harness.render(node, rightToLeft: false, margin: 0)
    }

    /// The colour at a pixel within the tolerance of a gradient (colour management and the half pixel of the centre).
    private func near(_ pixels: Pixels, _ x: Int, _ y: Int, _ hex: String) -> Bool {
        guard let c = pixels.rgb(x, y), let want = RGBA(hex: hex) else { return false }
        return abs(c.r - Int((want.red * 255).rounded())) <= 30 && abs(c.g - Int((want.green * 255).rounded())) <= 30
            && abs(c.b - Int((want.blue * 255).rounded())) <= 30
    }

    func testCircleOnAWideBox() throws {
        // 300x100, centre in the middle, radius 0.5: R = 0.5 * 158.11 = 79.06.
        let pixels = try fill(width: 300, height: 100, x: 0.5, y: 0.5, radius: 0.5)
        XCTAssertEqual(pixels.width, 300)
        XCTAssertTrue(near(pixels, 150, 50, "#ff0000"))
        XCTAssertTrue(near(pixels, 5, 5, "#0000ff"), "past the circle: the last colour")
        XCTAssertTrue(near(pixels, 295, 95, "#0000ff"))
        // 35 points to the right and 35 points down are the same distance from the centre.
        let right = try XCTUnwrap(pixels.rgb(150 + 35, 50)), below = try XCTUnwrap(pixels.rgb(150, 50 + 35))
        XCTAssertEqual(right.r, below.r, accuracy: 8)
        XCTAssertEqual(right.b, below.b, accuracy: 8)
        XCTAssertGreaterThan(right.r, 60)
        XCTAssertGreaterThan(right.b, 60)
    }

    func testCentreAtACornerAndNotMirrored() throws {
        let pixels = try fill(width: 200, height: 200, x: 0, y: 0, radius: 0.5)
        XCTAssertTrue(near(pixels, 0, 0, "#ff0000"))
        XCTAssertTrue(near(pixels, 199, 199, "#0000ff"))
        let rtl = try {
            let node = try Harness.node(
                .object(JSONObject([
                    ("id", "g"), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
                    ("style", ["width": 200, "height": 200, "background": ["kind": "gradient", "gradient": [
                        "shape": "radial", "center": ["x": 0, "y": 0], "radius": 0.5,
                        "stops": [["color": ["value": "#ff0000"], "position": 0], ["color": ["value": "#0000ff"], "position": 1]],
                    ]]]),
                    ("children", []),
                ])))
            return try Harness.render(node, rightToLeft: true, margin: 0)
        }()
        XCTAssertTrue(near(rtl, 0, 0, "#ff0000"), "the centre is physical: not mirrored in right-to-left text")
    }
}
