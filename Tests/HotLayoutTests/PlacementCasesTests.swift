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
}
