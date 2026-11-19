#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// The real screen playing a step of the stack: it is held at a chosen moment of the motion
/// (`stackTransitionFreezeMs`) and read back from the pixels of its window and from the accessibility
/// tree, which is what a person sees and what a screen reader says. The plans and the frames are in
/// `ScreenTransitionCasesTests`.
@MainActor
final class ScreenTransitionViewTests: XCTestCase {
    private func colour(_ hex: String) -> JSONValue { ["kind": "color", "color": ["value": .string(hex)]] }

    private func button(_ id: String, _ label: String, goes screen: String, type: String = "navigate") -> JSONValue {
        [
            "id": .string(id), "type": "Button",
            "props": [
                "label": ["kind": "literal", "value": .string(label)], "variant": "ghost", "fullWidth": false,
                "action": ["type": .string(type), "params": ["screenId": .string(screen)]],
            ],
        ]
    }

    private func screen(_ id: String, background: String, children: [JSONValue], modal: Bool = false, extra: JSONObject = JSONObject()) -> JSONValue {
        var entry: JSONObject = [
            "screenId": .string(id), "name": .string(id),
            "root": [
                "id": .string("root-\(id)"), "type": "Screen", "props": ["gap": "none"], "style": ["background": colour(background)], "children": .array(children),
            ],
        ]
        if modal { entry["presentation"] = "modal" }
        for (key, value) in extra { entry[key] = value }
        return .object(entry)
    }

    /// home (red) opens second (blue) by a push and a sheet (green); second goes back.
    private func document(secondTransition: String? = nil) throws -> HotlayoutDocument {
        var secondExtra = JSONObject()
        if let secondTransition { secondExtra["transition"] = .string(secondTransition) }
        return try HotlayoutDocument.load([
            "schemaVersion": .string(HotlayoutVersions.schema), "documentId": "d", "name": "n", "initialScreenId": "home",
            "screens": [
                screen("home", background: "#ff0000", children: [button("open", "Open", goes: "second"), button("sheet", "Sheet", goes: "layer")]),
                screen("second", background: "#0000ff", children: [button("back", "Back", goes: "x", type: "navigate.back")], extra: secondExtra),
                screen("layer", background: "#00ff00", children: [button("close", "Close", goes: "x", type: "navigate.back")], modal: true),
            ],
        ])
    }

    private func hosted(freeze: Double?, secondTransition: String? = nil) throws -> NSView {
        let screen = HotlayoutScreen(document: try document(secondTransition: secondTransition), locale: "en")
            .environment(\.stackTransitionFreezeMs, freeze)
        return host(screen)
    }

