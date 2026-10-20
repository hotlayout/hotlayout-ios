import XCTest

@testable import HotLayout

/// «Swipe to confirm» against the shared table (`swipe-confirm/swipe-confirm-cases.json`):
/// the geometry of the track and the thumb, the progress of a drag, what a release does, every
/// way of pressing, and the busy state after the action.
final class SwipeConfirmCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/swipe-confirm/swipe-confirm-cases.json")

    static let notRun: [String: String] = [
        "schemaCases": "verdicts of the schema and the validator on the field `confirm`; the reader draws any document it can read",
    ]

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "geometryCases", "naturalWidthCases", "progressCases", "releaseCases", "thumbCases", "captureCases", "pressCases", "ruleCases",
            "busyReleaseCases", "busyEndCases", "busyRuleCases",
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
            border: value?["border"]?.numberValue ?? 0, inset: value?["inset"]?.numberValue ?? 0
        )
    }

    func testGeometry() {
        for row in rows("geometryCases", 4) {
            let geometry = SwipeConfirmRules.geometry(track(row["track"]))
            let expect = row["expect"]
            XCTAssertEqual(geometry.diameter, expect?["diameter"]?.numberValue, name(row))
            XCTAssertEqual(geometry.thumbRoom, expect?["thumbRoom"]?.numberValue, name(row))
            XCTAssertEqual(geometry.travel, expect?["travel"]?.numberValue, name(row))
            XCTAssertEqual(geometry.labelStart, expect?["label"]?["start"]?.numberValue, name(row))
            XCTAssertEqual(geometry.labelWidth, expect?["label"]?["width"]?.numberValue, name(row))
        }
    }

    func testNaturalWidth() {
        for row in rows("naturalWidthCases", 2) {
            let t = track(row["track"])
            XCTAssertEqual(SwipeConfirmRules.naturalWidth(label: row["label"]?.numberValue ?? 0, height: t.height, border: t.border, inset: t.inset), row["expect"]?.numberValue, name(row))
        }
    }

    func testProgressAndRelease() {
        for row in rows("progressCases", 7) {
            XCTAssertEqual(SwipeConfirmRules.progress(dx: row["dx"]?.numberValue ?? 0, travel: row["travel"]?.numberValue ?? 0, rightToLeft: row["rtl"]?.boolValue ?? false), row["expect"]?.numberValue, name(row))
        }
        for row in rows("releaseCases", 5) {
            XCTAssertEqual(SwipeConfirmRules.release(progress: row["progress"]?.numberValue ?? 0, disabled: row["disabled"]?.boolValue ?? false).rawValue, row["expect"]?.stringValue, name(row))
        }
    }

    func testThumbAndCapture() {
        for row in rows("thumbCases", 5) {
            XCTAssertEqual(SwipeConfirmRules.thumbStart(track(row["track"]), progress: row["progress"]?.numberValue ?? 0), row["expect"]?.numberValue ?? -1, accuracy: 1e-9, name(row))
        }
        for row in rows("captureCases", 4) {
            XCTAssertEqual(SwipeConfirmRules.captures(dx: row["dx"]?.numberValue ?? 0, dy: row["dy"]?.numberValue ?? 0), row["expect"]?.boolValue, name(row))
        }
    }

    func testWaysToPress() {
        for row in rows("pressCases", 8) {
            let way = SwipeConfirmRules.Way(rawValue: row["way"]?.stringValue ?? "")
            let press = SwipeConfirmRules.press(try! XCTUnwrap(way), disabled: row["disabled"]?.boolValue ?? false)
            XCTAssertEqual(press.rawValue, row["expect"]?.stringValue, name(row))
        }
    }

    func testRulesMirrorTheArtifact() throws {
        let block = try Contract.json("screen-schema.json")["x-swipeConfirm"]
        let busy = try Contract.json("screen-schema.json")["x-swipeConfirmBusy"]
        XCTAssertEqual(block?["threshold"]?.numberValue, SwipeConfirmRules.threshold)
        XCTAssertEqual(block?["words"]?.arrayValue?.compactMap(\.stringValue), [SwipeConfirmRules.word])
        XCTAssertEqual(block?["thumb"]?["inset"]?.stringValue, SwipeConfirmRules.insetToken)
        XCTAssertEqual(busy?["completeMs"]?.numberValue, SwipeConfirmRules.completeMs)
        XCTAssertEqual(busy?["returnMs"]?.numberValue, SwipeConfirmRules.returnMs)
        XCTAssertEqual(busy?["busy"]?["turnMs"]?.numberValue, SwipeConfirmRules.spinnerTurnMs)
        XCTAssertEqual(busy?["ends"]?["noPromiseTimeoutMs"]?.numberValue, SwipeConfirmRules.busyMaxMs)
        for row in rows("ruleCases", 10) where row["rule"]?.stringValue == "threshold" {
            XCTAssertEqual(row["expect"]?.numberValue, SwipeConfirmRules.threshold)
        }
        for row in rows("busyRuleCases", 10) {
            let expect = row["expect"]?.numberValue
            switch row["rule"]?.stringValue {
            case "ends.noPromiseTimeoutMs": XCTAssertEqual(expect, SwipeConfirmRules.busyMaxMs)
            case "completeMs": XCTAssertEqual(expect, SwipeConfirmRules.completeMs)
            case "returnMs": XCTAssertEqual(expect, SwipeConfirmRules.returnMs)
            case "busy.turnMs": XCTAssertEqual(expect, SwipeConfirmRules.spinnerTurnMs)
            default: XCTAssertNil(expect, "\(name(row)) is a statement: it is held by the view tests")
            }
        }
    }

    // MARK: The busy state

    func testAfterRelease() {
        for row in rows("busyReleaseCases", 4) {
            let runner = SwipeConfirmRules.Runner(rawValue: row["runner"]?.stringValue ?? "")
            XCTAssertEqual(SwipeConfirmRules.afterRelease(try! XCTUnwrap(runner)).rawValue, row["expect"]?.stringValue, name(row))
        }
    }

    /// Who ran a press, judged from what the flow of the screen did with it (the same outcome the
    /// screen hands to the button that waits).
    func testRunnersOfActions() {
        let cases: [(JSONObject, SwipeConfirmRules.Runner)] = [
            (["type": "navigate", "params": ["screenId": "next"]], .reader), (["type": "navigate.back"], .reader),
            (["type": "navigate.section", "params": ["screenId": "home"]], .reader), (["type": "redeem"], .host),
            (["type": "navigate", "params": ["screenId": "elsewhere"]], .host), (["type": "navigate.back"], .host),
            (["type": "none"], .none), (["type": "openUrl"], .invalid), (["type": "openUrl", "params": ["url": "https://example.com/pay"]], .host),
        ]
        var deep = Flow(document: FlowDocument(documentId: "d", screens: [
            .init(screenId: "home", presentation: .page), .init(screenId: "next", presentation: .page),
        ], initialScreenId: "home", entryPoints: [:]), entry: nil)
        _ = deep.press(["type": "navigate", "params": ["screenId": "next"]])
        for (index, (action, runner)) in cases.enumerated() {
            // The second «back» is pressed on the first screen: the host's.
            var flow = index == 5 ? Flow(document: deep.document, entry: nil) : deep
            let outcome = flow.press(action)
            XCTAssertEqual(SwipeConfirmRules.runner(type: action["type"]?.stringValue, outcome: outcome), runner, "\(index) \(action["type"]?.stringValue ?? "")")
        }
    }

    func testHowBusyEnds() {
        for row in rows("busyEndCases", 7) {
            let event = SwipeConfirmRules.BusyEvent(rawValue: row["event"]?.stringValue ?? "")
            let outcome = SwipeConfirmRules.busyOutcome(try! XCTUnwrap(event), promise: row["answer"]?.stringValue == "promise")
            XCTAssertEqual(outcome.rawValue, row["expect"]?.stringValue, name(row))
        }
    }
}
