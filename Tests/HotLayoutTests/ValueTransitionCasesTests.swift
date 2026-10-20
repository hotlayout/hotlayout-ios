import XCTest

@testable import HotLayout

/// The shared value-transition table (`fixtures/value-transition/value-transition-cases.json`):
/// the curve, the step, the digits, the decisions and the targets of a changing value and of
/// an appearing one, each against the functions the engine runs on; then the engine itself on
/// a clock the test holds.
final class ValueTransitionCasesTests: XCTestCase {
    private static var table: JSONValue = { try! Contract.json("fixtures/value-transition/value-transition-cases.json") }()

    private func rows(_ group: String, expecting count: Int) -> [JSONObject] {
        let list = Contract.rows(Self.table, group)
        XCTAssertEqual(list.count, count, "\(group): the table has \(list.count) rows")
        return list
    }

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testDuration() {
        XCTAssertEqual(Self.table["durationMs"]?.numberValue, ValueTransition.durationMs)
    }

    func testCurve() {
        for row in rows("curveCases", expecting: 7) {
            XCTAssertEqual(ValueTransition.ease(row["p"]?.numberValue ?? 0), row["e"]?.numberValue ?? -1, accuracy: 1e-9, name(row))
        }
    }

    func testSteps() {
        for row in rows("stepCases", expecting: 16) {
            let actual = ValueTransition.value(from: row["from"]?.numberValue ?? 0, to: row["to"]?.numberValue ?? 0, t: row["t"]?.numberValue ?? 0, digits: row["digits"]?.numberValue.map(Int.init))
            XCTAssertEqual(actual, row["expected"]?.numberValue ?? -1, accuracy: 1e-9, name(row))
        }
    }

    func testDigits() {
        for row in rows("digitsCases", expecting: 7) {
            let digits = ValueTransition.digits(from: row["from"]?.numberValue ?? 0, to: row["to"]?.numberValue ?? 0, format: row["format"]?.stringValue, currency: row["currency"]?.stringValue)
            XCTAssertEqual(digits, Int(row["expected"]?.numberValue ?? -1), name(row))
        }
    }

    func testDecisions() {
        for row in rows("decisionCases", expecting: 12) {
            let input = row["change"]
            let change = ValueTransition.Change(
                animates: input?["animates"]?.boolValue ?? false, shownBefore: input?["shownBefore"]?.boolValue ?? false,
                from: input?["from"], to: input?["to"],
                localeChanged: input?["localeChanged"]?.boolValue ?? false, reducedMotion: input?["reducedMotion"]?.boolValue ?? false
            )
            switch (ValueTransition.decision(change), row["expected"]) {
            case (.leads, .bool(true)?): break
            case (.atOnce(let reason), .string(let word)?): XCTAssertEqual(reason.rawValue, word, name(row))
            default: XCTFail("\(name(row)): decision \(ValueTransition.decision(change)) against \(String(describing: row["expected"]))")
            }
        }
    }

    private func targets(_ expected: JSONValue?) -> [ValueTransition.Target] {
        (expected?.arrayValue ?? []).map {
            ValueTransition.Target(path: $0["path"]?.stringValue ?? "", scale: $0["scale"]?.boolValue ?? false, format: $0["format"]?.stringValue, currency: $0["currency"]?.stringValue)
        }
    }

    func testTargets() {
        for row in rows("targetCases", expecting: 7) {
            XCTAssertEqual(ValueTransition.targets(row["props"]?.objectValue ?? JSONObject()), targets(row["expected"]), name(row))
        }
    }

    func testAppearSteps() {
        for row in rows("appearStepCases", expecting: 9) {
            let actual = ValueTransition.value(from: ValueTransition.appearFrom, to: row["to"]?.numberValue ?? 0, t: row["t"]?.numberValue ?? 0, digits: row["digits"]?.numberValue.map(Int.init))
            XCTAssertEqual(actual, row["expected"]?.numberValue ?? -1, accuracy: 1e-9, name(row))
        }
    }

    func testAppearDecisions() {
        for row in rows("appearDecisionCases", expecting: 8) {
            let input = row["input"]
            let decision = ValueTransition.appearDecision(animates: input?["animates"]?.boolValue ?? false, to: input?["to"], reducedMotion: input?["reducedMotion"]?.boolValue ?? false)
            switch (decision, row["expected"]) {
            case (.grows, .bool(true)?): break
            case (.atOnce(let reason), .string(let word)?): XCTAssertEqual(reason.rawValue, word, name(row))
            default: XCTFail("\(name(row)): \(decision)")
            }
        }
    }

    func testAppearTargets() {
        for row in rows("appearTargetCases", expecting: 4) {
            XCTAssertEqual(ValueTransition.appearTargets(row["props"]?.objectValue ?? JSONObject()), targets(row["expected"]), name(row))
        }
    }

    func testAppearFlow() {
        for row in rows("appearFlowCases", expecting: 9) {
            guard let moment = ValueTransition.Moment(rawValue: row["moment"]?.stringValue ?? "") else { XCTFail("moment not read: \(name(row))"); continue }
            XCTAssertEqual(ValueTransition.appear(on: moment).rawValue, row["expected"]?.stringValue, name(row))
        }
    }

