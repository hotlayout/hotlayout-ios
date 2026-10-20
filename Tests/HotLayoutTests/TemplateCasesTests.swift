import Foundation
import XCTest

@testable import HotLayout

/// The shared table of text templates, number formats, money, dates and plurals
/// (`fixtures/template/template-cases.json`), run through the rule of this reader.
///
/// Rows marked `mayDiffer` depend on the CLDR data of the platform. Where Apple's data gives
/// other characters than the table records, the row is listed in `platformDiffers` with what
/// this reader shows and why; every other row must match character for character.
final class TemplateCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/template/template-cases.json")

    /// Rows where Apple's CLDR data writes other characters than the table, by name.
    /// Only `mayDiffer` rows (and the «no locale data» rows, see below) may stand here.
    static let platformDiffers: [String: String] = [
        // U+202F before PM (Apple CLDR data); the comma between date and time is the point of the row.
        "cases: CLARIFIED-3 dateTime joins date and time with the CLDR pattern of the language, not a space: en":
            "Oct 31, 2026, 2:05\u{202F}PM",
        // U+202F between the year and the year mark; the row allows it.
        "cases: CLARIFIED-3 dateTime joins date and time with the CLDR pattern of the language, not a space: uk":
            "31 жовт. 2026\u{202F}р., 14:05",
        "cases: CLARIFIED-3 dateTime joins date and time with the CLDR pattern of the language, not a space: ru":
            "31 окт. 2026\u{202F}г., 14:05",
        // Apple CLDR puts an Arabic comma after the month and U+00A0 before «م»; the joiner U+060C is the point.
        "cases: CLARIFIED-3 dateTime joins date and time with the CLDR pattern of the language, not a space: ar":
            "31 أكتوبر\u{060C} 2026\u{060C} 2:05\u{00A0}م",
        "datePartsCases: WITHOUT the field nothing changed: year, short month, day (uk)": "15 жовт. 2026\u{202F}р.",
        "datePartsCases: dayMonthYear: day, month in full and year (uk)": "15 жовтня 2026\u{202F}р.",
        "datePartsCases: the year stands where the language puts it: Kazakh": "2026\u{202F}ж. 15 қазан",
        // Apple CLDR: an Arabic comma between the month and the year.
        "datePartsCases: WITHOUT the field nothing changed: year, short month, day (ar)": "15 أكتوبر\u{060C} 2026",
        "datePartsCases: dayMonthYear: day, month in full and year (ar)": "15 أكتوبر\u{060C} 2026",
        // NOT marked `mayDiffer` in the table, listed in `unflaggedPlatformDiffers` with the reason.
        "datePartsCases: the order of parts is the language's: Japanese": "10月15日 木曜日",
    ]

    /// Rows WITHOUT `mayDiffer` that still differ on Apple platforms, with the reason. The
    /// order of the parts (the point of the row) is the same; the pattern of Apple's CLDR
    /// data puts a space before the weekday. Recorded in NOTES.md for the contract.
    static let unflaggedPlatformDiffers: Set<String> = [
        "datePartsCases: the order of parts is the language's: Japanese",
    ]

    func run(_ group: String) -> [Mismatch] {
        var mismatches: [Mismatch] = []
        for row in Contract.rows(Self.table, group) {
            let name = row["name"]?.stringValue ?? "?"
            let expected = row["expected"]?.stringValue ?? ""
            let actual = Self.text(of: row)
            if actual == expected { continue }
            if Self.platformHasDataForMissingLocale(row), !actual.isEmpty { continue }
            mismatches.append(Mismatch(name: "\(group): \(name)", expected: expected, actual: actual))
        }
        return mismatches
    }

    static func text(of row: JSONObject) -> String {
        let translations = row["translations"]?.objectValue ?? JSONObject()
        let language = TemplateLanguage(
            translationLocale: row["translationLocale"]?.stringValue,
            sourceLocale: row["sourceLocale"]?.stringValue,
            translated: { translations[$0]?.stringValue }
        )
        let zone = row["timeZone"]?.stringValue.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")
        let now = DateText.moment(row["now"]) ?? DateText.moment(Self.table["now"])
        let rtl = row["direction"]?.stringValue.map { $0 == "rtl" }
        let environment = TextEnvironment(
            scope: Contract.scope(row["data"]),
            formattingLocale: row["formattingLocale"]?.stringValue,
            fallbackLocale: row["translationLocale"]?.stringValue ?? row["sourceLocale"]?.stringValue,
            timeZone: zone,
            now: now,
            rightToLeft: rtl
        )
        return BindableText.text(row["value"], language: language, environment: environment)
    }

    /// The «no locale data» rows name languages no CLDR release had when the table was written
    /// (`tlh`, `dv`, `la`). A platform that HAS the data formats them (the rule says so), and then
    /// only non-empty text is required. Which languages have data is asked of the platform,
    /// never assumed.
    static func platformHasDataForMissingLocale(_ row: JSONObject) -> Bool {
        guard let name = row["name"]?.stringValue, name.contains("no locale data"), let locale = row["formattingLocale"]?.stringValue else { return false }
        return NumberText.hasData(locale)
    }

    func testTableShape() {
        XCTAssertEqual(Contract.rows(Self.table, "cases").count, 179)
        XCTAssertEqual(Contract.rows(Self.table, "moneyCases").count, 73)
        XCTAssertEqual(Contract.rows(Self.table, "datePartsCases").count, 37)
        XCTAssertEqual(Contract.rows(Self.table, "countdownCases").count, 28)
        XCTAssertEqual(Contract.rows(Self.table, "compactCases").count, 41)
    }

    /// Only rows whose answer the table says may depend on platform data stand in the list.
    func testExceptionsAreFlaggedRows() {
        var flagged: Set<String> = []
        for group in ["cases", "moneyCases", "datePartsCases", "countdownCases", "compactCases"] {
            for row in Contract.rows(Self.table, group) where row["mayDiffer"] != nil {
                flagged.insert("\(group): \(row["name"]?.stringValue ?? "")")
            }
        }
        let unflagged = Set(Self.platformDiffers.keys).subtracting(flagged)
        XCTAssertEqual(unflagged, Self.unflaggedPlatformDiffers)
    }

    func testCases() { assertOnlyKnownDifferences(run("cases"), known: Self.platformDiffers, group: "cases") }
    func testMoneyCases() { assertOnlyKnownDifferences(run("moneyCases"), known: Self.platformDiffers, group: "moneyCases") }
    func testDatePartsCases() { assertOnlyKnownDifferences(run("datePartsCases"), known: Self.platformDiffers, group: "datePartsCases") }
    func testCountdownCases() { assertOnlyKnownDifferences(run("countdownCases"), known: Self.platformDiffers, group: "countdownCases") }
    func testCompactCases() { assertOnlyKnownDifferences(run("compactCases"), known: Self.platformDiffers, group: "compactCases") }

    func testShownTextCases() {
        for row in Contract.rows(Self.table, "shownTextCases") {
            XCTAssertEqual(ShownText.of(row["text"]?.stringValue ?? ""), row["expected"]?.stringValue, row["name"]?.stringValue ?? "")
        }
    }

    func testShownTemplateCases() {
        for row in Contract.rows(Self.table, "shownTemplateCases") {
            let text = Self.text(of: row)
            XCTAssertEqual(text, row["expected"]?.stringValue, "before the rule: \(row["name"]?.stringValue ?? "")")
            XCTAssertEqual(ShownText.of(text), row["shown"]?.stringValue, "after the rule: \(row["name"]?.stringValue ?? "")")
        }
    }
}
