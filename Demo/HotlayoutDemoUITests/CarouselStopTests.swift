import XCTest

/// A carousel with `stopPath` (contract 9.32.0): each swipe of a person lands on a stop, writes it,
/// and the carousel stays there. The reader never follows the value it wrote itself.
final class CarouselStopTests: XCTestCase {
    private let cards = ["Debit card", "Credit card", "New card"]
    private let details = ["₴12 400.50", "₴48 000.00 limit", "No balance yet"]

    func testEverySwipeStaysOnItsStop() {
        let app = launchFixture("carousel-stop-screens", locale: "en")
        let card = { (index: Int) in app.staticTexts[self.cards[index]] }
        XCTAssertTrue(card(0).waitForExistence(timeout: 10))
        sleep(1)
        // The card whose title stands first on the screen (a peeking earlier card is off its start).
        let leading = { () -> Int? in
            (0..<3).filter { card($0).exists && card($0).frame.minX >= 0 }.min { card($0).frame.minX < card($1).frame.minX }
        }
        let shownDetail = { () -> Int? in (0..<3).first { app.staticTexts[self.details[$0]].exists } }
        let start = leading()!
        XCTAssertEqual(shownDetail(), start, "the content under the carousel reads the stop")
        attachScreenshot(app, "01 start")

        func swipe(forward: Bool, _ name: String) -> Int {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.8 : 0.2, dy: 0))
                .withOffset(CGVector(dx: 0, dy: card(0).frame.midY))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: forward ? -160 : 160, dy: 0)), withVelocity: 900, thenHoldForDuration: 0)
            sleep(2)
            let now = leading()!
            attachScreenshot(app, name)
            return now
        }

        var expected = start
        let moves: [(Bool, String)] = [(true, "02 forward"), (true, "03 forward again"), (false, "04 back"), (false, "05 back again")]
        for (forward, name) in moves {
            let next = min(2, max(0, expected + (forward ? 1 : -1)))
            let landed = swipe(forward: forward, name)
            XCTAssertEqual(landed, next, "\(name): the carousel stays on the stop the swipe reached")
            XCTAssertEqual(shownDetail(), next, "\(name): the content under it reads that stop")
            expected = next
        }
    }
}
