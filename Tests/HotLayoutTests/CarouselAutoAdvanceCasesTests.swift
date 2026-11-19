import SwiftUI
import XCTest

@testable import HotLayout

/// A carousel that advances by time (`carousel.autoAdvance`, block `x-carouselAutoAdvance`) against the
/// `autoAdvance…` groups of `carousel/carousel-cases.json`: how the field is read, the next stop, one
/// tick of the clock, what a step writes, the data of the artifact, and a whole screen on a clock of the
/// test in steps of 100 ms. `autoAdvanceDocumentCases` is the table of the builder's validator and is not
/// run here.
final class CarouselAutoAdvanceCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/carousel/carousel-cases.json")

    private static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "autoAdvanceReadCases", "autoAdvanceNextCases", "autoAdvanceTickCases", "autoAdvanceWriteCases", "autoAdvanceRunCases", "autoAdvanceRuleCases",
        ]
        let notRun: Set<String> = ["autoAdvanceDocumentCases"]
        let groups = Contract.groups(Self.table).filter { $0.hasPrefix("autoAdvance") }
        XCTAssertEqual(groups.subtracting(run).subtracting(notRun), [], "groups that are neither run nor named")
        XCTAssertEqual(run.union(notRun).subtracting(groups), [], "names that are no longer groups")
    }

    func testThePausesAreTheListOfTheArtifactInItsOrder() throws {
        let block = try XCTUnwrap(try Contract.json("screen-schema.json")["x-carouselAutoAdvance"])
        XCTAssertEqual(CarouselAutoAdvance.Pause.allCases.map(\.rawValue), (block["pauses"]?["list"]?.arrayValue ?? []).compactMap(\.stringValue))
        XCTAssertEqual(block["field"]?["intervalMs"]?["min"]?.numberValue, CarouselAutoAdvance.minMs)
        XCTAssertEqual(block["field"]?["intervalMs"]?["max"]?.numberValue, CarouselAutoAdvance.maxMs)
    }

    func testTheBlocksItRefinesDoNotMentionTheField() throws {
        let schema = try Contract.json("screen-schema.json")
        func text(_ value: JSONValue?) -> String { String(describing: value) }
        XCTAssertFalse(text(schema["x-style"]?["layout"]?["carousel"]).contains("autoAdvance"))
        XCTAssertFalse(text(schema["x-carouselStop"]).contains("autoAdvance"))
    }

    func testRules() {
        let rows = Contract.rows(Self.table, "autoAdvanceRuleCases")
        XCTAssertEqual(rows.count, 10)
        let block = try? Contract.json("screen-schema.json")["x-carouselAutoAdvance"]
        for row in rows {
            var at = block
            for key in (row["rule"]?.stringValue ?? "").split(separator: ".") { at = at?[String(key)] }
            XCTAssertEqual(at, row["expect"], Self.name(row))
        }
    }

    func testReading() {
        let rows = Contract.rows(Self.table, "autoAdvanceReadCases")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            let expected = row["expect"]
            let props = row["props"] ?? .null
            // The field alone is read by its shape; that a node hosts a carousel at all is the call of the node.
            if expected != nil, !(expected?.isNull ?? true) {
                let read = CarouselAutoAdvance.of(props["carousel"])
                XCTAssertEqual(read?.intervalMs, expected?["intervalMs"]?.numberValue, Self.name(row))
                XCTAssertEqual(read?.loop, expected?["loop"]?.boolValue, Self.name(row))
            }
            var propsObject = props.objectValue ?? JSONObject()
            if row["type"]?.stringValue == "Repeater" { propsObject["item"] = "item" }
            if row["type"]?.stringValue == "Row" { propsObject["gap"] = "none" }
            let node = ScreenSim.node(.object(["id": "host", "type": row["type"] ?? "Row", "props": .object(propsObject), "children": []]))
            let read = CarouselAutoAdvance.of(node)
            XCTAssertEqual(read?.intervalMs, expected?["intervalMs"]?.numberValue, "through the node: \(Self.name(row))")
            XCTAssertEqual(read?.loop, expected?["loop"]?.boolValue, "through the node: \(Self.name(row))")
        }
    }

    func testNext() {
        let rows = Contract.rows(Self.table, "autoAdvanceNextCases")
        XCTAssertEqual(rows.count, 7)
        for row in rows {
            let next = CarouselAutoAdvance.next(
                active: Int(row["active"]?.numberValue ?? 0), stopCount: Int(row["stops"]?.numberValue ?? 0), loop: row["loop"]?.boolValue == true)
            XCTAssertEqual(next.map { Double($0) }, row["expect"]?.numberValue, Self.name(row))
        }
    }

    func testTick() {
        let rows = Contract.rows(Self.table, "autoAdvanceTickCases")
        XCTAssertEqual(rows.count, 12)
        for row in rows {
            let from = row["state"], input = row["input"], expected = row["expect"]
            let tick = CarouselAutoAdvance.tick(
                CarouselAutoAdvance.State(active: Int(from?["active"]?.numberValue ?? 0), elapsed: from?["elapsed"]?.numberValue ?? 0),
                dtMs: input?["dtMs"]?.numberValue ?? 0, active: Int(input?["active"]?.numberValue ?? 0), stopCount: Int(input?["stops"]?.numberValue ?? 0),
                paused: input?["paused"]?.boolValue == true, intervalMs: input?["intervalMs"]?.numberValue ?? 0, loop: input?["loop"]?.boolValue == true)
            XCTAssertEqual(Double(tick.state.active), expected?["state"]?["active"]?.numberValue, Self.name(row))
            XCTAssertEqual(tick.state.elapsed, expected?["state"]?["elapsed"]?.numberValue, Self.name(row))
            XCTAssertEqual(tick.step.map { Double($0) }, expected?["step"]?.numberValue, Self.name(row))
        }
    }

    func testWrite() {
        let rows = Contract.rows(Self.table, "autoAdvanceWriteCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let written = CarouselAutoAdvance.write(step: Int(row["step"]?.numberValue ?? -1), current: row["current"].flatMap { $0.isNull ? nil : $0 })
            XCTAssertEqual(written.map { Double($0) }, row["expect"]?.numberValue, Self.name(row))
        }
    }

    // MARK: A whole screen

    func testTheRowsOfARealScreen() {
        let rows = Contract.rows(Self.table, "autoAdvanceRunCases")
        XCTAssertEqual(rows.count, 17)
        for row in rows {
            let run = AutoAdvanceRun(row: row)
            run.start()
            for step in row["steps"]?.arrayValue ?? [] { run.perform(step) }
            XCTAssertEqual(run.log, row["log"]?.arrayValue ?? [], Self.name(row))
            XCTAssertEqual(run.offset, row["offset"]?.numberValue, Self.name(row))
            XCTAssertEqual(run.behavior.map(JSONValue.string) ?? .null, row["behavior"] ?? .null, Self.name(row))
            XCTAssertEqual(run.shownDetails, (row["shown"]?.arrayValue ?? []).compactMap(\.stringValue), Self.name(row))
        }
    }

    /// A touch that does not move the row is no move of a person: it writes nothing when it is let go.
    func testATouchThatDoesNotMoveTheRowWritesNothing() {
        let run = AutoAdvanceRun(row: ["name": "touch", "field": "off"])
        run.start()
        run.perform("hold")
        run.perform("release")
        run.perform("scrollend")
        run.perform("quiet")
        XCTAssertEqual(run.log, [])
    }

    func testTheStepOfTheTimerIsNotMistakenForTheMoveOfAPerson() {
        let run = AutoAdvanceRun(row: ["name": "own step"])
        run.start()
        run.perform(.object(["wait": 3300]))
        // The settle of the step wrote nothing of its own: the one write is the step's.
        run.perform("scrollend")
        run.perform("quiet")
        XCTAssertEqual(run.log, [.array(["write", "account.cardIndex", 1])])
    }
}

