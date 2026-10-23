import XCTest

@testable import HotLayout

/// `HotlayoutPlacement.load` against a real local server: the ETag round trip, the last known
/// copies, the bundled map, and what is never asked for.
final class PlacementLoadTests: XCTestCase {
    private var server: LocalServer?
    /// Path → (status, body, etag). A missing path is a 404.
    private final class Files: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: (status: Int, body: String, etag: String?)] = [:]
        func put(_ path: String, _ body: String, etag: String? = nil, status: Int = 200) {
            lock.lock(); items[path] = (status, body, etag); lock.unlock()
        }
        func get(_ path: String) -> (status: Int, body: String, etag: String?)? {
            lock.lock(); defer { lock.unlock() }
            return items[path]
        }
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
    }

    private func start(_ files: Files) throws -> (base: URL, server: LocalServer) {
        let made = try LocalServer { request in
            guard let item = files.get(request.path) else { return LocalServer.Response(status: 404, headers: ["Content-Length": "0"]) }
            if item.status == 200, let etag = item.etag, request.headers["if-none-match"] == etag {
                return LocalServer.Response(status: 304, headers: ["Content-Length": "0", "ETag": etag])
            }
            var headers = ["Content-Type": "application/json"]
            if let etag = item.etag { headers["ETag"] = etag }
            if item.status != 200 { return LocalServer.Response(status: item.status, headers: ["Content-Length": "0"]) }
            let body = Data(item.body.utf8)
            headers["Content-Length"] = String(body.count)
            return LocalServer.Response(status: 200, headers: headers, chunks: AnyIterator([body].makeIterator()))
        }
        server = made
        return (URL(string: made.base + "/orgs/o/projects/p")!, made)
    }

    private func map(_ places: String) -> String { #"{"placementsVersion":"1.0.0","placements":{\#(places)}}"# }

    private func document(entries: String = #""raffle":"a""#) -> String {
        #"""
        {"schemaVersion":"9.27.0","documentId":"d1","name":"n","initialScreenId":"a","entryPoints":{\#(entries)},
         "screens":[{"screenId":"a","name":"A","root":{"id":"r","type":"Screen","props":{},"children":[]}}]}
        """#
    }

    /// The documents kept by a store given to `load`, by store: one per test.
    private var documentStores: [ObjectIdentifier: HotlayoutMemoryPlacementDocumentStore] = [:]

    private func load(_ name: String, _ base: URL, store: HotlayoutPlacementStore, bundled: String? = nil) async -> HotlayoutPlacement {
        let id = ObjectIdentifier(store as AnyObject)
        let documents = documentStores[id] ?? HotlayoutMemoryPlacementDocumentStore()
        documentStores[id] = documents
        return await HotlayoutPlacement.load(name: name, projectBase: base, bundledMap: bundled, store: store, documents: documents)
    }

    func testPlacesADocumentAndStartsAtItsEntry() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1","entry":"raffle"},"home.plain":{"documentId":"d1"}"#), etag: "\"m1\"")
        files.put("/orgs/o/projects/p/documents/d1/published.json", document())
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()

        let banner = await load("home.banner", base, store: store)
        XCTAssertEqual(banner.mapStatus, .fresh)
        XCTAssertEqual(banner.document?.documentId, "d1")
        XCTAssertEqual(banner.entry, "raffle")
        XCTAssertNil(banner.report)
        let plain = await load("home.plain", base, store: store)
        XCTAssertNotNil(plain.document)
        XCTAssertNil(plain.entry)
    }

    func testAnEntryTheDocumentLacksDrawsItFromTheFirstScreenAndSaysSo() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1","entry":"gone"}"#))
        files.put("/orgs/o/projects/p/documents/d1/published.json", document())
        let (base, _) = try start(files)
        let placement = await load("home.banner", base, store: HotlayoutMemoryPlacementStore())
        XCTAssertNotNil(placement.document)
        XCTAssertNil(placement.entry)
        XCTAssertEqual(placement.report, .entryMissing)
    }

    func testEmptyUnknownAndBrokenPlacesDrawNothing() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.empty":{"documentId":null},"home.broken":{"documentId":"../theme"}"#))
        let (base, server) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        for (name, report) in [("home.empty", HotlayoutPlacementReport.empty), ("home.nope", .unknown), ("home.broken", .unreadable), ("__proto__", .unknown)] {
            let placement = await load(name, base, store: store)
            XCTAssertNil(placement.document, name)
            XCTAssertEqual(placement.report, report, name)
        }
        XCTAssertFalse(server.requests.contains { $0.path.contains("documents") || $0.path.contains("..") }, "no request for a document of a broken place")
    }

    func testADocumentThatIsGoneOrBrokenDrawsNothing() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.gone":{"documentId":"nodoc"},"home.bad":{"documentId":"bad"}"#))
        files.put("/orgs/o/projects/p/documents/bad/published.json", "<html>oops</html>")
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        let gone = await load("home.gone", base, store: store)
        XCTAssertEqual(gone.report, .documentMissing)
        let bad = await load("home.bad", base, store: store)
        XCTAssertEqual(bad.report, .documentUnreadable)
        XCTAssertNil(bad.document)
    }

    func testTheEtagIsSentAndA304KeepsTheLastKnownMap() async throws {
        let files = Files()
        let mapPath = "/orgs/o/projects/p/placements/published.json"
        files.put(mapPath, map(#""home.banner":{"documentId":"d1"}"#), etag: "\"m1\"")
        files.put("/orgs/o/projects/p/documents/d1/published.json", document(), etag: "\"d1\"")
        let (base, server) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        _ = await load("home.banner", base, store: store)
        let again = await load("home.banner", base, store: store)
        XCTAssertEqual(again.mapStatus, .fresh)
        XCTAssertNotNil(again.document)
        let mapRequests = server.requests.filter { $0.path == mapPath }
        XCTAssertEqual(mapRequests.count, 2)
        XCTAssertNil(mapRequests[0].headers["if-none-match"])
        XCTAssertEqual(mapRequests[1].headers["if-none-match"], "\"m1\"")
        let documentRequests = server.requests.filter { $0.path.contains("documents") }
        XCTAssertEqual(documentRequests.last?.headers["if-none-match"], "\"d1\"")
    }

    func testAFreshMapReplacesTheOldOneAndARemovedPlaceIsUnknown() async throws {
        let files = Files()
        let mapPath = "/orgs/o/projects/p/placements/published.json"
        files.put(mapPath, map(#""home.banner":{"documentId":"d1"}"#), etag: "\"m1\"")
        files.put("/orgs/o/projects/p/documents/d1/published.json", document())
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        _ = await load("home.banner", base, store: store)
        files.put(mapPath, map(""), etag: "\"m2\"")
        let removed = await load("home.banner", base, store: store)
        XCTAssertEqual(removed.report, .unknown, "a place missing from a fresh map is not taken from the older one")
    }

    func testWhenTheNetworkIsSilentTheLastKnownMapAndDocumentAreUsed() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#), etag: "\"m1\"")
        files.put("/orgs/o/projects/p/documents/d1/published.json", document())
        let (base, server) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        _ = await load("home.banner", base, store: store)
        server.stop()
        let offline = await load("home.banner", base, store: store)
        XCTAssertEqual(offline.mapStatus, .offline)
        XCTAssertNotNil(offline.document, "the document read last is shown when the network is silent")
        XCTAssertNil(offline.report)
    }

    func testTheBundledMapServesAFirstStartWithoutANetworkAndNotPublishedIsNotOffline() async throws {
        let store = HotlayoutMemoryPlacementStore()
        let silent = URL(string: "http://127.0.0.1:1/p")!
        let bundled = map(#""home.banner":{"documentId":"d1"}"#)
        let first = await load("home.banner", silent, store: store, bundled: bundled)
        XCTAssertEqual(first.mapStatus, .offline)
        XCTAssertEqual(first.resolution.documentId, "d1")
        XCTAssertEqual(first.report, .documentUnreadable, "the document itself could not be had")
        let nothing = await load("home.banner", silent, store: store)
        XCTAssertEqual(nothing.report, .unreadable)

        let (base, _) = try start(Files())
        let unpublished = await load("home.banner", base, store: store)
        XCTAssertEqual(unpublished.mapStatus, .notPublished)
        XCTAssertEqual(unpublished.report, .unknown, "the server said there are no placements")
    }

    func testABrokenAnswerKeepsTheLastKnownMapUntouched() async throws {
        let files = Files()
        let mapPath = "/orgs/o/projects/p/placements/published.json"
        files.put(mapPath, map(#""home.banner":{"documentId":"d1"}"#), etag: "\"m1\"")
        files.put("/orgs/o/projects/p/documents/d1/published.json", document())
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        _ = await load("home.banner", base, store: store)
        files.put(mapPath, "<html>Sign in</html>", etag: "\"m2\"")
        let broken = await load("home.banner", base, store: store)
        XCTAssertEqual(broken.mapStatus, .corrupt)
        XCTAssertNotNil(broken.document)
        files.put(mapPath, #"{"placementsVersion":"2.0.0","placements":{}}"#, etag: "\"m3\"")
        let newer = await load("home.banner", base, store: store)
        XCTAssertEqual(newer.mapStatus, .unsupported)
        XCTAssertNotNil(newer.document)
        XCTAssertEqual(store.value(forKey: "\(base.absoluteString)/placements/published.json")?.contains("d1"), true, "only a fresh map is kept")
    }

    func testAGoneDocumentIsNotBroughtBackFromTheCopy() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#))
        files.put("/orgs/o/projects/p/documents/d1/published.json", document())
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        _ = await load("home.banner", base, store: store)
        files.put("/orgs/o/projects/p/documents/d1/published.json", "", status: 404)
        let gone = await load("home.banner", base, store: store)
        XCTAssertEqual(gone.report, .documentMissing)
    }
}
