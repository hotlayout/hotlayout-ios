import SwiftUI
import XCTest

@testable import HotLayout

/// Drawings of presses and paint read back pixel by pixel: the dashes of a border, the tinted
/// shadow, a moving node, the thumb of a swipe button and the card that sinks under a finger.
@MainActor
final class InteractionRenderTests: XCTestCase {
    private func card(_ fields: [(String, JSONValue)], style: JSONObject, width: Double = 120, height: Double = 60) throws -> DocumentNode {
        var style = style
        style["width"] = .number(width)
        style["height"] = .number(height)
        return try Harness.node(.object(JSONObject([
            ("id", "card"), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]), ("style", .object(style)), ("children", []),
        ] + fields)))
    }

    private func image(_ node: DocumentNode, rtl: Bool = false, margin: CGFloat = 20) throws -> ProgressPixels.Image {
        let view = NodeView(node: node, context: Harness.context(rightToLeft: rtl), placement: .natural)
            .padding(margin).background(Color.white)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        return ProgressPixels.render(view)
    }

    // MARK: Dashed border

    private let dashedBorder: JSONObject = ["border": ["width": 2, "color": ["value": "#ff0000"], "style": "dashed"], "radius": 0]

    /// A solid border has no gaps along an edge; a dashed one has, with the dash and the gap in the ratio 3 : 2.
    func testDashedBorderHasGapsAlongTheTopEdge() throws {
        let pixels = try image(card([], style: dashedBorder, width: 202, height: 62))
        // The top edge: the middle of the stroke is one point below the outer edge.
        var runs: [Bool] = []
        for x in 21..<221 { runs.append(ProgressPixels.color(pixels, x: x, y: 21).alpha > 0.5 && ProgressPixels.color(pixels, x: x, y: 21).red > 0.8 && ProgressPixels.color(pixels, x: x, y: 21).green < 0.4) }
        let changes = zip(runs, runs.dropFirst()).filter { $0 != $1 }.count
        XCTAssertGreaterThan(changes, 20, "a dashed line changes between the dash and the gap many times")
        XCTAssertTrue(runs.contains(false), "there are gaps")
        XCTAssertTrue(runs.first ?? false, "the pattern starts with a dash at the inline start")
        let drawn = runs.filter { $0 }.count
        XCTAssertEqual(Double(drawn) / Double(runs.count), 0.6, accuracy: 0.1, "a dash is 3 of every 5 widths")
    }

    func testSolidBorderHasNoGaps() throws {
        var style = dashedBorder
        style["border"] = ["width": 2, "color": ["value": "#ff0000"]]
        let pixels = try image(card([], style: style, width: 202, height: 62))
        for x in 22..<218 { XCTAssertGreaterThan(ProgressPixels.color(pixels, x: x, y: 21).red, 0.8, "x=\(x)") }
    }

    /// Right to left mirrors the drawing: the line still starts at the inline start (the right edge),
    /// so a pattern that starts with a dash has its dash at the right end of the top edge.
    func testDashedBorderStartsAtTheInlineStartInRightToLeft() throws {
        let rtl = try image(card([], style: dashedBorder, width: 202, height: 62), rtl: true)
        let ltr = try image(card([], style: dashedBorder, width: 202, height: 62), rtl: false)
        func filled(_ pixels: ProgressPixels.Image, x: Int) -> Bool { ProgressPixels.color(pixels, x: x, y: 21).red > 0.8 && ProgressPixels.color(pixels, x: x, y: 21).green < 0.4 }
        XCTAssertTrue(filled(ltr, x: 22), "left to right: a dash at the left end")
        XCTAssertTrue(filled(rtl, x: 219), "right to left: a dash at the right end")
    }

    // MARK: Shadow colour

    func testShadowTakesTheHueOfTheBackground() throws {
        let shadow: JSONValue = [["offsetX": 0, "offsetY": 14, "blur": 18, "spread": 0, "color": ["value": "#000000", "opacity": 1]]]
        let background: JSONValue = ["kind": "color", "color": ["value": "#ff0000"]]
        let tinted = try image(card([], style: ["background": background, "shadow": shadow, "shadowColor": "background"]), margin: 40)
        let plain = try image(card([], style: ["background": background, "shadow": shadow]), margin: 40)
        // Below the box: inside the shadow.
        let below = ProgressPixels.color(tinted, x: 100, y: 40 + 60 + 8)
        let blackBelow = ProgressPixels.color(plain, x: 100, y: 40 + 60 + 8)
        XCTAssertGreaterThan(below.red, below.green + 0.03, "the shadow of a red box is red")
        XCTAssertEqual(blackBelow.red, blackBelow.green, accuracy: 0.02, "without the field the shadow is grey")
        XCTAssertLessThan(blackBelow.red, 0.97, "there is a shadow")
    }

    // MARK: Motion

    private func square(_ motion: JSONValue, elapsed: Double, rtl: Bool = false) throws -> ProgressPixels.Image {
        let read = try XCTUnwrap(NodeMotion.read(motion))
        let view = Color.red.frame(width: 20, height: 20).nodeMotion(read, rightToLeft: rtl, fixedElapsedMs: elapsed)
            .padding(40).background(Color.white).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        return ProgressPixels.render(view)
    }

    private func isRed(_ pixels: ProgressPixels.Image, _ x: Int, _ y: Int) -> Bool {
        let c = ProgressPixels.color(pixels, x: x, y: y)
        return c.red > 0.8 && c.green < 0.4 && c.alpha > 0.5
    }

    func testFloatMovesThePaintingNotTheBox() throws {
        let motion: JSONValue = ["kind": "float", "axis": "horizontal", "amplitude": 12, "duration": 2000]
        let rest = try square(motion, elapsed: 0)
        let moved = try square(motion, elapsed: 500)
        XCTAssertTrue(isRed(rest, 50, 50) && !isRed(rest, 68, 50), "at rest the square is where its box is")
        XCTAssertTrue(isRed(moved, 68, 50), "a quarter cycle later it is painted 12 points toward the end")
        XCTAssertFalse(isRed(moved, 42, 50), "and not where it was")
        // Right to left: toward the end of the line is the left.
        let mirrored = try square(motion, elapsed: 500, rtl: true)
        XCTAssertTrue(isRed(mirrored, 32, 50), "right to left: toward the end is to the left")
        XCTAssertFalse(isRed(mirrored, 68, 50))
    }

    func testPulseScalesAboutTheCentre() throws {
        let motion: JSONValue = ["kind": "pulse", "scale": 1.5, "duration": 2000]
        let peak = try square(motion, elapsed: 1000)
        XCTAssertTrue(isRed(peak, 37, 50), "at the peak the square is 30 wide about the same centre")
        XCTAssertTrue(isRed(peak, 63, 50))
        XCTAssertFalse(isRed(peak, 33, 50))
        XCTAssertFalse(isRed(peak, 67, 50))
    }

    // MARK: Swipe to confirm

    private func swipe(progress: Double?, busy: Bool = false, rtl: Bool = false, dashed: Bool = false) -> ProgressPixels.Image {
        let theme = HotlayoutThemeSet.builtIn.theme(nil)
        let typography = theme.typography["titleM"]!
        let corners = Corners(topStart: 12, topEnd: 12, bottomEnd: 12, bottomStart: 12)
        let look = SwipeConfirmLook(
            label: "Swipe", typography: typography, theme: theme, trackFill: RGBA(hex: "#0000ff"), labelColor: RGBA(hex: "#ffffff")!,
            thumbFill: RGBA(hex: "#ff0000")!, glyphColor: RGBA(hex: "#ffffff")!, borderColor: nil, borderWidth: 0, dashedBorder: dashed,
            padding: Sides(top: 12, start: 16, bottom: 12, end: 16), shape: LogicalCornersShape(corners: corners, rightToLeft: rtl), corners: corners,
            shadow: [], fullWidth: true, icon: nil
        )
        let node = DocumentNode(id: "b", type: "Button", props: ["confirm": "swipe", "action": ["type": "none"]])
        let view = SwipeConfirmButton(node: node, context: Harness.context(rightToLeft: rtl), look: look, fixedProgress: progress, fixedBusy: busy)
            .frame(width: 300).padding(10).background(Color.white)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        return ProgressPixels.render(view)
    }

    private func isThumb(_ pixels: ProgressPixels.Image, x: Int, y: Int) -> Bool {
        let c = ProgressPixels.color(pixels, x: x, y: y)
        return c.red > 0.8 && c.blue < 0.4
    }

    func testThumbRestsAtTheInlineStartAndTravelsToTheEnd() {
        let start = swipe(progress: 0)
        let height = Double(start.height) - 20
        let diameter = height - 8
        let centreY = Int(10 + height / 2)
        XCTAssertTrue(isThumb(start, x: Int(10 + 4 + diameter / 2), y: centreY), "at rest the thumb is at the start")
        XCTAssertFalse(isThumb(start, x: Int(10 + 300 - 4 - diameter / 2), y: centreY))
        let end = swipe(progress: 1)
        XCTAssertTrue(isThumb(end, x: Int(10 + 300 - 4 - diameter / 2), y: centreY), "at the end it is at the other side")
        XCTAssertFalse(isThumb(end, x: Int(10 + 4 + diameter / 2), y: centreY))
        let rtl = swipe(progress: 0, rtl: true)
        XCTAssertTrue(isThumb(rtl, x: Int(10 + 300 - 4 - diameter / 2), y: centreY), "right to left the start is on the right")
    }

    func testBusyThumbStandsAtTheEnd() {
        let busy = swipe(progress: 1, busy: true)
        let height = Double(busy.height) - 20
        let diameter = height - 8
        XCTAssertTrue(isThumb(busy, x: Int(10 + 300 - 4 - diameter / 2) - 12, y: Int(10 + height / 2)), "busy: at the end, with the indicator instead of the glyph")
    }
}
