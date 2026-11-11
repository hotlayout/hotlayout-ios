import XCTest

@testable import HotLayout

/// Display typography against the shared table (`display-typography/display-typography-cases.json`): the effective
/// font size after the system text scale, tracking in shares of the font size, the line block, and what the reader
/// does with a typography override.
final class DisplayTypographyCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/display-typography/display-typography-cases.json")

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    func testEveryGroupIsRun() {
        XCTAssertEqual(Contract.groups(Self.table), ["scaleCases", "trackingCases", "lineCases", "documentCases"])
    }

    func testEffectiveFontSize() {
        let rows = Contract.rows(Self.table, "scaleCases")
        XCTAssertEqual(rows.count, 44)
        for row in rows {
            let effective = DisplayTypography.scaledFontSize(row["fontSize"]?.numberValue ?? .nan, scale: row["scale"]?.numberValue ?? .nan)
            XCTAssertEqual(effective, row["effective"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
        }
    }

    func testTracking() {
        let rows = Contract.rows(Self.table, "trackingCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            let effective = DisplayTypography.scaledFontSize(row["fontSize"]?.numberValue ?? .nan, scale: row["scale"]?.numberValue ?? .nan)
            XCTAssertEqual(effective, row["effective"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
            let tracking = DisplayTypography.trackingPx(
                letterSpacing: row["letterSpacing"]?.numberValue, letterSpacingEm: row["letterSpacingEm"]?.numberValue, effectiveFontSize: effective)
            XCTAssertEqual(tracking, row["trackingPx"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
        }
    }

    func testLineBlock() {
        let rows = Contract.rows(Self.table, "lineCases")
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            let block = DisplayTypography.lineBlock(
                fontSize: row["fontSize"]?.numberValue ?? .nan, lineHeight: row["lineHeight"]?.numberValue ?? .nan, scale: row["scale"]?.numberValue ?? .nan)
            XCTAssertEqual(block, row["lineBlock"]?.numberValue ?? .nan, accuracy: 1e-6, name(row))
        }
    }

    /// The reader is tolerant: a size past 400 or below 8 is brought to the bound, tracking in shares to its own bounds,
    /// and a document that names both kinds of tracking is read with the shares. Every row reads.
    func testOverrideAsTheReaderTakesIt() throws {
        let rows = Contract.rows(Self.table, "documentCases")
        XCTAssertEqual(rows.count, 12)
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme(nil))
        for row in rows {
            let override = try XCTUnwrap(row["typography"], name(row))
            let style = try XCTUnwrap(resolver.typography(override), name(row))
            let token = try XCTUnwrap(resolver.theme.typography[override["token"]?.stringValue ?? ""], name(row))
            let size = override["fontSize"]?.numberValue
            XCTAssertEqual(style.fontSize, size.map { min(400, max(8, $0)) } ?? token.fontSize, name(row))
            if let share = override["letterSpacingEm"]?.numberValue {
                let bounded = min(0.5, max(-0.1, share))
                XCTAssertEqual(style.letterSpacing, bounded * style.fontSize, accuracy: 1e-9, name(row))
            } else if override["letterSpacingEm"] == nil {
                XCTAssertEqual(style.letterSpacing, override["letterSpacing"]?.numberValue ?? token.letterSpacing, name(row))
            }
        }
    }

    /// The numbers of the poster rows of the screen fixture: size 240 with tracking -0.06 is -14.4 points, and the
    /// bound of a size in a THEME stays 96 (the theme names roles of text).
    func testPosterSizeAndTheBoundOfTheTheme() throws {
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme(nil))
        let poster = try XCTUnwrap(resolver.typography(["token": "displayL", "fontSize": 240, "letterSpacingEm": -0.06]))
        XCTAssertEqual(poster.fontSize, 240)
        XCTAssertEqual(poster.letterSpacing, -14.4, accuracy: 1e-9)
        XCTAssertEqual(ThemeNumbers.fontSize.high, 96)
        let both = try XCTUnwrap(resolver.typography(["token": "bodyS", "letterSpacing": 1, "letterSpacingEm": 0.1]))
        XCTAssertEqual(both.letterSpacing, 0.1 * both.fontSize, accuracy: 1e-9)
    }
}
