#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// What the real screen hands to the host, pressed through the accessibility interface: the
/// order of a press, the host's veto on navigation, a swipe button that waits for an `async`
/// handler, and reports that arrive once each, also after the parent draws again.
@MainActor
final class HostWiringTests: XCTestCase {
    final class Recorder {
        var log: [String] = []
        var reports: [HotlayoutReport] = []
    }

    func document(_ screens: [(String, [JSONValue])]) throws -> HotlayoutDocument {
        try loadDocument([
            "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": .string(screens[0].0),
            "screens": .array(screens.map { id, children in
                ["screenId": .string(id), "name": .string(id), "root": ["id": .string("root-\(id)"), "type": "Screen", "props": [:], "children": .array(children)]]
            }),
        ])
    }

    func button(_ id: String, _ label: String, _ action: JSONValue, extra: JSONObject = JSONObject()) -> JSONValue {
        var props: JSONObject = ["label": ["kind": "literal", "value": .string(label)], "variant": "ghost", "fullWidth": false, "action": action]
        for (key, value) in extra { props[key] = value }
        return ["id": .string(id), "type": "Button", "props": .object(props)]
    }

    func text(_ id: String, _ value: String) -> JSONValue {
        ["id": .string(id), "type": "Text", "props": ["content": ["kind": "literal", "value": .string(value)], "variant": "bodyM"]]
    }

    /// Whether a text is on the screen (a static text carries it as its value).
    func shows(_ view: NSView, _ value: String) -> Bool {
        elements(view).contains { text($0, "accessibilityLabel") == value || text($0, "accessibilityValue") == value }
    }

    func testAPressHandsHapticThenTrackThenTheAction() throws {
        let recorder = Recorder()
        let doc = try document([("a", [button("buy", "Buy", ["type": "redeem", "haptic": "success", "track": ["event": "redeemed"]])])])
        let view = host(HotlayoutScreen(
            document: doc, locale: "en",
            onAction: { action, _ in recorder.log.append("action \(action.type)") },
            onTrack: { event, _ in recorder.log.append("track \(event.event)") },
            onHaptic: { word, _ in recorder.log.append("haptic \(word.rawValue)") }
        ))
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Buy"))))
        spin(0.2)
        XCTAssertEqual(recorder.log, ["haptic success", "track redeemed", "action redeem"])
    }

    func testTheHostCanCancelANavigation() throws {
        let recorder = Recorder()
        var allow = false
        let doc = try document([
            ("a", [button("go", "Go", ["type": "navigate", "params": ["screenId": "b"], "track": ["event": "went"]])]),
            ("b", [text("title", "Second screen")]),
        ])
        let view = host(HotlayoutScreen(
            document: doc, locale: "en",
            onTrack: { event, _ in recorder.log.append("track \(event.event)") },
            onNavigate: { event in
                recorder.log.append("navigate \(event.kind.rawValue) \(event.from)→\(event.to) \(event.action.type) \(event.source.nodeId)")
                return allow
            },
            onScreenChange: { shown in recorder.log.append("shown \(shown.screenId) \(shown.cause.rawValue)") }
        ))
        recorder.log = []
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Go"))))
        spin(0.3)
        XCTAssertEqual(recorder.log, ["track went", "navigate push a→b navigate go"], "the analytics event goes, the change does not")
        XCTAssertFalse(shows(view, "Second screen"))

        allow = true
        recorder.log = []
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Go"))))
        spin(0.5)
        XCTAssertEqual(recorder.log, ["track went", "navigate push a→b navigate go", "shown b forward"])
        XCTAssertTrue(shows(view, "Second screen"))
    }

    func testASwipeButtonWaitsForAnAsyncHandler() throws {
        let recorder = Recorder()
        var release: CheckedContinuation<Void, Never>?
        let doc = try document([("a", [button("pay", "Swipe to pay", ["type": "redeem"], extra: ["confirm": "swipe"])])])
        let view = host(HotlayoutScreen(document: doc, locale: "en", onAction: { action, _ async in
            recorder.log.append("action \(action.type)")
            await withCheckedContinuation { release = $0 }
            recorder.log.append("done")
        }))
        let swipe = try XCTUnwrap(find(view, label: "Swipe to pay"))
        XCTAssertTrue(press(swipe))
        spin(0.3)
        XCTAssertEqual(recorder.log, ["action redeem"])
        // Busy while the handler runs: a press does nothing.
        _ = press(swipe)
        spin(0.3)
        XCTAssertEqual(recorder.log, ["action redeem"])
        // The handler returns: the thumb comes back at once, long before the eight seconds.
        release?.resume()
        spin(0.4)
        XCTAssertEqual(recorder.log, ["action redeem", "done"])
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Swipe to pay"))))
        spin(0.3)
        XCTAssertEqual(recorder.log.filter { $0 == "action redeem" }.count, 2, "the button acts again")
        release?.resume()
        spin(0.1)
    }

