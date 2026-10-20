import SwiftUI
import XCTest

@testable import HotLayout

/// What the three showcase apps drew wrongly beside the web reader: a picture in a stack, the nodes
/// of the top zone, the line box of an installed font and the material of the glass.
@MainActor
final class ShowcaseReaderTests: XCTestCase {
    /// The gap of the screen's column when the document names none.
    private let gap = 20.0

    private func box(_ id: String, height: Double, color: String, fields: [(String, JSONValue)] = []) -> JSONValue {
        .object(JSONObject([
            ("id", .string(id)), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
            ("style", ["height": .number(height), "background": ["kind": "color", "color": ["value": .string(color)]]]),
            ("children", []),
        ] + fields))
    }

    /// The bounding box of a colour of the table (`AdaptiveRender.hex(index)`) in the screen drawn at 393 × 852.
    private func frame(_ index: Int, in document: HotlayoutDocument) throws -> CGRect? {
        let pixels = try AdaptiveRender.render(document, width: 393, height: 852)
        return AdaptiveRender.box(of: [AdaptiveRender.colour(index)], in: pixels)[0]
    }

    // MARK: a picture in a stack

    /// A picture has no width of its own: as the first layer of a stack in a column it fills the width the
    /// stack is offered, with a named height (the card of a balance) and with a proportion (the picture of a quest).
    func testPictureLayerOfStackFillsTheWidth() throws {
        for named in [true, false] {
            var image: JSONObject = [
                "id": "pic", "type": "Image",
                "props": ["source": ["kind": "asset", "asset": "none"], "aspectRatio": ["width": 2, "height": 1], "fit": "cover"],
            ]
            var style: JSONObject = ["border": ["width": 4, "color": ["value": .string(AdaptiveRender.hex(0))]]]
            if named { style["height"] = 100 }
            image["style"] = .object(style)
            let stack: JSONValue = ["id": "stack", "type": "Stack", "props": ["alignHorizontal": "start", "alignVertical": "start"], "children": [.object(image)]]
            let document = try screenDocument([("a", [stack])])
            let found = try XCTUnwrap(try frame(0, in: document), "the picture is drawn (named height: \(named))")
            XCTAssertEqual(found.width, 393, accuracy: 2, "the whole width (named height: \(named))")
            XCTAssertEqual(found.height, named ? 100 : 196.5, accuracy: 6, "height (named height: \(named))")
        }
    }

    // MARK: the top zone

    /// The first node of the top zone pulls nothing; the second is pulled by its pull less the gap, as in the body
    /// (`topZone` cases: «a pulled second node overlaps the first by its pull minus the gap»).
    func testSecondNodeOfTopZoneIsPulled() throws {
        let first = box("sky", height: 60, color: AdaptiveRender.hex(0), fields: [("pin", "top")])
        let second = box("hello", height: 40, color: AdaptiveRender.hex(1), fields: [("pin", "top"), ("pull", 50)])
        let document = try AdaptiveRender.document(root: AdaptiveRender.screenRoot([first, second], props: ["gap": .number(gap)]))
        let sky = try XCTUnwrap(try frame(0, in: document))
        let hello = try XCTUnwrap(try frame(1, in: document))
        // The second node is drawn over the first.
        XCTAssertEqual(hello.minY - sky.minY, 60 + gap - 50, accuracy: 1, "the second node starts at the first one's height plus the gap less its pull")
    }

    func testFirstNodeOfTopZoneStillPullsNothing() throws {
        let pulled = box("sky", height: 60, color: AdaptiveRender.hex(0), fields: [("pin", "top"), ("pull", 50)])
        let plain = box("sky", height: 60, color: AdaptiveRender.hex(0), fields: [("pin", "top")])
        let withPull = try XCTUnwrap(try frame(0, in: try screenDocument([("a", [pulled])])))
        let without = try XCTUnwrap(try frame(0, in: try screenDocument([("a", [plain])])))
        XCTAssertEqual(withPull.minY, without.minY)
    }

    // MARK: the line box of an installed font

