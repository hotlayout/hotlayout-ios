#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// The frames of the contract of these minors: each reads with nothing skipped, and the frame of the
/// screen transitions is walked through on the real screen, step by step, as the contract's frame asks
/// (Next, Next, Read the terms, Got it, Finish, Close, Back).
@MainActor
final class MinorFramesTests: XCTestCase {
    private static let frames = [
        "screen-transition-screens", "motion-turn-screens", "appear-swipe-dot-screens", "carousel-auto-advance-screens",
    ]

    func testTheFramesReadWithNothingSkipped() throws {
        for name in Self.frames {
            let document = try HotlayoutDocument.load(try Contract.json("fixtures/\(name).json"))
            XCTAssertEqual(document.reports.map(\.reason), [], name)
        }
    }

    func testTheScreensCarryTheirTransitionWords() throws {
        let document = try HotlayoutDocument.load(try Contract.json("fixtures/screen-transition-screens.json"))
        XCTAssertEqual(document.screen("news")?.transition, .fade)
        XCTAssertEqual(document.screen("skip")?.transition, ScreenTransitionWord.none)
        XCTAssertNil(document.screen("welcome")?.transition)
    }

    func testTheFrameOfTheTransitionsIsWalkedThrough() throws {
        let document = try HotlayoutDocument.load(try Contract.json("fixtures/screen-transition-screens.json"))
        var reports: [HotlayoutReport] = []
        var shown: [String] = []
        let view = host(HotlayoutScreen(document: document, locale: "en", onScreenChange: { shown.append($0.screenId) }, onReport: { reports += $0 }))
        // The motion runs for real; each step is given the time of its longest motion.
        for label in ["Next", "Next", "Read the terms", "Got it", "Finish", "Close", "Back"] {
            let element = try XCTUnwrap(find(view, label: label), "no «\(label)»; shown so far: \(shown)")
            XCTAssertTrue(press(element), label)
            spin(0.5)
        }
        XCTAssertEqual(shown, ["welcome", "interests", "alerts", "terms", "alerts", "done", "alerts", "interests"])
        XCTAssertEqual(reports.map(\.kind), [])
        XCTAssertNotNil(find(view, label: "Next"), "back on the second page of the walk")
    }
}
#endif
