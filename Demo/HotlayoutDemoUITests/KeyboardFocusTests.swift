import XCTest

/// The focused field stays above the on-screen keyboard (`x-style.layout.bottomZone.keyboard` and the
/// focus rule of the inputs block): the body area ends at the top of the keyboard, or at the top of
/// the pinned block riding above it; the field is scrolled into that area together with the line
/// under it; the app bar stands where it stood.
final class KeyboardFocusTests: XCTestCase {
    /// `Screen.props.gap` of the survey («lg») and the bottom padding of the parts form («lg») in the built-in theme.
    private static let surveyGap = 16.0
    private static let partsBottomPadding = 16.0
    /// From the bottom of the accessibility frame of the single-line field to the bottom of its counter line.
    private static let counterLine = 31.7
    /// The keyboard of iOS 26 is a sheet with rounded corners: its frame starts about this far above the keys.
    private static let keyboardFrameMargin = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 16.5 : 0.0
    /// The accessibility frame of a multi-line field ends this far above the bottom of its box.
    private static let textViewInset = 13.0

    override func setUp() { continueAfterFailure = false }

    private func keyboard(_ app: XCUIApplication) -> XCUIElement {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "the software keyboard is shown")
        // The keyboard slides in; wait until its frame stops moving.
        var last = keyboard.frame
        for _ in 0..<10 {
            usleep(300_000)
            if keyboard.frame == last { break }
            last = keyboard.frame
        }
        XCTAssertLessThan(keyboard.frame.minY, app.frame.height - 100, "the software keyboard is on screen (a simulator with a hardware keyboard connected hides it)")
        return keyboard
    }

    /// Waits until the frame of `element` stops moving (the reveal scrolls it into place).
    private func settle(_ element: XCUIElement) {
        var last = element.frame
        var still = 0
        for _ in 0..<40 {
            usleep(200_000)
            if element.frame == last { still += 1; if still >= 4 { return } } else { still = 0; last = element.frame }
        }
    }

    func testBottomFieldOfLongFormRisesAboveKeyboard() {
        let app = launchFixture("parts-screens", screen: "form")
        let phone = app.textFields["Phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        attachScreenshot(app, "parts before focus")
        phone.tap()
        let keys = keyboard(app)
        settle(phone)
        attachScreenshot(app, "parts focused")
        // The counter is the line under the box: the box and 28 points under it are above the keys.
        XCTAssertLessThan(phone.frame.maxY + 28, keys.frame.minY, "the field and its counter are above the keyboard")
        // Without a pinned block the tail is the bottom padding of the root: it stays under the counter
        // line (the counter is not exposed to accessibility; its line ends `counterLine` below the field).
        XCTAssertEqual(keys.frame.minY - phone.frame.maxY, Self.partsBottomPadding + Self.counterLine + Self.keyboardFrameMargin, accuracy: 1,
                       "the bottom padding of the root stays between the counter and the keyboard")
    }

    func testPinnedButtonRidesAboveKeyboardAndBarStays() {
        let app = launchFixture("survey-screens", screen: "details")
        let bar = app.staticTexts.matching(NSPredicate(format: "label != ''")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let barTop = bar.frame.minY
        let note = app.textViews["Anything to add?"].exists ? app.textViews["Anything to add?"] : app.textFields["Anything to add?"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        attachScreenshot(app, "survey before focus")
        note.tap()
        let keys = keyboard(app)
        attachScreenshot(app, "survey focused")
        let next = app.buttons["Next"]
        XCTAssertTrue(next.exists)
        XCTAssertLessThanOrEqual(next.frame.maxY, keys.frame.minY, "the pinned block rides above the keyboard")
        XCTAssertLessThan(note.frame.maxY, next.frame.minY, "the field is in the body area above the pinned block")
        // The tail of the body stays under the field: the gap of the screen, not flush with the button.
        // (A tall screen may leave more than the gap: the block was in view with its tail and did not move.)
        XCTAssertGreaterThanOrEqual(next.frame.minY - note.frame.maxY, Self.surveyGap + Self.textViewInset - 1, "the gap of the screen stays between the field and the pinned block")
        XCTAssertEqual(bar.frame.minY, barTop, accuracy: 1, "the app bar stands")
    }

    func testFieldWithHelperAndPinnedSave() {
        let app = launchFixture("inputs-screens", screen: "profile")
        let phone = app.textFields["Phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        // The pinned «Save» appears once the terms are accepted.
        let terms = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'I agree to the terms'")).firstMatch
        XCTAssertTrue(terms.waitForExistence(timeout: 5))
        terms.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        phone.tap()
        let keys = keyboard(app)
        attachScreenshot(app, "profile focused")
        let save = app.buttons["Save"]
        XCTAssertLessThanOrEqual(save.frame.maxY, keys.frame.minY, "the pinned block rides above the keyboard")
        XCTAssertLessThan(phone.frame.maxY + 20, save.frame.minY, "the field and its helper stand above the pinned block")
    }

    func testVisibleFieldDoesNotScroll() {
        let app = launchFixture("parts-screens", screen: "form")
        let name = app.textFields["Full name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let top = name.frame.minY
        name.tap()
        _ = keyboard(app)
        XCTAssertEqual(name.frame.minY, top, accuracy: 1, "a field that is already in view stays where it is")
    }

    // MARK: Sheet and bar of navigation

    /// The accessibility frame of a single-line field is its text line: the box ends this far below it.
    private static let fieldBoxInset = 13.0
    /// `Screen.props.gap` / root padding («lg») of the fixture `keyboard-screens`.
    private static let tail = 16.0
    /// The suggestions row of the keyboard lies above the keys (the frame of the keyboard starts under it); simulators differ in showing it.
    private static let suggestionsRow = 60.0

    /// A modal sheet lifts above the keyboard as a whole: the field low in it is in view, with the tail of the sheet under it.
    func testFieldInModalSheetRisesAboveKeyboardWithTail() {
        let app = launchFixture("keyboard-screens")
        app.openLayer(by: "Open the form")
        let note = app.textFields["Sheet note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        let keys = keyboard(app)
        settle(note)
        attachScreenshot(app, "sheet focused")
        let gap = keys.frame.minY - note.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, Self.tail + Self.fieldBoxInset - 1, "the field of the sheet is above the keyboard with the tail of the sheet under it")
        XCTAssertLessThan(gap, Self.tail + Self.fieldBoxInset + Self.suggestionsRow, "the sheet is not lifted further than the keyboard")
    }

    /// A sheet as short as its content moves up above the keyboard whole: the field in it is not covered.
    func testFieldInShortModalSheetRisesAboveKeyboard() {
        let app = launchFixture("keyboard-screens")
        app.openLayer(by: "Open the short form")
        let note = app.textFields["Short note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        let keys = keyboard(app)
        settle(note)
        attachScreenshot(app, "short sheet focused")
        let gap = keys.frame.minY - note.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, Self.tail + Self.fieldBoxInset - 1, "the field of the short sheet is above the keyboard with the tail under it")
        XCTAssertLessThan(gap, Self.tail + Self.fieldBoxInset + Self.suggestionsRow, "the sheet is not lifted further than the keyboard")
    }

    /// The body area ends at the bar of navigation: the field is scrolled above it with the tail of the body under it.
    private func assertFieldAboveBar(_ screen: String) {
        let app = launchFixture("keyboard-screens", screen: screen)
        let comment = app.textFields["Comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()
        let keys = keyboard(app)
        settle(comment)
        attachScreenshot(app, "\(screen) focused")
        let home = app.buttons["Home"]
        XCTAssertTrue(home.exists)
        XCTAssertLessThan(comment.frame.maxY, keys.frame.minY, "the field is above the keyboard")
        // The bar of navigation stays under the keyboard (the keyboard covers it); only a pinned block rides above.
        // (The frame of the keyboard starts under its suggestions row, which belongs to the keyboard too.)
        XCTAssertGreaterThanOrEqual(home.frame.minY, keys.frame.minY - Self.suggestionsRow, "the bar of navigation is not lifted above the keyboard")
        print("NAVDBG home=\(home.frame) comment=\(comment.frame) keys=\(keys.frame)")
        XCTAssertEqual(home.frame.minY - comment.frame.maxY, Self.tail + Self.fieldBoxInset, accuracy: 1.5, "the tail of the body stays between the field and the bar of navigation")
    }

    func testFieldAboveNavBarRisesAboveKeyboardWithTail() { assertFieldAboveBar("nav") }

    func testFieldAboveFloatingNavBarRisesAboveKeyboardWithTail() { assertFieldAboveBar("navfloat") }

    /// The second reveal, a moment after the keyboard came, must not take the body back from a person who scrolled it away.
    func testScrollingAwayRightAfterFocusIsNotUndone() {
        let app = launchFixture("keyboard-screens", screen: "nav")
        let comment = app.textFields["Comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        comment.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        // The reveal has run; the second one is due about half a second after the keyboard.
        let before = comment.frame.minY
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        from.press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: .fast, thenHoldForDuration: 0)
        let scrolledTo = comment.frame.minY
        XCTAssertGreaterThan(scrolledTo, before + 20, "the swipe moved the body")
        // Wait past the moment the second reveal is due.
        let end = Date().addingTimeInterval(1.2)
        while Date() < end { usleep(100_000) }
        XCTAssertGreaterThanOrEqual(comment.frame.minY, scrolledTo - 1, "the body was not taken back to the field")
    }
}