    /// The line of a style is `lineHeight` × size whatever font the theme names: the extra leading is
    /// counted from the natural line of THAT font, not of the system one.
    func testNaturalLineHeightFollowsTheFontOfTheTheme() {
        var theme = HotlayoutThemeSet.builtIn.theme(nil)
        let style = TextStyleValue(fontSize: 20, lineHeight: 1.2, fontWeight: 400)
        let system = style.naturalLineHeight
        theme.fontFamilies["body"] = "No Such Family 77"
        XCTAssertEqual(style.naturalLineHeight(in: theme), system, accuracy: 0.001, "a family nobody installed: the system font")
        theme.fontFamilies["body"] = "Menlo"
        #if canImport(UIKit)
        guard let name = UIFont.fontNames(forFamilyName: "Menlo").first, let font = UIFont(name: name, size: 20) else { return }
        let own = Double(font.lineHeight)
        #else
        guard let name = NSFontManager.shared.availableMembers(ofFontFamily: "Menlo")?.first?.first as? String, let font = NSFont(name: name, size: 20) else { return }
        let own = Double(font.ascender - font.descender + font.leading)
        #endif
        XCTAssertEqual(style.naturalLineHeight(in: theme), own, accuracy: 0.001)
        XCTAssertNotEqual(own, system, accuracy: 0.01, "the test needs a font whose line differs from the system one")
    }

    /// A single line of text is the line box tall, from the natural line of the font of the theme (at 100 points the
    /// line of Menlo and of the system font differ by three).
    func testLineBoxIsTheLineHeightOfTheStyle() throws {
        var theme = HotlayoutThemeSet.builtIn.theme(nil)
        theme.fontFamilies["body"] = "Menlo"
        for lineHeight in [1.0, 1.3, 2.0] {
            let style = TextStyleValue(fontSize: 100, lineHeight: lineHeight, fontWeight: 400)
            let view = StyledText(text: "Mg", style: style, color: RGBA(hex: "#ffffff")!, theme: theme)
            #if canImport(UIKit)
            let height = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 1000)).height
            #else
            let height = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 1000)).height
            #endif
            XCTAssertEqual(Double(height), 100 * lineHeight, accuracy: 1.5, "lineHeight \(lineHeight)")
        }
    }
}

// MARK: lines of a text shorter than the font's own

extension ShowcaseReaderTests {
    /// With a line box SMALLER than the natural line of the font, every line of a text of two lines is the box tall
    /// (the second one too), as in CSS.
    func testTwoLinesAreTwoLineBoxesWhenTheBoxIsSmallerThanTheFont() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("the system sets the line height from 26") }
        var theme = HotlayoutThemeSet.builtIn.theme(nil)
        theme.fontFamilies["body"] = "Menlo"
        let style = TextStyleValue(fontSize: 40, lineHeight: 1.0, fontWeight: 400)
        let view = StyledText(text: "abcd efgh", style: style, color: RGBA(hex: "#ffffff")!, theme: theme)
        #if canImport(UIKit)
        let height = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 150, height: 1000)).height
        #else
        let height = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: 150, height: 1000)).height
        #endif
        XCTAssertEqual(Double(height), 80, accuracy: 2, "two lines of 40")
    }
}

// MARK: the clock of a countdown

extension ShowcaseReaderTests {
    /// A host that gives the moment owns the clock, as in the web reader: nothing ticks. Without it the
    /// countdown runs; a text with no countdown never does.
    func testHostMomentPinsTheClockOfACountdown() {
        let countdown: JSONObject = [
            "content": ["kind": "binding", "path": "endsAt", "fallback": "0", "format": "countdownPart", "unit": "seconds"]
        ]
        let plain: JSONObject = ["content": ["kind": "literal", "value": "Hi"]]
        XCTAssertEqual(CountdownRules.clock(countdown, pinned: false, fixedSeconds: nil), .running)
        XCTAssertEqual(CountdownRules.clock(countdown, pinned: true, fixedSeconds: nil), .still)
        XCTAssertEqual(CountdownRules.clock(countdown, pinned: true, fixedSeconds: 3), .fixed)
        XCTAssertEqual(CountdownRules.clock(plain, pinned: false, fixedSeconds: nil), .still)
    }
}
