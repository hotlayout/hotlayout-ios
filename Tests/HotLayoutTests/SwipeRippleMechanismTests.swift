#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// The fill of a swipe button on the real screen: the thumb is let go as a finger would (`SwipeProbe`),
/// the circle grows over the screen first, the action runs under it, the fill fades away over what the
/// action put on the screen. The shared frame is `swipe-motion-screens`; its button `pay-swipe` goes to
/// the screen `paid` with `confirmTransition: 'ripple'`.
@MainActor
final class SwipeRippleMechanismTests: XCTestCase {
    final class Log { var lines: [String] = [] }

    private func fixtureDocument() throws -> HotlayoutDocument {
        try HotlayoutDocument.load(try Contract.json("fixtures/swipe-motion-screens.json"))
    }

    private struct Probed<Screen: View>: View {
        let probe: SwipeProbe
        let screen: Screen
        var body: some View { screen.environment(\.swipeProbe, probe) }
    }

    /// The screen of the frame in a window, with a probe to let go of its swipe buttons.
    private func show(_ log: Log, covered: ((Bool) -> Void)? = nil, allowNavigation: Bool = true) throws -> (NSView, SwipeProbe) {
        let probe = SwipeProbe()
        let screen = HotlayoutScreen(
            document: try fixtureDocument(), locale: "en",
            onNavigate: { event in
                log.lines.append("navigate \(event.from)>\(event.to)")
                return allowNavigation
            },
            onScreenChange: { log.lines.append("shown \($0.screenId)") },
            onScreenCovered: covered)
        let view = host(Probed(probe: probe, screen: screen))
        log.lines = []
        return (view, probe)
    }

    /// Lets the screen run until the log reads `lines`, at most `limit` seconds: the steps are timed by the clock.
    private func spin(until log: Log, equals lines: [String], limit: Double = 3) {
        let end = Date().addingTimeInterval(limit)
        while log.lines != lines, Date() < end { spin(0.05) }
    }

    private func shows(_ view: NSView, _ value: String) -> Bool {
        elements(view).contains { text($0, "accessibilityLabel") == value || text($0, "accessibilityValue") == value }
    }

    func testTheActionWaitsForTheFillAndThenTheScreenChanges() throws {
        try skipUnderReducedMotion()
        let log = Log()
        let (view, probe) = try show(log)
        probe.release("pay-swipe", .swipe)
        spin(0.5)
        XCTAssertEqual(log.lines, [], "the thumb has glided and the button collapses: the action has not run")
        spin(0.7)
        XCTAssertEqual(log.lines, [], "the circle grows over the screen: the action still waits")
        XCTAssertTrue(shows(view, "Slide to pay"), "the first screen is still there under the fill")
        spin(0.7)
        XCTAssertEqual(log.lines, ["navigate pay>paid", "shown paid"], "the screen is covered: the action ran, once")
        XCTAssertTrue(shows(view, "Payment sent"))
        spin(0.5)
        XCTAssertEqual(log.lines, ["navigate pay>paid", "shown paid"], "nothing runs again when the fill is gone")
    }

    func testTheKeyboardAndAssistiveTechnologyActAtOnce() throws {
        let log = Log()
        let (view, probe) = try show(log)
        probe.release("pay-swipe", .keyboard)
        spin(0.3)
        XCTAssertEqual(log.lines, ["navigate pay>paid", "shown paid"], "no circle and no fill: the action runs at once")
        XCTAssertTrue(shows(view, "Payment sent"))
    }

    func testAButtonThatLeavesBeforeTheCoverTakesTheFillWithIt() throws {
        try skipUnderReducedMotion()
        let log = Log()
        let (view, probe) = try show(log)
        probe.release("pay-swipe", .swipe)
        spin(1.1)
        XCTAssertEqual(log.lines, [])
        // The host puts another document on the screen: the button is gone before the screen is covered.
        let another = try HotlayoutDocument.load(
            [
                "schemaVersion": "9.34.0", "documentId": "d", "name": "n", "initialScreenId": "a",
                "screens": [["screenId": "a", "name": "a", "root": ["id": "r", "type": "Screen", "props": [:], "children": []]]],
            ])
        (view as? NSHostingView<Probed<HotlayoutScreen>>)?.rootView = Probed(probe: SwipeProbe(), screen: HotlayoutScreen(document: another, locale: "en"))
        spin(1.5)
        XCTAssertEqual(log.lines, [], "the action never ran")
    }

    func testBusyIsTheCircleAndTheHostsAnswerExpandsItBack() throws {
        let log = Log()
        var release: CheckedContinuation<Void, Never>?
        let probe = SwipeProbe()
        let screen = HotlayoutScreen(
            document: try fixtureDocument(), locale: "en",
            onAction: { action, _ async in
                log.lines.append("action \(action.type)")
                await withCheckedContinuation { release = $0 }
            })
        let view = host(Probed(probe: probe, screen: screen))
        probe.release("pay-tip", .swipe)
        spin(0.3)
        XCTAssertEqual(log.lines, ["action submit"], "the action of the host runs at once")
        spin(1.0)
        // Busy: the circle stands, and a press does nothing.
        let tip = try XCTUnwrap(find(view, label: "Slide to add a tip"))
        _ = press(tip)
        spin(0.2)
        XCTAssertEqual(log.lines, ["action submit"])
        release?.resume()
        // The circle expands back (600 ms), then the thumb returns (250 ms): the button acts again.
        spin(1.2)
        probe.release("pay-tip", .swipe)
        spin(0.3)
        XCTAssertEqual(log.lines, ["action submit", "action submit"], "at rest again")
        release?.resume()
        spin(0.1)
    }

