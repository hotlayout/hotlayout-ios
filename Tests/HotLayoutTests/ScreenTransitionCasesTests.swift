import XCTest

@testable import HotLayout

/// Default transitions between screens (`x-screenTransition`) against
/// `screen-transition/screen-transition-cases.json`: the three curves, which motion a step of the stack
/// plays, where both screens stand at chosen moments, how the field is read, and how a screen entry
/// carries it. The views that play the plan are in `ScreenTransitionViewTests`.
final class ScreenTransitionCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/screen-transition/screen-transition-cases.json")

    private static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    private static func screen(_ value: JSONValue?) -> TransitionScreen {
        TransitionScreen(
            modal: value?["presentation"]?.stringValue == "modal", placement: value?["modalPlacement"],
            transition: ScreenTransitionWord.of(value?["transition"]))
    }

    private static func plan(_ row: JSONObject) -> ScreenTransitionPlan {
        ScreenTransition.plan(
            step: StackStep(rawValue: row["kind"]?.stringValue ?? "") ?? .start, from: row["from"].flatMap { $0.isNull ? nil : screen($0) },
            to: screen(row["to"]), areaWidth: row["areaWidth"]?.numberValue ?? 0, reducedMotion: row["reducedMotion"]?.boolValue == true,
            covered: row["covered"]?.boolValue == true, dragged: row["dragged"]?.boolValue == true)
    }

    private static func curve(_ values: JSONValue?) -> VisibilityFade.Curve? {
        let numbers = (values?.arrayValue ?? []).compactMap(\.numberValue)
        return numbers.count == 4 ? VisibilityFade.Curve(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3]) : nil
    }

    func testEveryGroupIsRun() {
        XCTAssertEqual(Contract.groups(Self.table), ["curveCases", "planCases", "frameCases", "fieldCases", "documentCases"])
    }

    /// The numbers of the artifact are the numbers of the rules.
    func testTheBlockOfTheArtifact() throws {
        let block = try XCTUnwrap(try Contract.json("screen-schema.json")["x-screenTransition"])
        XCTAssertEqual(block["field"]?.stringValue, ScreenTransition.field)
        XCTAssertEqual(block["words"], ["fade", "none"])
        XCTAssertEqual(block["page"]?["push"]?["durationMs"]?.numberValue, ScreenTransition.pageMs)
        XCTAssertEqual(block["page"]?["pop"]?["durationMs"]?.numberValue, ScreenTransition.pageMs)
        XCTAssertEqual(block["page"]?["push"]?["parallax"]?.numberValue, ScreenTransition.pageParallax)
        XCTAssertEqual(Self.curve(block["page"]?["push"]?["curve"]), ScreenTransition.decelerate)
        XCTAssertEqual(block["sheet"]?["open"]?["durationMs"]?.numberValue, ScreenTransition.sheetOpenMs)
        XCTAssertEqual(block["sheet"]?["close"]?["durationMs"]?.numberValue, ScreenTransition.sheetCloseMs)
        XCTAssertEqual(Self.curve(block["sheet"]?["close"]?["curve"]), ScreenTransition.accelerate)
        XCTAssertEqual(block["window"]?["open"]?["durationMs"]?.numberValue, ScreenTransition.windowOpenMs)
        XCTAssertEqual(block["window"]?["close"]?["durationMs"]?.numberValue, ScreenTransition.windowCloseMs)
        XCTAssertEqual(block["window"]?["open"]?["scaleFrom"]?.numberValue, ScreenTransition.windowScaleFrom)
        XCTAssertEqual(block["fade"]?["durationMs"]?.numberValue, ScreenTransition.fadeMs)
        XCTAssertEqual(Self.curve(block["fade"]?["curve"]), ScreenTransition.standardFade)
    }

    func testCurves() {
        let curves = ["page": ScreenTransition.decelerate, "sheetClose": ScreenTransition.accelerate, "fade": ScreenTransition.standardFade]
        let rows = Contract.rows(Self.table, "curveCases")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            let curve = curves[row["curve"]?.stringValue ?? ""]
            XCTAssertNotNil(curve, Self.name(row))
            XCTAssertEqual(VisibilityFade.bezier(curve!, at: row["x"]?.numberValue ?? 0), row["y"]?.numberValue ?? -1, accuracy: 0.001, Self.name(row))
        }
    }

    func testPlans() {
        let rows = Contract.rows(Self.table, "planCases")
        XCTAssertEqual(rows.count, 29)
        for row in rows {
            let plan = Self.plan(row)
            let expected = row["expect"]
            XCTAssertEqual(plan.motion.rawValue, expected?["motion"]?.stringValue, Self.name(row))
            if expected?["motion"]?.stringValue == "none" {
                XCTAssertEqual(plan.reason?.rawValue, expected?["reason"]?.stringValue, Self.name(row))
                continue
            }
            XCTAssertEqual(plan.durationMs, expected?["durationMs"]?.numberValue, Self.name(row))
            XCTAssertEqual(plan.curve, Self.curve(expected?["curve"]), Self.name(row))
            XCTAssertEqual(plan.parallax, expected?["parallax"]?.numberValue, Self.name(row))
            XCTAssertEqual(plan.scaleFrom, expected?["scaleFrom"]?.numberValue, Self.name(row))
            XCTAssertEqual(plan.scrim?.rawValue, expected?["scrim"]?.stringValue, Self.name(row))
        }
    }

    func testFrames() {
        let rows = Contract.rows(Self.table, "frameCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let plan = Self.plan(row["plan"]?.objectValue ?? JSONObject())
            XCTAssertTrue(plan.moves, Self.name(row))
            for probe in row["probes"]?.arrayValue ?? [] {
                let at = probe["at"]?.numberValue ?? 0
                let frame = ScreenTransition.frame(plan, at: at)
                func check(_ side: String, _ layer: TransitionLayerFrame) {
                    guard let expected = probe[side]?.objectValue else { return }
                    let got = ["x": layer.x, "y": layer.y, "opacity": layer.opacity, "scale": layer.scale]
                    for (key, value) in expected {
                        XCTAssertEqual(got[key] ?? .nan, value.numberValue ?? .nan, accuracy: 0.001, "\(Self.name(row)) at \(at) ms, \(side).\(key)")
                    }
                }
                check("incoming", frame.incoming)
                check("outgoing", frame.outgoing)
                if let scrim = probe["scrim"]?.numberValue {
                    XCTAssertEqual(frame.scrim, scrim, accuracy: 0.001, "\(Self.name(row)) at \(at) ms, scrim")
                }
            }
        }
    }

    func testFields() {
        let rows = Contract.rows(Self.table, "fieldCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            XCTAssertEqual(ScreenTransitionWord.of(row["value"])?.rawValue, row["reads"]?.stringValue, Self.name(row))
        }
    }

    /// The field on a screen entry: read when it is a word of the list, otherwise no field.
    func testScreenEntriesCarryTheField() throws {
        let rows = Contract.rows(Self.table, "documentCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            var entry = row["screen"]?.objectValue ?? JSONObject()
            entry["screenId"] = "s"
            entry["name"] = "S"
            entry["root"] = ["id": "root", "type": "Screen", "props": [:], "children": []]
            let document = try HotlayoutDocument.load([
                "schemaVersion": .string(HotlayoutVersions.schema), "documentId": "d", "name": "n", "initialScreenId": "s", "screens": [.object(entry)],
            ])
            let valid = row["schema"]?.boolValue == true
            XCTAssertEqual(document.screens.first?.transition, valid ? ScreenTransitionWord.of(entry["transition"]) : nil, Self.name(row))
        }
    }

    func testTheFramePastTheDurationIsTheFinalState() {
        let plan = ScreenTransition.plan(step: .push, from: TransitionScreen(), to: TransitionScreen(), areaWidth: 393)
        let end = ScreenTransition.frame(plan, at: 5000)
        XCTAssertEqual(end.incoming.x, 0)
        XCTAssertEqual(end.outgoing.x, -0.3, accuracy: 1e-9)
    }
}
