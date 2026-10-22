import XCTest

/// A fast flick in the carousel moves one card, never two.
final class CarouselFlickTests: XCTestCase {
    func testFlickMovesOneCardAndBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-app", "obsidian", "-locale", "en"]
        app.launch()
        let card = { (title: String) in app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Quest: \(title),")).firstMatch }
        let first = card("Coffee week")
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        sleep(2)
        // Bring the carousel above the tab bar.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        top.withOffset(CGVector(dx: 0, dy: 600)).press(
            forDuration: 0.2, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 100)), withVelocity: 300, thenHoldForDuration: 0.6)
        sleep(2)
        let startX = first.frame.minX
        let flick = { (title: String, dx: CGFloat) in
            let from = card(title).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: dx, dy: 0)), withVelocity: 800, thenHoldForDuration: 0)
            sleep(2)
        }

        // A 100 pt flick forward, fast: the second card, not the third.
        flick("Coffee week", -100)
        attachScreenshot(app, "after flick forward")
        XCTAssertEqual(card("Ride & earn").frame.minX, startX, accuracy: 2, "one card on")

        // A flick back returns the first card.
        flick("Ride & earn", 100)
        attachScreenshot(app, "after flick back")
        XCTAssertEqual(card("Coffee week").frame.minX, startX, accuracy: 2, "one card back")
    }
}