    // MARK: Engine

    private let points = ValueTransition.Target(path: "user.points", scale: true)

    func testFirstShowDoesNotTransition() {
        let engine = ValueTransitionEngine()
        engine.sync(targets: [points], read: { _ in .number(10) }, leads: true, localeKey: "en", reducedMotion: false)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.shown(["user.points": .number(10)]).smooth["user.points"], .number(10))
    }

    func testAChangeLeadsFromTheOldValueAndEndsOnTheNew() {
        let engine = ValueTransitionEngine()
        engine.sync(targets: [points], read: { _ in .number(0) }, leads: true, localeKey: "en", reducedMotion: false)
        engine.sync(targets: [points], read: { _ in .number(100) }, leads: true, localeKey: "en", reducedMotion: false)
        XCTAssertTrue(engine.isRunning)
        engine.tick(1000)
        XCTAssertEqual(engine.shown([:]).smooth["user.points"], .number(0), "the first frame is the old value")
        engine.tick(1350)
        XCTAssertEqual(engine.shown([:]).smooth["user.points"]?.numberValue ?? -1, 87.5, accuracy: 1e-9)
        XCTAssertEqual(engine.shown([:]).ends["user.points"], ValueTransitionEngine.Ends(from: 0, to: 100, shown: 87.5))
        engine.tick(1700)
        XCTAssertFalse(engine.isRunning)
        XCTAssertTrue(engine.takeFinished())
        XCTAssertEqual(engine.shown(["user.points": .number(100)]).smooth["user.points"], .number(100))
    }

    func testAnInterruptionStartsFromTheShownValueWithTheFullDuration() {
        let engine = ValueTransitionEngine()
        engine.sync(targets: [points], read: { _ in .number(0) }, leads: true, localeKey: "en", reducedMotion: false)
        engine.sync(targets: [points], read: { _ in .number(100) }, leads: true, localeKey: "en", reducedMotion: false)
        engine.tick(0)
        engine.tick(350)
        engine.sync(targets: [points], read: { _ in .number(0) }, leads: true, localeKey: "en", reducedMotion: false)
        XCTAssertEqual(engine.runs["user.points"]?.from ?? -1, 87.5, accuracy: 1e-9)
        engine.tick(400)
        engine.tick(400 + 699)
        XCTAssertTrue(engine.isRunning)
        engine.tick(400 + 700)
        XCTAssertFalse(engine.isRunning)
    }

    func testNoTransitionWithoutTheFieldWithReducedMotionOrAChangedLanguage() {
        for (leads, reduced, locale) in [(false, false, "en"), (true, true, "en"), (true, false, "uk")] {
            let engine = ValueTransitionEngine()
            engine.sync(targets: [points], read: { _ in .number(0) }, leads: true, localeKey: "en", reducedMotion: false)
            engine.sync(targets: [points], read: { _ in .number(100) }, leads: leads, localeKey: locale, reducedMotion: reduced)
            XCTAssertFalse(engine.isRunning, "leads \(leads), reduced \(reduced), locale \(locale)")
        }
    }

    func testAnAppearanceGrowsFromZeroAndAChangeWithoutTheFieldEndsIt() {
        let engine = ValueTransitionEngine()
        engine.appear(targets: [points], read: { _ in .number(80) }, reducedMotion: false)
        engine.sync(targets: [points], read: { _ in .number(80) }, leads: false, localeKey: "en", reducedMotion: false)
        engine.tick(0)
        XCTAssertEqual(engine.shown([:]).smooth["user.points"], .number(0), "the first frame is zero")
        engine.tick(175)
        XCTAssertEqual(engine.shown([:]).smooth["user.points"]?.numberValue ?? -1, 80 * 0.578125, accuracy: 1e-9)
        engine.sync(targets: [points], read: { _ in .number(60) }, leads: false, localeKey: "en", reducedMotion: false)
        XCTAssertFalse(engine.isRunning, "without animateChanges the new value is there at once")
    }

    func testALiteralValueAppearsUnderItsOwnKey() {
        let engine = ValueTransitionEngine()
        let literal = ValueTransition.Target(path: ValueTransition.literalKey, scale: true)
        engine.appear(targets: [literal], read: { $0 == ValueTransition.literalKey ? .number(87) : nil }, reducedMotion: false)
        engine.tick(10)
        engine.tick(185)
        XCTAssertEqual(engine.shown([:]).literal?.smooth ?? -1, 87 * 0.578125, accuracy: 1e-9)
        XCTAssertNil(engine.shown([:]).smooth[ValueTransition.literalKey], "a literal has no path in the data")
    }

    func testReducedMotionAndZeroDoNotAppear() {
        for (value, reduced) in [(JSONValue.number(80), true), (JSONValue.number(0), false), (JSONValue.string("80"), false)] {
            let engine = ValueTransitionEngine()
            engine.appear(targets: [points], read: { _ in value }, reducedMotion: reduced)
            XCTAssertFalse(engine.isRunning)
        }
    }
}
