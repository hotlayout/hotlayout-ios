import XCTest

/// Launches the demo on one fixture screen, as the screenshot script does.
func launchFixture(_ fixture: String, screen: String? = nil, locale: String = "en") -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = ["-fixture", fixture, "-locale", locale, "-contractSamples", "YES", "-showActions", "YES"]
    if let screen { arguments += ["-screen", screen] }
    app.launchArguments = arguments
    app.launch()
    return app
}

extension XCUIElement {
    /// The first element whose label contains `text`.
    func labelled(_ text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}

extension XCTestCase {
    func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIApplication {
    /// Opens a modal screen the way a person does: by the control that leads to it.
    func openLayer(by button: String) {
        let control = buttons[button]
        XCTAssertTrue(control.waitForExistence(timeout: 5), "no «\(button)»")
        control.tap()
        sleep(1)
    }

    /// Drags the thumb of a swipe-to-confirm button past its threshold.
    func swipeToConfirm(_ button: String) {
        let control = buttons[button]
        XCTAssertTrue(control.waitForExistence(timeout: 5), "no «\(button)»")
        let start = control.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: control.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.1)
        sleep(2)
    }

    /// The demo's log of what reached the host (`-showActions`).
    var actionLog: String { staticTexts["demo-action-log"].label }
}
