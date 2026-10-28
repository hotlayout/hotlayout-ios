import SwiftUI
import XCTest

@testable import HotLayout

/// The carousel that tells its active stop (`carousel.stopPath`) against the `stop…` groups of
/// `carousel/carousel-cases.json`: how the path is read, which stop a value shows, where a change
/// of the value goes, what is written when a scroll settles, the data of the block in the artifact,
/// and the rows of a whole screen (show, swipe, hold and release, own dots, reduced motion).
///
/// The scroll of the screen is driven through the controller the view uses and a stand-in of the
/// scroll view (a stop jump sets the offset and reports it), the way a layout-less test must.
/// `stopDocumentCases` is the table of the builder's validator and is not run here.
final class CarouselStopCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/carousel/carousel-cases.json")

    private static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    private static func value(_ json: JSONValue?) -> JSONValue? { json.flatMap { $0.isNull ? nil : $0 } }

    func testPath() {
        let rows = Contract.rows(Self.table, "stopPathCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let node = ScreenSim.node(.object(["type": row["type"] ?? .null, "props": row["props"] ?? .null]))
            XCTAssertEqual(CarouselStop.path(of: node), row["expect"]?.stringValue, Self.name(row))
        }
    }

    func testShownStop() {
        let rows = Contract.rows(Self.table, "stopShownCases")
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            let shown = CarouselStop.shownStop(row["value"], stopCount: Int(row["stops"]?.numberValue ?? 0))
            XCTAssertEqual(Double(shown), row["expect"]?.numberValue, Self.name(row))
        }
    }

    func testFollow() {
        let rows = Contract.rows(Self.table, "stopFollowCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            let target = CarouselStop.follow(
                previous: row["previous"], next: row["next"], stopCount: Int(row["stops"]?.numberValue ?? 0), active: Int(row["active"]?.numberValue ?? 0))
            XCTAssertEqual(target.map(Double.init), row["expect"]?.numberValue, Self.name(row))
        }
    }

    func testWrite() {
        let rows = Contract.rows(Self.table, "stopWriteCases")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let written = CarouselStop.write(settled: Int(row["settled"]?.numberValue ?? -1), byPerson: row["byPerson"]?.boolValue ?? false, current: row["current"])
            XCTAssertEqual(written.map(Double.init), row["expect"]?.numberValue, Self.name(row))
        }
    }

    func testTheBlockOfTheArtifact() {
        let block = (try? Contract.json("screen-schema.json"))?["x-carouselStop"]
        XCTAssertNotNil(block)
        XCTAssertEqual(block?["path"]?["maxLength"]?.numberValue, Double(CarouselStop.pathMax))
        let rows = Contract.rows(Self.table, "stopRuleCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            var value = block
            for part in (row["rule"]?.stringValue ?? "").split(separator: ".") { value = value?[String(part)] }
            XCTAssertEqual(value, row["expect"], Self.name(row))
        }
    }

    func testAFieldOnANodeThatIsNoHostGivesNoPath() {
        let node = ScreenSim.node(.object(["type": "Row", "props": ["scrollable": false, "carousel": ["stopPath": "a.b"]]]))
        XCTAssertNil(CarouselStop.path(of: node))
    }

    // MARK: A whole screen

    func testTheLayoutGivesTheStopsOfTheTable() {
        let layout = Self.table["stopRunLayout"]
        let cards = (layout?["cards"]?.arrayValue ?? []).compactMap(\.numberValue)
        let plan = CarouselRules.stops(
            viewport: layout?["viewport"]?.numberValue ?? 0, paddingStart: layout?["paddingStart"]?.numberValue ?? 0,
            paddingEnd: layout?["paddingEnd"]?.numberValue ?? 0, gap: layout?["gap"]?.numberValue ?? 0, cards: cards)
        XCTAssertEqual(plan.stops, (layout?["stops"]?.arrayValue ?? []).compactMap(\.numberValue))
    }

    func testTheRowsOfARealScreen() {
        let rows = Contract.rows(Self.table, "stopRunCases")
        XCTAssertEqual(rows.count, 14)
        for row in rows {
            let run = ScreenRun(row: row)
            run.start()
            for step in row["steps"]?.arrayValue ?? [] { run.perform(step) }
            XCTAssertEqual(run.log, (row["log"]?.arrayValue ?? []), Self.name(row))
            XCTAssertEqual(run.actions, [], "onAction is never called: \(Self.name(row))")
            XCTAssertEqual(run.offset, row["offset"]?.numberValue, Self.name(row))
            XCTAssertEqual(run.behavior.map(JSONValue.string) ?? .null, row["behavior"] ?? .null, Self.name(row))
            XCTAssertEqual(run.shownDetails, (row["shown"]?.arrayValue ?? []).compactMap(\.stringValue), Self.name(row))
        }
    }

    /// The frame of the contract draws through the real views with a path on the carousel.
    @MainActor
    func testTheFrameDrawsWithAPathOnTheCarousel() throws {
        let document = try HotlayoutDocument.load(try Contract.json("fixtures/carousel-stop-screens.json"))
        let entry = try XCTUnwrap(document.screens.first)
        var context = Harness.context(rightToLeft: false)
        var written: [String] = []
        context.scope = [Self.stopPath: .number(1)]
        context.screen.write = { path, _ in written.append(path) }
        let view = ScreenRootView(root: entry.root, context: context).frame(width: 393, height: 852)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        XCTAssertNotNil(renderer.cgImage)
        XCTAssertEqual(written, [], "drawing writes nothing")
    }

    private static let stopPath = "account.cardIndex"

    func testAWriteTheHostRefusedLeavesTheCarouselWherePersonPutIt() {
        let run = ScreenRun(row: ["name": "refused"], writes: false)
        run.start()
        run.perform(.object(["swipe": [280]]))
        XCTAssertEqual(run.log, [])
        XCTAssertEqual(run.offset, 280)
    }

    func testAGestureWritesOncePerSettling() {
        let run = ScreenRun(row: ["name": "once"])
        run.start()
        run.perform("wheel")
        run.perform(.object(["scroll": 280]))
        run.perform("scrollend")
        run.perform("quiet")
        run.perform("scrollend")
        XCTAssertEqual(run.log, [.array(["write", "account.cardIndex", 1])])
    }

    func testAScrollWithNoGestureWritesNothing() {
        let run = ScreenRun(row: ["name": "none"])
        run.start()
        run.perform(.object(["scroll": 280]))
        run.perform("scrollend")
        run.perform("quiet")
        XCTAssertEqual(run.log, [])
    }

    func testTheHostChangingTheValueMovesTheCarouselAndAPersonHoldingTheRowWins() {
        let run = ScreenRun(row: ["name": "host"], session: ["account.cardIndex": 0])
        run.start()
        run.hostSets(2)
        XCTAssertEqual(run.offset, 540)
        XCTAssertEqual(run.behavior, "smooth")
        run.perform("hold")
        run.hostSets(1)
        XCTAssertEqual(run.offset, 540)
    }
}

