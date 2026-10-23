import XCTest

@testable import HotLayout

/// The shared table of placements (`fixtures/placements/placement-cases.json`): every row of
/// every group.
final class PlacementCasesTests: XCTestCase {
    private func table() throws -> JSONValue { try Contract.json("fixtures/placements/placement-cases.json") }

    private func assertResolves(_ map: HotlayoutPlacementMap, _ expected: [JSONValue], _ row: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var count = 0
        for item in expected.compactMap(\.objectValue) {
            let name = item["name"]?.stringValue ?? "?"
            let resolved = map.resolve(name)
            XCTAssertEqual(resolved.status.rawValue, item["status"]?.stringValue, "\(row) / \(name): status", file: file, line: line)
            XCTAssertEqual(resolved.documentId, item["documentId"]?.stringValue, "\(row) / \(name): documentId", file: file, line: line)
            XCTAssertEqual(resolved.entry, item["entry"]?.stringValue, "\(row) / \(name): entry", file: file, line: line)
            count += 1
        }
        return count
    }

    private func readingName(_ reading: HotlayoutPlacementMap.Reading) -> String {
        switch reading {
        case .map: return "map"
        case .corrupt: return "corrupt"
        case .unsupported: return "unsupported"
        }
    }

    func testReadCases() throws {
        let rows = Contract.rows(try table(), "readCases")
        XCTAssertEqual(rows.count, 36)
        var resolutions = 0
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let map: HotlayoutPlacementMap
            if let text = row["text"]?.stringValue {
                map = HotlayoutPlacementMap(text: text)
                XCTAssertEqual(HotlayoutPlacementMap(data: Data(text.utf8)), map, "\(name): text and data read alike")
            } else if let json = row["json"] {
                map = HotlayoutPlacementMap(json: json)
            } else {
                XCTFail("\(name): the row has neither text nor json")
                continue
            }
            XCTAssertEqual(readingName(map.reading), row["read"]?.stringValue, name)
            resolutions += assertResolves(map, row["resolve"]?.arrayValue ?? [], name)
        }
        XCTAssertEqual(resolutions, 80)
    }

    func testSourceCases() throws {
        let rows = Contract.rows(try table(), "sourceCases")
        XCTAssertEqual(rows.count, 21)
        var resolutions = 0
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let network = row["network"]?.objectValue ?? JSONObject()
            let outcome: PlacementNetworkOutcome
            switch network["kind"]?.stringValue {
            case "map": outcome = .map(network["text"]?.stringValue ?? "")
            case "notModified": outcome = .notModified
            case "notFound": outcome = .notFound
            case "offline": outcome = .offline
            default:
                XCTFail("\(name): unknown network kind")
                continue
            }
            let decision = PlacementSource.pick(network: outcome, lastKnown: row["lastKnown"]?.stringValue, bundled: row["bundled"]?.stringValue)
            let expected = row["expected"]?.objectValue ?? JSONObject()
            let source: String
            switch decision.source {
            case .network: source = "network"
            case .lastKnown: source = "lastKnown"
            case .bundled: source = "bundled"
            case .none: source = "none"
            }
            XCTAssertEqual(source, expected["source"]?.stringValue, "\(name): source")
            XCTAssertEqual(decision.status.rawValue, expected["status"]?.stringValue, "\(name): status")
            XCTAssertEqual(decision.remember, expected["remember"]?.boolValue, "\(name): remember")
            resolutions += assertResolves(decision.map, row["resolve"]?.arrayValue ?? [], name)
        }
        XCTAssertEqual(resolutions, 22)
    }

    func testShowingCases() throws {
        let rows = Contract.rows(try table(), "showingCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let given = row["resolution"]?.objectValue ?? JSONObject()
            let resolution = HotlayoutPlacementResolution(
                status: HotlayoutPlacementResolution.Status(rawValue: given["status"]?.stringValue ?? "") ?? .unreadable,
                documentId: given["documentId"]?.stringValue, entry: given["entry"]?.stringValue
            )
            var document: PlacementDocumentOutcome?
            if let read = row["document"]?.objectValue {
                switch read["kind"]?.stringValue {
                case "ok": document = .ok(entryPoints: Set((read["entryPoints"]?.arrayValue ?? []).compactMap(\.stringValue)))
                case "missing": document = .missing
                default: document = .unreadable
                }
            }
            let showing = PlacementShowing.of(resolution, document: document)
            let expected = row["expected"]?.objectValue ?? JSONObject()
            XCTAssertEqual(showing.showsDocument ? "document" : "nothing", expected["show"]?.stringValue, "\(name): show")
            XCTAssertEqual(showing.entry, expected["entry"]?.stringValue, "\(name): entry")
            XCTAssertEqual(showing.report?.rawValue, expected["report"]?.stringValue, "\(name): report")
        }
    }

    // MARK: - reading the bytes, the transport, the events, the memory

    /// The bytes of a row: parts joined in order, `text` as UTF-8, `hex` as raw bytes, `times` repeating.
    private func bytes(_ parts: JSONValue?) -> Data {
        var out = Data()
        for part in (parts?.arrayValue ?? []).compactMap(\.objectValue) {
            var piece = Data()
            if let text = part["text"]?.stringValue {
                piece = Data(text.utf8)
            } else if let hex = part["hex"]?.stringValue {
                var index = hex.startIndex
                while index < hex.endIndex {
                    let next = hex.index(index, offsetBy: 2)
                    piece.append(UInt8(hex[index..<next], radix: 16)!)
                    index = next
                }
            }
            for _ in 0..<(part["times"].flatMap { $0.numberValue.map(Int.init) } ?? 1) { out.append(piece) }
        }
        return out
    }

    func testBodyCases() throws {
        let rows = Contract.rows(try table(), "bodyCases")
        XCTAssertEqual(rows.count, 26)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let map = HotlayoutPlacementMap(data: bytes(row["body"]))
            XCTAssertEqual(readingName(map.reading), row["read"]?.stringValue, name)
            _ = assertResolves(map, row["resolve"]?.arrayValue ?? [], name)
        }
    }

    func testTransportCases() throws {
        let rows = Contract.rows(try table(), "transportCases")
        XCTAssertEqual(rows.count, 26)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let answer = row["answer"]?.objectValue ?? JSONObject()
            let reply = PlacementReply(
                status: answer["status"]?.numberValue.map(Int.init) ?? 0, body: bytes(answer["body"]),
                completedAtMs: answer["completedAtMs"]?.numberValue.map(Int.init)
            )
            let actual: String
            if row["request"]?.stringValue == "map" {
                switch PlacementAnswer.map(reply) {
                case .map: actual = "map"
                case .corrupt: actual = "corrupt"
                case .notModified: actual = "notModified"
                case .notFound: actual = "notFound"
                case .offline: actual = "offline"
                }
            } else {
                switch PlacementAnswer.document(reply) {
                case .read: actual = "read"
                case .notModified: actual = "notModified"
                case .missing: actual = "missing"
                case .unreadable: actual = "unreadable"
                }
            }
            XCTAssertEqual(actual, row["expected"]?.stringValue, name)
        }
    }

    func testEventCases() throws {
        let rows = Contract.rows(try table(), "eventCases")
        XCTAssertEqual(rows.count, 8)
        func event(_ state: JSONObject) -> HotlayoutPlacementEvent {
            HotlayoutPlacementEvent(
                status: state["status"]?.stringValue ?? "",
                report: state["report"]?.stringValue.flatMap(HotlayoutPlacementReport.init(rawValue:)),
                mapStatus: HotlayoutPlacementMapStatus(rawValue: state["mapStatus"]?.stringValue ?? "") ?? .offline,
                documentId: state["documentId"]?.stringValue, entry: state["entry"]?.stringValue
            )
        }
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            var tracker = PlacementEventTracker()
            let told = (row["states"]?.arrayValue ?? []).compactMap(\.objectValue).compactMap { tracker.next(event($0)) }
            let expected = (row["events"]?.arrayValue ?? []).compactMap(\.objectValue).map(event)
            XCTAssertEqual(told, expected, name)
        }
    }

    private final class Hub: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: (Int, Data)] = [:]
        func put(_ path: String, _ status: Int, _ body: Data = Data()) { lock.lock(); items[path] = (status, body); lock.unlock() }
        func clear() { lock.lock(); items = [:]; lock.unlock() }
        func get(_ path: String) -> (Int, Data)? { lock.lock(); defer { lock.unlock() }; return items[path] }
    }

    func testCacheCases() async throws {
        let rows = Contract.rows(try table(), "cacheCases")
        XCTAssertEqual(rows.count, 3)
        let hub = Hub()
        let server = try LocalServer { request in
            guard let (status, body) = hub.get(request.path) else { return LocalServer.Response(status: 404, headers: ["Content-Length": "0"]) }
            if status != 200 { return LocalServer.Response(status: status, headers: ["Content-Length": "0"]) }
            return .data(body, type: "application/json")
        }
        defer { server.stop() }
        let document = #"""
            {"schemaVersion":"9.27.0","documentId":"d1","name":"n","initialScreenId":"a","entryPoints":{},
             "screens":[{"screenId":"a","name":"A","root":{"id":"r","type":"Screen","props":{},"children":[]}}]}
            """#
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let store = HotlayoutMemoryPlacementStore()
            let documents = HotlayoutMemoryPlacementDocumentStore()
            for (index, step) in (row["steps"]?.arrayValue ?? []).compactMap(\.objectValue).enumerated() {
                hub.clear()
                let project = step["project"]?.stringValue ?? "?"
                let root = "/orgs/o/projects/\(project)"
                let map = step["map"]?.objectValue ?? JSONObject()
                if map["kind"]?.stringValue == "map" {
                    hub.put(root + "/placements/published.json", 200, Data((map["text"]?.stringValue ?? "").utf8))
                } else {
                    hub.put(root + "/placements/published.json", 503)
                }
                switch step["document"]?.stringValue {
                case "ok": hub.put(root + "/documents/d1/published.json", 200, Data(document.utf8))
                case "notFound": hub.put(root + "/documents/d1/published.json", 404)
                case "offline": hub.put(root + "/documents/d1/published.json", 503)
                default: break
                }
                let placement = await HotlayoutPlacement.load(
                    name: "home.banner", projectBase: URL(string: server.base + root)!, store: store, documents: documents
                )
                let expected = step["expected"]?.objectValue ?? JSONObject()
                let event = placement.event
                XCTAssertEqual(event.status, expected["status"]?.stringValue, "\(name) / step \(index): status")
                XCTAssertEqual(event.report?.rawValue, expected["report"]?.stringValue, "\(name) / step \(index): report")
                XCTAssertEqual(event.mapStatus.rawValue, expected["mapStatus"]?.stringValue, "\(name) / step \(index): mapStatus")
            }
        }
    }
}