/// A screen of the table without views: the layers, the controller and the clock the carousel view uses,
/// and a scroll that reports where it stands. Time is moved by `wait`, in ticks of the reader's clock.
private final class AutoAdvanceRun {
    static let path = "account.cardIndex"

    var sim: ScreenSim
    let stops: [Double]
    var log: [JSONValue] = []
    private(set) var offset = 0.0
    private(set) var behavior: String?
    private var now = 0.0
    private final class Box { var live = true }
    private var timers: [(due: Double, action: () -> Void, live: Box)] = []
    private let reducedMotion: Bool
    private let hasPath: Bool
    /// A modal layer covers the screen: the stack tells the carousel it is not in front (`ModalStack`).
    private let covered: Bool
    private let controller: CarouselStopController
    private let driver: CarouselAutoAdvanceDriver

    private static func later(_ run: AutoAdvanceRun) -> CarouselStopController.Later {
        { [unowned run] seconds, action in
            let box = Box()
            run.timers.append((run.now + seconds * 1000, action, box))
            return { box.live = false }
        }
    }

    init(row: JSONObject) {
        let layout = CarouselAutoAdvanceCasesTests.table["stopRunLayout"]
        let cards = (layout?["cards"]?.arrayValue ?? []).compactMap(\.numberValue)
        stops =
            CarouselRules.stops(
                viewport: layout?["viewport"]?.numberValue ?? 0, paddingStart: layout?["paddingStart"]?.numberValue ?? 0,
                paddingEnd: layout?["paddingEnd"]?.numberValue ?? 0, gap: layout?["gap"]?.numberValue ?? 0, cards: cards
            ).stops
        let withPath = row["field"]?.stringValue != "noPath"
        let withField = row["field"]?.stringValue != "off"
        hasPath = withPath
        covered = row["inert"]?.boolValue == true
        reducedMotion = row["reducedMotion"]?.boolValue == true
        var initial = DataScope()
        for (key, value) in row["session"]?.objectValue ?? JSONObject() { initial[key] = value }
        var nodes = CarouselAutoAdvanceCasesTests.table["autoAdvanceRunScreen"]?.arrayValue ?? []
        nodes = nodes.map { node in
            guard node["id"]?.stringValue == "row", var props = node["props"]?.objectValue, var carousel = props["carousel"]?.objectValue else { return node }
            if !withPath { carousel["stopPath"] = nil }
            if !withField { carousel["autoAdvance"] = nil }
            if row["loop"]?.boolValue == true, var timer = carousel["autoAdvance"]?.objectValue {
                timer["loop"] = true
                carousel["autoAdvance"] = .object(timer)
            }
            props["carousel"] = .object(carousel)
            var copy = node.objectValue ?? JSONObject()
            copy["props"] = .object(props)
            return .object(copy)
        }
        sim = ScreenSim(nodes: nodes, layers: DataLayers(session: initial))
        // The clock of the test: the controller and the driver both start their timers on it.
        let holder = ClockHolder()
        controller = CarouselStopController(later: { holder.later?($0, $1) ?? {} })
        driver = CarouselAutoAdvanceDriver(later: { holder.later?($0, $1) ?? {} })
        holder.later = Self.later(self)
    }

