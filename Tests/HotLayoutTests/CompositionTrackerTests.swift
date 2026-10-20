import XCTest

@testable import HotLayout

/// The events a native control's reports become: the same rule the shared table checks on the pure
/// functions (`compositionStart` / `compositionEnd`), fed from `markedTextRange`.
final class CompositionTrackerTests: XCTestCase {
    private func run(_ steps: [(String, Bool)], bound: String = "", maxLength: JSONValue? = nil) -> (writes: [String], shown: String) {
        var tracker = CompositionTracker()
        var state = InputRules.TextState(focused: true, touched: true)
        var writes: [String] = []
        for (text, marked) in steps {
            for event in tracker.changed(text: text, marked: marked) {
                let result = InputRules.step(state, event, bound: bound, maxLength: maxLength)
                state = result.state
                if let write = result.write { writes.append(write) }
            }
        }
        return (writes, InputRules.shownText(state, bound: bound))
    }

    func testNothingIsWrittenWhileComposingAndTheCommitIsWrittenOnce() {
        let result = run([("k", true), ("ka", true), ("か", true), ("か", false)])
        XCTAssertEqual(result.writes, ["か"])
        XCTAssertEqual(result.shown, "か")
    }

    func testPlainTypingWritesEveryChange() {
        XCTAssertEqual(run([("A", false), ("Al", false)]).writes, ["A", "Al"])
    }

    func testTheCommittedTextIsCutToTheLimit() {
        XCTAssertEqual(run([("a", true), ("abcdef", false)], maxLength: 4).writes, ["abcd"])
    }

    func testALostFocusCommitsAnOpenComposition() {
        var tracker = CompositionTracker()
        _ = tracker.changed(text: "ni", marked: true)
        XCTAssertEqual(tracker.ended(text: "に"), [.compositionEnd("に")])
        XCTAssertEqual(tracker.ended(text: "に"), [], "a second end has nothing to commit")
    }
}
