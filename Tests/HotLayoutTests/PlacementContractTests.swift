import XCTest

@testable import HotLayout

/// The shipped mirrors of the placement contract against the artifact (`placements.json`), and
/// the forms against the artifact's own patterns on hostile input.
final class PlacementContractTests: XCTestCase {
    private func artifact() throws -> JSONObject {
        try XCTUnwrap(Contract.json("placements.json").objectValue)
    }

    private func limits() throws -> JSONObject {
        try XCTUnwrap(try artifact()["x-limits"]?.objectValue)
    }

    func testVersionAndLimitsMirrorTheArtifact() throws {
        XCTAssertEqual(HotlayoutVersions.placements, try artifact()["x-placementsVersion"]?.stringValue)
        let limits = try limits()
        XCTAssertEqual(limits["name"]?.objectValue?["maxLength"]?.numberValue, Double(PlacementForms.nameMax))
        XCTAssertEqual(limits["entry"]?.objectValue?["maxLength"]?.numberValue, Double(PlacementForms.entryMax))
        XCTAssertEqual(limits["documentId"]?.objectValue?["pattern"]?.stringValue, "^(?!\\.+$)[A-Za-z0-9._-]{1,\(PlacementForms.documentIdMax)}$")
    }

    func testThePolicyBlocksSayWhatTheReaderDoes() throws {
        let reading = try XCTUnwrap(try artifact()["x-placementReading"]?.objectValue)
        XCTAssertEqual(reading["notAMap"]?.stringValue, "corrupt")
        XCTAssertEqual(reading["otherMajor"]?.stringValue, "unsupported")
        XCTAssertEqual(reading["invalidName"]?.stringValue, "unknown")
        XCTAssertEqual(reading["nullDocument"]?.stringValue, "empty")
        XCTAssertEqual(reading["brokenPlace"]?.stringValue, "unreadable")
        XCTAssertEqual(reading["limits"]?.stringValue, "publish-only")
        let statuses = try XCTUnwrap(try artifact()["x-placementSource"]?.objectValue?["statuses"]?.objectValue)
        XCTAssertEqual(Set(statuses.keys), Set(["fresh", "offline", "corrupt", "unsupported", "notPublished"]))
        XCTAssertEqual(Set(statuses.keys), Set(["fresh", "offline", "corrupt", "unsupported", "notPublished"].filter { HotlayoutPlacementMapStatus(rawValue: $0) != nil }))
    }

    /// The hand-written forms agree with the artifact's patterns on a large generated set of
    /// strings, hostile ones included (a final newline, non-ASCII look-alikes, dots, slashes).
    func testFormsAgreeWithTheArtifactPatterns() throws {
        let limits = try limits()
        func regex(_ key: String) throws -> NSRegularExpression {
            try NSRegularExpression(pattern: try XCTUnwrap(limits[key]?.objectValue?["pattern"]?.stringValue))
        }
        let name = try regex("name"), documentId = try regex("documentId"), entry = try regex("entry")
        func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
            // `$` of NSRegularExpression also matches before a final newline; the contract's does not.
            if text.hasSuffix("\n") { return false }
            return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        let alphabet = Array("ab09AZ.-_/\\ \n\u{0430}\u{FF41}".map(String.init)) + ["..", "%2e"]
        var generator = SystemRandomNumberGenerator()
        var samples = ["", ".", "..", "...", "a", "a.", ".a", "a..b", "a.-b", "a-b", "A", "home.banner", "home.banner\n", "../theme", "a/b", "a\u{0000}"]
        samples += [String(repeating: "a", count: 64), String(repeating: "a", count: 65), String(repeating: "9", count: 48), String(repeating: "9", count: 49)]
        for _ in 0..<20_000 {
            samples.append((0..<Int.random(in: 1...8, using: &generator)).map { _ in alphabet.randomElement(using: &generator) ?? "a" }.joined())
        }
        for text in samples where text.utf8.count <= PlacementForms.nameMax + 1 {
            XCTAssertEqual(PlacementForms.isName(text), matches(name, text) && text.count <= 64, "name “\(text.debugDescription)”")
            XCTAssertEqual(PlacementForms.isDocumentId(text), matches(documentId, text), "documentId “\(text.debugDescription)”")
            XCTAssertEqual(PlacementForms.isEntry(text), matches(entry, text) && text.count <= 48, "entry “\(text.debugDescription)”")
        }
    }

    func testTheLimitsOnSizeAndCountArePublishOnly() {
        var places = ""
        for index in 0..<250 { places += #""p\#(index)":{"documentId":"d\#(index)"},"# }
        let big = HotlayoutPlacementMap(text: #"{"placementsVersion":"1.0.0","placements":{\#(places)"home":{"documentId":"last"}}}"#)
        XCTAssertEqual(big.reading, .map)
        XCTAssertEqual(big.resolve("p249").documentId, "d249")
        XCTAssertEqual(big.resolve("home").documentId, "last")
        let padding = String(repeating: " ", count: 70_000)
        let wide = HotlayoutPlacementMap(text: #"{"placementsVersion":"1.0.0","placements":{"home":{"documentId":"d"}}}"# + padding)
        XCTAssertEqual(wide.resolve("home").documentId, "d")
    }

    func testHostileNames() {
        let map = HotlayoutPlacementMap(text: #"{"placementsVersion":"1.0.0","placements":{"home.banner":{"documentId":"d1"},"constructor":{"documentId":"d2"}}}"#)
        for name in ["", "__proto__", "toString", "hasOwnProperty", "HOME.BANNER", "home.banner\n", " home.banner", "home.banner ", "home..banner",
            "home.banner.", ".home", "home/banner", "../home.banner", "home.banner\u{0000}", "h\u{043E}me.banner", String(repeating: "a", count: 65)] {
            XCTAssertEqual(map.resolve(name).status, .unknown, name.debugDescription)
        }
        XCTAssertEqual(map.resolve("constructor").documentId, "d2")
        XCTAssertEqual(map.resolve("home.banner").documentId, "d1")
        let broken = HotlayoutPlacementMap(text: "[]")
        for name in ["", "__proto__", "home.banner"] { XCTAssertEqual(broken.resolve(name).status, .unreadable) }
    }
}
