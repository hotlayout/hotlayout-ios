import XCTest

/// Broken and hostile documents: the reader must not crash and must draw the rest.
final class HostileDocumentTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func open(_ name: String) -> XCUIApplication {
        let app = launchFixture("hostile/\(name)", screen: "s")
        sleep(3)
        attachScreenshot(app, name)
        XCTAssertEqual(app.state, .runningForeground, "\(name): the app is still running")
        return app
    }

    func testUnknownWidgetIsSkipped() {
        let app = open("hostile-unknown-widget")
        XCTAssertTrue(app.staticTexts["Before unknown"].exists)
        XCTAssertTrue(app.staticTexts["After unknown"].exists)
    }

    func testNodesWithoutProps() {
        let app = open("hostile-no-props")
        XCTAssertTrue(app.staticTexts["Before"].exists)
        XCTAssertTrue(app.staticTexts["After"].exists)
    }

    func testDepth40IsRefusedDepth31IsDrawn() {
        let deep = open("hostile-depth-40")
        XCTAssertFalse(deep.staticTexts["DEEP LEAF"].exists, "deeper than 32 levels: the screen is not drawn")
        let ok = open("hostile-depth-31")
        XCTAssertTrue(ok.staticTexts["LEAF AT 31"].exists, "31 levels under the root are drawn")
    }

    func testStringsInStyle() {
        let app = open("hostile-style-strings")
        XCTAssertTrue(app.staticTexts["Strings in style"].exists)
        XCTAssertTrue(app.staticTexts["After hostile style"].exists)
        XCTAssertTrue(app.staticTexts["Container with hostile style"].exists)
    }

    func testHostileAddresses() {
        let app = open("hostile-urls")
        XCTAssertTrue(app.staticTexts["After links"].exists)
        app.buttons["Decimal IP"].tap()
        app.buttons["JS URL"].tap()
        app.buttons["Good URL"].tap()
        sleep(1)
        let log = app.actionLog
        attachScreenshot(app, "after taps")
        XCTAssertTrue(log.contains("openUrl|invalid:url,openUrl|invalid:url,openUrl|standard"), "decimal IP and javascript: are invalid, https is standard: \(log)")
    }

    func testHugeText() {
        let app = open("hostile-huge-text")
        XCTAssertTrue(app.staticTexts["Huge text below"].waitForExistence(timeout: 20))
    }

    func testPrototypeKeys() {
        let app = open("hostile-proto")
        XCTAssertTrue(app.staticTexts["After proto"].exists)
        if app.buttons["Proto"].exists { app.buttons["Proto"].tap(); sleep(1) }
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot(app, "after proto tap")
    }

    func testBrokenWholeDocuments() {
        for name in ["hostile-truncated", "hostile-major-99"] {
            let app = open(name)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Could not open'")).firstMatch.exists, "\(name): a refusal, not a crash")
        }
    }
}
