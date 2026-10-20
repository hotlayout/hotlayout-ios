import XCTest

@testable import HotLayout

/// The accessible name of a pressable card is read by VoiceOver. It should name what is SHOWN on
/// the card. `PressTarget.name` walks the children in document order and reads their text fields,
/// but it is never given the data scope and so cannot tell a child hidden by `visibleIf` (or by a
/// width class, `showOn`) from a shown one. In the React reader the name is the rendered subtree,
/// so a hidden child is not in the DOM and not in the name; here its text is spoken.
///
/// A bank screen that hides a balance (privacy mode, a `visibleIf`) still draws the card without
/// the balance, but VoiceOver reads the balance aloud — the heard text differs from the shown text.
@MainActor
final class AccessibilityNameAdversarialTests: XCTestCase {
    /// A pressable container with a shown title and a child whose `visibleIf` fails on the current
    /// (empty) data. The card is not drawn with that child, but its text is in the accessible name.
    func testHiddenChildIsNotInTheAccessibleName() throws {
        let card = try Harness.node(.object(JSONObject([
            ("id", "card"), ("type", "Container"),
            ("props", ["direction": "column", "gap": "none", "action": ["type": "navigate", "params": ["screenId": "a"]]]),
            ("children", [
                .object(JSONObject([("id", "t1"), ("type", "Text"), ("props", ["content": "Account 1234"]), ("children", [])])),
                .object(JSONObject([
                    ("id", "t2"), ("type", "Text"), ("props", ["content": "Balance 5000 USD"]),
                    ("visibleIf", ["path": "privacy.off", "op": "eq", "value": "yes"]),
                    ("children", []),
                ])),
            ]),
        ])))
        // The hidden child really is hidden with empty data.
        let hidden = try XCTUnwrap(card.children.first { $0.id == "t2" })
        XCTAssertFalse(Conditions.isVisible(hidden.visibleIf, scope: [:]), "the balance child is hidden on this data")

        let name = PressTarget.name(of: card) { node, field in node.props[field]?.stringValue ?? "" }
        XCTAssertFalse(name.contains("Balance 5000 USD"), "the name of the card speaks a child the card does not show: “\(name)”")
    }

    // MARK: Guards

    /// A shown child's text IS part of the name, and a list template (`Repeater`) is not (it has
    /// no text without data) — the parts of the rule that already hold.
    func testShownTextIsInTheNameAndListTemplateIsNot() throws {
        let card = try Harness.node(.object(JSONObject([
            ("id", "card"), ("type", "Container"),
            ("props", ["direction": "column", "gap": "none", "label": "Open rewards", "action": ["type": "navigate", "params": ["screenId": "a"]]]),
            ("children", [
                .object(JSONObject([("id", "t1"), ("type", "Text"), ("props", ["content": "Rewards"]), ("children", [])])),
                .object(JSONObject([
                    ("id", "rep"), ("type", "Repeater"), ("props", ["source": "items"]),
                    ("children", [.object(JSONObject([("id", "row"), ("type", "Text"), ("props", ["content": "in the template"]), ("children", [])]))]),
                ])),
            ]),
        ])))
        let name = PressTarget.name(of: card) { node, field in node.props[field]?.stringValue ?? "" }
        XCTAssertTrue(name.contains("Open rewards"), name)
        XCTAssertTrue(name.contains("Rewards"), name)
        XCTAssertFalse(name.contains("in the template"), "a list template does not name the card")
    }
}
