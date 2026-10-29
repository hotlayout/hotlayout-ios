import XCTest

@testable import HotLayout

/// The schedule of a placement (placement contract 1.1.0): the shared table, the instants against
/// the artifact's own pattern, the timer, and a load that resolves by an injected clock.
final class PlacementScheduleTests: XCTestCase {
    private func table() throws -> JSONValue { try Contract.json("fixtures/placements/placement-cases.json") }

    private func date(_ text: String) throws -> Date { try XCTUnwrap(PlacementInstant.date(text), text) }

    func testScheduleCases() throws {
        let rows = Contract.rows(try table(), "scheduleCases")
        XCTAssertEqual(rows.count, 37)
        var checks = 0
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let map: HotlayoutPlacementMap
            if let text = row["text"]?.stringValue {
                map = HotlayoutPlacementMap(text: text)
            } else if let json = row["json"] {
                map = HotlayoutPlacementMap(json: json)
            } else {
                XCTFail("\(name): the row has neither text nor json")
                continue
            }
            for check in (row["checks"]?.arrayValue ?? []).compactMap(\.objectValue) {
                let place = check["place"]?.stringValue ?? "?"
                let nowText = check["now"]?.stringValue ?? "?"
                let label = "\(name) / \(place) @ \(nowText)"
                let now = try date(nowText)
                let shown = map.resolve(place, at: now)
                XCTAssertEqual(shown.status.rawValue, check["status"]?.stringValue, "\(label): status")
                XCTAssertEqual(shown.documentId, check["documentId"]?.stringValue, "\(label): documentId")
                XCTAssertEqual(shown.entry, check["entry"]?.stringValue, "\(label): entry")
                let next = map.nextBoundary(place, after: now)
                XCTAssertEqual(next, check["next"]?.stringValue.flatMap(PlacementInstant.date), "\(label): next")
                checks += 1
            }
        }
        XCTAssertEqual(checks, 89)
    }

    /// The hand-written instant check against the regular expression of the artifact.
    func testInstantsAgreeWithTheArtifactPattern() throws {
        let schedule = try XCTUnwrap(try Contract.json("placements.json").objectValue?["x-placementSchedule"]?.objectValue)
        let pattern = try XCTUnwrap(schedule["instant"]?.objectValue?["pattern"]?.stringValue)
        let regex = try NSRegularExpression(pattern: pattern)
        let samples = [
            "2026-11-27T22:00:00Z", "2026-11-27T22:00:00z", "2026-11-27T22:00:00+02:00", "2026-11-27T22:00:00.5Z", "2026-11-27 22:00:00Z",
            "2026-11-27T22:00Z", "2024-02-29T00:00:00Z", "2026-02-29T00:00:00Z", "2100-02-29T00:00:00Z", "2099-12-31T23:59:59Z",
            "2000-01-01T00:00:00Z", "1999-12-31T23:59:59Z", "2100-01-01T00:00:00Z", "2026-04-31T00:00:00Z", "2026-13-01T00:00:00Z",
            "2026-00-10T00:00:00Z", "2026-01-00T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T23:60:00Z", "2026-01-01T23:59:60Z",
            "2026-11-27T22:00:00Z\n", "", "2026-11-27", "٢٠٢٦-11-27T22:00:00Z",
        ]
        for sample in samples {
            let matches = regex.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)) != nil
            XCTAssertEqual(PlacementInstant.seconds(sample) != nil, matches && !sample.hasSuffix("\n"), "instant: \(sample.debugDescription)")
        }
        XCTAssertEqual(PlacementInstant.seconds("1970-01-01T00:00:00Z"), nil, "before 2000 is not an instant")
        XCTAssertEqual(PlacementInstant.seconds("2000-01-01T00:00:00Z"), 946_684_800)
        XCTAssertEqual(PlacementInstant.seconds("2026-11-27T22:00:00Z"), 1_795_816_800)
    }

    func testTheArtifactTimerLimitIsTheReaders() throws {
        let schedule = try XCTUnwrap(try Contract.json("placements.json").objectValue?["x-placementSchedule"]?.objectValue)
        XCTAssertEqual(schedule["maxTimerMs"]?.numberValue, Double(PlacementTimer.maxMs))
        XCTAssertEqual(schedule["clock"]?.stringValue, "device")
        XCTAssertEqual(schedule["olderReaders"]?.stringValue, "permanent-only")
    }

    func testTimerSleepIsCutAtTheLimit() throws {
        let now = try date("2026-10-01T00:00:00Z")
        XCTAssertEqual(PlacementTimer.sleepMs(until: now.addingTimeInterval(1), from: now), 1000)
        XCTAssertEqual(PlacementTimer.sleepMs(until: now.addingTimeInterval(0.0004), from: now), 1)
        XCTAssertEqual(PlacementTimer.sleepMs(until: now.addingTimeInterval(-5), from: now), 1, "a boundary already past still waits a tick")
        XCTAssertEqual(PlacementTimer.sleepMs(until: now.addingTimeInterval(3_000_000), from: now), 2_147_483_647, "35 days are cut")
        XCTAssertEqual(PlacementTimer.sleepMs(until: now.addingTimeInterval(2_147_483.647), from: now), 2_147_483_647)
    }

    func testDocumentsOfScheduledItemsAreKept() {
        let map = HotlayoutPlacementMap(
            text: #"{"placementsVersion":"1.1.0","placements":{"a":{"documentId":"d1","schedule":[{"documentId":"d2","from":"2026-11-01T00:00:00Z","until":"2026-11-02T00:00:00Z"},{"documentId":null,"from":"2026-11-03T00:00:00Z","until":"2026-11-04T00:00:00Z"},{"documentId":"../x","from":"2026-11-05T00:00:00Z","until":"2026-11-06T00:00:00Z"}]}}}"#
        )
        XCTAssertEqual(map.documentIds(), ["d1", "d2"])
    }

    // MARK: - a load by an injected clock

    private final class Files: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: String] = [:]
        private(set) var requests: [String] = []
        func put(_ path: String, _ body: String) { lock.lock(); items[path] = body; lock.unlock() }
        func get(_ path: String) -> String? { lock.lock(); defer { lock.unlock() }; requests.append(path); return items[path] }
        func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return requests.filter { $0 == path }.count }
    }

    private func document(_ id: String) -> String {
        #"""
        {"schemaVersion":"9.27.0","documentId":"\#(id)","name":"n","initialScreenId":"a","entryPoints":{"sale":"a"},
         "screens":[{"screenId":"a","name":"A","root":{"id":"r","type":"Screen","props":{},"children":[]}}]}
        """#
    }

    func testLoadResolvesByTheClockAndShowAsksNoMapAgain() async throws {
        let files = Files()
        let root = "/orgs/o/projects/p"
        files.put(
            root + "/placements/published.json",
            #"{"placementsVersion":"1.1.0","placements":{"home.banner":{"documentId":"d-everyday","schedule":[{"documentId":"d-sale","entry":"sale","from":"2026-11-27T22:00:00Z","until":"2026-11-30T22:00:00Z"},{"documentId":null,"from":"2026-12-05T00:00:00Z","until":"2026-12-06T00:00:00Z"}]}}}"#
        )
        files.put(root + "/documents/d-everyday/published.json", document("d-everyday"))
        files.put(root + "/documents/d-sale/published.json", document("d-sale"))
        let server = try LocalServer { request in
            guard let body = files.get(request.path) else { return LocalServer.Response(status: 404, headers: ["Content-Length": "0"]) }
            let data = Data(body.utf8)
            return LocalServer.Response(status: 200, headers: ["Content-Type": "application/json", "Content-Length": String(data.count)], chunks: AnyIterator([data].makeIterator()))
        }
        defer { server.stop() }
        let base = URL(string: server.base + root)!
        let documents = HotlayoutMemoryPlacementDocumentStore()
        let before = try date("2026-11-01T00:00:00Z")

        let read = await HotlayoutPlacement.read(
            name: "home.banner", projectBase: base, bundledMap: nil, store: HotlayoutMemoryPlacementStore(), documents: documents, session: nil, clock: { before }
        )
        XCTAssertEqual(read.placement.document?.documentId, "d-everyday")
        let context = try XCTUnwrap(read.context)
        XCTAssertEqual(context.map.nextBoundary("home.banner", after: before), try date("2026-11-27T22:00:00Z"))

        let sale = await HotlayoutPlacement.show("home.banner", context: context, at: try date("2026-11-28T00:00:00Z"))
        XCTAssertEqual(sale.document?.documentId, "d-sale")
        XCTAssertEqual(sale.entry, "sale")
        XCTAssertEqual(sale.event.documentId, "d-sale")
        let pause = await HotlayoutPlacement.show("home.banner", context: context, at: try date("2026-12-05T12:00:00Z"))
        XCTAssertNil(pause.document)
        XCTAssertEqual(pause.report, .empty)
        XCTAssertEqual(pause.resolution.status, .empty)
        let after = await HotlayoutPlacement.show("home.banner", context: context, at: try date("2026-12-06T00:00:00Z"))
        XCTAssertEqual(after.document?.documentId, "d-everyday")
        XCTAssertEqual(files.count(root + "/placements/published.json"), 1, "the map is asked once, not on a boundary")

        let viaLoad = await HotlayoutPlacement.load(
            name: "home.banner", projectBase: base, store: HotlayoutMemoryPlacementStore(), documents: documents,
            clock: { Date(timeIntervalSince1970: 1_795_816_800) }
        )
        XCTAssertEqual(viaLoad.document?.documentId, "d-sale", "load resolves by the injected clock")
    }
}
