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
        return keyboard
    }

    func testBottomFieldOfLongFormRisesAboveKeyboard() {
        let app = launchFixture("parts-screens", screen: "form")
        let phone = app.textFields["Phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        attachScreenshot(app, "parts before focus")
        phone.tap()
        let keys = keyboard(app)
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
}