    /// A parent that draws again with new arguments for the screen.
    final class Parent: ObservableObject {
        @Published var back = "Back"
    }

    struct ParentView: View {
        @ObservedObject var parent: Parent
        let document: HotlayoutDocument
        let recorder: Recorder

        var body: some View {
            HotlayoutScreen(document: document, locale: "en", labels: ScreenLabels(back: parent.back), onReport: { recorder.reports += $0 })
        }
    }

    func testReportsArriveOnceEachAlsoAfterThePressAndAfterTheParentDrawsAgain() throws {
        let recorder = Recorder()
        let parent = Parent()
        let doc = try document([("a", [
            ["id": "odd", "type": "Mystery", "props": [:], "children": [text("inside", "Hello")]],
            button("go", "Go", ["type": "redeem", "track": "not an event"]),
        ])])
        let view = host(ParentView(parent: parent, document: doc, recorder: recorder))
        spin(0.3)
        let first = recorder.reports
        XCTAssertFalse(first.isEmpty, "a report of drawing reaches the host")
        XCTAssertEqual(Set(first).count, first.count)

        parent.back = "Zurück"
        spin(0.4)
        XCTAssertEqual(recorder.reports, first, "a parent that draws again neither repeats nor loses reports")

        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Go"))))
        spin(0.3)
        let added = recorder.reports.dropFirst(first.count)
        XCTAssertEqual(added.map(\.location), ["screen “a”: node “go”: action: track"], "a report of a press arrives after the press, with its place")
    }

    /// A node is a button on the screen exactly when `PressTarget.actsOnPress` says so: a list row
    /// with an action (`none` too, as a button), a card whose action does something.
    func testWhatIsAButtonIsWhatTheRuleSays() throws {
        let doc = try document([("a", [
            ["id": "row", "type": "ListTile", "props": ["title": ["kind": "literal", "value": "Row with none"], "action": ["type": "none"]]],
            ["id": "card", "type": "Container", "props": ["action": ["type": "none"]], "children": [text("t1", "Card with none")]],
            ["id": "tracked", "type": "Container", "props": ["action": ["type": "none", "track": ["event": "seen"]]], "children": [text("t2", "Card with track")]],
        ])])
        let view = host(HotlayoutScreen(document: doc, locale: "en"))
        func role(_ label: String) -> String? {
            elements(view).first { text($0, "accessibilityLabel") == label }.flatMap { text($0, "accessibilityRole") }
        }
        let rows = [("row", "Row with none"), ("card", "Card with none"), ("tracked", "Card with track")]
        for (id, label) in rows {
            let node = try XCTUnwrap(doc.screens[0].root.children.first { $0.id == id })
            XCTAssertEqual(role(label) == "AXButton", PressTarget.actsOnPress(node), "\(id): \(role(label) ?? "no element")")
        }
    }
}
#endif


#if canImport(AppKit)
/// Every widget the reader knows is drawn by its own view: none of them reaches the rule for an
/// unknown widget.
@MainActor
final class KnownWidgetsDrawnTests: XCTestCase {
    func testEveryKnownWidgetIsDrawn() throws {
        func node(_ type: String, _ children: [JSONValue] = []) -> JSONValue {
            ["id": .string("n-\(type)"), "type": .string(type), "props": [:], "children": .array(children)]
        }
        let parents: [String: String] = ["Tab": "Tabs", "NavItem": "NavBar"]
        var children: [JSONValue] = []
        for type in DocumentReader.knownWidgets.sorted() where type != "Screen" {
            if parents[type] != nil { continue }
            let inner = parents.filter { $0.value == type }.map { node($0.key) }
            children.append(node(type, inner))
        }
        let document = try loadDocument([
            "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": "a",
            "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": .array(children)]]],
        ])
        var reports: [HotlayoutReport] = []
        _ = host(HotlayoutScreen(document: document, locale: "en", onReport: { reports += $0 }))
        spin(0.5)
        XCTAssertEqual(reports.filter { $0.kind == .unknownWidget }, [])
    }
}
#endif
