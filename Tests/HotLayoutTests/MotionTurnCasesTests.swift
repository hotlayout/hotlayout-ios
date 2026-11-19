import SwiftUI
import XCTest

@testable import HotLayout

/// `spin` and `sway` of a node and its one-time appearance (`appear`) against
/// `motion/motion-turn-cases.json`: the turn and the pose of the appearance at a moment (through the
/// formulas, and through the real node drawn at that moment), the moments at which the appearance
/// plays, and the values the reader accepts. `zoneCases` is the table of the builder's validator and
/// is not run here.
@MainActor
final class MotionTurnCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/motion/motion-turn-cases.json")

    private static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = ["turnCases", "appearCases", "momentCases", "documentCases"]
        let notRun: Set<String> = ["zoneCases"]
        let groups = Contract.groups(Self.table)
        XCTAssertEqual(groups.subtracting(run).subtracting(notRun), [], "groups that are neither run nor named")
        XCTAssertEqual(run.union(notRun).subtracting(groups), [], "names that are no longer groups")
    }

    func testTheBlocksOfTheArtifact() throws {
        let schema = try Contract.json("screen-schema.json")
        let turn = try XCTUnwrap(schema["x-motionTurn"])
        XCTAssertEqual(turn["kinds"], ["spin", "sway"])
        XCTAssertEqual(turn["spin"]?["directions"], ["clockwise", "counterclockwise"])
        XCTAssertEqual(turn["sway"]?["pivots"], ["center", "top", "bottom"])
        XCTAssertEqual(turn["ranges"]?["angle"]?["min"]?.numberValue, Double(NodeMotion.angleRange.lowerBound))
        XCTAssertEqual(turn["ranges"]?["angle"]?["max"]?.numberValue, Double(NodeMotion.angleRange.upperBound))
        XCTAssertEqual(turn["ranges"]?["duration"]?["min"]?.numberValue, Double(NodeMotion.durationRange.lowerBound))
        XCTAssertEqual(turn["ranges"]?["delay"]?["max"]?.numberValue, Double(NodeMotion.delayRange.upperBound))
        let appear = try XCTUnwrap(schema["x-appear"])
        XCTAssertEqual(appear["prop"]?.stringValue, NodeAppear.field)
        XCTAssertEqual(appear["kinds"], ["fade", "rise"])
        XCTAssertEqual(appear["ranges"]?["duration"]?["min"]?.numberValue, Double(NodeAppear.durationRange.lowerBound))
        XCTAssertEqual(appear["ranges"]?["duration"]?["max"]?.numberValue, Double(NodeAppear.durationRange.upperBound))
        XCTAssertEqual(appear["ranges"]?["distance"]?["min"]?.numberValue, Double(NodeAppear.distanceRange.lowerBound))
        XCTAssertEqual(appear["ranges"]?["distance"]?["max"]?.numberValue, Double(NodeAppear.distanceRange.upperBound))
        let curve = (appear["curve"]?["bezier"]?.arrayValue ?? []).compactMap(\.numberValue)
        XCTAssertEqual(curve, [VisibilityFade.inCurve.x1, VisibilityFade.inCurve.y1, VisibilityFade.inCurve.x2, VisibilityFade.inCurve.y2])
        XCTAssertEqual(schema["x-motion"]?["kinds"], ["float", "pulse"], "`x-motion` does not name the new kinds")
    }

    // MARK: The turn

    func testTurnFormulas() throws {
        let rows = Contract.rows(Self.table, "turnCases")
        XCTAssertEqual(rows.count, 24)
        for row in rows {
            let motion = try XCTUnwrap(NodeMotion.read(row["motion"]), Self.name(row))
            let pose = motion.pose(at: row["t"]?.numberValue ?? 0, reducedMotion: row["reducedMotion"]?.boolValue == true, rightToLeft: row["direction"]?.stringValue == "rtl")
            let expected = row["expected"]
            XCTAssertEqual(pose.rotate, expected?["rotate"]?.numberValue ?? .nan, accuracy: 1e-6, Self.name(row))
            XCTAssertEqual(pose.pivot.rawValue, expected?["pivot"]?.stringValue, Self.name(row))
            XCTAssertEqual([pose.x, pose.y, pose.scale, pose.opacity], [0, 0, 1, 1], Self.name(row))
        }
    }

    /// The real node, drawn at the moment of the row: a thin vertical bar, turned about its pivot. The
    /// angle of its axis and the place of its centre say what was painted.
    func testTurnedNodesArePaintedAtTheTurnOfTheTable() throws {
        try skipUnderReducedMotion()
        var checked = 0
        for row in Contract.rows(Self.table, "turnCases") where row["reducedMotion"]?.boolValue != true {
            let rtl = row["direction"]?.stringValue == "rtl"
            let motion = try XCTUnwrap(row["motion"], Self.name(row))
            let rest = try Self.bar(motion: motion, at: 0, rtl: rtl)
            let moved = try Self.bar(motion: motion, at: row["t"]?.numberValue ?? 0, rtl: rtl)
            let degrees = row["expected"]?["rotate"]?.numberValue ?? .nan
            let radians = degrees * .pi / 180
            // The axis of a vertical bar after a clockwise turn by r is 90 + r degrees from the x axis, modulo 180.
            var delta = (moved.axis - (90 + degrees)).truncatingRemainder(dividingBy: 180)
            if delta > 90 { delta -= 180 }
            if delta < -90 { delta += 180 }
            XCTAssertEqual(delta, 0, accuracy: 2.5, "the angle painted: \(Self.name(row))")
            let pivot: (x: Double, y: Double) = switch row["expected"]?["pivot"]?.stringValue {
            case "top": (rest.x, rest.top)
            case "bottom": (rest.x, rest.bottom)
            default: (rest.x, rest.y)
            }
            let dx = rest.x - pivot.x, dy = rest.y - pivot.y
            let expectedX = pivot.x + dx * cos(radians) - dy * sin(radians)
            let expectedY = pivot.y + dx * sin(radians) + dy * cos(radians)
            XCTAssertEqual(moved.x, expectedX, accuracy: 2, "the place painted, x: \(Self.name(row))")
            XCTAssertEqual(moved.y, expectedY, accuracy: 2, "the place painted, y: \(Self.name(row))")
            checked += 1
        }
        XCTAssertEqual(checked, 22)
    }

    /// The ink of a drawing: its centre, the axis of its mass and the top and bottom of its box.
    struct Ink {
        var x = 0.0, y = 0.0, axis = 0.0, top = 0.0, bottom = 0.0
    }

    /// A node of 8 by 60 points with `motion`, drawn on white at the moment `t`, in the writing direction asked for.
    static func bar(motion: JSONValue, at t: Double, rtl: Bool) throws -> Ink {
        let node = try Harness.node(Harness.box("bar", width: 8, height: 60, color: "#ff0000", fields: [("motion", motion)]))
        let view = NodeView(node: node, context: Harness.context(rightToLeft: rtl), placement: .natural)
            .environment(\.nodeMotionClockMs, t)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .padding(100).background(Color.white)
        return ink(ProgressPixels.render(view))
    }

    static func ink(_ image: ProgressPixels.Image) -> Ink {
        var count = 0.0, sx = 0.0, sy = 0.0
        var points: [(Double, Double)] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let c = ProgressPixels.color(image, x: x, y: y)
                guard c.alpha > 0.5, c.red > 0.8, c.green < 0.5 else { continue }
                points.append((Double(x), Double(y)))
                count += 1
                sx += Double(x)
                sy += Double(y)
            }
        }
        guard count > 0 else { return Ink() }
        let mx = sx / count, my = sy / count
        var m20 = 0.0, m02 = 0.0, m11 = 0.0
        for (x, y) in points {
            m20 += (x - mx) * (x - mx)
            m02 += (y - my) * (y - my)
            m11 += (x - mx) * (y - my)
        }
        let axis = 0.5 * atan2(2 * m11, m20 - m02) * 180 / .pi
        return Ink(x: mx, y: my, axis: axis, top: points.map(\.1).min() ?? 0, bottom: (points.map(\.1).max() ?? 0) + 1)
    }

    /// A spin has no direction of the line: it turns the same way in a right-to-left environment, where
    /// SwiftUI mirrors a turn by itself. A sway is mirrored by the contract.
    func testSpinIsNotMirroredAndSwayIs() throws {
        try skipUnderReducedMotion()
        func redEnd(of rtl: Bool, motion: JSONValue, at t: Double) throws -> Double {
            // Two boxes in a row: the first is red. In right-to-left writing the first lies at the right.
            let row: JSONValue = [
                "id": "row", "type": "Container", "props": ["direction": "row", "gap": "none"], "motion": motion,
                "children": [Harness.box("a", width: 30, height: 8, color: "#ff0000"), Harness.box("b", width: 30, height: 8, color: "#0000ff")],
            ]
            let node = try Harness.node(row)
            let view = NodeView(node: node, context: Harness.context(rightToLeft: rtl), placement: .natural)
                .environment(\.nodeMotionClockMs, t)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                .padding(100).background(Color.white)
            return Self.ink(ProgressPixels.render(view)).y
        }
        let spin: JSONValue = ["kind": "spin", "direction": "clockwise", "duration": 4000]
        let quarter = 1000.0
        let centre = try redEnd(of: false, motion: ["kind": "spin", "direction": "clockwise", "duration": 4000], at: 0)
        // Clockwise by a quarter turn: the left end goes up, the right end goes down.
        XCTAssertLessThan(try redEnd(of: false, motion: spin, at: quarter), centre - 10, "left to right: the first box (left) goes up")
        XCTAssertGreaterThan(try redEnd(of: true, motion: spin, at: quarter), centre + 10, "right to left: the first box (right) goes down: the same turn")
        // A sway about the top, the bottom of a bar goes left when the turn is clockwise.
        func bottomShift(rtl: Bool) throws -> Double {
            let motion: JSONValue = ["kind": "sway", "angle": 45, "pivot": "top", "duration": 4000]
            return try Self.bar(motion: motion, at: quarter, rtl: rtl).x - Self.bar(motion: motion, at: 0, rtl: rtl).x
        }
        XCTAssertLessThan(try bottomShift(rtl: false), -10, "left to right: clockwise, the bottom swings left")
        XCTAssertGreaterThan(try bottomShift(rtl: true), 10, "right to left: mirrored, the bottom swings right")
    }

    /// The turn of a node moves nothing next to it.
    func testATurningNodeDoesNotMoveItsNeighbours() throws {
        try skipUnderReducedMotion()
        func belowY(at t: Double) throws -> Double {
            let column: JSONValue = [
                "id": "col", "type": "Container", "props": ["direction": "column", "gap": "none"],
                "children": [
                    Harness.box("tile", width: 40, height: 40, color: "#00ff00", fields: [("motion", ["kind": "sway", "angle": 45, "pivot": "top", "duration": 4000])]),
                    Harness.box("below", width: 40, height: 20, color: "#ff0000"),
                ],
            ]
            let node = try Harness.node(column)
            let view = NodeView(node: node, context: Harness.context(rightToLeft: false), placement: .natural)
                .environment(\.nodeMotionClockMs, t).padding(100).background(Color.white)
            return Self.ink(ProgressPixels.render(view)).bottom
        }
        XCTAssertEqual(try belowY(at: 1000), try belowY(at: 0), accuracy: 0.5)
    }

    // MARK: The appearance

    func testAppearanceFormulas() throws {
        let rows = Contract.rows(Self.table, "appearCases")
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            let appear = try XCTUnwrap(NodeAppear.read(row["appear"]), Self.name(row))
            let pose = appear.pose(at: row["t"]?.numberValue ?? 0, reducedMotion: row["reducedMotion"]?.boolValue == true)
            XCTAssertEqual(pose.y, row["expected"]?["y"]?.numberValue ?? .nan, accuracy: 1e-6, Self.name(row))
            XCTAssertEqual(pose.opacity, row["expected"]?["opacity"]?.numberValue ?? .nan, accuracy: 1e-6, Self.name(row))
        }
    }

    /// The real node, drawn at the moment of the row inside a screen (which opens the window): a red square
    /// of 40 points on white, its opacity read from the colour and its shift from the place.
    func testAppearingNodesArePaintedAtThePoseOfTheTable() throws {
        var checked = 0
        for row in Contract.rows(Self.table, "appearCases") where row["reducedMotion"]?.boolValue != true {
            let node = try Harness.node(Harness.box("sq", width: 40, height: 40, color: "#ff0000", fields: [("appear", row["appear"] ?? .null)]))
            func drawn(at t: Double) -> (opacity: Double, y: Double) {
                let view = NodeView(node: node, context: Harness.context(rightToLeft: false), placement: .natural)
                    .environment(\.appearClockMs, t).padding(100).background(Color.white)
                let image = ProgressPixels.render(view)
                let inside = ProgressPixels.color(image, x: image.width / 2, y: image.height / 2 + 0)
                // A shifted square may not cover the centre; read the opacity from the first pixel that is not white.
                var opacity = 0.0, top = Double(image.height)
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let c = ProgressPixels.color(image, x: x, y: y)
                        if c.green < 0.999, c.red > 0.99 {
                            opacity = max(opacity, 1 - c.green)
                            top = min(top, Double(y))
                        }
                    }
                }
                _ = inside
                return (opacity, top)
            }
            let expectedY = row["expected"]?["y"]?.numberValue ?? .nan
            let expectedOpacity = row["expected"]?["opacity"]?.numberValue ?? .nan
            let atRest = drawn(at: 100_000)
            let now = drawn(at: row["t"]?.numberValue ?? 0)
            XCTAssertEqual(now.opacity, expectedOpacity, accuracy: 0.02, "opacity painted: \(Self.name(row))")
            if expectedOpacity > 0.02 { XCTAssertEqual(now.y - atRest.y, expectedY, accuracy: 1.1, "shift painted: \(Self.name(row))") }
            checked += 1
        }
        XCTAssertEqual(checked, 12)
    }

    /// The appearance is laid over the pose of a motion: its shift adds, its opacity multiplies.
    func testTheAppearanceLiesOverTheMotion() throws {
        let node = try Harness.node(
            Harness.box(
                "sq", width: 40, height: 40, color: "#ff0000",
                fields: [
                    ("motion", ["kind": "pulse", "scale": 1, "opacity": 0.5, "duration": 4000]),
                    ("appear", ["kind": "fade", "duration": 400]),
                ]))
        func opacity(motionAt: Double, appearAt: Double) -> Double {
            let view = NodeView(node: node, context: Harness.context(rightToLeft: false), placement: .natural)
                .environment(\.nodeMotionClockMs, motionAt).environment(\.appearClockMs, appearAt).padding(20).background(Color.white)
            let image = ProgressPixels.render(view)
            return 1 - ProgressPixels.color(image, x: image.width / 2, y: image.height / 2).green
        }
        // At half of the cycle the breath is at its dimmest (0.5); the appearance is over.
        XCTAssertEqual(opacity(motionAt: 2000, appearAt: 100_000), 0.5, accuracy: 0.02)
        // The appearance at its quarter (0.5776) multiplies the breath at rest (1).
        XCTAssertEqual(opacity(motionAt: 0, appearAt: 100), 0.5776, accuracy: 0.02)
        XCTAssertEqual(opacity(motionAt: 2000, appearAt: 100), 0.5776 * 0.5, accuracy: 0.02)
    }

    func testMoments() {
        let rows = Contract.rows(Self.table, "momentCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let moment = NodeAppear.Moment(rawValue: row["moment"]?.stringValue ?? "")
            XCTAssertNotNil(moment, Self.name(row))
            XCTAssertEqual(NodeAppear.plays(on: moment!), row["plays"]?.boolValue, Self.name(row))
        }
    }

    // MARK: Documents

    /// The value of `motion` or `appear` on a node: what the reader draws and what it leaves standing; the
    /// root screen never moves and never appears.
    func testDocuments() throws {
        let rows = Contract.rows(Self.table, "documentCases")
        XCTAssertEqual(rows.count, 34)
        for row in rows {
            let isAppear = row["field"]?.stringValue == "appear"
            let valid = row["valid"]?.boolValue == true
            let onRoot = row["onRoot"]?.boolValue == true
            let read: Bool = isAppear ? NodeAppear.read(row["value"]) != nil : NodeMotion.read(row["value"]) != nil
            // What the reader draws: a node (not the root) with a field the reader reads.
            let node = try Harness.node(Harness.box("n", width: 10, height: 10, color: "#ff0000", fields: [(row["field"]?.stringValue ?? "", row["value"] ?? .null)]))
            let root = try Self.root(field: row["field"]?.stringValue ?? "", value: row["value"] ?? .null)
            if onRoot {
                XCTAssertFalse(NodeAppear.reads(root, isScreenZone: false) && isAppear, Self.name(row))
                XCTAssertTrue(root.widget == .screen, Self.name(row))
            } else {
                XCTAssertEqual(read, valid, Self.name(row))
                XCTAssertEqual(isAppear ? NodeAppear.reads(node, isScreenZone: false) && read : read, valid, Self.name(row))
            }
        }
    }

    private static func root(field: String, value: JSONValue) throws -> DocumentNode {
        var root: JSONObject = ["id": "r", "type": "Screen", "props": [:], "children": []]
        root[field] = value
        let document = try HotlayoutDocument.load([
            "schemaVersion": .string(HotlayoutVersions.schema), "documentId": "d", "name": "n", "initialScreenId": "a",
            "screens": [["screenId": "a", "name": "A", "root": .object(root)]],
        ])
        return try XCTUnwrap(document.screens.first?.root)
    }
}
