import SwiftUI
import XCTest

@testable import HotLayout

/// A node that fades and is out of the layout takes no place and no gap in a column or a list:
/// it draws no view at all. And a fade ends by itself, in the layout as on the clock.
@MainActor
final class VisibilityFadeLayoutTests: XCTestCase {
    private static let blue: JSONValue = ["kind": "color", "color": ["value": "#0000ff"]]
    private static let green: JSONValue = ["kind": "color", "color": ["value": "#00ff00"]]

    private func box(_ id: String, _ color: JSONValue, fades: Bool = false, path: String = "flag") -> JSONValue {
        var object = JSONObject([
            ("id", .string(id)), ("type", "Container"), ("props", ["direction": "column", "gap": "none"]),
            ("style", ["width": 40, "height": 20, "background": color]), ("children", []),
        ])
        if fades {
            object["visibleIf"] = ["path": .string(path), "op": "isTrue"]
            object[VisibilityFade.field] = "fade"
        }
        return .object(object)
    }

    private var gap: Int { Int(Harness.context(rightToLeft: false).resolver.spacing("md") ?? 0) }

    @MainActor
    private func draw(_ node: JSONValue, scope: DataScope) throws -> Pixels {
        var context = Harness.context(rightToLeft: false)
        context.scope = scope
        let view = NodeView(node: ScreenSim.node(node), context: context, placement: .natural)
            .frame(width: 100, height: 120, alignment: .topLeading).background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return Pixels(try XCTUnwrap(renderer.cgImage))
    }

    @MainActor
    func testAHiddenFadingChildOfAColumnTakesNoGap() throws {
        XCTAssertGreaterThan(gap, 5)
        let column: JSONValue = [
            "id": "p", "type": "Column", "props": ["gap": "md"],
            "children": [box("a", Self.green), box("b", Self.blue, fades: true), box("c", Self.green)],
        ]
        let hidden = try draw(column, scope: ["flag": false])
        XCTAssertTrue(hidden.isColor(10, 20 + gap + 5, "#00ff00"), "the next child stands one gap below the first")
        XCTAssertFalse(hidden.isColor(10, 20 + gap + 5, "#0000ff"))
        let shown = try draw(column, scope: ["flag": true])
        XCTAssertTrue(shown.isColor(10, 20 + gap + 5, "#0000ff"), "shown: the node is in its place")
    }

    @MainActor
    func testAHiddenRowOfAFadingTemplateLeavesNoHole() throws {
        let list: JSONValue = [
            "id": "p", "type": "Repeater", "props": ["source": "rows", "item": "row", "direction": "column", "gap": "md"],
            "children": [box("t", Self.green, fades: true, path: "row.show")],
        ]
        let rows: JSONValue = [["show": true], ["show": false], ["show": true]]
        let pixels = try draw(list, scope: ["rows": rows])
        XCTAssertTrue(pixels.isColor(10, 10, "#00ff00"))
        XCTAssertTrue(pixels.isColor(10, 20 + gap + 5, "#00ff00"), "the third row closes up under the first")
        XCTAssertFalse(pixels.isColor(10, 40 + gap + 5, "#00ff00"), "nothing below the two shown rows")
    }

    #if canImport(AppKit)
    private final class Model: ObservableObject {
        @Published var flag = true
    }

    private struct Host: View {
        @ObservedObject var model: Model
        let node: DocumentNode
        var body: some View {
            var context = Harness.context(rightToLeft: false)
            context.scope = ["flag": .bool(model.flag)]
            return NodeView(node: node, context: context, placement: .natural).fixedSize()
        }
    }

    private func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// A hosted column, in a window off every screen and never ordered in.
    @MainActor
    func testAFadeLeavesTheLayoutWhenItEndsAndAnEntryWaitsOutOfIt() throws {
        let node = ScreenSim.node([
            "id": "p", "type": "Column", "props": ["gap": "md"],
            "children": [box("a", Self.green), box("b", Self.blue, fades: true)],
        ])
        let model = Model()
        let hosting = NSHostingView(rootView: Host(model: model, node: node))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        pump(0.3)
        let both = 40 + CGFloat(gap)
        XCTAssertEqual(hosting.fittingSize.height, both, accuracy: 0.5)

        model.flag = false
        pump(0.05)
        XCTAssertEqual(hosting.fittingSize.height, both, accuracy: 0.5, "while it fades out the node keeps its place")
        pump(0.6)
        XCTAssertEqual(hosting.fittingSize.height, 20, accuracy: 0.5, "after the fade it is out of the layout, with its gap")

        model.flag = true
        pump(0.05)
        XCTAssertEqual(hosting.fittingSize.height, 20, accuracy: 0.5, "an appearing node waits out of the layout")
        pump(0.6)
        XCTAssertEqual(hosting.fittingSize.height, both, accuracy: 0.5, "then enters it")
    }
    #endif
}
