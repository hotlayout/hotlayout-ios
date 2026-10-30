import SwiftUI
import XCTest

@testable import HotLayout

/// While a value runs, the node takes the place of its final value and the value in between is
/// only painted there (`value-transition/value-transition-cases.json`, `layoutCases`). The rows
/// are replayed on the engine the node runs on; then the real `Text` node is drawn and measured
/// at several moments of a transition.
@MainActor
final class ValueLayoutCasesTests: XCTestCase {
    private static let table: JSONValue = { try! Contract.json("fixtures/value-transition/value-transition-cases.json") }()

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testEveryRowOfTheTable() {
        let rows = Contract.rows(Self.table, "layoutCases")
        XCTAssertEqual(rows.count, 13, "layoutCases: the table has \(rows.count) rows")
        for row in rows { replay(row) }
    }

    /// Feeds the engine the way the node does: the value before, then each change at its moment,
    /// then reads the frame at `t`.
    private func replay(_ row: JSONObject) {
        let digits = row["digits"]?.numberValue
        let from = row["from"]?.numberValue ?? 0
        let reduced = row["reducedMotion"]?.boolValue ?? false
        // A whole number steps by whole numbers; a fraction steps by the cents of a currency.
        let whole = digits == 0
        let target = ValueTransition.Target(
            path: "p", scale: digits == nil, format: digits == nil || whole ? nil : "currency", currency: digits == nil || whole ? nil : "USD")
        var value = from
        var engine = ValueTransitionEngine()
        engine.sync(targets: [target], read: { _ in .number(from) }, leads: true, localeKey: "en", reducedMotion: reduced)
        let t = row["t"]?.numberValue ?? 0
        for change in row["changes"]?.arrayValue ?? [] {
            let at = change["at"]?.numberValue ?? 0
            guard at <= t else { break }
            engine.tick(at)
            value = change["to"]?.numberValue ?? 0
            engine.sync(targets: [target], read: { _ in .number(value) }, leads: true, localeKey: "en", reducedMotion: reduced)
            engine.tick(at)
        }
        engine.tick(t)
        let expected = row["expected"]
        let shown = engine.shown(["p": .number(value)])
        let painted = (digits == nil ? shown.smooth : shown.stepped)["p"]?.numberValue ?? .nan
        XCTAssertEqual(value, expected?["layout"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)): the value the node is measured by")
        XCTAssertEqual(painted, expected?["shown"]?.numberValue ?? .nan, accuracy: 1e-9, "\(name(row)): the value painted")
        XCTAssertEqual(shown.held, expected?["held"]?.boolValue, "\(name(row)): whether the painted value lies over the final place")
    }

    // MARK: The real node

    private func node(animates: String) throws -> DocumentNode {
        try Harness.node(.object(JSONObject([
            ("id", "t"), ("type", "Text"),
            (
                "props",
                .object(JSONObject([
                    (
                        "content",
                        [
                            "kind": "template", "template": "You are ahead of {p} users of this very long program",
                            "values": ["p": ["kind": "binding", "path": "p", "fallback": "0", "format": "number"]],
                        ]
                    ),
                    ("align", "start"), ("overflow", "ellipsis"), (animates, true),
                ])),
            ),
        ])))
    }

    private func picture(_ node: DocumentNode, scope: DataScope, elapsedMs: Double?, tabular: Bool = false) -> ProgressPixels.Image {
        let context = Body.context(scope: scope)
        let view = TextRichWidget(node: node, context: context, position: nil)
            .environment(\.valueTransitionElapsedMs, elapsedMs)
            .environment(\.paintsTabularDigits, tabular)
            .frame(width: 200, alignment: .leading).padding(10).background(Color.white)
        return ProgressPixels.render(view)
    }

    func testTheHeightOfACountingTextDoesNotMoveOnAnyFrame() throws {
        let node = try node(animates: "animateIn")
        let final: DataScope = ["p": 9_999_999]
        let heights = [0.0, 175, 350, 525, 699, 700].map { picture(node, scope: final, elapsedMs: $0).height }
        let plain = try self.node(animates: "none")
        let finalHeight = picture(plain, scope: final, elapsedMs: nil).height
        let startHeight = picture(plain, scope: ["p": 0], elapsedMs: nil).height
        XCTAssertGreaterThan(finalHeight, startHeight, "the premise: the final text wraps, the number it starts from does not")
        for (index, height) in heights.enumerated() {
            XCTAssertEqual(height, finalHeight, "frame \(index): the height of the card is that of the final text")
        }
    }

    func testTheNumberInBetweenIsPaintedOverTheFinalPlaceWithEqualFigures() throws {
        let node = try node(animates: "animateIn")
        let plain = try self.node(animates: "none")
        // 175 ms of 700: 9 999 999 × 0.578125 cut to a whole number.
        let midway = picture(node, scope: ["p": 9_999_999], elapsedMs: 175)
        let drawn = picture(plain, scope: ["p": 5_781_249], elapsedMs: nil, tabular: true)
        let proportional = picture(plain, scope: ["p": 5_781_249], elapsedMs: nil, tabular: false)
        XCTAssertEqual(midway.height, picture(plain, scope: ["p": 9_999_999], elapsedMs: nil).height, "the place is that of the final text")
        XCTAssertEqual(midway.width, drawn.width)
        XCTAssertNotEqual(midway.data, proportional.data, "the figures are not the proportional ones")
    }

    func testAtTheEndTheFinalTextStandsInItsOwnPlace() throws {
        let node = try node(animates: "animateIn")
        let plain = try self.node(animates: "none")
        let end = picture(node, scope: ["p": 9_999_999], elapsedMs: 700)
        let final = picture(plain, scope: ["p": 9_999_999], elapsedMs: nil)
        XCTAssertEqual(end.data, final.data, "no tabular figures, no second layer once the motion ends")
    }
}
