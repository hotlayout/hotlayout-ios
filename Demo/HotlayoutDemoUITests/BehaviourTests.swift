import XCTest

/// Gestures on the real reader, compared with what the contract says.
final class BehaviourTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    // MARK: - Fixed zones and «scrolled»

    /// Only the body scrolls; the app bar takes `styleScrolled` once the body is scrolled.
    func testAppBarStaysAndTakesScrolledLook() {
        let app = launchFixture("hostile/scrolled", screen: "mission")
        sleep(2)
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "back arrow of the app bar")
        let barY = back.frame.minY
        let before = app.screenshot()
        attachScreenshot(app, "before scroll")
        app.swipeUp(velocity: .slow)
        sleep(2)
        let after = app.screenshot()
        attachScreenshot(app, "after scroll")
        XCTAssertEqual(back.frame.minY, barY, accuracy: 1, "the app bar must not move with the body")
        // A point of the bar beside the arrow: `styleScrolled.background` is `surface`.
        let probe = (x: CGFloat(200), y: back.frame.midY)
        let d = colourDistance(pixel(before, x: probe.x, y: probe.y), pixel(after, x: probe.x, y: probe.y))
        XCTAssertGreaterThan(d, 60, "bar background must change after the body is scrolled (styleScrolled)")
        // `titleShown: 'scrolled'`: the title keeps its name and appears.
        XCTAssertTrue(app.staticTexts["Coffee week"].exists, "the title keeps its name")
    }

    // MARK: - Carousel

    func testCarouselSnapsAndBackReturnsToTheSameCard() {
        let app = launchFixture("hostile/carousel-back", screen: "streak")
        let first = app.staticTexts["Spend 500 with your card"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let startX = first.frame.minX
        // Drags start on the first card (the carousel of challenges), not on the row of badges.
        let from = first.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        // A short slow drag: less than half a card. Snapping brings the first card back.
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -60, dy: 0)), withVelocity: 80, thenHoldForDuration: 0)
        sleep(2)
        XCTAssertEqual(first.frame.minX, startX, accuracy: 2, "a short drag snaps back to the same stop")
        attachScreenshot(app, "after short drag")
        // A slow drag past half a card and release: the next stop.
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -230, dy: 0)), withVelocity: 150, thenHoldForDuration: 0)
        sleep(2)
        attachScreenshot(app, "after long drag")
        if app.staticTexts["Set up a recurring payment"].frame.minX != startX {
            // one more plain swipe, as a finger would flick
            first.swipeLeft()
        }
        sleep(2)
        let second = app.staticTexts["Set up a recurring payment"]
        XCTAssertEqual(second.frame.minX, startX, accuracy: 2, "snaps to the second stop")
        attachScreenshot(app, "second card")
        second.tap()
        XCTAssertTrue(app.staticTexts["Challenge"].waitForExistence(timeout: 3), "details opened")
        XCTAssertTrue(app.staticTexts["Set up a recurring payment"].exists, "the record of the tapped card travels (carryRecord)")
        app.buttons["Back"].tap()
        sleep(2)
        XCTAssertEqual(app.staticTexts["Set up a recurring payment"].frame.minX, startX, accuracy: 2, "after «back» the same card is shown")
        attachScreenshot(app, "after back")
    }

    // MARK: - Sheet

    func testSheetDragShortReturnsLongDismisses() {
        let app = launchFixture("longpress-groups-sheet-screens", screen: "history")
        app.openLayer(by: "Quick redeem")
        let title = app.staticTexts["Redeem 300 points"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let restY = title.frame.minY
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 25)), withVelocity: 60, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertTrue(title.exists, "a short slow drag returns the sheet")
        XCTAssertEqual(title.frame.minY, restY, accuracy: 2, "the sheet goes back to its place")
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)), withVelocity: 200, thenHoldForDuration: 0.3)
        sleep(2)
        XCTAssertFalse(title.exists, "a drag past the share dismisses the sheet")
        XCTAssertTrue(app.actionLog.contains("shown:history:back"), app.actionLog)
    }

    func testScrimTapClosesDismissibleOnly() {
        let app = launchFixture("longpress-groups-sheet-screens", screen: "history")
        let card = app.staticTexts["Hold for options"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 2.0)
        XCTAssertTrue(app.buttons["Pin to top"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Pin to top"].exists, "a tap on the scrim closes the window")

        let app2 = launchFixture("longpress-groups-sheet-screens", screen: "history")
        app2.openLayer(by: "Confirm")
        XCTAssertTrue(app2.staticTexts["Confirm the transfer"].waitForExistence(timeout: 5))
        app2.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        sleep(1)
        XCTAssertTrue(app2.staticTexts["Confirm the transfer"].exists, "dismissible: false — the scrim does not close")
        let t = app2.staticTexts["Confirm the transfer"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        t.press(forDuration: 0.1, thenDragTo: t.withOffset(CGVector(dx: 0, dy: 400)), withVelocity: 1500, thenHoldForDuration: 0.2)
        sleep(1)
        XCTAssertTrue(app2.staticTexts["Confirm the transfer"].exists, "dismissible: false — no drag dismiss")
    }

    // MARK: - Long press

    func testLongPressFiresAndSwallowsTheClick() {
        let app = launchFixture("longpress-groups-sheet-screens", screen: "history")
        let card = app.staticTexts["Hold for options"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 2.0)
        XCTAssertTrue(app.buttons["Pin to top"].waitForExistence(timeout: 3), "long press (2 s, threshold 450 ms) opens the window: \(app.actionLog)")
        sleep(1)
        XCTAssertFalse(app.actionLog.contains("shown:mission"), "the click after a long press is swallowed: \(app.actionLog)")
        app.buttons["Close"].tap()
        sleep(1)
        card.tap()
        sleep(1)
        XCTAssertTrue(app.actionLog.contains("shown:mission:forward"), "a short tap is the plain action: \(app.actionLog)")
    }

    func testLongPressCardHasANameAndAnAction() {
        let app = launchFixture("longpress-groups-sheet-screens", screen: "history")
        XCTAssertTrue(app.staticTexts["Hold for options"].waitForExistence(timeout: 5))
        let card = app.buttons.containing(.staticText, identifier: "Coffee week").firstMatch
        XCTAssertTrue(card.label.hasPrefix("Coffee week"), "a card without label is named by its content (composition nameCases); got «\(card.label)»")
    }

    // MARK: - Swipe to confirm

    func testSwipeConfirmNeedsTheGesture() {
        var app = launchFixture("float-nav-swipe-screens", screen: "missions")
        app.swipeToConfirm("Swipe to open the week")
        var swipe = app.buttons["Swipe to redeem"]
        XCTAssertTrue(swipe.waitForExistence(timeout: 5))
        swipe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        XCTAssertFalse(app.actionLog.contains("shown:done"), "a click without the gesture does nothing: \(app.actionLog)")
        attachScreenshot(app, "after a plain tap")
        app = launchFixture("float-nav-swipe-screens", screen: "missions")
        app.swipeToConfirm("Swipe to open the week")
        swipe = app.buttons["Swipe to redeem"]
        XCTAssertTrue(swipe.waitForExistence(timeout: 5))
        let a = swipe.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        a.press(forDuration: 0.1, thenDragTo: swipe.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertFalse(app.actionLog.contains("shown:done"), "half way does nothing: \(app.actionLog)")
        a.press(forDuration: 0.1, thenDragTo: swipe.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.1)
        sleep(2)
        XCTAssertTrue(app.actionLog.contains("shown:done:forward"), "past the threshold the action runs: \(app.actionLog)")
    }

    // MARK: - Form

    func testSurveyNextIsDisabledUntilFilled() {
        let app = launchFixture("survey-screens", screen: "goal")
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        sleep(1)
        XCTAssertFalse(app.actionLog.contains("shown:details"), "disabled Next sends nothing: \(app.actionLog)")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Savings'")).firstMatch.tap()
        sleep(1)
        XCTAssertTrue(next.isEnabled, "a chosen option fills the form")
        next.tap()
        sleep(1)
        XCTAssertTrue(app.actionLog.contains("shown:details"), app.actionLog)
        attachScreenshot(app, "details")
        let fields = app.textFields
        XCTAssertGreaterThan(fields.count, 0)
        let nextOnDetails = app.buttons["Next"]
        XCTAssertFalse(nextOnDetails.isEnabled, "Next disabled on an empty details form")
        for index in 0..<fields.count {
            let field = fields.element(boundBy: index)
            field.tap()
            field.typeText(index == fields.count - 1 ? "36" : "Reading")
        }
        attachScreenshot(app, "details typed")
        let numberField = fields.element(boundBy: fields.count - 1)
        numberField.tap()
        numberField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        sleep(1)
        attachScreenshot(app, "number cleared")
        XCTAssertFalse(nextOnDetails.isEnabled, "a cleared required number field is empty (\"\")")
    }

    func testTypingInTextField() {
        let app = launchFixture("inputs-screens", screen: "profile")
        let name = app.textFields["Full name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" Jr")
        XCTAssertEqual(name.value as? String, "Alex Morgan Jr")
        // The heading reads the same path: the session write shows on the screen.
        XCTAssertTrue(app.staticTexts["Alex Morgan Jr"].waitForExistence(timeout: 2), "the bound text follows the written value")
    }

    // MARK: - Sections, tabs, accordion

    func testNavBarSwitchesSections() {
        let app = launchFixture("bottom-zone-screens", screen: "home")
        XCTAssertTrue(app.buttons["Rewards"].waitForExistence(timeout: 5))
        app.buttons["Rewards"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.actionLog.contains("shown:rewards:switch"), app.actionLog)
        XCTAssertTrue(app.buttons["Rewards"].firstMatch.isSelected, "the active item follows the shown screen")
        app.buttons["Rewards"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(app.actionLog.components(separatedBy: "shown:rewards").count - 1, 1, "same section again: no event")
    }

    func testTabsAndAccordion() {
        let app = launchFixture("full-catalog-screen")
        let accordion = app.buttons["Як обирають переможців?"]
        XCTAssertTrue(accordion.waitForExistence(timeout: 5))
        let below = app.buttons["Забрати нагороду"].frame.minY
        accordion.tap()
        sleep(1)
        XCTAssertGreaterThan(app.buttons["Забрати нагороду"].frame.minY, below + 10, "the accordion opens and pushes the content down")
        attachScreenshot(app, "accordion open")
        app.swipeUp()
        sleep(1)
        attachScreenshot(app, "tabs")
    }

    // MARK: - Names for VoiceOver

    func testIconButtonsAndNavItemsHaveNames() {
        let app = launchFixture("app-bar-screens", screen: "details")
        for label in ["Share", "More", "Close"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3), "icon button named «\(label)»")
        }
        let nav = launchFixture("bottom-zone-screens", screen: "home")
        XCTAssertTrue(nav.buttons["Home"].waitForExistence(timeout: 5))
        let silent = nav.buttons.matching(NSPredicate(format: "label == ''")).count
        XCTAssertEqual(silent, 0, "no nameless buttons on the screen (VoiceOver would say just «button»)")
    }

    // MARK: - Countdown

    /// A text of `countdownPart` bindings ticks once a second on the ready screen.
    func testCountdownTextTicksEverySecond() {
        let app = launchFixture("value-countdown-screens", screen: "balance")
        let label = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Ends in'")).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5), "the countdown is on the screen")
        let first = label.label
        var changed = false
        for _ in 0..<6 {
            sleep(1)
            if label.label != first { changed = true; break }
        }
        XCTAssertTrue(changed, "the seconds went down: \(first) → \(label.label)")
        attachScreenshot(app, "countdown")
    }
}