/// A screen of the table without views: the layers, the controller the view uses and a scroll that
/// reports where it stands.
private final class ScreenRun {
    static let path = "account.cardIndex"

    var sim: ScreenSim
    let stops: [Double]
    var log: [JSONValue] = []
    var actions: [String] = []
    private(set) var offset = 0.0
    private(set) var behavior: String?
    private var now = 0.0
    private var timers: [(due: Double, action: () -> Void, live: Box)] = []
    private final class Box { var live = true }
    private let reducedMotion: Bool
    private let hasField: Bool
    private let allowsWrites: Bool

    init(row: JSONObject, session: [String: JSONValue]? = nil, writes: Bool = true) {
        let layout = CarouselStopCasesTests.table["stopRunLayout"]
        let cards = (layout?["cards"]?.arrayValue ?? []).compactMap(\.numberValue)
        stops =
            CarouselRules.stops(
                viewport: layout?["viewport"]?.numberValue ?? 0, paddingStart: layout?["paddingStart"]?.numberValue ?? 0,
                paddingEnd: layout?["paddingEnd"]?.numberValue ?? 0, gap: layout?["gap"]?.numberValue ?? 0, cards: cards
            ).stops
        hasField = row["field"]?.boolValue != false
        reducedMotion = row["reducedMotion"]?.boolValue == true
        allowsWrites = writes
        var initial = DataScope()
        for (key, value) in session ?? row["session"]?.objectValue.map({ Dictionary(uniqueKeysWithValues: $0.map { ($0.key, $0.value) }) }) ?? [:] { initial[key] = value }
        var nodes = CarouselStopCasesTests.table["stopRunScreen"]?.arrayValue ?? []
        if !hasField {
            nodes = nodes.map { node in
                guard node["id"]?.stringValue == "row", var props = node["props"]?.objectValue, var carousel = props["carousel"]?.objectValue else { return node }
                carousel["stopPath"] = nil
                props["carousel"] = .object(carousel)
                var copy = node.objectValue ?? JSONObject()
                copy["props"] = .object(props)
                return .object(copy)
            }
        }
        sim = ScreenSim(nodes: nodes, layers: DataLayers(session: initial))
    }

    convenience init(row: JSONObject, session: [String: JSONValue]) {
        self.init(row: row, session: Optional(session), writes: true)
    }

    private var controller: CarouselStopController!

