import XCTest

@testable import HotLayout

/// The motion of «swipe to confirm» against the shared table (`swipe-motion/swipe-motion-cases.json`):
/// the fill behind the thumb, the label, the radius of the thumb, the collapse into a circle, the fill
/// over the screen, the order of the steps and the one word of the field. Curves are compared to 1e-4.
final class SwipeMotionCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/swipe-motion/swipe-motion-cases.json")
    static let schema = try! Contract.json("screen-schema.json")

    static let notRun: [String: String] = [
        "documentCases": "verdicts of the schema and the validator on the field; the reader draws any document it can read",
    ]

    private let tolerance = 1e-4

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "labelCases", "trailCases", "thumbRadiusCases", "collapseCases", "rippleScaleCases", "rippleCases", "revealCases", "sequenceCases",
            "busyReturnCases", "fieldCases", "ruleCases",
        ]
        let groups = Contract.groups(Self.table)
        XCTAssertEqual(groups.subtracting(run).subtracting(Self.notRun.keys), [], "groups that are neither run nor named")
        XCTAssertEqual(run.union(Self.notRun.keys).subtracting(groups), [], "names that are no longer groups")
    }

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    private func rows(_ group: String, _ count: Int) -> [JSONObject] {
        let list = Contract.rows(Self.table, group)
        XCTAssertEqual(list.count, count, "\(group): the table has \(list.count) rows")
        return list
    }

    private func track(_ value: JSONValue?) -> SwipeConfirmRules.Track {
        SwipeConfirmRules.Track(
            height: value?["height"]?.numberValue ?? 0, width: value?["width"]?.numberValue ?? 0,
            border: value?["border"]?.numberValue ?? 0, inset: value?["inset"]?.numberValue ?? 0)
    }

    func testLabelAndTrail() {
        for row in rows("labelCases", 6) {
            XCTAssertEqual(SwipeMotion.labelOpacity(row["progress"]?.numberValue ?? 0), row["expect"]?.numberValue ?? -1, accuracy: tolerance, name(row))
        }
        for row in rows("trailCases", 4) {
            let strip = SwipeMotion.trail(track(row["track"]), progress: row["progress"]?.numberValue ?? 0)
            XCTAssertEqual(strip.start, row["expect"]?["start"]?.numberValue ?? -1, accuracy: tolerance, name(row))
            XCTAssertEqual(strip.width, row["expect"]?["width"]?.numberValue ?? -1, accuracy: tolerance, name(row))
        }
    }

    func testThumbRadius() {
        for row in rows("thumbRadiusCases", 12) {
            let radius = SwipeMotion.thumbRadius(track(row["track"]), radius: row["radius"]?.numberValue)
            XCTAssertEqual(radius, row["expect"]?.numberValue ?? -1, accuracy: tolerance, name(row))
        }
    }

    func testCollapse() {
        for row in rows("collapseCases", 7) {
            let frame = SwipeMotion.collapse(track(row["track"]), elapsed: row["elapsed"]?.numberValue ?? 0)
            let expect = row["expect"]
            XCTAssertEqual(frame.start, expect?["start"]?.numberValue ?? -1, accuracy: tolerance, name(row))
            XCTAssertEqual(frame.width, expect?["width"]?.numberValue ?? -1, accuracy: tolerance, name(row))
            XCTAssertEqual(frame.height, expect?["height"]?.numberValue ?? -1, accuracy: tolerance, name(row))
            XCTAssertEqual(frame.ring, expect?["ring"]?.numberValue ?? -1, accuracy: tolerance, name(row))
            XCTAssertEqual(frame.surfaceOpacity, expect?["surfaceOpacity"]?.numberValue ?? -1, accuracy: tolerance, name(row))
            XCTAssertEqual(frame.haloOpacity, expect?["haloOpacity"]?.numberValue ?? -1, accuracy: tolerance, name(row))
        }
    }

    func testRippleAndReveal() {
        for row in rows("rippleScaleCases", 4) {
            let area = row["area"]
            let scale = SwipeMotion.rippleScale(
                centerX: area?["centerX"]?.numberValue ?? 0, centerY: area?["centerY"]?.numberValue ?? 0,
                screenWidth: area?["screenWidth"]?.numberValue ?? 0, screenHeight: area?["screenHeight"]?.numberValue ?? 0,
                core: area?["core"]?.numberValue ?? 0)
            XCTAssertEqual(scale, row["expect"]?.numberValue ?? -1, accuracy: 1e-4, name(row))
        }
        for row in rows("rippleCases", 5) {
            XCTAssertEqual(
                SwipeMotion.rippleAt(scale: row["scale"]?.numberValue ?? 1, elapsed: row["elapsed"]?.numberValue ?? 0), row["expect"]?.numberValue ?? -1,
                accuracy: tolerance, name(row))
        }
        for row in rows("revealCases", 4) {
            XCTAssertEqual(SwipeMotion.revealAt(row["elapsed"]?.numberValue ?? 0), row["expect"]?.numberValue ?? -1, accuracy: tolerance, name(row))
        }
    }

    func testTheOrderOfTheSteps() throws {
        for row in rows("sequenceCases", 10) {
            let input = row["input"]
            let runner = try XCTUnwrap(SwipeConfirmRules.Runner(rawValue: input?["runner"]?.stringValue ?? ""))
            let way = try XCTUnwrap(SwipeMotion.Way(rawValue: input?["way"]?.stringValue ?? ""))
            let steps = SwipeMotion.sequence(
                runner: runner, actionType: input?["actionType"]?.stringValue ?? "", ripple: input?["transition"]?.stringValue == "ripple", way: way,
                reducedMotion: input?["reducedMotion"]?.boolValue ?? false)
            XCTAssertEqual(steps.map(\.rawValue), row["expect"]?.arrayValue?.compactMap(\.stringValue), name(row))
        }
        for row in rows("busyReturnCases", 2) {
            let steps = SwipeMotion.busyReturn(reducedMotion: row["reducedMotion"]?.boolValue ?? false)
            XCTAssertEqual(steps.map(\.rawValue), row["expect"]?.arrayValue?.compactMap(\.stringValue), name(row))
        }
    }

    func testTheFieldHasOneWord() {
        for row in rows("fieldCases", 4) {
            let reads = SwipeMotion.readsRipple(row["props"]?.objectValue ?? JSONObject())
            XCTAssertEqual(reads ? "ripple" : nil, row["reads"]?.stringValue, name(row))
        }
    }

    func testTheRulesMirrorTheArtifact() throws {
        XCTAssertEqual(SwipeMotion.rules, Self.schema["x-swipeConfirmMotion"], "the block of the artifact, whole")
        let props = Self.schema["$defs"]?["ButtonProps"]?["properties"]
        XCTAssertEqual(props?[SwipeMotion.field]?["enum"]?.arrayValue?.compactMap(\.stringValue), [SwipeMotion.rippleWord])
        for row in rows("ruleCases", 12) {
            var node: JSONValue? = SwipeMotion.rules
            for key in (row["rule"]?.stringValue ?? "").split(separator: ".") { node = node?[String(key)] }
            XCTAssertEqual(node, row["expect"], name(row))
        }
        XCTAssertEqual(SwipeMotion.collapseMs, 600)
        XCTAssertEqual(SwipeMotion.rippleMs, 800)
        XCTAssertEqual(SwipeMotion.revealMs, 200)
        XCTAssertEqual(SwipeMotion.haloOpacity, 0.4)
        XCTAssertEqual(SwipeMotion.collapseCurve, VisibilityFade.Curve(x1: 0.4, y1: 0, x2: 0.2, y2: 1))
        XCTAssertEqual(SwipeMotion.rippleActionTypes, ["navigate", "navigate.back"])
    }

    // MARK: Who will run the action

    func testTheRunnerIsJudgedBeforeTheActionRuns() {
        let cases: [(String, [String: String]?, SwipeConfirmRules.Runner)] = [
            ("navigate", ["screenId": "next"], .reader), ("navigate.back", nil, .reader), ("navigate.section", ["screenId": "a"], .reader),
            ("setValue", nil, .reader), ("redeem", nil, .host), ("none", nil, .none), ("openUrl", nil, .invalid),
            ("openUrl", ["url": "https://example.com/pay"], .host),
        ]
        for (type, params, runner) in cases {
            var object: JSONObject = ["type": .string(type)]
            if let params {
                var values = JSONObject()
                for (key, value) in params { values[key] = .string(value) }
                object["params"] = .object(values)
            }
            let handed = ActionCatalog.handed(object, scope: [:])
            XCTAssertEqual(SwipeConfirmRules.intendedRunner(of: handed), runner, type)
        }
    }
}
