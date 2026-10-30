import SwiftUI
import XCTest

@testable import HotLayout

/// The carousel against `carousel/carousel-cases.json` (9.11.0) and the carousel rows of
/// `repeater-filter/` (9.23.0): who is a host, how the field is read, the width of a card, the
/// stops, the active stop, the dots, the area and the state key.
final class CarouselCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/carousel/carousel-cases.json")

    private let tolerance = 1e-9

    /// The spacing steps of the table's theme.
    private var spacing: [String: Double] {
        (Self.table["theme"]?["spacing"]?.objectValue).map { object in
            Dictionary(uniqueKeysWithValues: object.map { ($0.key, $0.value.numberValue ?? 0) })
        } ?? [:]
    }

    private func points(_ value: JSONValue?) -> Double {
        if let number = value?.numberValue { return number }
        return spacing[value?.stringValue ?? ""] ?? 0
    }

    func testEveryGroupIsRun() {
        let run: Set<String> = ["hostCases", "readCases", "cardCases", "stopCases", "activeCases", "dotCases", "areaCases", "stateCases"]
        // The `stop…` groups from `stopPathCases` on belong to the carousel that tells its stop
        // (`CarouselStopCasesTests`); `stopDocumentCases` is the validator's table.
        let stopGroups: Set<String> = [
            "stopPathCases", "stopShownCases", "stopFollowCases", "stopWriteCases", "stopDocumentCases", "stopRunCases", "stopRuleCases",
        ]
        let groups = Set((Self.table.objectValue ?? JSONObject()).filter { $0.key.hasSuffix("Cases") && $0.value.arrayValue != nil }.map(\.key))
        XCTAssertEqual(groups.subtracting(stopGroups), run, "a group of the table this test does not run, or a name that is no group")
    }

    func testDefaultsAreTheTables() {
        let defaults = Self.table["defaults"]
        XCTAssertEqual(defaults?["peek"]?.stringValue, CarouselRules.defaultPeek)
        XCTAssertEqual(defaults?["maxDots"]?.numberValue, Double(CarouselRules.maxDots))
        XCTAssertEqual(defaults?["stopMerge"]?.numberValue, CarouselRules.stopMerge)
        XCTAssertEqual(defaults?["minCard"]?.numberValue, CarouselRules.minCard)
        XCTAssertEqual(defaults?["inactiveOpacity"]?.numberValue, CarouselRules.inactiveDotOpacity)
        XCTAssertEqual(defaults?["perViewMin"]?.numberValue, Double(CarouselRules.perViewRange.lowerBound))
        XCTAssertEqual(defaults?["perViewMax"]?.numberValue, Double(CarouselRules.perViewRange.upperBound))
        XCTAssertEqual(defaults?["dotSize"]?.stringValue, CarouselRules.dotSizeToken)
        XCTAssertEqual(defaults?["dotGap"]?.stringValue, CarouselRules.dotGapToken)
        XCTAssertEqual(defaults?["indicatorGap"]?.stringValue, CarouselRules.indicatorGapToken)
        XCTAssertEqual(defaults?["activeColor"]?.stringValue, CarouselRules.dotColorToken)
    }

    func testHosts() {
        let rows = Contract.rows(Self.table, "hostCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let host = CarouselRules.isHost(type: row["type"]?.stringValue ?? "", props: row["props"]?.objectValue ?? JSONObject())
            XCTAssertEqual(host, row["expect"]?.boolValue, row["name"]?.stringValue ?? "?")
        }
    }

    func testReadingTheField() {
        let rows = Contract.rows(Self.table, "readCases")
        XCTAssertEqual(rows.count, 17)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let read = CarouselRules.read(row["value"])
            guard let expect = row["expect"]?.objectValue else {
                XCTAssertNil(read, name)
                continue
            }
            XCTAssertEqual(read?.perView.map { JSONValue.number(Double($0)) } ?? .null, expect["perView"], name)
            XCTAssertEqual(read?.peek ?? .null, expect["peek"], name)
            XCTAssertEqual(read?.indicator == CarouselSpec.Indicator.none ? "none" : "dots", expect["indicator"]?.stringValue, name)
        }
    }

    func testCardWidth() {
        let rows = Contract.rows(Self.table, "cardCases")
        XCTAssertEqual(rows.count, 18)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let peek = CarouselRules.peekPixels(row["peek"].flatMap { $0.isNull ? nil : $0 }, spacing: { spacing[$0] })
            let width = CarouselRules.cardWidth(
                viewport: row["viewport"]?.numberValue ?? 0, paddingStart: points(row["paddingStart"]), gap: points(row["gap"]),
                peek: peek, perView: Int(row["perView"]?.numberValue ?? 1)
            )
            if let expected = row["expect"]?.numberValue {
                XCTAssertEqual(width ?? .nan, expected, accuracy: tolerance, name)
            } else {
                XCTAssertNil(width, name)
            }
        }
    }

    private func doubles(_ value: JSONValue?) -> [Double] { (value?.arrayValue ?? []).compactMap(\.numberValue) }

    private func assertStops(_ row: JSONObject, cards: [Double], viewport: Double, expect: JSONObject?, name: String) {
        let result = CarouselRules.stops(
            viewport: viewport, paddingStart: points(row["paddingStart"]), paddingEnd: points(row["paddingEnd"]),
            gap: points(row["gap"]), cards: cards
        )
        if let maxScroll = expect?["maxScroll"]?.numberValue { XCTAssertEqual(result.maxScroll, maxScroll, accuracy: tolerance, name) }
        let stops = doubles(expect?["stops"])
        XCTAssertEqual(result.stops.count, stops.count, name)
        for (actual, wanted) in zip(result.stops, stops) { XCTAssertEqual(actual, wanted, accuracy: tolerance, name) }
        if let wantedCards = expect?["stopOfCard"] {
            XCTAssertEqual(result.stopOfCard, doubles(wantedCards).map(Int.init), name)
        }
    }

    func testStops() {
        let rows = Contract.rows(Self.table, "stopCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            assertStops(row, cards: doubles(row["cards"]), viewport: row["viewport"]?.numberValue ?? 0, expect: row["expect"]?.objectValue, name: row["name"]?.stringValue ?? "?")
        }
    }

    func testActiveStop() {
        let rows = Contract.rows(Self.table, "activeCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            let active = CarouselRules.activeStop(doubles(row["stops"]), offset: row["offset"]?.numberValue ?? 0)
            XCTAssertEqual(Double(active), row["expect"]?.numberValue, row["name"]?.stringValue ?? "?")
        }
    }

    func testDots() {
        let rows = Contract.rows(Self.table, "dotCases")
        XCTAssertEqual(rows.count, 10)
        let size = points("sm"), gap = points("sm")
        for row in rows {
            let indicator: CarouselSpec.Indicator = row["indicator"]?.stringValue == "none" ? .none : .dots
            let dots = CarouselRules.dotCount(indicator: indicator, stops: Int(row["stops"]?.numberValue ?? 0), viewport: row["viewport"]?.numberValue ?? 0, dotSize: size, dotGap: gap)
            let name = row["name"]?.stringValue ?? "?"
            XCTAssertEqual(Double(dots), row["expect"]?["dots"]?.numberValue, name)
            XCTAssertEqual(CarouselRules.indicatorBlock(dots: dots, gap: points("sm"), dotSize: size), row["expect"]?["block"]?.numberValue, name)
        }
    }

    func testTheAreaDoesNotDependOnTheDots() {
        let rows = Contract.rows(Self.table, "areaCases")
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let viewport = row["place"]?.numberValue ?? 0
            assertStops(row, cards: doubles(row["cards"]), viewport: viewport, expect: row["expect"]?.objectValue, name: name)
            let stops = CarouselRules.stops(viewport: viewport, paddingStart: points(row["paddingStart"]), paddingEnd: points(row["paddingEnd"]), gap: points(row["gap"]), cards: doubles(row["cards"]))
            let indicator: CarouselSpec.Indicator = row["indicator"]?.stringValue == "none" ? .none : .dots
            let dots = CarouselRules.dotCount(indicator: indicator, stops: stops.stops.count, viewport: viewport, dotSize: points("sm"), dotGap: points("sm"))
            XCTAssertEqual(Double(dots), row["expect"]?["dots"]?.numberValue, name)
            XCTAssertEqual(viewport, row["expect"]?["viewport"]?.numberValue, name)
        }
    }

    func testStateKeys() {
        let rows = Contract.rows(Self.table, "stateCases")
        XCTAssertEqual(rows.count, 6)
        func key(_ side: JSONValue?) -> String {
            CarouselRules.stateKey(nodeId: side?["node"]?.stringValue ?? "", instancePath: (side?["instance"]?.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) })
        }
        for row in rows {
            XCTAssertEqual(key(row["a"]) == key(row["b"]), row["sameState"]?.boolValue, row["name"]?.stringValue ?? "?")
        }
    }

    // MARK: Filtered cards (repeater-filter/carouselCases)

    func testStopsOfTheCardsDrawn() {
        let table = ListsCasesTests.filterTable
        let records = table["records"]?.arrayValue ?? []
        let rows = Contract.rows(table, "carouselCases")
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            let drawn = RepeaterPlan.drawnIndexes(records: records, item: "reward", filter: row["where"], outer: Contract.scope(row["outer"]), limit: nil)
            let cards = [Double](repeating: row["card"]?.numberValue ?? 0, count: drawn.count)
            let result = CarouselRules.stops(viewport: row["viewport"]?.numberValue ?? 0, paddingStart: 0, paddingEnd: 0, gap: row["gap"]?.numberValue ?? 0, cards: cards)
            XCTAssertEqual(Double(result.stops.count), row["stops"]?.numberValue, row["name"]?.stringValue ?? "?")
        }
    }

    // MARK: Memory of the stack

    func testMemoryFollowsTheFramesOfTheStack() {
        let memory = CarouselMemory()
        let first = CarouselMemory.key(frame: 0, screenId: "home", state: "[\"strip\"]")
        let second = CarouselMemory.key(frame: 1, screenId: "detail", state: "[\"strip\"]")
        memory.set(2, for: first)
        memory.set(1, for: second)
        XCTAssertEqual(memory.stop(for: first), 2)
        memory.prune(frames: ["home"])
        XCTAssertEqual(memory.stop(for: first), 2, "the frame below stays: back shows the same card")
        XCTAssertNil(memory.stop(for: second), "a frame that left the stack takes its state")
        memory.prune(frames: ["other"])
        XCTAssertEqual(memory.count, 0, "frame 0 is another screen now (a section switch)")
    }
}