    private final class ClockHolder { var later: CarouselStopController.Later? }

    func start() {
        let row = sim.root.children.first { $0.id == "row" }
        controller.path = hasPath ? Self.path : nil
        controller.reducedMotion = reducedMotion
        controller.write = { [unowned self] path, value in
            sim.session[path] = value
            log.append(.array([.string("write"), .string(path), value]))
            controller.update(value: sim.scope[path])
        }
        controller.scrollToStop = { [unowned self] index, animated in jump(to: index, animated: animated) }
        controller.current = sim.scope[Self.path]
        controller.observe(stops: stops)
        driver.configure(row.flatMap { CarouselAutoAdvance.of($0) })
        driver.set(.notShown, covered)
        driver.view = { [unowned self] in (active: CarouselRules.activeStop(stops, offset: offset), stopCount: stops.count) }
        driver.onStep = { [unowned self] step in
            driver.scrollMoved()
            controller.timerStep(to: step) { index, animated in jump(to: index, animated: animated) }
        }
    }

    private func jump(to index: Int, animated: Bool) {
        offset = stops[index]
        behavior = animated ? "smooth" : "instant"
        driver.scrollMoved()
        controller.scrolled(to: offset)
        controller.settle()
    }

    var shownDetails: [String] { ["details-0", "details-1", "details-2"].filter { sim.isShown($0) } }

