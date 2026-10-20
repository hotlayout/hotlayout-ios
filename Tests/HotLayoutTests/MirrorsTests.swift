import XCTest

@testable import HotLayout

/// The package carries copies of contract data (the built-in theme, the icon set, the lists the
/// reader needs at run time). These tests compare every copy with the artifacts, so that a
/// sync of the contract cannot leave the reader behind silently.
final class MirrorsTests: XCTestCase {
    func testVersionsMatchTheArtifacts() throws {
        XCTAssertEqual(try Contract.json("screen-schema.json")["x-schemaVersion"]?.stringValue, HotlayoutVersions.schema)
        XCTAssertEqual(try Contract.json("theme.json")["x-themeContractVersion"]?.stringValue, HotlayoutVersions.theme)
        XCTAssertEqual(try Contract.json("icons.json")["iconSetVersion"]?.stringValue, HotlayoutVersions.iconSet)
        XCTAssertEqual(IconSet.shippedVersion, HotlayoutVersions.iconSet)
    }

    func testBuiltInThemeIsTheContractBlock() throws {
        let artifact = try Contract.json("theme.json")["contract"]
        let url = try XCTUnwrap(Self.libraryResource("built-in-theme.json"))
        XCTAssertEqual(try JSONValue.parse(Data(contentsOf: url)), artifact)
        let set = HotlayoutThemeSet.builtIn
        XCTAssertEqual(set.defaultThemeId, artifact?["defaultThemeId"]?.stringValue)
        XCTAssertEqual(Set(set.themes.keys), Set((artifact?["themes"]?.objectValue ?? JSONObject()).keys))
        XCTAssertEqual(set.theme("light").colorValue("primary"), RGBA(hex: artifact?["themes"]?["light"]?["color"]?["primary"]?.stringValue ?? ""))
    }

    func testOptionalColorFallbacksMirrorTheArtifact() throws {
        let fallbacks = try Contract.json("theme.json")["x-optionalColors"]?["fallbacks"]?.objectValue ?? JSONObject()
        var expected: [String: String] = [:]
        for (key, value) in fallbacks { expected[key] = value.stringValue }
        XCTAssertEqual(HotlayoutTheme.optionalColorFallbacks, expected)
    }

    func testIconSetIsTheArtifact() throws {
        let artifact = try Contract.json("icons.json")
        XCTAssertEqual(Set(IconSet.names), Set((artifact["icons"]?.objectValue ?? JSONObject()).keys))
        let schema = try Contract.json("screen-schema.json")
        XCTAssertEqual(IconSet.mirrored, Set((schema["x-mirroredIcons"]?.arrayValue ?? []).compactMap(\.stringValue)))
        let grid = artifact["grid"]
        XCTAssertEqual(grid?["size"]?.numberValue, IconSet.gridSize)
        XCTAssertEqual(grid?["strokeWidth"]?.numberValue, IconSet.defaultStrokeWidth)
        let elements = Set((artifact["format"]?["elements"]?.objectValue ?? JSONObject()).keys)
        XCTAssertEqual(elements, Set(IconBody.geometry.keys))
    }

    /// Every icon of the set parses into at least one element: a body the parser drops would
    /// draw an empty box in place of a known icon.
    func testEveryIconDraws() {
        for name in IconSet.names {
            let elements = IconSet.elements(name) ?? []
            XCTAssertFalse(elements.isEmpty, name)
            for element in elements { XCTAssertFalse(element.path.commands.isEmpty, name) }
        }
        XCTAssertNil(IconSet.elements("no-such-icon"))
    }

    func testWidgetListMirrorsTheArtifact() throws {
        let widgets = try Contract.json("screen-schema.json")["x-compatibility"]?["widgets"]?.objectValue ?? JSONObject()
        XCTAssertEqual(DocumentReader.knownWidgets, Set(widgets.keys))
    }

    static func libraryResource(_ name: String) -> URL? {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HotLayout/Resources/\(name)")
    }
}
