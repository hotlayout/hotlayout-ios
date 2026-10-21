import Combine
import SwiftUI
import XCTest

#if canImport(UIKit)
import UIKit
#endif

@testable import HotLayout

/// What the views do across time: a timer that belongs to a view ends with it or with the change
/// that replaced it, reports reach the host once and through its newest handler, a failed picture
/// is asked for again after a while, and the closing of a layer by its scrim.
@MainActor
final class ViewLifetimeTests: XCTestCase {
    private var server: LocalServer?

    override func setUp() async throws { ImageStore.shared.reset() }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        ImageStore.shared.reset()
    }

    /// The motions these tests time are not made when the device asks to reduce motion.
    private func skipUnderReducedMotion() throws {
        #if canImport(UIKit)
        if UIAccessibility.isReduceMotionEnabled { throw XCTSkip("the device asks to reduce motion") }
        #endif
    }

    private func start(_ handler: @escaping (LocalServer.Request) -> LocalServer.Response) throws -> LocalServer {
        let made = try LocalServer(handler: handler)
        server = made
        return made
    }

    // MARK: Timers of a view

    final class Switch: ObservableObject {
        @Published var on = true
    }

    /// A layer sliding out after a drag, which the test can take away before it has left.
    private struct LeavingLayer: View {
        @ObservedObject var shown: Switch
        let dismissed: () -> Void

        var body: some View {
            ZStack {
                Color.white
                if shown.on {
                    ModalLayerView(
                        content: Color.blue.frame(height: 100), shape: .sheet, placement: nil, margin: 24, dismissible: true, isTop: true, blurredBy: 0, exiting: true,
                        dismiss: { _ in dismissed() })
                }
            }
        }
    }

    func testALayerThatSlidOutClosesOnceItHasLeft() {
        var closed = 0
        let held = showScreen(LeavingLayer(shown: Switch(), dismissed: { closed += 1 }), wait: 0.8)
        withExtendedLifetime(held) {}
        XCTAssertEqual(closed, 1)
    }

    func testALayerThatIsGoneBeforeItHasLeftClosesNothing() throws {
        try skipUnderReducedMotion()
        var closed = 0
        let shown = Switch()
        shown.on = false
        let held = showScreen(LeavingLayer(shown: shown, dismissed: { closed += 1 }), wait: 0.3)
        shown.on = true
        runLoop(0.05)
        shown.on = false
        runLoop(0.8)
        withExtendedLifetime(held) {}
        XCTAssertEqual(closed, 0, "the wait for the end of the slide ends with the layer")
    }

    final class Press: ObservableObject {
        @Published var down = false
        /// The drawn width of the box, 200 at rest.
        var width = 0.0
    }

    private struct WidthKey: PreferenceKey {
        static let defaultValue = 0.0
        static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
    }

    /// A box that sinks under the finger and says how wide it is drawn.
    private struct PressedBox: View {
        @ObservedObject var press: Press

        var body: some View {
            PressablePose(kind: .card, pressed: press.down) {
                Color.red.frame(width: 200, height: 200)
                    .background(GeometryReader { proxy in Color.clear.preference(key: WidthKey.self, value: Double(proxy.frame(in: .global).width)) })
            }
            .onPreferenceChange(WidthKey.self) { press.width = $0 }
        }
    }

    func testAReleasedBoxComesBack() throws {
        try skipUnderReducedMotion()
        let press = Press()
        let held = showScreen(PressedBox(press: press), wait: 0.3)
        XCTAssertEqual(press.width, 200, accuracy: 0.01)
        press.down = true
        runLoop(0.3)
        XCTAssertEqual(press.width, 200 * 0.97, accuracy: 0.01, "sunk under the finger")
        press.down = false
        runLoop(0.6)
        withExtendedLifetime(held) {}
        XCTAssertEqual(press.width, 200, accuracy: 0.01, "back after the release")
    }

    func testASecondPressIsNotLetGoByTheReturnOfTheFirst() throws {
        try skipUnderReducedMotion()
        let press = Press()
        let held = showScreen(PressedBox(press: press), wait: 0.3)
        press.down = true
        runLoop(0.01)
        // Released before the way down is over: the return waits for the rest of it ...
        press.down = false
        runLoop(0.01)
        // ... and a new press in that wait keeps the box down.
        press.down = true
        runLoop(0.6)
        withExtendedLifetime(held) {}
        XCTAssertEqual(press.width, 200 * 0.97, accuracy: 0.01, "still sunk under the second press")
    }

    // MARK: A number that leads

    final class Feed: ObservableObject {
        @Published var points = 1000.0
        /// Every number the node was drawn with, frame by frame.
        var shown: [Double] = []
    }

    private struct Counting: View {
        let node: DocumentNode
        @ObservedObject var feed: Feed

        var body: some View {
            ValueTransitioned(node: node, context: HotLayoutTests.Body.context(scope: ["p": .number(feed.points)])) { shown in
                feed.shown.append(shown.stepped["p"]?.numberValue ?? -1)
                return Color.clear.frame(width: 10, height: 10)
            }
        }
    }

    func testANumberLeadsToTheNewValueAndThenStopsDrawing() throws {
        try skipUnderReducedMotion()
        let node = try Harness.node([
            "id": "t", "type": "Text",
            "props": ["content": ["kind": "binding", "path": "p", "fallback": "0", "format": "number"], "animateChanges": true],
        ])
        let feed = Feed()
        let held = showScreen(Counting(node: node, feed: feed), wait: 0.3)
        XCTAssertEqual(feed.shown.last, 1000, "the first show does not lead")
        feed.shown = []
        feed.points = 5000
        runLoop(1.2)
        XCTAssertEqual(feed.shown.first, 1000, "the frame that brings the change starts from the old number")
        XCTAssertTrue(feed.shown.contains { $0 > 1000 && $0 < 5000 }, "\(feed.shown)")
        XCTAssertEqual(feed.shown.last, 5000)
        let frames = feed.shown.count
        runLoop(0.5)
        withExtendedLifetime(held) {}
        XCTAssertEqual(feed.shown.count, frames, "after the last run the timeline stops")
    }

    // MARK: Reports

    final class Host: ObservableObject {
        @Published var generation = 0
    }

    final class Heard {
        var reports: [(generation: Int, report: HotlayoutReport)] = []
    }

    /// A host that draws again with a new `onReport` on every generation.
    private struct ReportingHost: View {
        let document: HotlayoutDocument
        @ObservedObject var host: Host
        let heard: Heard

        var body: some View {
            let generation = host.generation
            var data: DataScope = ["generation": .number(Double(generation))]
            if generation >= 3 { data["late.picture"] = "https://localhost/late.png" }
            return HotlayoutScreen(
                document: document, data: data, locale: "en", onReport: { reports in heard.reports += reports.map { (generation, $0) } })
        }
    }

    func testAReportIsHandedOverOnceAndToTheNewestHandler() throws {
        let image: (String, JSONValue) -> JSONValue = { id, source in ["id": .string(id), "type": "Image", "props": ["source": source, "aspectRatio": "1:1"]] }
        let document = try screenDocument([
            ("a", [image("early", ["kind": "url", "url": "https://localhost/early.png"]), image("late", ["kind": "binding", "path": "late.picture"])])
        ])
        let host = Host()
        let heard = Heard()
        let held = showScreen(ReportingHost(document: document, host: host, heard: heard), wait: 0.5)
        for generation in 1...3 {
            host.generation = generation
            runLoop(0.3)
        }
        withExtendedLifetime(held) {}
        let early = heard.reports.filter { $0.report.reason.contains("localhost/early.png") }
        let late = heard.reports.filter { $0.report.reason.contains("localhost") && !$0.report.reason.contains("early.png") }
        XCTAssertEqual(early.count, 1, "\(heard.reports)")
        XCTAssertEqual(late.count, 1, "\(heard.reports)")
        XCTAssertEqual(late.first?.generation, 3, "a report that comes later reaches the handler of the newest body")
    }

    // MARK: A new document

    final class Documents: ObservableObject {
        @Published var document: HotlayoutDocument
        var shown: [String] = []

        init(_ document: HotlayoutDocument) { self.document = document }
    }

    private struct DocumentHost: View {
        @ObservedObject var documents: Documents

        var body: some View {
            HotlayoutScreen(document: documents.document, locale: "en", onScreenChange: { [documents] in documents.shown.append("\($0.cause):\($0.screenId)") })
        }
    }

    private func screens(_ ids: [String], initial: String, name: String = "n") throws -> HotlayoutDocument {
        try HotlayoutDocument.load([
            "schemaVersion": "9.27.0", "documentId": "d", "name": .string(name), "initialScreenId": .string(initial),
            "screens": .array(ids.map { ["screenId": .string($0), "name": .string($0), "root": ["id": .string("r-\($0)"), "type": "Screen", "props": [:], "children": []]] }),
        ])
    }

    func testANewVersionWithoutTheScreenOnTopStartsTheFlowAgain() throws {
        let documents = Documents(try screens(["a"], initial: "a"))
        let held = showScreen(DocumentHost(documents: documents), wait: 0.4)
        documents.document = try screens(["a"], initial: "a", name: "renamed")
        runLoop(0.3)
        XCTAssertEqual(documents.shown, ["entry:a"], "a new name draws nothing new")
        documents.document = try screens(["b"], initial: "b")
        runLoop(0.3)
        withExtendedLifetime(held) {}
        XCTAssertEqual(documents.shown, ["entry:a", "entry:b"])
    }

    final class Shows: ObservableObject {
        @Published var document: HotlayoutDocument
        @Published var entry: String?
        @Published var generation = 0
        var heard: [(generation: Int, shown: String)] = []

        init(_ document: HotlayoutDocument) { self.document = document }
    }

    /// A host whose handler of the screen-shown event changes with every update it makes.
    private struct ShowHost: View {
        @ObservedObject var shows: Shows

        var body: some View {
            let generation = shows.generation
            HotlayoutScreen(
                document: shows.document, locale: "en", entry: shows.entry,
                onScreenChange: { [shows] in shows.heard.append((generation, "\($0.cause):\($0.screenId)")) })
        }
    }

    func testAShowAfterAnUpdateReachesTheNewestHandler() throws {
        func document(_ ids: [String]) throws -> HotlayoutDocument {
            try HotlayoutDocument.load([
                "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": .string(ids[0]), "entryPoints": ["late": .string(ids.last ?? "")],
                "screens": .array(ids.map { ["screenId": .string($0), "name": .string($0), "root": ["id": .string("r-\($0)"), "type": "Screen", "props": [:], "children": []]] }),
            ])
        }
        let shows = Shows(try document(["a"]))
        let held = showScreen(ShowHost(shows: shows), wait: 0.4)
        shows.generation = 1
        shows.document = try document(["b", "c"])
        runLoop(0.3)
        shows.generation = 2
        shows.entry = "late"
        runLoop(0.3)
        withExtendedLifetime(held) {}
        XCTAssertEqual(shows.heard.map(\.shown), ["entry:a", "entry:b", "entry:c"])
        XCTAssertEqual(shows.heard.map(\.generation), [0, 1, 2], "each show reaches the handler of the update that made it")
    }

    // MARK: Pictures

    func testAFailedPictureIsAskedForAgainAfterItsLifetime() async throws {
        let server = try start { _ in LocalServer.Response(status: 404, headers: ["Content-Length": "0"]) }
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = ImageStore(now: { clock })
        let url = try XCTUnwrap(URL(string: "\(server.base)/missing.png"))
        _ = await store.image(for: url)
        _ = await store.image(for: url)
        XCTAssertEqual(server.requests.count, 1, "within its lifetime a failure is not asked for again")
        clock += ImageStore.failureLifetime + 1
        _ = await store.image(for: url)
        XCTAssertEqual(server.requests.count, 2, "after it, the address is asked for again")
    }

    func testAFailedPictureIsAskedForAgainWhenTheAppBecomesActive() async throws {
        let server = try start { _ in LocalServer.Response(status: 404, headers: ["Content-Length": "0"]) }
        let store = ImageStore()
        let url = try XCTUnwrap(URL(string: "\(server.base)/missing.png"))
        _ = await store.image(for: url)
        #if canImport(UIKit)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        #else
        store.forgetFailures()
        #endif
        _ = await store.image(for: url)
        XCTAssertEqual(server.requests.count, 2)
    }

    func testAPictureIsKeptByTheSideItWasDecodedAt() async throws {
        let server = try start { _ in .data(PNGFile.blank(width: 400, height: 400)) }
        let address = "\(server.base)/same.png"
        let small = ImagePolicy(maxPixelSide: 50, resolve: { URL(string: $0) })
        let large = ImagePolicy(maxPixelSide: 300, resolve: { URL(string: $0) })
        let first = await ImageStore.shared.image(for: try XCTUnwrap(small.resolve(address)))
        let second = await ImageStore.shared.image(for: try XCTUnwrap(large.resolve(address)))
        XCTAssertEqual(Int(max(first?.size.width ?? 0, first?.size.height ?? 0)), 50)
        XCTAssertEqual(Int(max(second?.size.width ?? 0, second?.size.height ?? 0)), 300, "not the picture decoded for the other side")
    }

    // MARK: Closing a layer

    private func flow() throws -> Flow {
        let page: JSONValue = ["screenId": "a", "name": "A", "root": ["id": "ra", "type": "Screen", "props": [:], "children": []]]
        let sheet: JSONValue = ["screenId": "m", "name": "M", "presentation": "modal", "root": ["id": "rm", "type": "Screen", "props": [:], "children": []]]
        let document = try HotlayoutDocument.load(["schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": "a", "screens": [page, sheet]])
        var flow = Flow(document: FlowDocument(document), entry: nil)
        _ = flow.press(["type": "navigate", "params": ["screenId": "m"]])
        return flow
    }

    func testTheScrimClosesTheLayerOnTopAsTheHostAllows() throws {
        var flow = try flow()
        var asked: [(NavigationEvent.Kind, String, String, String)] = []
        let refused = flow.dismissLayer { kind, from, to, action in
            asked.append((kind, from, to, action.type))
            return false
        }
        XCTAssertNil(refused)
        XCTAssertEqual(flow.stack.map(\.screenId), ["a", "m"], "the host's no leaves the stack")
        let shown = flow.dismissLayer { _, _, _, _ in true }
        XCTAssertEqual(flow.stack.map(\.screenId), ["a"])
        XCTAssertEqual(shown?.cause, .back)
        XCTAssertEqual(shown?.screenId, "a")
        XCTAssertEqual(asked.first?.0, .back)
        XCTAssertEqual(asked.first?.1, "m")
        XCTAssertEqual(asked.first?.2, "a")
        XCTAssertEqual(asked.first?.3, "navigate.back")
        XCTAssertNil(flow.dismissLayer { _, _, _, _ in true }, "on the first screen there is no layer to close")
        XCTAssertEqual(flow.stack.map(\.screenId), ["a"])
    }
}