    func start() {
        // The controller runs on the clock of this object.
        let later: CarouselStopController.Later = { [unowned self] seconds, action in
            let box = Box()
            timers.append((now + seconds * 1000, action, box))
            return { box.live = false }
        }
        controller = CarouselStopController(later: later)
        controller.path = hasField ? Self.path : nil
        controller.reducedMotion = reducedMotion
        controller.write = { [unowned self] path, value in
            guard allowsWrites else { return }
            sim.session[path] = value
            log.append(.array([.string("write"), .string(path), value]))
            controller.update(value: sim.scope[path])
        }
        controller.scrollToStop = { [unowned self] index, animated in
            offset = stops[index]
            behavior = animated ? "smooth" : "instant"
            controller.scrolled(to: offset)
            controller.settle()
        }
        controller.current = sim.scope[Self.path]
        controller.observe(stops: stops)
    }

    var shownDetails: [String] { ["details-0", "details-1", "details-2"].filter { sim.isShown($0) } }

    func hostSets(_ stop: Int) {
        sim.session[Self.path] = .number(Double(stop))
        controller.update(value: sim.scope[Self.path])
    }

    private func scroll(_ to: Double) {
        offset = to
        controller.scrolled(to: to)
    }

    func perform(_ step: JSONValue) {
        if let word = step.stringValue {
            switch word {
            case "hold": controller.personBegan()
            case "release": controller.personReleased()
            case "wheel": controller.personMoved()
            case "scrollend": controller.settle()
            case "quiet": advance(CarouselStop.settleSeconds * 1000 + 1)
            default: XCTFail("a step this test does not know: \(word)")
            }
        } else if let to = step["scroll"]?.numberValue {
            scroll(to)
        } else if let id = step["tap"]?.stringValue {
            let before = sim.log.count
            sim.press(id)
            for entry in sim.log[before...] where entry.first?.stringValue == "write" {
                log.append(.array(entry))
                controller.update(value: sim.scope[entry[1].stringValue ?? ""])
            }
            sim.log.removeSubrange(before...)
        } else if let offsets = step["swipe"]?.arrayValue {
            perform("hold")
            for offset in offsets.compactMap(\.numberValue) { scroll(offset) }
            perform("release")
            perform("scrollend")
        }
    }

    private func advance(_ ms: Double) {
        now += ms
        for timer in timers.sorted(by: { $0.due < $1.due }) where timer.live.live && timer.due <= now {
            timer.live.live = false
            timer.action()
        }
    }
}

/// The host changes the number twice while the reader still scrolls smoothly to the first target:
/// the second target is compared with where the scroll is heading, not with the stop it passes.
final class CarouselStopRaceTests: XCTestCase {
    private var timers: [(due: Double, action: () -> Void, live: Bool)] = []
    private var now = 0.0
    private var targets: [Int] = []
    private var controller: CarouselStopController!
    private let stops = [0.0, 270.0, 540.0]

    private func make(start: Int) {
        controller = CarouselStopController(later: { [unowned self] seconds, action in
            let index = timers.count
            timers.append((now + seconds * 1000, action, true))
            return { [unowned self] in timers[index].live = false }
        })
        controller.path = "a.b"
        controller.current = .number(Double(start))
        controller.write = { _, _ in XCTFail("the reader never writes") }
        controller.scrollToStop = { [unowned self] index, _ in targets.append(index) }
        controller.observe(stops: stops)
        controller.scrolled(to: stops[start])
        targets = []
    }

    private func advance(_ ms: Double) {
        now += ms
        for index in timers.indices where timers[index].live && timers[index].due <= now {
            timers[index].live = false
            timers[index].action()
        }
    }

    func testASecondTargetDuringTheFirstScrollIsNotTakenForArrival() {
        make(start: 2)
        controller.update(value: .number(0))
        XCTAssertEqual(targets, [0])
        controller.scrolled(to: 400)
        controller.scrolled(to: 270)  // passing the stop 1 on the way to 0
        controller.update(value: .number(1))
        XCTAssertEqual(targets, [0, 1])
    }

    func testOnceTheScrollSettledTheStopAtRestIsUsed() {
        make(start: 2)
        controller.update(value: .number(0))
        controller.scrolled(to: 0)
        advance(CarouselStop.settleSeconds * 1000 + 1)
        controller.update(value: .number(0))
        controller.update(value: .number(1))
        XCTAssertEqual(targets, [0, 1])
        controller.scrolled(to: 270)
        advance(CarouselStop.settleSeconds * 1000 + 1)
        controller.update(value: .number(1))  // same number: nothing
        XCTAssertEqual(targets, [0, 1])
    }

    func testAPersonMovingTheRowForgetsTheHeading() {
        make(start: 2)
        controller.update(value: .number(0))
        controller.personMoved()
        controller.scrolled(to: 270)
        controller.update(value: .number(1))
        XCTAssertEqual(targets, [0])  // the person put the row on the stop 1 already
    }
}
