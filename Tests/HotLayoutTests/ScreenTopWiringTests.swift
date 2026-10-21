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
        return try loadDocument([
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
}
#endif