    private func scroll(_ to: Double) {
        offset = to
        driver.scrollMoved()
        controller.scrolled(to: to)
    }

    func perform(_ step: JSONValue) {
        if let word = step.stringValue {
            switch word {
            case "hold":
                controller.personBegan()
                driver.set(.held, true)
            case "release":
                controller.personReleased()
                driver.set(.held, false)
            case "scrollend": controller.settle()
            case "quiet": advance(CarouselStop.settleSeconds * 1000 + 1)
            default: XCTFail("a step this test does not know: \(word)")
            }
        } else if let ms = step["wait"]?.numberValue {
            var left = ms
            while left > 0 {
                let part = min(left, CarouselAutoAdvance.tickMs)
                advance(part)
                // The clock of the reader ticks every 100 ms of its own.
                if part == CarouselAutoAdvance.tickMs { driver.tick() }
                left -= part
            }
        } else if let offsets = step["swipe"]?.arrayValue {
            perform("hold")
            for offset in offsets.compactMap(\.numberValue) { scroll(offset) }
            perform("release")
            perform("scrollend")
        } else if let visibility = step["visibility"]?.stringValue {
            driver.set(.notShown, visibility == "hidden")
        } else {
            XCTFail("a step this test does not know: \(step)")
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

#if canImport(AppKit)
import AppKit

/// The real carousel view on its real clock: it takes itself to the next stop after the interval, writes
/// the stop once, and stands still when its screen is not in front.
@MainActor
final class CarouselAutoAdvanceViewTests: XCTestCase {
    private final class Writes { var log: [String] = [] }

    private struct Host: View {
        let writes: Writes
        let inFront: Bool
        var body: some View {
            let setup = CarouselSetup(
                spec: CarouselSpec(perView: 1, peek: nil, indicator: .none), peek: 0, gap: 0, padding: .zero,
                vertical: .center, rightToLeft: false, dotSize: 8, dotGap: 8, indicatorGap: 8, dotColor: .black,
                memory: nil, memoryKey: "k", stopPath: "account.cardIndex", stopValue: .number(0),
                write: { path, value in writes.log.append("\(path) \(value)") }, autoAdvance: CarouselAutoAdvance(intervalMs: 2000))
            CarouselView(setup: setup, count: 3, knownViewport: 200) { index, width in
                Color.gray.frame(width: width ?? 200, height: 40).id("card-\(index)")
            }
            .frame(width: 200, height: 60)
            .environment(\.screenInFront, inFront)
        }
    }

    private func offset(in view: NSView) -> CGFloat? {
        if let scroll = view as? NSScrollView { return scroll.contentView.bounds.origin.x }
        for child in view.subviews { if let found = offset(in: child) { return found } }
        return nil
    }

    private func run(inFront: Bool, seconds: Double) -> (offset: CGFloat, writes: [String]) {
        let writes = Writes()
        let hosting = NSHostingView(rootView: Host(writes: writes, inFront: inFront))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 200, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        return (offset(in: hosting) ?? -1, writes.log)
    }

    func testTheRowGoesToTheNextStopAfterTheIntervalAndWritesItOnce() throws {
        try skipUnderReducedMotion()
        let before = run(inFront: true, seconds: 1.5)
        XCTAssertEqual(before.offset, 0, accuracy: 1, "before the interval nothing moved")
        XCTAssertEqual(before.writes, [])
        let after = run(inFront: true, seconds: 3)
        XCTAssertEqual(after.offset, 200, accuracy: 1, "after the interval: the second stop")
        XCTAssertEqual(after.writes, ["account.cardIndex number(1.0)"])
    }

    func testARowOnAScreenThatIsNotInFrontStandsStill() throws {
        let still = run(inFront: false, seconds: 3)
        XCTAssertEqual(still.offset, 0, accuracy: 1)
        XCTAssertEqual(still.writes, [])
    }
}
#endif