    func testAHostThatKeepsItsStackHearsTheCoverAndTheFillLiesOverTheWindow() throws {
        try skipUnderReducedMotion()
        let log = Log()
        let (view, probe) = try show(log, covered: { log.lines.append("covered \($0)") }, allowNavigation: false)
        let content = try XCTUnwrap(view.window?.contentView)
        let chosen = SwipeRippleWindow.appKitContent
        SwipeRippleWindow.appKitContent = { content }
        defer { SwipeRippleWindow.appKitContent = chosen }
        let before = content.subviews.count
        probe.release("pay-swipe", .swipe)
        spin(0.5)
        XCTAssertEqual(log.lines, [], "the thumb glides and the button collapses: no fill yet")
        spin(0.5)
        XCTAssertEqual(log.lines, ["covered true"], "told before the action")
        XCTAssertEqual(content.subviews.count, before + 1, "the fill lies in a layer over the window")
        spin(until: log, equals: ["covered true", "navigate pay>paid"])
        XCTAssertEqual(log.lines, ["covered true", "navigate pay>paid"], "the action reaches the host once the screen is covered")
        spin(until: log, equals: ["covered true", "navigate pay>paid", "covered false"])
        XCTAssertEqual(log.lines, ["covered true", "navigate pay>paid", "covered false"], "told again when the last fill is gone")
        XCTAssertEqual(content.subviews.count, before, "the layer is taken away")
    }
}

/// The store of the fills with no screen: the order of the report and the action, the cancel, the window.
@MainActor
final class SwipeRippleStoreTests: XCTestCase {
    private func spec(_ log: @escaping (String) -> Void) -> SwipeRippleSpec {
        SwipeRippleSpec(
            center: CGPoint(x: 100, y: 100), halo: 40, core: 36, color: .red, indicatorColor: .white, indicatorSize: 16, onCovered: { log("acted") })
    }

    private func waitFor(limit: Double = 3, _ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(limit)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testTheReportComesBeforeTheActionAndTheLastFillEndsIt() {
        var log: [String] = []
        let store = SwipeRippleStore()
        XCTAssertFalse(store.covers)
        _ = store.start(spec { log.append($0) }, report: { log.append("covered \($0)") })
        XCTAssertTrue(store.covers)
        XCTAssertEqual(log, ["covered true"])
        // Waits for the event in small steps rather than a fixed delay: a slow machine that overslept a fixed
        // 0.9 s would land after the fill had already ended.
        let start = Date()
        waitFor { log.count >= 2 }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.75, "the action runs when the circle has grown for 800 ms")
        XCTAssertEqual(log, ["covered true", "acted"])
        XCTAssertTrue(store.covers, "the fill is still there, fading over the next screen")
        waitFor { log.count >= 3 }
        XCTAssertEqual(log, ["covered true", "acted", "covered false"])
        XCTAssertFalse(store.covers)
    }

    func testAFillCancelledBeforeTheCoverRunsNothing() {
        var log: [String] = []
        let store = SwipeRippleStore()
        let handle = store.start(spec { log.append($0) }, report: { log.append("covered \($0)") })
        spin(0.1)
        handle?.cancel()
        XCTAssertFalse(store.covers)
        spin(0.9)
        XCTAssertEqual(log, ["covered true", "covered false"], "no action")
    }

    func testAFillThatHasActedGoesOnToItsEnd() {
        var log: [String] = []
        let store = SwipeRippleStore()
        let handle = store.start(spec { log.append($0) }, report: { log.append("covered \($0)") })
        // Cancels right after the action rather than after a fixed delay: a slow machine that overslept a fixed
        // 0.9 s would cancel a fill that had already ended.
        waitFor { log.contains("acted") }
        handle?.cancel()
        XCTAssertTrue(store.covers, "the button left with its screen, the fill did not")
        // The report of the end comes on the next turn of the main queue, after the fill is gone.
        waitFor { log.count >= 3 }
        XCTAssertFalse(store.covers)
        XCTAssertEqual(log, ["covered true", "acted", "covered false"])
    }

    func testTheWindowLayerIsMountedOnceAndTakenAwayWithTheLastFill() {
        var mounts = 0
        var unmounts = 0
        let store = SwipeRippleStore(mount: { _ in
            mounts += 1
            return { unmounts += 1 }
        })
        _ = store.start(spec { _ in }, overWindow: true)
        _ = store.start(spec { _ in }, overWindow: true)
        XCTAssertEqual(mounts, 1)
        spin(1.4)
        XCTAssertEqual(unmounts, 1)
        XCTAssertFalse(store.covers)
    }

    func testWithNoWindowThereIsNoFill() {
        var ran = false
        let store = SwipeRippleStore(mount: { _ in nil })
        XCTAssertNil(store.start(SwipeRippleSpec(center: .zero, halo: 1, core: 1, color: .red, indicatorColor: .white, indicatorSize: 1, onCovered: { ran = true }), overWindow: true))
        XCTAssertFalse(store.covers)
        XCTAssertFalse(ran)
    }
}
#endif