    private func colourAt(_ view: NSView, x: Double, y: Double) throws -> (red: Double, green: Double, blue: Double) {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = Double(rep.pixelsWide) / Double(view.bounds.width)
        let c = try XCTUnwrap(rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    private func isRed(_ c: (red: Double, green: Double, blue: Double)) -> Bool { c.red > 0.8 && c.blue < 0.35 && c.green < 0.35 }
    private func isBlue(_ c: (red: Double, green: Double, blue: Double)) -> Bool { c.blue > 0.8 && c.red < 0.35 && c.green < 0.4 }

    private func press(_ view: NSView, _ label: String) throws {
        let element = try XCTUnwrap(find(view, label: label), "no «\(label)» on the screen")
        XCTAssertTrue(press(element))
        spin(0.3)
    }

    /// A push: the page that comes slides in from the end edge over the one that goes, which drifts back under it.
    func testAPushHeldInTheMiddle() throws {
        let view = try hosted(freeze: 150)
        try press(view, "Open")
        // At 150 ms the incoming page stands at 0.1222 of the width: its edge is at 44 points of 360.
        XCTAssertTrue(isRed(try colourAt(view, x: 20, y: 600)), "left of the edge of the incoming page: the page that goes")
        XCTAssertTrue(isBlue(try colourAt(view, x: 70, y: 600)), "right of it: the page that comes")
        XCTAssertTrue(isBlue(try colourAt(view, x: 340, y: 600)))
    }

    func testAPushHeldAtItsEndIsTheNewPageAlone() throws {
        let view = try hosted(freeze: 300)
        try press(view, "Open")
        XCTAssertTrue(isBlue(try colourAt(view, x: 5, y: 600)))
        XCTAssertTrue(isBlue(try colourAt(view, x: 340, y: 600)))
    }

    /// A pop: the page that goes slides out to the end edge above the one that comes back from under it.
    func testAPopHeldInTheMiddle() throws {
        let held = try hosted(freeze: 75)
        try press(held, "Open")
        try press(held, "Back")
        // At 75 ms the page that goes stands at 0.6072 of the width: its edge is at 219 points.
        XCTAssertTrue(isRed(try colourAt(held, x: 100, y: 600)), "left of its edge: the page that comes back")
        XCTAssertTrue(isBlue(try colourAt(held, x: 300, y: 600)), "right of it: the page that goes, over it")
    }

    /// The page that goes takes no touch and leaves the accessibility tree from the first frame; the page
    /// that comes is a control from the first frame.
    func testThePageThatGoesIsInertAndTheOneThatComesIsAControl() throws {
        let view = try hosted(freeze: 150)
        try press(view, "Open")
        XCTAssertNotNil(find(view, label: "Back"), "the page that comes is there for a screen reader")
        XCTAssertNil(find(view, label: "Open"), "the page that goes is not")
    }

    /// `none` on the screen that comes: at once, even though a push of a page would slide.
    func testTheWordNoneIsAtOnce() throws {
        let view = try hosted(freeze: 150, secondTransition: "none")
        try press(view, "Open")
        XCTAssertTrue(isBlue(try colourAt(view, x: 5, y: 600)))
        XCTAssertNotNil(find(view, label: "Back"))
    }

    /// `fade` on the screen that comes: the page that goes dissolves over the one that comes, which stands still.
    func testTheWordFadeDissolves() throws {
        let view = try hosted(freeze: 100, secondTransition: "fade")
        try press(view, "Open")
        let c = try colourAt(view, x: 20, y: 600)
        XCTAssertGreaterThan(c.red, 0.2, "the page that goes is still partly there")
        XCTAssertGreaterThan(c.blue, 0.2, "and the page that comes shows through it")
        XCTAssertLessThan(try colourAt(view, x: 340, y: 600).red, 0.9, "the page that comes is not moved")
    }

    /// A motion that is played to its end leaves the new stack alone: the page that went is gone, and a way back works.
    func testTheMotionRunsToItsEndAndLeavesOneStack() throws {
        try skipUnderReducedMotion()
        let view = try hosted(freeze: nil)
        try press(view, "Open")
        spin(0.8)
        XCTAssertTrue(isBlue(try colourAt(view, x: 5, y: 600)))
        XCTAssertNotNil(find(view, label: "Back"))
        XCTAssertNil(find(view, label: "Open"))
        try press(view, "Back")
        spin(0.8)
        XCTAssertTrue(isRed(try colourAt(view, x: 340, y: 600)))
        XCTAssertNotNil(find(view, label: "Open"))
        XCTAssertNil(find(view, label: "Back"))
    }

    /// A sheet comes with its scrim: the scrim under it starts at nothing and grows with the sheet.
    func testASheetComesWithItsScrim() throws {
        func redOfHome(freeze: Double?, settle: Double = 0) throws -> Double {
            let view = try hosted(freeze: freeze)
            try press(view, "Sheet")
            spin(settle)
            return try colourAt(view, x: 20, y: 60).red
        }
        let start = try redOfHome(freeze: 0)
        let middle = try redOfHome(freeze: 140)
        let end = try redOfHome(freeze: 280)
        let rest = try redOfHome(freeze: nil, settle: 0.7)
        XCTAssertGreaterThan(start, 0.9, "at the start the page is not dimmed")
        XCTAssertLessThan(middle, start - 0.05, "the scrim is on its way")
        XCTAssertLessThan(end, middle, "and it grows")
        XCTAssertLessThan(end, start - 0.2, "the scrim shows")
        XCTAssertEqual(end, rest, accuracy: 0.02, "the end of the motion is the scrim at rest")
    }
}
#endif

#if canImport(AppKit)
/// The layers of the stack in motion: a layer that goes is drawn while it goes and takes no touch; the
/// screens say whether they are in front.
@MainActor
final class StackLayerMotionTests: XCTestCase {
    private final class Seen { var values: [String: Bool] = [:] }

    private struct Probe: View {
        let name: String
        let seen: Seen
        @Environment(\.screenInFront) private var inFront
        var body: some View {
            Color.gray.frame(width: 100, height: 100).onAppear { seen.values[name] = inFront }
        }
    }

    private func layer(_ id: Int, ghost: Bool = false) -> ModalStackLayer {
        ModalStackLayer(id: id, shape: .sheet, placement: nil, blur: nil, dismissible: true, ghost: ghost)
    }

    /// The page under a layer is not in front, and neither is a layer under another; a layer that goes is not either.
    func testOnlyTheTopOfTheStackIsInFront() {
        let seen = Seen()
        let stack = ModalStack(
            layers: [layer(1), layer(2), layer(3, ghost: true)], margin: 24, motion: nil, dismiss: { _ in },
            page: { Probe(name: "page", seen: seen) }, layer: { Probe(name: "layer\($0.id)", seen: seen) })
        let hosting = NSHostingView(rootView: stack.frame(width: 300, height: 500))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(seen.values, ["page": false, "layer1": false, "layer2": true, "layer3": false])
    }

    /// The colours of a column of the bottom of the screen, where the sheet goes down.
    private func bottom(_ view: NSView) throws -> [Double] {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = Double(rep.pixelsWide) / Double(view.bounds.width)
        return stride(from: 380.0, to: 636.0, by: 8).flatMap { y -> [Double] in
            guard let c = rep.colorAt(x: Int(200 * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return [] }
            return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
        }
    }

    private func pressed(freeze: Double) throws -> NSView {
        let document = try HotlayoutDocument.load(try Contract.json("fixtures/screen-transition-screens.json"))
        let view = host(HotlayoutScreen(document: document, locale: "en").environment(\.stackTransitionFreezeMs, freeze))
        for label in ["Next", "Next", "Read the terms"] {
            XCTAssertTrue(press(try XCTUnwrap(find(view, label: label), label)))
            spin(0.3)
        }
        return view
    }

    /// The terms are a sheet over the page: closing it takes it down. Held in the middle it is still there, drawn by the
    /// stack that no longer holds it, and what is under it is the page a person can use.
    func testASheetThatGoesIsDrawnWhileItGoesAndTakesNoTouch() throws {
        let view = try pressed(freeze: 110)
        let held = try bottom(view)
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Got it"))))
        spin(1.5)
        XCTAssertNil(find(view, label: "Got it"), "the sheet that goes is not in the accessibility tree")
        XCTAssertNotNil(find(view, label: "Finish"), "the page under it is")
        let gone = try bottom(try pressed(freeze: 220).then { v in
            XCTAssertTrue(self.press(try XCTUnwrap(self.find(v, label: "Got it"))))
            self.spin(0.3)
        })
        XCTAssertNotEqual(held, gone, "in the middle of its going the sheet is still drawn, and at the end it is not")
    }
}
#endif

private extension NSView {
    /// Runs `body` on the view and returns it.
    func then(_ body: (NSView) throws -> Void) rethrows -> NSView {
        try body(self)
        return self
    }
}
