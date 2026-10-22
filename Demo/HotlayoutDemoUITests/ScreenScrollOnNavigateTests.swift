import XCTest

/// A screen opened by `navigate` starts at its top, whatever the screen it replaced was scrolled to
/// (Obsidian: scroll the home screen, open a quest, and the quest must not come up scrolled).
final class ScreenScrollOnNavigateTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func questCard(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Quest: ")).firstMatch
    }

    func testQuestOpenedFromAScrolledHomeStartsAtItsTop() {
        let app = XCUIApplication()
        app.launchArguments = ["-app", "obsidian", "-locale", "en"]
        app.launch()
        let card = questCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no quest card")
        sleep(2)

        // Scroll the home screen until its first card sits in the upper half of the window.
        let window = app.windows.firstMatch.frame
        var tries = 0
        while card.frame.minY > window.height * 0.45 && tries < 6 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            from.withOffset(CGVector(dx: 0, dy: 500)).press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 100)), withVelocity: 300, thenHoldForDuration: 0.5)
            tries += 1
        }
        XCTAssertFalse(app.staticTexts["Points balance"].isHittable, "the home screen is scrolled")
        card.tap()

        // The quest screen: the bar title and the picture at the head of the body are in view.
        let progress = app.staticTexts["Your progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "the quest is open")
        sleep(1)
        attachScreenshot(app, "quest after a scrolled home")
        XCTAssertGreaterThan(progress.frame.minY, window.height * 0.45, "the quest starts at its top: «Your progress» is still below the hero")
    }
}
