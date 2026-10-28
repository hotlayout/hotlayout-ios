#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// The real carousel view, hosted in a window: the value under `stopPath` changes twice and the row
/// follows each change to its stop. The controller must be given the NEW value: a closure of
/// `onChange` that read the value from the view it captured saw the previous one, and the row went
/// back to the stop before.
@MainActor
final class CarouselStopViewTests: XCTestCase {
    private final class Model: ObservableObject {
        @Published var value: JSONValue? = .number(0)
    }

    private struct Host: View {
        @ObservedObject var model: Model
        var body: some View {
            let setup = CarouselSetup(
                spec: CarouselSpec(perView: 1, peek: nil, indicator: .none), peek: 0, gap: 0, padding: .zero,
                vertical: .center, rightToLeft: false, dotSize: 8, dotGap: 8, indicatorGap: 8, dotColor: .black,
                memory: nil, memoryKey: "k", stopPath: "account.cardIndex", stopValue: model.value, write: { _, _ in })
            CarouselView(setup: setup, count: 3, knownViewport: 200) { index, width in
                Color.gray.frame(width: width ?? 200, height: 40).id("card-\(index)")
            }
            .frame(width: 200, height: 60)
        }
    }

    private func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func scrollOffset(in view: NSView) -> CGFloat? {
        if let scroll = view as? NSScrollView { return scroll.contentView.bounds.origin.x }
        for child in view.subviews { if let found = scrollOffset(in: child) { return found } }
        return nil
    }

    func testTheRowFollowsEveryChangeOfTheValueToItsStop() throws {
        let model = Model()
        let hosting = NSHostingView(rootView: Host(model: model))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 200, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // Off every screen and never ordered in: nothing appears on the screen of the person running the tests.
        pump(0.5)
        XCTAssertEqual(try XCTUnwrap(scrollOffset(in: hosting)), 0, accuracy: 1)

        model.value = .number(1)
        pump(1)
        XCTAssertEqual(try XCTUnwrap(scrollOffset(in: hosting)), 200, accuracy: 1, "the first change: stop 1")

        model.value = .number(2)
        pump(1)
        XCTAssertEqual(try XCTUnwrap(scrollOffset(in: hosting)), 400, accuracy: 1, "the second change: stop 2, not back to 1")

        model.value = .number(0)
        pump(1)
        XCTAssertEqual(try XCTUnwrap(scrollOffset(in: hosting)), 0, accuracy: 1, "back to the start")
    }
}
#endif
