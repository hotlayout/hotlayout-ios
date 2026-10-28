import SwiftUI
import XCTest

@testable import HotLayout

/// A node that fades when its `visibleIf` changes (`visibilityTransition: 'fade'`) against
/// `visibility-fade/visibility-fade-cases.json`: the two curves, the timeline of one node with its
/// interruptions, the pair of neighbours, the changes that are made at once, how the field is read,
/// the data of the block in the artifact, and the frame of the contract with its phases at chosen
/// moments. `documentCases` is the table of the builder's validator and is not run here.
final class VisibilityFadeCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/visibility-fade/visibility-fade-cases.json")

    private static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    private struct Change {
        let at: Double
        let shown: Bool
    }

    private static func changes(_ value: JSONValue?) -> [Change] {
        (value?.arrayValue ?? []).map { Change(at: $0["at"]?.numberValue ?? 0, shown: $0["shown"]?.boolValue ?? false) }
    }

    /// The state after a chain of changes, every one made by a transition.
    private static func state(after changes: [Change], from shown: Bool, until: Double) -> VisibilityFade.State {
        var state = VisibilityFade.rest(shown: shown)
        for change in changes where change.at <= until { state = VisibilityFade.change(state, shown: change.shown, at: change.at, animate: true) }
        return state
    }

    func testEveryGroupIsRun() {
        let groups = (Self.table.objectValue ?? JSONObject()).filter { $0.key.hasSuffix("Cases") && $0.value.arrayValue != nil }.map(\.key)
        XCTAssertEqual(
            Set(groups), ["curveCases", "timelineCases", "pairCases", "animateCases", "fieldCases", "documentCases", "screenCases"],
            "a group of the table that this reader does not run")
    }

    func testTheBlockOfTheArtifact() throws {
        let block = try XCTUnwrap(try Contract.json("screen-schema.json")["x-visibilityFade"])
        XCTAssertEqual(block["field"]?.stringValue, VisibilityFade.field)
        XCTAssertEqual(block["words"], ["fade"])
        XCTAssertEqual(block["out"]?["durationMs"]?.numberValue, VisibilityFade.outMs)
        XCTAssertEqual(block["in"]?["durationMs"]?.numberValue, VisibilityFade.inMs)
        XCTAssertEqual(block["in"]?["delayMs"]?.numberValue, VisibilityFade.delayMs)
        func curve(_ value: JSONValue?) -> VisibilityFade.Curve? {
            let numbers = (value?.arrayValue ?? []).compactMap(\.numberValue)
            return numbers.count == 4 ? VisibilityFade.Curve(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3]) : nil
        }
        XCTAssertEqual(curve(block["out"]?["curve"]), VisibilityFade.outCurve)
        XCTAssertEqual(curve(block["in"]?["curve"]), VisibilityFade.inCurve)
        XCTAssertEqual(VisibilityFade.delayMs, VisibilityFade.outMs, "a pair is never in the layout together")
    }

    func testCurves() {
        let rows = Contract.rows(Self.table, "curveCases")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            let curve = row["curve"]?.stringValue == "out" ? VisibilityFade.outCurve : VisibilityFade.inCurve
            XCTAssertEqual(VisibilityFade.bezier(curve, at: row["x"]?.numberValue ?? 0), row["y"]?.numberValue ?? -1, accuracy: 0.001, Self.name(row))
        }
    }

    func testTimelines() {
        let rows = Contract.rows(Self.table, "timelineCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            let changes = Self.changes(row["changes"])
            for probe in row["probes"]?.arrayValue ?? [] {
                let at = probe["at"]?.numberValue ?? 0
                let frame = VisibilityFade.frame(Self.state(after: changes, from: row["shown"]?.boolValue ?? false, until: at), at: at)
                let label = "\(Self.name(row)) at \(at)"
                XCTAssertEqual(frame.phase.rawValue, probe["phase"]?.stringValue, label)
                XCTAssertEqual(frame.inLayout, probe["inLayout"]?.boolValue, label)
                XCTAssertEqual(frame.interactive, probe["interactive"]?.boolValue, label)
                XCTAssertEqual(frame.opacity, probe["opacity"]?.numberValue ?? -1, accuracy: 0.001, label)
            }
        }
    }

    func testPairsOfNeighbours() {
        let rows = Contract.rows(Self.table, "pairCases")
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            let at = row["at"]?.numberValue ?? 0
            func chain(_ to: Bool) -> [Change] {
                var list = [Change(at: at, shown: to)]
                if let back = row["back"]?.numberValue { list.append(Change(at: back, shown: !to)) }
                return list
            }
            var previous: (leaving: Bool, appearing: Bool)?
            var layoutChanges: [Double] = []
            for probe in (row["probes"]?.arrayValue ?? []).compactMap(\.numberValue) {
                let leaving = VisibilityFade.frame(Self.state(after: chain(false), from: true, until: probe), at: probe).inLayout
                let appearing = VisibilityFade.frame(Self.state(after: chain(true), from: false, until: probe), at: probe).inLayout
                XCTAssertFalse(leaving && appearing, "both in the layout at \(probe): \(Self.name(row))")
                if let before = previous, before.leaving != leaving || before.appearing != appearing {
                    XCTAssertTrue(before.leaving != leaving && before.appearing != appearing, "both change together at \(probe): \(Self.name(row))")
                    layoutChanges.append(probe)
                }
                previous = (leaving, appearing)
            }
            XCTAssertEqual(layoutChanges, row["layoutChangesAt"]?.numberValue.map { [$0] } ?? [], Self.name(row))
        }
    }

    func testChangesMadeAtOnce() {
        let rows = Contract.rows(Self.table, "animateCases")
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            var start = VisibilityFade.rest(shown: row["shown"]?.boolValue ?? false)
            var at = 0.0
            if let midway = row["midway"] {
                at = midway["at"]?.numberValue ?? 0
                start = VisibilityFade.change(start, shown: midway["shown"]?.boolValue ?? false, at: 0, animate: true)
            }
            let frame = VisibilityFade.frame(VisibilityFade.change(start, shown: row["to"]?.boolValue ?? false, at: at, animate: false), at: at)
            XCTAssertEqual(frame.phase.rawValue, row["phase"]?.stringValue, Self.name(row))
            XCTAssertEqual(frame.inLayout, row["inLayout"]?.boolValue, Self.name(row))
            XCTAssertEqual(frame.opacity, row["opacity"]?.numberValue ?? -1, accuracy: 0.001, Self.name(row))
        }
    }

    func testReadingTheField() {
        let rows = Contract.rows(Self.table, "fieldCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            var fields = JSONObject()
            if let value = row["value"] { fields[VisibilityFade.field] = value }
            let node = DocumentNode(id: "n", type: "Text", fields: fields)
            XCTAssertEqual(VisibilityFade.word(of: node), row["reads"]?.stringValue, Self.name(row))
        }
    }

    // MARK: Which nodes read the field

    private func node(_ type: String, _ extra: [(String, JSONValue)] = [], id: String = "n", children: [DocumentNode] = []) -> DocumentNode {
        DocumentNode(
            id: id, type: type, fields: JSONObject([("visibleIf", true), (VisibilityFade.field, "fade")] + extra), children: children)
    }

    func testTheZonesOfTheScreenReadNoFade() {
        let body = DocumentNode(id: "body", type: "Text")
        func parent(_ children: [DocumentNode]) -> DocumentNode { DocumentNode(id: "root", type: "Screen", children: children) }
        let first = node("AppBar", id: "bar")
        XCTAssertTrue(VisibilityFade.isZoneNode(first, parent: parent([first, body])), "the app bar of the screen")
        let later = node("AppBar", id: "bar")
        XCTAssertFalse(VisibilityFade.isZoneNode(later, parent: parent([body, later])), "an app bar that is not the first child is no zone: it fades")
        XCTAssertFalse(VisibilityFade.isZoneNode(first, parent: DocumentNode(id: "c", type: "Column", children: [first])), "an app bar inside a column")
        XCTAssertTrue(VisibilityFade.isZoneNode(node("NavBar"), parent: nil))
        XCTAssertTrue(VisibilityFade.isZoneNode(node("NavItem"), parent: nil))
        XCTAssertTrue(VisibilityFade.isZoneNode(node("Button", [("pin", "bottom")]), parent: nil), "a pinned block")
        XCTAssertTrue(VisibilityFade.isZoneNode(node("Container", [("pin", "top")]), parent: nil), "a node of the top zone")
        XCTAssertFalse(VisibilityFade.isZoneNode(node("Text"), parent: parent([body])))
        XCTAssertTrue(VisibilityFade.reads(node("Text")))
        XCTAssertFalse(VisibilityFade.reads(node("Container", [("pin", "top")])))
        XCTAssertFalse(VisibilityFade.reads(node("Button", [("pin", "bottom")])))
        XCTAssertFalse(VisibilityFade.reads(node("NavBar")))
        XCTAssertFalse(VisibilityFade.reads(node("AppBar"), inZone: true), "the app bar the screen draws as its zone")
        XCTAssertTrue(VisibilityFade.reads(node("AppBar")), "an app bar that is no zone")
        XCTAssertFalse(VisibilityFade.reads(DocumentNode(id: "n", type: "Text", fields: JSONObject([(VisibilityFade.field, "fade")]))), "no condition: nothing to change")
    }

    // MARK: What a node remembers between draws

    func testALanguageOrWidthClassChangeIsNoTransition() {
        let holder = VisibilityFadeHolder(shown: true, context: "compact|en", now: 0)
        holder.sync(shown: false, context: "compact|uk", now: 10, animate: true)
        XCTAssertEqual(holder.frame(at: 10).phase, .hidden, "the language changed with the condition: at once")
        holder.sync(shown: true, context: "compact|uk", now: 20, animate: true)
        XCTAssertEqual(holder.frame(at: 20).phase, .waiting, "the same context: a transition")
        holder.sync(shown: false, context: "medium|uk", now: 30, animate: true)
        XCTAssertEqual(holder.frame(at: 30).phase, .hidden, "the width class changed: at once")
    }

    func testReducedMotionIsAtOnce() {
        let holder = VisibilityFadeHolder(shown: true, context: "c", now: 0)
        holder.sync(shown: false, context: "c", now: 5, animate: false)
        XCTAssertEqual(holder.frame(at: 5).phase, .hidden)
        holder.sync(shown: true, context: "c", now: 6, animate: false)
        XCTAssertEqual(holder.frame(at: 6).phase, .shown)
        XCTAssertNil(holder.endsAt)
    }

    func testTheEndOfATransitionIsTheEndOfTheLastPhase() {
        let holder = VisibilityFadeHolder(shown: false, context: "c", now: 0)
        holder.sync(shown: true, context: "c", now: 0, animate: true)
        XCTAssertEqual(holder.endsAt ?? -1, 280, accuracy: 0.001, "a wait of 120 and a fade of 160")
    }

    // MARK: The frame of the contract

    func testTheFrame() throws {
        let rows = Contract.rows(Self.table, "screenCases")
        XCTAssertEqual(rows.count, 1)
        let document = try Contract.json("fixtures/visibility-fade-screens.json")
        let children = document["screens"]?.arrayValue?.first?["root"]?["children"]?.arrayValue ?? []
        for row in rows {
            var sim = ScreenSim(nodes: children, layers: DataLayers(session: [:], data: ["account.cardIndex": 0]))
            let faded = Self.fadingIds(children)
            XCTAssertFalse(faded.isEmpty)
            var states = Dictionary(uniqueKeysWithValues: faded.map { ($0, VisibilityFade.rest(shown: sim.isShown($0))) })
            sim.press(row["press"]?.stringValue ?? "")
            for id in faded { states[id] = VisibilityFade.change(states[id]!, shown: sim.isShown(id), at: 0, animate: true) }
            for probe in row["probes"]?.arrayValue ?? [] {
                let at = probe["at"]?.numberValue ?? 0
                var seen = Set<String>()
                for phase in ["shown", "leaving", "hidden", "waiting", "entering"] {
                    for id in (probe[phase]?.arrayValue ?? []).compactMap(\.stringValue) {
                        XCTAssertEqual(VisibilityFade.frame(states[id]!, at: at).phase.rawValue, phase, "\(id) at \(at)")
                        seen.insert(id)
                    }
                }
                XCTAssertEqual(seen, Set(faded), "the probe names every fading node at \(at)")
            }
        }
    }

    private static func fadingIds(_ nodes: [JSONValue]) -> [String] {
        nodes.flatMap { node -> [String] in
            let own = node[VisibilityFade.field]?.stringValue == "fade" ? [node["id"]?.stringValue ?? ""] : []
            return own + fadingIds(node["children"]?.arrayValue ?? [])
        }
    }

    // MARK: The real node

    @MainActor
    private func render(shown: Bool) throws -> Pixels {
        let blue: JSONValue = ["kind": "color", "color": ["value": "#0000ff"]]
        let node = ScreenSim.node(
            .object([
                "id": "box", "type": "Container", "props": ["direction": "column", "gap": "none"],
                "style": ["width": 40, "height": 20, "background": blue], "children": [],
                "visibleIf": ["path": "flag", "op": "isTrue"], VisibilityFade.field: "fade",
            ]))
        var context = Harness.context(rightToLeft: false)
        context.scope = ["flag": .bool(shown)]
        let view = NodeView(node: node, context: context, placement: .natural).padding(10).background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return Pixels(try XCTUnwrap(renderer.cgImage))
    }

    @MainActor
    func testANodeAtRestFollowsItsCondition() throws {
        XCTAssertTrue(try render(shown: true).isColor(25, 15, "#0000ff"), "shown: drawn")
        XCTAssertFalse(try render(shown: false).isColor(25, 15, "#0000ff"), "hidden: not in the layout")
    }

    @MainActor
    func testTheFrameDraws() throws {
        let document = try HotlayoutDocument.load(try Contract.json("fixtures/visibility-fade-screens.json"))
        let entry = try XCTUnwrap(document.screens.first)
        var context = Harness.context(rightToLeft: false)
        context.scope = ["account.cardIndex": .number(0)]
        let renderer = ImageRenderer(content: ScreenRootView(root: entry.root, context: context).frame(width: 393, height: 852))
        renderer.scale = 1
        XCTAssertNotNil(renderer.cgImage)
    }
}
