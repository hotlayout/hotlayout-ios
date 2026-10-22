import XCTest

/// The parts of a text field on a real screen (`parts-screens`, the form): the mark at the end of the
/// field, the counter under the box. A mark and a counter are not read as separate elements (they are
/// part of the description of the field), so they are found by their ink in the screenshot.
final class InputPartsTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// How many pixels of `rect` (points) differ from the pixel at its top-left corner.
    func ink(_ shot: XCUIScreenshot, _ rect: CGRect) -> Int {
        let background = pixel(shot, x: rect.minX, y: rect.minY)
        var count = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                if colourDistance(pixel(shot, x: x, y: y), background) > 90 { count += 1 }
                x += 1
            }
            y += 1
        }
        return count
    }

    func testMarkAndCounterAreDrawn() {
        let app = launchFixture("parts-screens", screen: "form")
        let amount = app.textFields["Amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        attachScreenshot(app, "form")
        let shot = app.screenshot()
        // The suffix «₴» stands at the end of the box, after the text of the field.
        let mark = CGRect(x: amount.frame.maxX + 2, y: amount.frame.minY + 2, width: 10, height: amount.frame.height - 4)
        XCTAssertGreaterThan(ink(shot, mark), 8, "the suffix is drawn at the end of the box")
        // The field of several lines with a counter: the row under the box holds «0 / 280» at the end.
        let comment = app.textViews["Comment"]
        XCTAssertTrue(comment.exists, "the comment field is several lines: a text view")
        let counter = CGRect(x: comment.frame.maxX - 60, y: comment.frame.maxY + 14, width: 60, height: 14)
        XCTAssertGreaterThan(ink(shot, counter), 20, "the counter is drawn under the box, at the end")
    }

    func testCounterFollowsTheTypedText() {
        let app = launchFixture("parts-screens", screen: "form")
        let phone = app.textFields["Phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        let region = { (shot: XCUIScreenshot) in CGRect(x: phone.frame.maxX - 70, y: phone.frame.maxY + 14, width: 70, height: 14) }
        let before = app.screenshot()
        let first = ink(before, region(before))
        XCTAssertGreaterThan(first, 20, "the counter is drawn before anything is typed")
        phone.tap()
        phone.typeText("0501234567")
        // The numeric pad has no return key and covers the lower part of the screen, the counter
        // included (on every iOS version: the screen keeps its size when the keyboard comes). The
        // ink under the box would then be the keys, not the counter, so the form is scrolled until
        // the counter stands above the keyboard before it is measured.
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        for _ in 0..<4 where phone.frame.maxY + 40 > keyboard.frame.minY {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            from.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        }
        XCTAssertLessThan(phone.frame.maxY + 28, keyboard.frame.minY, "the counter stands above the keyboard when it is measured")
        let after = app.screenshot()
        attachScreenshot(app, "phone typed")
        XCTAssertGreaterThan(ink(after, region(after)), 20, "the counter is drawn after typing")
        XCTAssertNotEqual(ink(after, region(after)), first, "the counter changed with the text")
        // The field holds a value from the data already; the limit of 16 code points cuts what was typed.
        XCTAssertEqual((phone.value as? String ?? "").unicodeScalars.count, 16, "the text is cut to the limit")
    }

    func testTheFieldWithAMarkTakesTyping() {
        let app = launchFixture("parts-screens", screen: "form")
        let amount = app.textFields["Amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("1500")
        XCTAssertTrue((amount.value as? String ?? "").hasSuffix("1500"), "typed: \(amount.value as? String ?? "")")
        XCTAssertFalse((amount.value as? String ?? "").contains("₴"), "the mark is not part of the value")
    }
}
