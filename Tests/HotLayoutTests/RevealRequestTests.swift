import XCTest
@testable import HotLayout

final class RevealRequestTests: XCTestCase {
    func testRepeatMayScrollUntilThePersonDrags() {
        let request = RevealRequest()
        request.begin()
        XCTAssertTrue(request.repeatMayScroll, "nothing has moved the body: the repeat settles the field")
        request.userDragged()
        XCTAssertFalse(request.repeatMayScroll, "the person scrolled: the repeat leaves the body where it is")
    }

    func testNewRequestStartsFresh() {
        let request = RevealRequest()
        request.userDragged()
        request.begin()
        XCTAssertTrue(request.repeatMayScroll, "a new focus or keyboard change asks for its own reveal")
    }
}
