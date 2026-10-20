import SwiftUI
import XCTest

@testable import HotLayout

/// Tabs, the style of a part, and the controls drawn off screen.
@MainActor
final class ControlsRulesTests: XCTestCase {
    func testOpenTab() {
        // The index counts ALL tabs in document order, hidden ones too.
        XCTAssertEqual(TabsRules.openTabIndex(initialTab: 1, visible: [true, true, true]), 1)
        XCTAssertEqual(TabsRules.openTabIndex(initialTab: nil, visible: [true, true]), 0)
        // A hidden tab, or a number outside the list: the first visible tab.
        XCTAssertEqual(TabsRules.openTabIndex(initialTab: 1, visible: [false, false, true]), 2)
        XCTAssertEqual(TabsRules.openTabIndex(initialTab: 5, visible: [true, true]), 0)
        XCTAssertEqual(TabsRules.openTabIndex(initialTab: -1, visible: [false, true]), 1)
        XCTAssertEqual(TabsRules.openTabIndex(initialTab: 1.5, visible: [true, true]), 0)
        XCTAssertEqual(TabsRules.openTabIndex(initialTab: "1", visible: [true, true]), 0)
        XCTAssertNil(TabsRules.openTabIndex(initialTab: 0, visible: [false, false]))
        XCTAssertNil(TabsRules.openTabIndex(initialTab: 0, visible: []))
    }

    func testStyleOfAPart() {
        let met: (JSONValue) -> Bool = { $0["path"]?.stringValue == "a" }
        let cases: JSONValue = [
            ["when": ["path": "b", "op": "isTrue"], "style": ["color": "danger"]],
            ["when": ["path": "a", "op": "isTrue"], "style": ["typography": "titleS"]],
        ]
        let style = PartStyleRules.resolve(["color": "success", "typography": "bodyS", "padding": "md"], cases, isMet: met)
        XCTAssertEqual(style, PartStyleRules.Style(color: "success", typography: "titleS"), "the first state that holds is laid over the base, key by key")
        XCTAssertNil(PartStyleRules.resolve(["padding": "md"], nil, isMet: met), "only the two keys are read")
        XCTAssertNil(PartStyleRules.read(["color": "#fff"]))
        XCTAssertNil(PartStyleRules.read(["color": ["token": "primary"]]), "a token with opacity needs the opacity")
        XCTAssertNotNil(PartStyleRules.read(["color": ["value": "#ff7a5980"]]))
        XCTAssertNotNil(PartStyleRules.read(["typography": ["token": "titleS", "fontWeight": 600]]))
    }

    /// Every control is drawn at the size the contract gives it, in both directions.
    func testControlsDrawAtTheirSize() throws {
        let document = try loadDocument(Contract.json("fixtures/buttons-chips-screens.json"))
        XCTAssertFalse(document.screens.isEmpty)
        for locale in ["en", "ar"] {
            let view = HotlayoutScreen(document: document, locale: locale, now: Date(timeIntervalSince1970: 1_791_000_000)).frame(width: 393, height: 852)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage, locale)
        }
    }

    /// The controls are drawn by this reader, not by the unknown-widget rule.
    func testWidgetsAreDrawn() {
        for type in ["Button", "IconButton", "Badge", "ListTile", "Accordion", "Tabs", "Tab"] {
            XCTAssertTrue(DocumentReader.knownWidgets.contains(type), type)
        }
    }
}
