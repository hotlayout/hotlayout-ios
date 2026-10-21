#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest

@testable import HotLayout

/// The top of a real screen on a window with a status bar: what a scrolled body does under the inset
/// (`x-style.layout.safeTop`) and when the app bar takes its scrolled look (`styleScrolled`).
/// The colours are the same in every channel order, so that the byte order of the bitmap does not matter.
@MainActor
final class ScreenTopWiringTests: XCTestCase {
    private static let inset = 59.0
    private static let magenta = "#ff00ff"
    private static let green = "#00ff00"
    private static let white = "#ffffff"

    private func fill(_ hex: String) -> JSONValue { ["kind": "color", "color": ["value": .string(hex)]] }

    private func block(_ id: String, height: Double, color: String = green) -> JSONValue {
        ["id": .string(id), "type": "Container", "props": ["direction": "column", "gap": "none"],
         "style": ["height": .number(height), "background": fill(color)], "children": []]
    }

    private func document(bar: Bool, bodyTop: Bool) throws -> HotlayoutDocument {
        var children: [JSONValue] = []
        if bar {
            children.append([
                "id": "bar", "type": "AppBar",
                "props": ["title": ["kind": "literal", "value": "Mission"], "showBack": false, "titleShown": "scrolled"],
                "style": ["padding": ["top": "sm", "bottom": "sm", "start": "gutter", "end": "gutter"], "background": ["kind": "color", "color": ["value": "#ff00ff", "opacity": 0]]],
                "styleScrolled": ["background": fill(Self.white)], "children": [],
            ])
        }
        children.append(block("tall", height: 3000))
        var props: JSONObject = ["gap": "none"]
        if bodyTop { props["bodyTop"] = "screenTop" }
        return try HotlayoutDocument.load([
            "schemaVersion": "9.28.0", "documentId": "d", "name": "n", "initialScreenId": "a",
            "screens": [["screenId": "a", "name": "A", "root": [
                "id": "r", "type": "Screen", "props": .object(props),
                "style": ["background": fill(Self.magenta), "padding": ["top": "none", "bottom": "none", "start": "none", "end": "none"]],
                "children": .array(children)]]],
        ])
    }

