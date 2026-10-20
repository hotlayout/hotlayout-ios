import SwiftUI
import XCTest

@testable import HotLayout

/// What the real node does with a field, drawn and read back. The rule tables prove the rules; these
/// prove that `NodeView` and the widgets call them (a merge once dropped the call to the motion of a
/// node and every table kept passing).
@MainActor
final class WiringTests: XCTestCase {
    private let slide: JSONValue = ["kind": "float", "axis": "horizontal", "amplitude": 12, "duration": 2000]

    private func render(_ node: DocumentNode, at elapsed: Double) -> ProgressPixels.Image {
        let view = NodeView(node: node, context: Harness.context(rightToLeft: false), placement: .natural)
            .environment(\.nodeMotionClockMs, elapsed)
            .padding(40).background(Color.white)
        return ProgressPixels.render(view)
    }

    private func isRed(_ pixels: ProgressPixels.Image, _ x: Int, _ y: Int) -> Bool {
        let c = ProgressPixels.color(pixels, x: x, y: y)
        return c.red > 0.8 && c.green < 0.4 && c.alpha > 0.5
    }

    /// A node with `motion` moves when drawn by `NodeView`, with no help from the test.
    func testNodeViewPaintsTheMotionOfItsNode() throws {
        let node = try Harness.node(Harness.box("m", width: 20, height: 20, color: "#ff0000", fields: [("motion", slide)]))
        let rest = render(node, at: 0)
        let moved = render(node, at: 500)
        XCTAssertTrue(isRed(rest, 50, 50) && !isRed(rest, 68, 50), "at rest the box is where it is")
        XCTAssertTrue(isRed(moved, 68, 50), "a quarter cycle later the real node is painted 12 points to the end")
        XCTAssertFalse(isRed(moved, 42, 50))
    }

    func testNodeWithoutMotionStandsStill() throws {
        let node = try Harness.node(Harness.box("m", width: 20, height: 20, color: "#ff0000"))
        XCTAssertTrue(isRed(render(node, at: 500), 50, 50))
        XCTAssertFalse(isRed(render(node, at: 500), 68, 50))
    }

    /// A layer of a `Stack` moves too, after its own turn.
    func testStackLayerMoves() throws {
        let stack = try Harness.node(.object(JSONObject([
            ("id", "s"), ("type", "Stack"), ("props", ["alignHorizontal": "start", "alignVertical": "start"]),
            ("children", [
                Harness.box("size", width: 100, height: 40, color: "#ffffff"),
                Harness.box("dot", width: 20, height: 20, color: "#ff0000", fields: [("layer", ["alignHorizontal": "start", "alignVertical": "start"]), ("motion", slide)]),
            ]),
        ])))
        let rest = render(stack, at: 0)
        let moved = render(stack, at: 500)
        // The layer stands at the start corner of the stack: x from 40 to 60 with the margin.
        XCTAssertTrue(isRed(rest, 50, 50) && !isRed(rest, 68, 50))
        XCTAssertTrue(isRed(moved, 68, 50), "the layer is painted 12 points to the end a quarter cycle later")
        XCTAssertFalse(isRed(moved, 42, 50))
    }

    // MARK: Numbers of a list from data

    private func numberedText(_ id: String) -> JSONValue {
        .object(JSONObject([("id", .string(id)), ("type", "Text"), ("props", ["content": ["kind": "literal", "value": "Item"], "marker": "number"])]))
    }

    private func picture(_ node: DocumentNode, scope: DataScope) -> ProgressPixels.Image {
        ProgressPixels.render(NodeView(node: node, context: Body.context(scope: scope), placement: .stretched).frame(width: 200).padding(10).background(Color.white))
    }

    /// The template of a list from data that is a numbered text counts the INSTANCES: three records
    /// draw «1.», «2.», «3.», the same pixels as three numbered texts one after another.
    func testRepeaterNumbersItsInstances() throws {
        let repeater = try Harness.node(.object(JSONObject([
            ("id", "list"), ("type", "Repeater"), ("props", ["source": "things", "item": "thing", "gap": "none"]), ("children", [numberedText("t")]),
        ])))
        let column = try Harness.node(.object(JSONObject([
            ("id", "col"), ("type", "Column"), ("props", ["gap": "none"]), ("children", [numberedText("a"), numberedText("b"), numberedText("c")]),
        ])))
        let records: JSONValue = [["id": 1], ["id": 2], ["id": 3]]
        let listed = picture(repeater, scope: ["things": records])
        let reference = picture(column, scope: [:])
        XCTAssertEqual(listed.width, reference.width)
        XCTAssertEqual(listed.height, reference.height, "three lines either way")
        var differing = 0
        for y in 0..<listed.height { for x in 0..<listed.width where ProgressPixels.color(listed, x: x, y: y) != ProgressPixels.color(reference, x: x, y: y) { differing += 1 } }
        XCTAssertEqual(differing, 0, "the list from data numbers 1, 2, 3 like the texts one after another")
    }
}
