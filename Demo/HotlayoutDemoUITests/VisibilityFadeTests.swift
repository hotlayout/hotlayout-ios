import XCTest

/// Nodes that fade when their condition changes (contract 9.33.0): the one that leaves gives up its
/// place once it has faded, the one that comes takes it, and a list keeps no hole for a hidden row.
final class VisibilityFadeTests: XCTestCase {
    func testTheHeadingThatLeavesGivesUpItsPlace() {
        let app = launchFixture("visibility-fade-screens", locale: "en")
        let debit = app.staticTexts["Debit card"]
        let credit = app.staticTexts["Credit card"]
        XCTAssertTrue(debit.waitForExistence(timeout: 10))
        sleep(1)
        let headingTop = debit.frame.minY
        let firstCard = app.staticTexts["•••• 4417"]
        let cardTop = firstCard.frame.minY
        XCTAssertFalse(credit.exists, "the other headings are hidden")
        attachScreenshot(app, "01 start")

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0)).withOffset(CGVector(dx: 0, dy: firstCard.frame.midY))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -160, dy: 0)), withVelocity: 900, thenHoldForDuration: 0)
        sleep(2)
        attachScreenshot(app, "02 after the swipe")
        XCTAssertTrue(credit.exists, "the heading of the new card is shown")
        XCTAssertFalse(debit.exists, "the old one is gone")
        XCTAssertEqual(credit.frame.minY, headingTop, accuracy: 1, "the new heading stands where the old one stood")
        XCTAssertEqual(app.staticTexts["•••• 9032"].frame.minY, cardTop, accuracy: 1, "the carousel has not moved down")
        sleep(4)
        attachScreenshot(app, "03 five seconds later")
        XCTAssertEqual(credit.frame.minY, headingTop, accuracy: 1)
        XCTAssertEqual(app.staticTexts["•••• 9032"].frame.minY, cardTop, accuracy: 1)
    }

    func testAHiddenRowOfAFadingListLeavesNoHole() {
        let app = launchFixture("cases/repeater-fade", locale: "en")
        let rows = { (name: String) in app.staticTexts.matching(NSPredicate(format: "label == %@", name)) }
        XCTAssertTrue(app.staticTexts["END"].waitForExistence(timeout: 10))
        sleep(1)
        attachScreenshot(app, "repeater")
        let speakers = rows("Bluetooth speaker").allElementsBoundByIndex.map(\.frame).sorted { $0.minY < $1.minY }
        let grinders = rows("Coffee grinder set").allElementsBoundByIndex.map(\.frame).sorted { $0.minY < $1.minY }
        XCTAssertEqual(speakers.count, 2)
        XCTAssertEqual(grinders.count, 2)
        guard speakers.count == 2, grinders.count == 2 else { return }
        let plainStep = grinders[0].minY - speakers[0].minY
        let fadingStep = grinders[1].minY - speakers[1].minY
        XCTAssertEqual(fadingStep, plainStep, accuracy: 1, "the fading list closes up like the plain one")
    }
}
