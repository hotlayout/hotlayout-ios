import XCTest

@testable import HotLayout

/// Adversarial pass over placements: the placement map and the documents it names come from the
/// network, so they are untrusted input.
///
/// The first group are the findings of the audit, now fixed; the second are GUARDS: paths around
/// the claims that were tried and did not work.
final class PlacementAdversarialTests: XCTestCase {
    private var servers: [LocalServer] = []
    private final class Files: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: String] = [:]
        func put(_ path: String, _ body: String) { lock.lock(); items[path] = body; lock.unlock() }
        func get(_ path: String) -> String? { lock.lock(); defer { lock.unlock() }; return items[path] }
    }

    override func tearDown() async throws {
        servers.forEach { $0.stop() }
        servers = []
    }

    private func start(_ files: Files) throws -> (base: URL, server: LocalServer) {
        let made = try LocalServer { request in
            guard let body = files.get(request.path) else { return LocalServer.Response(status: 404, headers: ["Content-Length": "0"]) }
            return .data(Data(body.utf8), type: "application/json")
        }
        servers.append(made)
        return (URL(string: made.base + "/orgs/o/projects/p")!, made)
    }

    private func map(_ places: String) -> String { #"{"placementsVersion":"1.0.0","placements":{\#(places)}}"# }

    private let document = #"""
        {"schemaVersion":"9.27.0","documentId":"d","name":"n","initialScreenId":"a","entryPoints":{"raffle":"a"},
         "screens":[{"screenId":"a","name":"A","root":{"id":"r","type":"Screen","props":{},"children":[]}}]}
        """#

    // MARK: - findings

    func testAMajorTooLongForNineDigitsIsUnsupportedAsInTheReference() {
        XCTAssertEqual(HotlayoutPlacementMap(text: #"{"placementsVersion":"1234567890.0.0","placements":{}}"#).reading, .unsupported)
        // A 10-digit MINOR of major 1 is a readable map.
        XCTAssertEqual(HotlayoutPlacementMap(text: #"{"placementsVersion":"1.1234567890.0","placements":{}}"#).reading, .map)
        // A major that would wrap around to 1 in a 32- or 64-bit integer is still another major.
        for major in ["4294967297", "18446744073709551617", "1000000000000000000000001"] {
            XCTAssertEqual(HotlayoutPlacementMap(text: #"{"placementsVersion":"\#(major).0.0","placements":{}}"#).reading, .unsupported, major)
        }
    }

    func testDocumentsTheMapNoLongerNamesAreNotKeptForever() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/documents/d1/published.json", document)
        files.put("/orgs/o/projects/p/documents/d2/published.json", document)
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        let documents = HotlayoutMemoryPlacementDocumentStore()
        func load() async -> HotlayoutPlacement {
            await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store, documents: documents)
        }
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#))
        _ = await load()
        let d1 = base.absoluteString + "/documents/d1/published.json"
        let d2 = base.absoluteString + "/documents/d2/published.json"
        XCTAssertEqual(documents.keys(), [d1])
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d2"}"#))
        _ = await load()
        XCTAssertEqual(documents.keys(), [d2], "one document for the place, and none for an id the map dropped")
        // A document of another project is not touched by this project's pruning.
        let other = "https://other.example/documents/x/published.json"
        documents.setDocument(HotlayoutPlacementCachedDocument(data: Data("x".utf8), etag: nil), forKey: other)
        files.put("/orgs/o/projects/p/placements/published.json", map(""))
        _ = await load()
        XCTAssertEqual(documents.keys(), [other])
    }

    func testDocumentsLiveInFilesAndNotInUserDefaults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hl-placements-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#))
        files.put("/orgs/o/projects/p/documents/d1/published.json", document)
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        let documents = HotlayoutFilePlacementDocumentStore(directory: directory)
        let first = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store, documents: documents)
        XCTAssertNotNil(first.document)
        XCTAssertNil(store.value(forKey: base.absoluteString + "/documents/d1/published.json"))
        XCTAssertEqual(documents.keys(), [base.absoluteString + "/documents/d1/published.json"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        // A new store object over the same directory reads the copy.
        let reopened = HotlayoutFilePlacementDocumentStore(directory: directory)
        XCTAssertEqual(reopened.document(forKey: base.absoluteString + "/documents/d1/published.json")?.data, Data(document.utf8))
        reopened.setDocument(nil, forKey: base.absoluteString + "/documents/d1/published.json")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 0)
    }

    func testTheMapDoesNotFollowARedirectToAnotherHost() async throws {
        let elsewhere = Files()
        elsewhere.put("/placements/published.json", map(#""home.banner":{"documentId":null}"#))
        let (otherBase, other) = try start(elsewhere)
        let redirecting = try LocalServer { request in
            request.path.hasSuffix("/placements/published.json") ? .redirect(otherBase.absoluteString.replacingOccurrences(of: "/orgs/o/projects/p", with: "") + "/placements/published.json") : LocalServer.Response(status: 404, headers: ["Content-Length": "0"])
        }
        servers.append(redirecting)
        let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: URL(string: redirecting.base + "/orgs/o/projects/p")!, store: HotlayoutMemoryPlacementStore(), documents: HotlayoutMemoryPlacementDocumentStore())
        XCTAssertTrue(other.requests.isEmpty)
        XCTAssertEqual(placement.mapStatus, .offline)
    }

    func testARedirectWithinTheSameHostIsNotFollowedEither() async throws {
        let files = Files()
        files.put("/elsewhere/map.json", map(#""home.banner":{"documentId":null}"#))
        let server = try LocalServer { request in
            if request.path == "/orgs/o/projects/p/placements/published.json" { return .redirect("/elsewhere/map.json") }
            return files.get(request.path).map { .data(Data($0.utf8), type: "application/json") } ?? LocalServer.Response(status: 404, headers: ["Content-Length": "0"])
        }
        servers.append(server)
        let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: URL(string: server.base + "/orgs/o/projects/p")!, store: HotlayoutMemoryPlacementStore(), documents: HotlayoutMemoryPlacementDocumentStore())
        XCTAssertEqual(placement.mapStatus, .offline)
        XCTAssertFalse(server.requests.contains { $0.path == "/elsewhere/map.json" })
    }

    func testADocumentThatRedirectsIsUnreadable() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#))
        files.put("/elsewhere/doc.json", document)
        let server = try LocalServer { request in
            if request.path == "/orgs/o/projects/p/documents/d1/published.json" { return .redirect("/elsewhere/doc.json") }
            return files.get(request.path).map { .data(Data($0.utf8), type: "application/json") } ?? LocalServer.Response(status: 404, headers: ["Content-Length": "0"])
        }
        servers.append(server)
        let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: URL(string: server.base + "/orgs/o/projects/p")!, store: HotlayoutMemoryPlacementStore(), documents: HotlayoutMemoryPlacementDocumentStore())
        XCTAssertEqual(placement.report, .documentUnreadable)
        XCTAssertFalse(server.requests.contains { $0.path == "/elsewhere/doc.json" })
    }

    // MARK: - guards

    func testADocumentIdThatWouldLeaveTheProjectIsNeverRequested() async throws {
        let escapes = ["..", ".", "...", "%2e%2e", "%2F", "a/b", #"a\b"#, "//evil.test", "https://evil.test/x", "d?x=1", "d#x", "．．", "ｄ1", "d\n", " d", "d ", "d\u{0}", "d\u{200B}", "", String(repeating: "x", count: 65)]
        for id in escapes {
            let files = Files()
            let encoded = String(data: try JSONSerialization.data(withJSONObject: [id], options: [.fragmentsAllowed]), encoding: .utf8)!.dropFirst().dropLast()
            files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":\#(encoded)}"#))
            let (base, server) = try start(files)
            let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: HotlayoutMemoryPlacementStore(), documents: HotlayoutMemoryPlacementDocumentStore())
            XCTAssertEqual(placement.resolution.status, .unreadable, id)
            XCTAssertEqual(server.requests.map(\.path), ["/orgs/o/projects/p/placements/published.json"], id)
        }
    }

    func testOwnKeysOnly() {
        let read = HotlayoutPlacementMap(text: #"{"placementsVersion":"1.0.0","placements":{"__proto__":{"documentId":"x"},"constructor":{"documentId":"c"}}}"#)
        XCTAssertEqual(read.resolve("__proto__").status, .unknown)
        XCTAssertEqual(read.resolve("constructor").documentId, "c")
        XCTAssertEqual(HotlayoutPlacementMap(text: map("")).resolve("constructor").status, .unknown)
    }

    func testMalformedVersionsAreCorrupt() {
        for version in ["01.0.0", "1.0.0-x", "1.0.0+b", "1.0", " 1.0.0", "1.0.0 ", "1.0.0\\n", "v1.0.0", "١.0.0", "+1.0.0", "-1.0.0", ""] {
            XCTAssertEqual(HotlayoutPlacementMap(text: #"{"placementsVersion":"\#(version)","placements":{}}"#).reading, .corrupt, version)
        }
    }

    func testDuplicateKeysTakeTheLast() {
        let read = HotlayoutPlacementMap(text: #"{"placementsVersion":"1.0.0","placements":{"home.banner":{"documentId":"a"},"home.banner":{"documentId":null}}}"#)
        XCTAssertEqual(read.resolve("home.banner").status, .empty)
    }

    func testHostileEntriesAreUnreadable() {
        for entry in ["__proto__", "A", "-x", "x_y", String(repeating: "x", count: 49), "x\\n", "ｘ"] {
            XCTAssertEqual(HotlayoutPlacementMap(text: map(#""home.banner":{"documentId":"d","entry":"\#(entry)"}"#)).resolve("home.banner").status, .unreadable, entry)
        }
    }

    func testDeepJSONDoesNotOverflowTheStack() {
        let depth = 100_000
        let text = #"{"placementsVersion":"1.0.0","placements":{},"x":"# + String(repeating: "[", count: depth) + String(repeating: "]", count: depth) + "}"
        XCTAssertEqual(HotlayoutPlacementMap(text: text).reading, .corrupt)
    }

    func testABodyWithOneByteOrderMarkIsRead() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", "\u{FEFF}" + map(#""home.banner":{"documentId":null}"#))
        let (base, _) = try start(files)
        let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: HotlayoutMemoryPlacementStore(), documents: HotlayoutMemoryPlacementDocumentStore())
        XCTAssertEqual(placement.mapStatus, .fresh)
        XCTAssertEqual(placement.report, .empty)
    }

    func testTheLastKnownMapIsScopedByProject() async throws {
        let filesA = Files()
        filesA.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":null}"#))
        let (baseA, _) = try start(filesA)
        let (baseB, _) = try start(Files())
        let store = HotlayoutMemoryPlacementStore()
        _ = await HotlayoutPlacement.load(name: "home.banner", projectBase: baseA, store: store, documents: HotlayoutMemoryPlacementDocumentStore())
        let b = await HotlayoutPlacement.load(name: "home.banner", projectBase: baseB, store: store, documents: HotlayoutMemoryPlacementDocumentStore())
        XCTAssertEqual(b.mapStatus, .notPublished)
        XCTAssertEqual(b.resolution.status, .unknown)
    }

    func testCorruptOtherMajorAnd404NeverOverwriteTheLastKnownMap() async throws {
        let good = map(#""home.banner":{"documentId":null}"#)
        for answer in ["<html>", #"{"placementsVersion":"2.0.0","placements":{}}"#, nil] {
            let files = Files()
            if let answer { files.put("/orgs/o/projects/p/placements/published.json", answer) }
            let (base, _) = try start(files)
            let store = HotlayoutMemoryPlacementStore()
            store.set(good, forKey: "\(base.absoluteString)/placements/published.json")
            let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store, documents: HotlayoutMemoryPlacementDocumentStore())
            XCTAssertEqual(store.value(forKey: "\(base.absoluteString)/placements/published.json"), good)
            XCTAssertEqual(placement.resolution.status, .empty)
        }
    }

    func testADocumentThatIsGoneIsNotRevivedFromTheCache() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#))
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        let documents = HotlayoutMemoryPlacementDocumentStore()
        let key = base.absoluteString + "/documents/d1/published.json"
        documents.setDocument(HotlayoutPlacementCachedDocument(data: Data(document.utf8), etag: nil), forKey: key)
        let missing = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store, documents: documents)
        XCTAssertEqual(missing.report, .documentMissing)
        XCTAssertNil(documents.document(forKey: key))
    }

    func testABodyThatNeverEndsIsNoAnswerAfterTheDeadline() async throws {
        let stalled = try LocalServer { _ in
            var sent = false
            let chunks = AnyIterator<Data> {
                if !sent { sent = true; return Data("{".utf8) }
                Thread.sleep(forTimeInterval: 5)
                return nil
            }
            return LocalServer.Response(status: 200, headers: ["Content-Type": "application/json"], chunks: chunks)
        }
        servers.append(stalled)
        var transport = PlacementTransport(session: PlacementTransport.defaultSession())
        transport.deadline = .milliseconds(300)
        let started = Date()
        let reply = await transport.get(URL(string: stalled.base + "/map.json")!, etag: nil, maxBytes: PlacementBody.maxBytes)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertNil(reply.completedAtMs)
        XCTAssertEqual(PlacementAnswer.map(reply), .offline)
    }
}
