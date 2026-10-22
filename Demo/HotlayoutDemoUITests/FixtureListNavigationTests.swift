import XCTest

/// A fixture opened from the list shows the document's own bar only: the demo's navigation bar is
/// hidden, and the arrow of the document, with nowhere to go back to, closes the screen.
final class FixtureListNavigationTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func listApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixtureList", "YES", "-locale", "en"]
        app.launch()
        return app
    }

    /// The list is lazy: scrolls until the row is on screen.
    private func openRow(_ app: XCUIApplication, _ name: String) {
        let row = app.buttons[name]
        var tries = 0
        while !row.isHittable && tries < 12 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no row «\(name)»")
        row.tap()
    }

    private func atList(_ app: XCUIApplication) -> Bool { app.navigationBars["HotLayout fixtures"].waitForExistence(timeout: 5) || app.staticTexts["HotLayout fixtures"].exists }

    func testDocumentBarReplacesTheDemoBarAndItsArrowReturnsToTheList() {
        let app = listApp()
        XCTAssertTrue(app.buttons["actions-screens"].waitForExistence(timeout: 10))
        openRow(app, "reward-catalog-screens")

        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the arrow of the document's app bar")
        XCTAssertFalse(app.navigationBars["reward-catalog-screens"].exists, "no navigation bar of the demo over the fixture")
        XCTAssertEqual(app.navigationBars.count, 0, "one bar only: the document's")
        attachScreenshot(app, "fixture from the list")

        back.tap()
        XCTAssertTrue(app.buttons["actions-screens"].waitForExistence(timeout: 5) || atList(app), "back at the list")
    }

    func testEdgeSwipeStillReturnsToTheList() {
        let app = listApp()
        XCTAssertTrue(app.buttons["actions-screens"].waitForExistence(timeout: 10))
        openRow(app, "reward-catalog-screens")
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        edge.withOffset(CGVector(dx: 2, dy: 0)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(app.buttons["actions-screens"].waitForExistence(timeout: 5) || atList(app), "the edge swipe goes back")
    }
}
