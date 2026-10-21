import XCTest

@testable import HotLayout

final class DocumentTests: XCTestCase {
    /// Every screen fixture of the contract loads: the reader is tolerant, so a fixture of any
    /// minor of this major is readable, and unknown pieces end in reports, not in a failure.
    func testEveryFixtureLoads() throws {
        let folder = Contract.root.appendingPathComponent("fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertGreaterThan(files.count, 30)
        for file in files {
            let document = try HotlayoutDocument.load(Data(contentsOf: file))
            XCTAssertFalse(document.screens.isEmpty, file.lastPathComponent)
            XCTAssertFalse(document.reports.contains { $0.kind == .unknownWidget }, "\(file.lastPathComponent): \(document.reports)")
        }
    }

    func testVersionGate() {
        XCTAssertEqual(HotlayoutVersions.check("9.0.0"), .compatible)
        XCTAssertEqual(HotlayoutVersions.check("9.27.5"), .compatible)
        XCTAssertEqual(HotlayoutVersions.check("9.99.0"), .newerMinor(documentVersion: "9.99.0"))
        XCTAssertFalse(HotlayoutVersions.check("10.0.0").isReadable)
        XCTAssertFalse(HotlayoutVersions.check("8.20.0").isReadable)
        XCTAssertFalse(HotlayoutVersions.check("9.1").isReadable)
        XCTAssertFalse(HotlayoutVersions.check("+9.1.0").isReadable)
        XCTAssertThrowsError(try HotlayoutDocument.load(Data(#"{"schemaVersion":"10.0.0","screens":[]}"#.utf8)))
    }

    func testPiecesOfTheWrongShapeAreReportedNotFatal() throws {
        let json = #"""
        {"schemaVersion":"9.27.0","documentId":"d","name":"n","initialScreenId":"a",
         "entryPoints":{"__proto__":"a","promo":"a"},
         "screens":[{"screenId":"a","name":"A","root":{"id":"r","type":"Screen","props":{"gap":"sm"},
           "children":[42,{"id":"x"},{"id":"w","type":"FancyWidget","props":{},"children":[{"id":"t","type":"Text","props":"oops"}]}]}}]}
        """#
        let document = try HotlayoutDocument.load(Data(json.utf8))
        let root = document.screens[0].root
        XCTAssertEqual(root.children.map(\.id), ["w"])
        XCTAssertEqual(root.children[0].children.map(\.type), ["Text"])
        XCTAssertEqual(document.entryPoints, ["promo": "a"])
        XCTAssertTrue(document.reports.contains { $0.kind == .unknownWidget })
        XCTAssertGreaterThanOrEqual(document.reports.filter { $0.kind == .ignoredInput }.count, 3)
    }

    func testTooDeepIsRefusedBeforeRecursion() {
        var node = #"{"id":"leaf","type":"Text","props":{}}"#
        for level in 0..<40 { node = #"{"id":"c\#(level)","type":"Column","props":{},"children":[\#(node)]}"# }
        let json = #"{"schemaVersion":"9.27.0","documentId":"d","name":"n","initialScreenId":"a","screens":[{"screenId":"a","name":"A","root":\#(node)}]}"#
        XCTAssertThrowsError(try HotlayoutDocument.load(Data(json.utf8))) { error in
            XCTAssertEqual(error as? HotlayoutLoadError, .maxDepthExceeded(screenId: "a"))
        }
    }

    func testFirstMatchingStateLaysOverTheBase() throws {
        let node = try XCTUnwrap(DocumentReader.node(
            [
                "id": "n", "type": "Container", "props": [:],
                "style": ["padding": "md", "background": ["kind": "color", "color": "surface"]],
                "styleWhen": [
                    ["when": ["path": "task.done", "op": "isTrue"], "style": ["background": ["kind": "color", "color": "success"]]],
                    ["when": ["path": "task.done", "op": "isTrue"], "style": ["padding": "xl"]],
                ],
            ],
            location: "test", position: "root", sink: ReportSink()))
        let done = NodeStyle.effective(node, scope: ["task.done": true])
        XCTAssertEqual(done["padding"], "md")
        XCTAssertEqual(done["background"]?["color"], "success")
        XCTAssertEqual(NodeStyle.effective(node, scope: [:])["background"]?["color"], "surface")
    }

    func testTokenOrOwnValue() {
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme("light"))
        XCTAssertEqual(resolver.color("primary"), RGBA(hex: "#4f46e5"))
        XCTAssertEqual(resolver.color(["token": "primary", "opacity": 0.5])?.alpha, 0.5)
        XCTAssertEqual(resolver.color(["value": "#ff000080"])?.alpha ?? 0, 128.0 / 255, accuracy: 0.0001)
        XCTAssertNil(resolver.color("no-such-token"))
        XCTAssertNil(resolver.color(["value": "red;position:fixed"]))
        XCTAssertEqual(resolver.spacing(500), 128)
        XCTAssertEqual(resolver.sides(["start": "md"]), Sides(top: 0, start: 12, bottom: 0, end: 0))
        // The optional state colors fall back to the token they borrowed.
        var theme = HotlayoutThemeSet.builtIn.theme("light")
        theme.color["locked"] = nil
        XCTAssertEqual(theme.colorValue("locked"), theme.colorValue("muted"))
    }
}
