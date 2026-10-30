import SwiftUI
import XCTest

@testable import HotLayout

/// What the real `Text` node does with `animateChanges`, `animateIn` and a countdown, drawn and
/// compared with the same text drawn plainly at the number that must be shown at that moment.
@MainActor
final class TextTransitionWiringTests: XCTestCase {
    private func textNode(_ content: JSONValue, extra: [(String, JSONValue)] = []) throws -> DocumentNode {
        try Harness.node(.object(JSONObject([
            ("id", "t"), ("type", "Text"),
            ("props", .object(JSONObject([("content", content), ("align", "start"), ("overflow", "ellipsis")] + extra))),
        ])))
    }

    private func points(_ extra: [(String, JSONValue)] = []) throws -> DocumentNode {
        try textNode(["kind": "binding", "path": "p", "fallback": "0", "format": "number"], extra: extra)
    }

    private func picture(_ node: DocumentNode, scope: DataScope, now: Double = 1_791_000_000_000, elapsedMs: Double? = nil, ticked: Double? = nil, engine: ValueTransitionEngine? = nil, tabular: Bool = false) -> ProgressPixels.Image {
        var context = Body.context(scope: scope)
        context.now = now
        let view = TextRichWidget(node: node, context: context, position: nil)
            .environment(\.valueTransitionElapsedMs, elapsedMs)
            .environment(\.countdownTickedSeconds, ticked)
            .environment(\.paintsTabularDigits, tabular)
            .frame(width: 240, alignment: .leading).padding(10).background(Color.white)
        return ProgressPixels.render(view)
    }

    private func same(_ a: ProgressPixels.Image, _ b: ProgressPixels.Image) -> Bool {
        a.width == b.width && a.height == b.height && a.data == b.data
    }

    func testAnimateInCountsUpFromZeroOnTheRealNode() throws {
        let node = try points([("animateIn", true)])
        let plain = try points()
        // 175 ms of 700: e = 0.578125, 80 × e = 46.25, whole steps cut towards zero: 46.
        // The number in between is painted with figures of equal width.
        XCTAssertTrue(same(picture(node, scope: ["p": 80], elapsedMs: 0), picture(plain, scope: ["p": 0], tabular: true)), "the first frame shows zero")
        XCTAssertTrue(same(picture(node, scope: ["p": 80], elapsedMs: 175), picture(plain, scope: ["p": 46], tabular: true)), "mid-transition the node shows an intermediate number")
        XCTAssertFalse(same(picture(node, scope: ["p": 80], elapsedMs: 175), picture(plain, scope: ["p": 80])))
        XCTAssertTrue(same(picture(node, scope: ["p": 80], elapsedMs: 700), picture(plain, scope: ["p": 80])), "at the end the final number")
    }

    func testAnimateChangesLeadsFromTheOldNumberThroughTheSameFormat() throws {
        let node = try points([("animateChanges", true)])
        let plain = try points()
        var context = Body.context(scope: ["p": 5000])
        context.now = 0
        // The node has shown 1000 before, then the data changes to 5000.
        var engine = ValueTransitionEngine()
        let key = "\(context.locale.translation ?? "")|\(context.locale.formatting ?? "")"
        engine.sync(targets: ValueTransition.targets(node.props), read: { _ in .number(1000) }, leads: true, localeKey: key, reducedMotion: false)
        engine.sync(targets: ValueTransition.targets(node.props), read: { _ in .number(5000) }, leads: true, localeKey: key, reducedMotion: false)
        XCTAssertTrue(engine.isRunning)
        let view = { (elapsed: Double) -> ProgressPixels.Image in
            ProgressPixels.render(
                ValueTransitioned(node: node, context: context, engine: engine) { shown in
                    var shownContext = context
                    shownContext.scope = shown.stepped
                    return TextRichContent(node: node, context: shownContext, position: nil)
                }
                .environment(\.valueTransitionElapsedMs, elapsed).frame(width: 240, alignment: .leading).padding(10).background(Color.white))
        }
        // 350 ms: e = 0.875, 1000 + 4000 × 0.875 = 4500, shown with grouping like the final number.
        XCTAssertTrue(same(view(350), picture(plain, scope: ["p": 4500])), "an intermediate number, written by the same format")
        XCTAssertTrue(same(view(700), picture(plain, scope: ["p": 5000])))
    }

    func testWithoutTheFieldsTheNumberStandsAtOnce() throws {
        let node = try points()
        XCTAssertTrue(same(picture(node, scope: ["p": 80], elapsedMs: 175), picture(node, scope: ["p": 80])))
    }

    private let countdown: JSONValue = [
        "kind": "template", "template": "{m}:{s}",
        "values": [
            "m": ["kind": "binding", "path": "endsAt", "fallback": "0", "format": "countdownPart", "unit": "minutes", "pad": 2],
            "s": ["kind": "binding", "path": "endsAt", "fallback": "0", "format": "countdownPart", "unit": "seconds", "pad": 2],
        ],
    ]

    func testACountdownTextTicksOnTheRealNode() throws {
        let node = try textNode(countdown)
        let now = 1_791_000_000_000.0
        let scope: DataScope = ["endsAt": .string(Self.iso(now + 125_500))]
        // 125.5 s left: 02:05; a second later 02:04; three seconds later 02:02.
        let plain = try textNode(["kind": "literal", "value": "02:05"])
        XCTAssertTrue(same(picture(node, scope: scope, now: now, ticked: 0), picture(plain, scope: [:])))
        XCTAssertTrue(same(picture(node, scope: scope, now: now, ticked: 1), picture(try textNode(["kind": "literal", "value": "02:04"]), scope: [:])))
        XCTAssertTrue(same(picture(node, scope: scope, now: now, ticked: 3), picture(try textNode(["kind": "literal", "value": "02:02"]), scope: [:])))
        XCTAssertTrue(same(picture(node, scope: scope, now: now, ticked: 500), picture(try textNode(["kind": "literal", "value": "00:00"]), scope: [:])), "a past moment is zeros")
    }

    func testOnlyACountdownTextTicks() throws {
        XCTAssertTrue(CountdownRules.ticks(try textNode(countdown).props))
        XCTAssertFalse(CountdownRules.ticks(try points().props))
        XCTAssertFalse(CountdownRules.ticks(try textNode(["kind": "literal", "value": "x"]).props))
        XCTAssertTrue(CountdownRules.ticks(try textNode(["kind": "binding", "path": "e", "format": "countdownPart", "unit": "days"]).props))
    }

    private static func iso(_ milliseconds: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
}