    private func scrollViews(_ view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } .map { $0 + view.subviews.flatMap(scrollViews) } ?? view.subviews.flatMap(scrollViews)
    }

    /// The screen in a window of an iPhone 16 with the status bar inset; `scrollBy` moves its body.
    private func shoot(_ document: HotlayoutDocument, scrollBy: Double?) throws -> Pixels {
        let screen = HotlayoutScreen(document: document, locale: "en")
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: CGFloat(Self.inset)) }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 34) }
        let controller = UIHostingController(rootView: screen)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        runLoop(0.6)
        if let scrollBy {
            let body = try XCTUnwrap(scrollViews(window).max { $0.bounds.height < $1.bounds.height }, "the body scrolls")
            body.setContentOffset(CGPoint(x: 0, y: scrollBy), animated: false)
            runLoop(0.6)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { window.layer.render(in: $0.cgContext) }
        return Pixels(try XCTUnwrap(image.cgImage))
    }

    /// Without an app bar the body is cut at the bottom edge of the inset: a scrolled body does not show under the status bar.
    func testBodyWithoutAppBarIsClippedAtTheInset() throws {
        let doc = try document(bar: false, bodyTop: false)
        let still = try shoot(doc, scrollBy: nil)
        let scrolled = try shoot(doc, scrollBy: 500)
        func firstBody(_ pixels: Pixels) -> Int? { (0..<pixels.height).first { pixels.isColor(200, $0, Self.green) } }
        let top = try XCTUnwrap(firstBody(still), "the body is drawn")
        XCTAssertGreaterThanOrEqual(Double(top), Self.inset, "the body starts below the inset")
        XCTAssertEqual(firstBody(scrolled), top, "scrolled, it is cut at the same edge and does not slide under the status bar")
        XCTAssertTrue((0..<top).allSatisfy { scrolled.isColor(200, $0, Self.magenta) }, "the inset shows the screen background")
    }

    /// The scrolled look of the app bar of a screen whose body starts at the top of the screen (`bodyTop: screenTop`).
    func testAppBarTakesItsScrolledLookOverABodyAtTheScreenTop() throws {
        let doc = try document(bar: true, bodyTop: true)
        let still = try shoot(doc, scrollBy: nil)
        XCTAssertTrue(still.isColor(300, 80, Self.green), "the bar has no background: the body shows through")
        let scrolled = try shoot(doc, scrollBy: 400)
        XCTAssertTrue(scrolled.isColor(300, 80, Self.white), "scrolled past the bar: its own background")
    }

    func testAppBarTakesItsScrolledLookOverABodyUnderIt() throws {
        let doc = try document(bar: true, bodyTop: false)
        let still = try shoot(doc, scrollBy: nil)
        XCTAssertFalse(still.isColor(300, 80, Self.white))
        let scrolled = try shoot(doc, scrollBy: 400)
        XCTAssertTrue(scrolled.isColor(300, 80, Self.white), "scrolled: its own background")
    }

    /// A round picture with a border (`style.border` on an `Image`): the ring is drawn round the picture.
    func testBorderOfARoundImageIsDrawn() throws {
        let avatar: JSONValue = [
            "id": "avatar", "type": "Image", "props": ["source": ["kind": "asset", "asset": "placeholder"], "aspectRatio": "1:1", "fit": "cover"],
            "style": ["width": 100, "height": 100, "radius": "pill", "border": ["width": 4, "color": ["value": "#00ff00"]]],
        ]
        let doc = try HotlayoutDocument.load([
            "schemaVersion": "9.28.0", "documentId": "d", "name": "n", "initialScreenId": "a",
            "screens": [["screenId": "a", "name": "A", "root": [
                "id": "r", "type": "Screen", "props": ["gap": "none"],
                "style": ["background": fill(Self.magenta), "padding": ["top": "none", "bottom": "none", "start": "none", "end": "none"]],
                "children": [avatar]]]],
        ])
        let pixels = try shoot(doc, scrollBy: nil)
        let ring = (0..<pixels.height).contains { y in (0..<150).contains { x in pixels.isColor(x, y, Self.green) } }
        XCTAssertTrue(ring, "the green ring of the border is on the screen")
    }

    /// The middle of a window drawn by `ModalStack` in a host that leaves these insets.
    private func windowCentre(top: Double, bottom: Double) throws -> Double {
        let stack = ModalStack(
            page: AnyView(Color.clear),
            layers: [ModalStack.Layer(
                id: 1, content: AnyView(Color.green.frame(height: 200)), shape: .window, placement: "center", blur: nil, dismissible: true)],
            margin: 24, insets: ScreenInsets(top: top, bottom: bottom), dismiss: { _ in })
        let controller = UIHostingController(rootView: stack)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        runLoop(0.8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { window.layer.render(in: $0.cgContext) }
        let pixels = Pixels(try XCTUnwrap(image.cgImage))
        // The scrim is black over a clear page; the window is the green block.
        let rows = (0..<pixels.height).filter { (pixels.rgb(196, $0)?.g ?? 0) > 150 }
        return Double(try XCTUnwrap(rows.first) + (try XCTUnwrap(rows.last)) + 1) / 2
    }

    /// A window (`modalPlacement: center`) stands in the middle of the area between the inset and the home indicator
    /// (`x-style.layout.safeTop.modal.window`; `modalAreaCases`: 59 above and 34 below on 852 gives 438.5, which is
    /// 12.5 below the middle of the whole screen).
    func testCenteredWindowStandsInTheAreaBelowTheInset() throws {
        let whole = try windowCentre(top: 0, bottom: 0)
        XCTAssertEqual(try windowCentre(top: Self.inset, bottom: 34) - whole, 12.5, accuracy: 1)
        XCTAssertEqual(try windowCentre(top: 20, bottom: 16) - whole, 2, accuracy: 1, "320 × 568 row: 286 against 284")
    }
}
#endif
