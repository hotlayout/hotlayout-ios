import XCTest

@testable import HotLayout

/// Adversarial pass over placements: the placement map and the documents it names come from the
/// network, so they are untrusted input.
///
/// Tests wrapped in `XCTExpectFailure` are FINDINGS: they state what should hold and currently does
/// not; a fix removes the wrapper. The other tests are GUARDS: paths around the claims that were
/// tried and did not work.
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
        XCTExpectFailure("adversary: PlacementVersion refuses parts longer than 9 digits, so a 10-digit major reads as corrupt; the reference (and React, Android) say unsupported") {
            XCTAssertEqual(HotlayoutPlacementMap(text: #"{"placementsVersion":"1234567890.0.0","placements":{}}"#).reading, .unsupported)
        }
        // A 10-digit MINOR of major 1 is a readable map in the reference; here it is corrupt.
        XCTExpectFailure("adversary: same 9-digit cap on the minor") {
            XCTAssertEqual(HotlayoutPlacementMap(text: #"{"placementsVersion":"1.1234567890.0","placements":{}}"#).reading, .map)
        }
    }

    func testDocumentsTheMapNoLongerNamesAreNotKeptForever() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/documents/d1/published.json", document)
        files.put("/orgs/o/projects/p/documents/d2/published.json", document)
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#))
        _ = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store)
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d2"}"#))
        _ = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store)
        // Every document id a map ever named stays in the store (UserDefaults by default, up to 8 MB
        // each, no eviction): a map that rotates ids grows the app's defaults without bound.
        XCTExpectFailure("adversary: the per-document cache under \"<base>#document.<id>\" is never pruned") {
            XCTAssertNil(store.value(forKey: "\(base.absoluteString)#document.d1"))
        }
    }

    func testTheMapDoesNotFollowARedirectToAnotherHost() async throws {
        let elsewhere = Files()
        elsewhere.put("/placements/published.json", map(#""home.banner":{"documentId":null}"#))
        let (otherBase, other) = try start(elsewhere)
        let redirecting = try LocalServer { request in
            request.path.hasSuffix("/placements/published.json") ? .redirect(otherBase.absoluteString.replacingOccurrences(of: "/orgs/o/projects/p", with: "") + "/placements/published.json") : LocalServer.Response(status: 404, headers: ["Content-Length": "0"])
        }
        servers.append(redirecting)
        let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: URL(string: redirecting.base + "/orgs/o/projects/p")!, store: HotlayoutMemoryPlacementStore())
        XCTExpectFailure("adversary: URLSession follows a cross-origin redirect for the map (Android refuses redirects and reads it as offline)") {
            XCTAssertTrue(other.requests.isEmpty)
            XCTAssertEqual(placement.mapStatus, .offline)
        }
    }

    // MARK: - guards

    func testADocumentIdThatWouldLeaveTheProjectIsNeverRequested() async throws {
        let escapes = ["..", ".", "...", "%2e%2e", "%2F", "a/b", #"a\b"#, "//evil.test", "https://evil.test/x", "d?x=1", "d#x", "．．", "ｄ1", "d\n", " d", "d ", "d\u{0}", "d\u{200B}", "", String(repeating: "x", count: 65)]
        for id in escapes {
            let files = Files()
            let encoded = String(data: try JSONSerialization.data(withJSONObject: [id], options: [.fragmentsAllowed]), encoding: .utf8)!.dropFirst().dropLast()
            files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":\#(encoded)}"#))
            let (base, server) = try start(files)
            let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: HotlayoutMemoryPlacementStore())
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
        // Cross-reader note: the depth cap (256) makes this corrupt here and on Android; React and Flutter read a map.
        XCTAssertEqual(HotlayoutPlacementMap(text: text).reading, .corrupt)
    }

    func testABodyWithAByteOrderMark() async throws {
        // Cross-reader note: corrupt here and on Android; React and Flutter strip the BOM and read a map.
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", "\u{FEFF}" + map(#""home.banner":{"documentId":null}"#))
        let (base, _) = try start(files)
        let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: HotlayoutMemoryPlacementStore())
        XCTAssertEqual(placement.mapStatus, .corrupt)
    }

    func testTheLastKnownMapIsScopedByProject() async throws {
        let filesA = Files()
        filesA.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":null}"#))
        let (baseA, _) = try start(filesA)
        let (baseB, _) = try start(Files())
        let store = HotlayoutMemoryPlacementStore()
        _ = await HotlayoutPlacement.load(name: "home.banner", projectBase: baseA, store: store)
        let b = await HotlayoutPlacement.load(name: "home.banner", projectBase: baseB, store: store)
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
            store.set(good, forKey: "\(base.absoluteString)#map")
            let placement = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store)
            XCTAssertEqual(store.value(forKey: "\(base.absoluteString)#map"), good)
            XCTAssertEqual(placement.resolution.status, .empty)
        }
    }

    func testADocumentThatIsGoneIsNotRevivedFromTheCache() async throws {
        let files = Files()
        files.put("/orgs/o/projects/p/placements/published.json", map(#""home.banner":{"documentId":"d1"}"#))
        let (base, _) = try start(files)
        let store = HotlayoutMemoryPlacementStore()
        store.set(document, forKey: "\(base.absoluteString)#document.d1")
        let missing = await HotlayoutPlacement.load(name: "home.banner", projectBase: base, store: store)
        XCTAssertEqual(missing.report, .documentMissing)
        XCTAssertNil(store.value(forKey: "\(base.absoluteString)#document.d1"))
    }
}
