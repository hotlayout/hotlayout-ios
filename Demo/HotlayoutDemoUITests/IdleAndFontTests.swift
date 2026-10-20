import XCTest

/// What the screen does to the automation of the host: it has to come to rest, and the font of
/// the theme has to be the one the demo registered.
final class IdleAndFontTests: XCTestCase {
    /// Glass (`backdropBlur`) was set by an animator left paused, which counted as an animation in
    /// flight: every tap waited the whole minute of the idle timeout, before and after the event.
    func testScreenWithGlassComesToRest() {
        let app = launchFixture("float-nav-swipe-screens", screen: "home")
        let text = app.staticTexts.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        let started = Date()
        text.tap()
        XCTAssertLessThan(Date().timeIntervalSince(started), 15, "the tap did not wait for an animation that never ends")
    }

    func testThemeFontIsRegisteredInTheDemo() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", "rewards-showcase-screens", "-screen", "home", "-fontReport", "YES"]
        app.launch()
        let report = app.staticTexts["demo-font-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertEqual(report.label, "body-family=Inter installed=true", "the showcase theme names Inter and the demo bundles it")
    }
}
