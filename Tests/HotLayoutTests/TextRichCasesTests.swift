import Foundation
import XCTest

@testable import HotLayout

/// The shared table of composed text and text emphasis (`fixtures/rich-text/rich-text-cases.json`):
/// pieces of a string with their own style, the pitch of the lines, slant and line, and the gradient
/// on the glyphs.
///
/// Groups the rules of a reader cannot answer are named in `notAReaderRule` with the reason; a test
/// fails when a group of the table is neither run nor listed.
final class TextRichCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/rich-text/rich-text-cases.json")

    /// Groups that are rules of the builder's validator, not of a reader.
    static let notAReaderRule: [String: String] = [
        "textGradientDocumentCases": "codes of the validator for documents; a reader meets the field only through textGradientCases",
    ]

    static let runGroups: Set<String> = [
        "cases", "struts", "emphasis", "emphasisStruts", "amountPartCases", "amountPartStruts",
        "textGradientCases", "textGradientPartCases",
    ]

    func testEveryGroupIsRunOrNamed() {
        let groups = Set((Self.table.objectValue ?? JSONObject()).keys.filter { (Self.table[$0]?.arrayValue) != nil })
        XCTAssertEqual(groups, Self.runGroups.union(Self.notAReaderRule.keys), "a group of the table is not run and not named")
        for group in Self.notAReaderRule.keys { XCTAssertFalse(Contract.rows(Self.table, group).isEmpty, "\(group) no longer exists") }
    }

    func testTableShape() {
        XCTAssertEqual(Contract.rows(Self.table, "cases").count, 34)
        XCTAssertEqual(Contract.rows(Self.table, "struts").count, 10)
        XCTAssertEqual(Contract.rows(Self.table, "emphasis").count, 38)
        XCTAssertEqual(Contract.rows(Self.table, "emphasisStruts").count, 6)
        XCTAssertEqual(Contract.rows(Self.table, "amountPartCases").count, 19)
        XCTAssertEqual(Contract.rows(Self.table, "amountPartStruts").count, 5)
        XCTAssertEqual(Contract.rows(Self.table, "textGradientCases").count, 9)
        XCTAssertEqual(Contract.rows(Self.table, "textGradientPartCases").count, 3)
    }

    // MARK: - Runs

    /// What a row of `cases` and its relatives gives: the text, the styled runs and the styles read.
    struct Outcome {
        var text: String
        var runs: [TextSpanRun]
        var styles: [String: TextSpanStyle]
    }

    static func outcome(of row: JSONObject) -> Outcome {
        let translations = row["translations"]?.objectValue ?? JSONObject()
        let language = TemplateLanguage(
            translationLocale: row["translationLocale"]?.stringValue,
            sourceLocale: row["sourceLocale"]?.stringValue,
            translated: { translations[$0]?.stringValue }
        )
        let environment = TextEnvironment(
            scope: Contract.scope(row["data"]),
            formattingLocale: row["formattingLocale"]?.stringValue,
            fallbackLocale: row["translationLocale"]?.stringValue ?? row["sourceLocale"]?.stringValue,
            timeZone: TimeZone(identifier: "UTC"),
            now: DateText.moment(row["now"]) ?? DateText.moment(table["now"]),
            rightToLeft: row["direction"]?.stringValue.map { $0 == "rtl" }
        )
        let templateRuns = BindableText.runs(row["content"], language: language, environment: environment)
        let active = TextSpans.active(content: row["content"], spans: TextSpans.read(row["spans"]))
        return Outcome(text: templateRuns.map(\.text).joined(), runs: TextSpans.runs(templateRuns, active: active), styles: active)
    }

    private func assertText(_ outcome: Outcome, _ row: JSONObject, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = row["expected"]
        XCTAssertEqual(outcome.text, expected?["text"]?.stringValue, "text: \(name)", file: file, line: line)
        if let styles = expected?["styles"] {
            let read = JSONValue.object(JSONObject(outcome.styles.keys.sorted().map { ($0, outcome.styles[$0]!.json) }))
            XCTAssertEqual(read, styles, "styles read: \(name)", file: file, line: line)
        }
    }

    func testCases() {
        for row in Contract.rows(Self.table, "cases") {
            let name = row["name"]?.stringValue ?? "?"
            let outcome = Self.outcome(of: row)
            assertText(outcome, row, name)
            let expected = row["expected"]?["runs"]?.arrayValue ?? []
            XCTAssertEqual(outcome.runs.count, expected.count, "number of runs: \(name)")
            for (run, want) in zip(outcome.runs, expected) {
                XCTAssertEqual(run.text, want["text"]?.stringValue, "run text: \(name)")
                XCTAssertEqual(run.span, want["span"]?.stringValue, "run place: \(name)")
            }
        }
    }

    func testAmountPartCases() {
        for row in Contract.rows(Self.table, "amountPartCases") {
            let name = row["name"]?.stringValue ?? "?"
            let outcome = Self.outcome(of: row)
            assertText(outcome, row, name)
            let expected = row["expected"]?["runs"]?.arrayValue ?? []
            XCTAssertEqual(outcome.runs.count, expected.count, "number of runs: \(name)")
            for (run, want) in zip(outcome.runs, expected) {
                XCTAssertEqual(run.text, want["text"]?.stringValue, "run text: \(name)")
                XCTAssertEqual(run.span, want["span"]?.stringValue, "run place: \(name)")
                XCTAssertEqual(run.part?.rawValue, want["part"]?.stringValue, "run part: \(name)")
            }
        }
    }

    func testEmphasis() {
        for row in Contract.rows(Self.table, "emphasis") {
            let name = row["name"]?.stringValue ?? "?"
            let outcome = Self.outcome(of: row)
            assertText(outcome, row, name)
            var emphasis = TextEmphasisRules.inherit(.root, style: row["inherited"]?.objectValue)
            emphasis = TextEmphasisRules.inherit(emphasis, style: row["style"]?.objectValue)
            let expected = row["expected"]?["runs"]?.arrayValue ?? []
            XCTAssertEqual(outcome.runs.count, expected.count, "number of runs: \(name)")
            for (run, want) in zip(outcome.runs, expected) {
                let drawn = TextEmphasisRules.run(emphasis, span: TextSpans.style(of: run, active: outcome.styles))
                XCTAssertEqual(run.text, want["text"]?.stringValue, "run text: \(name)")
                XCTAssertEqual(run.span, want["span"]?.stringValue, "run place: \(name)")
                XCTAssertEqual(drawn.fontStyle, want["fontStyle"]?.stringValue, "slant of «\(run.text)»: \(name)")
                XCTAssertEqual(drawn.textDecoration, want["textDecoration"]?.stringValue, "line of «\(run.text)»: \(name)")
                XCTAssertEqual(drawn.weight.map(Double.init), want["weight"]?.numberValue, "weight of «\(run.text)»: \(name)")
            }
        }
    }

    // MARK: - Line pitch

    private func metric(_ value: JSONValue?) -> LineMetric {
        LineMetric(fontSize: value?["fontSize"]?.numberValue ?? 0, lineHeight: value?["lineHeight"]?.numberValue ?? 0)
    }

    private func runStruts(_ group: String) {
        for row in Contract.rows(Self.table, group) {
            let name = row["name"]?.stringValue ?? "?"
            var spans: [String: LineMetric] = [:]
            for (key, value) in row["spans"]?.objectValue ?? JSONObject() { spans[key] = metric(value) }
            let strut = RichText.strut(base: metric(row["base"]), spans: spans)
            XCTAssertEqual(strut.span, row["expected"]?["span"]?.stringValue, "strut: \(name)")
            XCTAssertEqual(strut.lineBlock, row["expected"]?["lineBlock"]?.numberValue ?? -1, accuracy: 1e-9, "pitch: \(name)")
        }
    }

    func testStruts() { runStruts("struts") }
    func testEmphasisStruts() { runStruts("emphasisStruts") }
    func testAmountPartStruts() { runStruts("amountPartStruts") }

    // MARK: - Gradient

    func testTextGradientCases() {
        let theme = HotlayoutThemeSet.builtIn.theme()
        for row in Contract.rows(Self.table, "textGradientCases") {
            let name = row["name"]?.stringValue ?? "?"
            var style = row["style"]?.objectValue ?? JSONObject()
            let met = (row["met"]?.arrayValue ?? []).map { $0.boolValue ?? false }
            for (index, item) in (row["styleWhen"]?.arrayValue ?? []).enumerated() where index < met.count && met[index] {
                for (key, value) in item["style"]?.objectValue ?? JSONObject() { style[key] = value }
                break
            }
            let reference = TextGradientRules.reference(type: row["type"]?.stringValue ?? "", style: style)
            let want: JSONValue? = row["gradient"]?.isNull == false ? row["gradient"] : Optional<JSONValue>.none
            XCTAssertEqual(reference, want, name)
            if let reference, let token = reference.stringValue, theme.gradient[token] == nil {
                XCTAssertNil(StyleResolver(theme: theme).gradient(reference), "an unknown token gives the colour: \(name)")
            }
        }
    }

    func testTextGradientPartCases() {
        for row in Contract.rows(Self.table, "textGradientPartCases") {
            let name = row["name"]?.stringValue ?? "?"
            let gradient = !(row["gradient"]?.isNull ?? true)
            let spans = TextSpans.read(row["spans"])
            for (key, want) in row["parts"]?.objectValue ?? JSONObject() {
                let taken = TextGradientRules.takes(gradient: gradient, span: key.isEmpty ? nil : spans[key])
                XCTAssertEqual(taken, want.boolValue, "\(name): «\(key)»")
            }
        }
    }
}
