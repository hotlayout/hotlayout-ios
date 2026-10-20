import Foundation
import XCTest

@testable import HotLayout

/// What the reader does with rich text beyond the shared tables: the look a run resolves to, the
/// shown text over runs, the siblings of a list item and the words of emphasis.
final class TextRichPlanTests: XCTestCase {
    private let theme = HotlayoutThemeSet.builtIn.theme()
    private var resolver: StyleResolver { StyleResolver(theme: theme) }
    private var base: TextStyleValue { theme.typography["bodyM"]! }
    private var color: RGBA { theme.colorValue("onSurface")! }

    private func plan(_ content: JSONValue, spans: JSONValue?, emphasis: TextEmphasis = .root, data: DataScope = [:]) -> TextRichPlan {
        let environment = TextEnvironment(scope: data, formattingLocale: "en", fallbackLocale: "en")
        let runs = BindableText.runs(content, language: .none, environment: environment)
        let active = TextSpans.active(content: content, spans: TextSpans.read(spans))
        return TextRichPlan.make(runs: runs, active: active, base: base, color: color, emphasis: emphasis, resolver: resolver)
    }

    private let doubled: JSONValue = ["kind": "template", "template": "Earn {double} points", "values": ["double": ["kind": "text", "text": "double"]]]

    func testWeightOfAPartIsStrongerThanItsTypography() {
        let result = plan(doubled, spans: ["double": ["typography": "titleM", "weight": "regular"]])
        XCTAssertEqual(result.runs.map(\.text), ["Earn ", "double", " points"])
        XCTAssertEqual(result.runs[1].typography.fontWeight, 400)
        XCTAssertEqual(result.runs[1].typography.fontSize, theme.typography["titleM"]!.fontSize)
        XCTAssertEqual(result.runs[0].typography, base)
    }

    func testPartWithoutTypographyKeepsTheTextFontAndTakesTheWeightWord() {
        let result = plan(doubled, spans: ["double": ["weight": "bold"]])
        XCTAssertEqual(result.runs[1].typography.fontWeight, 700)
        XCTAssertEqual(result.runs[1].typography.fontSize, base.fontSize)
        XCTAssertFalse(result.runs[1].namesColor)
    }

    func testPartColourReplacesTheTextColour() {
        let result = plan(doubled, spans: ["double": ["color": "accent"]])
        XCTAssertEqual(result.runs[1].color, theme.colorValue("accent"))
        XCTAssertTrue(result.runs[1].namesColor)
        XCTAssertEqual(result.runs[0].color, color)
    }

    func testPitchCountsAPartTheShownStringDoesNotMention() {
        let content: JSONValue = ["kind": "template", "template": "Plain text", "values": ["big": ["kind": "text", "text": "x"]]]
        let result = plan(content, spans: ["big": ["typography": "displayL"]])
        let big = theme.typography["displayL"]!
        XCTAssertEqual(result.runs.map(\.text), ["Plain text"])
        XCTAssertEqual(result.lineBlock, max(base.lineBox, big.lineBox), accuracy: 1e-9)
    }

    func testShownTextRuleRunsAcrossRuns() {
        let runs = [TextSpanRun(text: "  a  ", span: nil), TextSpanRun(text: " b\n\n", span: "x"), TextSpanRun(text: " ", span: nil), TextSpanRun(text: " c ", span: nil)]
        let shown = TextRichPlan.shown(runs)
        XCTAssertEqual(shown.map(\.text), ["a ", "b ", "c"])
        XCTAssertEqual(shown.map(\.span), [nil, "x", nil])
        XCTAssertEqual(shown.map(\.text).joined(), ShownText.of(runs.map(\.text).joined()))
    }

    func testEmphasisWordsOutsideTheListAreNoField() {
        let inherited = TextEmphasis(fontStyle: "italic", textDecoration: "underline")
        XCTAssertEqual(TextEmphasisRules.inherit(inherited, style: ["fontStyle": "oblique", "textDecoration": "overline"]), inherited)
        XCTAssertEqual(TextEmphasisRules.inherit(inherited, style: ["fontStyle": "normal"]).fontStyle, "normal")
        var look = InheritedLook(color: color, typography: base, fontStyleItalic: true, decoration: "underline")
        look = NodeStyle.inherited(look, style: ["fontStyle": "oblique", "textDecoration": 1], resolver: resolver)
        XCTAssertTrue(look.fontStyleItalic)
        XCTAssertEqual(look.decoration, "underline")
    }

    func testSiblingsOfAListItem() {
        let items: [DocumentNode] = [
            DocumentNode(id: "a", type: "Text", props: ["marker": "number"]),
            DocumentNode(id: "b", type: "Text", props: ["marker": "number"], fields: ["visibleIf": ["path": "flag", "op": "isTrue"]]),
            DocumentNode(id: "c", type: "Text", props: ["marker": "number"]),
            DocumentNode(id: "d", type: "Text", props: ["marker": "bullet"]),
        ]
        let siblings = ListSiblings(children: items, scope: [:])
        XCTAssertEqual((0..<4).map { ListPosition(siblings: siblings, index: $0).number }, [1, 2, 2, nil])
        XCTAssertEqual((0..<4).map { ListPosition(siblings: siblings, index: $0).groupSize }, [3, 3, 3, nil])
        let shown = ListSiblings(children: items, scope: ["flag": true])
        XCTAssertEqual((0..<3).map { ListPosition(siblings: shown, index: $0).number }, [1, 2, 3])
    }
}
