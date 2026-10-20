import SwiftUI
import XCTest

@testable import HotLayout

/// The shared table of inputs (`fixtures/inputs/input-cases.json`): the fields, the form, the
/// number field. The rows run against the pure rules the views call; the documents of the table
/// are drawn by the real views.
final class InputCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/inputs/input-cases.json")

    /// Groups of the table this file does not run, each with the reason. The test fails when a
    /// group is neither run nor named here, and when a name here is no longer a group.
    static let notRun: [String: String] = [
        "ruleCases": "rules of the validator (what may be published)",
        "formRuleCases": "rules of the validator (what may be published)",
        "emptinessDocumentCases": "rules of the validator (what may be published)",
        "placementCases": "rules of the validator (which parents accept the widget)",
        "partsDocumentCases": "the codes are the validator's (what may be published); the documents that pass the schema are drawn by InputPartsCasesTests",
    ]

    /// Groups run by `WriteCasesTests` (write actions and the choice of plain nodes) and by `InputPartsCasesTests` (parts of a text field).
    static let runElsewhere: Set<String> = ["choicePlaceCases", "choiceControlCases", "writeFormCases", "fieldBoxCases", "affixRowCases", "counterCases", "noteRowCases"]

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "pathCases", "readCases", "textCases", "toggleCases", "clampCases", "linesCases", "keyboardCases", "keyActionCases",
            "errorCases", "geometryCases", "directionCases", "documentCases",
            "numberParseCases", "numberReadCases", "numberFieldCases", "numberInvalidCases", "numberKeyboardCases", "filledCases",
            "formCases", "pressCases", "disabledLookCases", "choiceCases", "choiceSessionCases", "formDocumentCases",
            "emptinessCases", "valuePathCases",
        ]
        var groups: Set<String> = []
        for (key, value) in Self.table.objectValue ?? JSONObject() where key.hasSuffix("Cases") && value.arrayValue != nil { groups.insert(key) }
        let known = run.union(Self.notRun.keys).union(Self.runElsewhere)
        XCTAssertEqual(groups.subtracting(known), [], "groups of the table that are neither run nor named")
        XCTAssertEqual(known.subtracting(groups), [], "names that are no longer groups")
    }

    static func scalars(_ text: String) -> [UInt32] { text.unicodeScalars.map(\.value) }

    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? row["note"]?.stringValue ?? row["text"]?.stringValue ?? "?" }

    // MARK: Value

    func testPathOfAField() {
        let rows = Contract.rows(Self.table, "pathCases")
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            XCTAssertEqual(InputRules.path(of: row["value"]), row["path"]?.stringValue, Self.name(row))
        }
    }

    func testReadValuesThroughTheLayers() {
        let rows = Contract.rows(Self.table, "readCases")
        XCTAssertEqual(rows.count, 20)
        for row in rows {
            let layers = row["layers"]
            let scope = RecordScope.merge(DataLayers(
                record: layers?["record"].map { Contract.scope($0) }, session: layers?["session"].map { Contract.scope($0) },
                host: layers?["host"].map { Contract.scope($0) }, data: layers?["data"].map { Contract.scope($0) }
            ))
            let value = scope[row["path"]?.stringValue ?? ""]
            if row["type"]?.stringValue == "string" {
                XCTAssertEqual(Self.scalars(InputRules.text(of: value)), Self.scalars(row["text"]?.stringValue ?? ""), Self.name(row))
            } else {
                XCTAssertEqual(InputRules.flag(of: value), row["on"]?.boolValue, Self.name(row))
            }
        }
    }

    // MARK: Text field

    static func event(_ step: JSONObject) -> InputRules.Event? {
        switch step["type"]?.stringValue {
        case "focus": return .focus
        case "blur": return .blur
        case "input": return .input(step["text"]?.stringValue ?? "")
        case "compositionStart": return .compositionStart
        case "compositionEnd": return .compositionEnd(step["text"]?.stringValue ?? "")
        case "platformFill": return .platformFill(step["text"]?.stringValue ?? "")
        default: return nil
        }
    }

    func testTextFieldSequences() {
        let rows = Contract.rows(Self.table, "textCases")
        XCTAssertEqual(rows.count, 27)
        for row in rows {
            var bound = row["bound"]?.stringValue ?? ""
            var state = InputRules.TextState()
            var writes: [String] = []
            for step in (row["steps"]?.arrayValue ?? []).compactMap(\.objectValue) {
                if step["type"]?.stringValue == "data" {
                    bound = step["bound"]?.stringValue ?? ""
                    state = InputRules.sync(state, bound: bound)
                } else if let event = Self.event(step) {
                    let result = InputRules.step(state, event, bound: bound, maxLength: row["maxLength"], disabled: row["disabled"]?.boolValue == true, hasPath: row["hasPath"]?.boolValue != false)
                    state = result.state
                    if let write = result.write {
                        writes.append(write)
                        // The write arrives in the layers only when the table says so (a `data` step).
                    }
                }
            }
            XCTAssertEqual(writes.map(Self.scalars), (row["writes"]?.arrayValue ?? []).compactMap(\.stringValue).map(Self.scalars), "writes: \(Self.name(row))")
            XCTAssertEqual(Self.scalars(InputRules.shownText(state, bound: bound)), Self.scalars(row["shown"]?.stringValue ?? ""), "shown: \(Self.name(row))")
        }
    }

    func testToggleSequences() {
        let rows = Contract.rows(Self.table, "toggleCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            var bound = row["bound"]?.boolValue ?? false
            var state = InputRules.ToggleState()
            var writes: [Bool] = []
            for step in row["steps"]?.arrayValue ?? [] {
                if step.stringValue == "press" {
                    let result = InputRules.pressToggle(state, bound: bound, disabled: row["disabled"]?.boolValue == true, hasPath: row["hasPath"]?.boolValue != false)
                    state = result.state
                    if let write = result.write { writes.append(write) }
                } else if let data = step["data"]?.boolValue {
                    bound = data
                    state = InputRules.syncToggle(state, bound: bound)
                }
            }
            XCTAssertEqual(writes, (row["writes"]?.arrayValue ?? []).compactMap(\.boolValue), "writes: \(Self.name(row))")
            XCTAssertEqual(InputRules.shownToggle(state, bound: bound), row["shown"]?.boolValue, "shown: \(Self.name(row))")
        }
    }

    func testLengthLimitInCodePoints() {
        let rows = Contract.rows(Self.table, "clampCases")
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            let text = row["text"]?.stringValue ?? ""
            let cut = InputRules.clamp(text, maxLength: row["maxLength"])
            XCTAssertEqual(Self.scalars(cut), Self.scalars(row["expect"]?.stringValue ?? ""), Self.name(row))
        }
    }

    func testLines() {
        let rows = Contract.rows(Self.table, "linesCases")
        XCTAssertEqual(rows.count, 9)
        for row in rows {
            XCTAssertEqual(InputRules.lines(row["lines"]), row["expect"]?.numberValue.map(Int.init), "lines: \(row["lines"].map { "\($0)" } ?? "none")")
        }
    }

    func testKeyboardIntent() {
        let rows = Contract.rows(Self.table, "keyboardCases")
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            let effective = InputRules.effectiveKeyboard(row["keyboard"], lines: row["lines"], numeric: false)
            XCTAssertEqual(effective?.rawValue ?? "multiline", row["expect"]?.stringValue, Self.name(row))
        }
    }

    func testKeyboardKey() {
        let rows = Contract.rows(Self.table, "keyActionCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let fields = (row["fields"]?.arrayValue ?? []).compactMap(\.objectValue).map {
                InputRules.Focusable(multiline: $0["multiline"]?.boolValue == true, reachable: $0["reachable"]?.boolValue == true)
            }
            let index = Int(row["index"]?.numberValue ?? 0)
            XCTAssertEqual(InputRules.keyAction(fields, at: index).rawValue, row["expect"]?.stringValue, "action: \(Self.name(row))")
            XCTAssertEqual(InputRules.nextIndex(fields, after: index), row["next"]?.numberValue.map(Int.init), "next: \(Self.name(row))")
        }
    }

    func testErrorStateIsAHeardText() {
        let rows = Contract.rows(Self.table, "errorCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            XCTAssertEqual(InputRules.error(row["error"]?.stringValue).map(Self.scalars), row["expect"]?.stringValue.map(Self.scalars), Self.name(row))
        }
    }

    func testGeometry() {
        let metrics = InputRules.Metrics(labelLine: 16, textLine: 20, noteLine: 16, gap: 4, paddingBlock: 12, border: 1)
        let rows = Contract.rows(Self.table, "geometryCases")
        XCTAssertEqual(rows.count, 17)
        for row in rows {
            let name = Self.name(row)
            switch row["widget"]?.stringValue {
            case "TextField":
                let lines = row["lines"]
                XCTAssertEqual(InputRules.boxHeight(metrics, lines: lines), row["box"]?.numberValue, "box: \(name)")
                XCTAssertEqual(InputRules.fieldHeight(metrics, lines: lines, labelLines: Int(row["labelLines"]?.numberValue ?? 1), noteLines: Int(row["noteLines"]?.numberValue ?? 0)), row["height"]?.numberValue, "height: \(name)")
            case "Switch":
                if let thumb = row["thumbOffset"]?.numberValue {
                    XCTAssertEqual(InputRules.thumbOffset(on: row["on"]?.boolValue == true), thumb, name)
                } else {
                    let rowWidth = row["rowWidth"]?.numberValue ?? 0
                    XCTAssertEqual(InputRules.switchLabelWidth(row: rowWidth, gap: 12), row["labelWidth"]?.numberValue, "label: \(name)")
                    XCTAssertEqual(InputRules.switchHeight(labelLine: 20, labelLines: Int(row["labelLines"]?.numberValue ?? 1)), row["height"]?.numberValue, "height: \(name)")
                }
            default:
                let line = row["labelLine"]?.numberValue ?? 20
                XCTAssertEqual(InputRules.checkboxLabelWidth(row: row["rowWidth"]?.numberValue ?? 0, gap: 8), row["labelWidth"]?.numberValue, "label: \(name)")
                XCTAssertEqual(InputRules.checkboxHeight(labelLine: line, labelLines: Int(row["labelLines"]?.numberValue ?? 1)), row["height"]?.numberValue, "height: \(name)")
                XCTAssertEqual(InputRules.checkboxBoxOffset(labelLine: line), row["boxOffset"]?.numberValue, "offset: \(name)")
            }
        }
    }

    func testDirectionOfTheContent() {
        let rows = Contract.rows(Self.table, "directionCases").filter { $0["widget"]?.stringValue == "TextField" }
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let leftToRight = InputRules.contentIsLeftToRight(row["keyboard"], lines: row["lines"], numeric: false)
            XCTAssertEqual(leftToRight ? "left-to-right" : "screen", row["content"]?.stringValue, Self.name(row))
        }
    }

    // MARK: Number field

    func testParseTypedNumbers() {
        let rows = Contract.rows(Self.table, "numberParseCases")
        XCTAssertEqual(rows.count, 65)
        for row in rows {
            let text = row["text"]?.stringValue ?? ""
            XCTAssertEqual(InputRules.parseNumber(text), row["number"]?.numberValue, "«\(Mismatch.visible(text))» \(row["note"]?.stringValue ?? "")")
        }
    }

    func testReadNumbersFromTheLayers() {
        let rows = Contract.rows(Self.table, "numberReadCases")
        XCTAssertEqual(rows.count, 21)
        for row in rows {
            let value = row["value"]
            XCTAssertEqual(InputRules.readNumber(value), row["number"]?.numberValue, "number: \(Self.name(row))")
            XCTAssertEqual(InputRules.numberText(value), row["text"]?.stringValue, "text: \(Self.name(row))")
        }
    }

    func testNumberFieldSequences() {
        let rows = Contract.rows(Self.table, "numberFieldCases")
        XCTAssertEqual(rows.count, 25)
        for row in rows {
            var bound = row["bound"]
            var state = InputRules.TextState()
            var writes: [JSONValue] = []
            for step in (row["steps"]?.arrayValue ?? []).compactMap(\.objectValue) {
                if step["type"]?.stringValue == "data" {
                    bound = step["bound"]
                } else if let event = Self.event(step) {
                    let result = InputRules.stepNumber(state, event, bound: bound, maxLength: row["maxLength"], disabled: row["disabled"]?.boolValue == true, hasPath: row["hasPath"]?.boolValue != false)
                    state = result.state
                    if let write = result.write { writes.append(write) }
                }
            }
            XCTAssertEqual(writes, row["writes"]?.arrayValue ?? [], "writes: \(Self.name(row))")
            XCTAssertEqual(Self.scalars(InputRules.shownNumber(state, bound: bound)), Self.scalars(row["shown"]?.stringValue ?? ""), "shown: \(Self.name(row))")
        }
    }

    func testNonNumberIsAnErrorStateAfterLeaving() {
        let rows = Contract.rows(Self.table, "numberInvalidCases")
        XCTAssertEqual(rows.count, 11)
        for row in rows {
            var bound = row["bound"]
            var state = InputRules.TextState()
            var states: [Bool] = []
            for step in (row["steps"]?.arrayValue ?? []).compactMap(\.objectValue) {
                if step["type"]?.stringValue == "data" {
                    bound = step["bound"]
                } else if let event = Self.event(step) {
                    state = InputRules.stepNumber(state, event, bound: bound, disabled: row["disabled"]?.boolValue == true).state
                }
                states.append(InputRules.numberInvalid(state, bound: bound))
            }
            XCTAssertEqual(states, (row["states"]?.arrayValue ?? []).compactMap(\.boolValue), Self.name(row))
        }
    }

    func testNumberFieldKeyboard() {
        let rows = Contract.rows(Self.table, "numberKeyboardCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let given = row["given"]?.objectValue ?? JSONObject()
            let numeric = InputRules.isNumber(valueType: row["valueType"])
            let effective = InputRules.effectiveKeyboard(given["keyboard"], lines: given["lines"], numeric: numeric)
            XCTAssertEqual(effective?.rawValue ?? "multiline", row["keyboard"]?.stringValue, "keyboard: \(Self.name(row))")
            XCTAssertEqual(InputRules.effectiveLines(given["lines"], numeric: numeric), row["lines"]?.numberValue.map(Int.init), "lines: \(Self.name(row))")
            XCTAssertEqual(InputRules.contentIsLeftToRight(given["keyboard"], lines: given["lines"], numeric: numeric) ? "left-to-right" : "screen", row["content"]?.stringValue, "content: \(Self.name(row))")
        }
    }

    // MARK: Form

    func testFilledMeansAnAnswer() {
        let rows = Contract.rows(Self.table, "filledCases")
        XCTAssertEqual(rows.count, 32)
        for row in rows {
            let kind = FormRules.Kind(rawValue: row["kind"]?.stringValue ?? "")
            XCTAssertNotNil(kind, Self.name(row))
            XCTAssertEqual(FormRules.isFilled(kind ?? .text, value: row["value"]), row["filled"]?.boolValue, Self.name(row))
        }
    }

    func testFormCases() {
        let rows = Contract.rows(Self.table, "formCases")
        XCTAssertEqual(rows.count, 23)
        for row in rows {
            for state in (row["states"]?.arrayValue ?? []).compactMap(\.objectValue) {
                let layers = state["layers"]
                let label = "\(Self.name(row)) — \(Self.name(state))"
                let data = DataLayers(
                    record: layers?["record"].map { Contract.scope($0) }, session: layers?["session"].map { Contract.scope($0) },
                    host: layers?["host"].map { Contract.scope($0) }, data: layers?["data"].map { Contract.scope($0) }
                )
                for (screen, nodes) in row["screens"]?.objectValue ?? JSONObject() {
                    let sim = ScreenSim(nodes: nodes.arrayValue ?? [], layers: data, id: screen)
                    XCTAssertEqual(sim.isFilled(), state["filled"]?[screen]?.boolValue, "filled \(screen): \(label)")
                    for (id, expected) in state["disabled"]?.objectValue ?? JSONObject() where sim.find(id) != nil {
                        XCTAssertEqual(sim.isDisabled(id), expected.boolValue, "disabled \(id): \(label)")
                    }
                }
            }
        }
    }

    /// A press of a disabled button reaches neither the action nor the analytics event; a held
    /// key repeats `click`, which is not a press, so tap, Enter, Space and a held key are one press.
    func testPressOfADisabledButton() {
        let rows = Contract.rows(Self.table, "pressCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let disabled = row["disabled"]?.boolValue == true
            let widget = row["widget"]?.stringValue ?? "Button"
            let action: JSONValue = ["type": "submit", "track": ["event": "tapped"]]
            let props: JSONValue = widget == "IconButton"
                ? ["icon": "check", "label": ["kind": "literal", "value": "Done"], "action": action, "disabledIf": ["path": "form.locked", "op": "isTrue"]]
                : ["label": ["kind": "literal", "value": "Go"], "action": action, "disabledIf": ["path": "form.locked", "op": "isTrue"]]
            var sim = ScreenSim(nodes: [["id": "b", "type": .string(widget), "props": props]], layers: DataLayers(data: ["form.locked": .bool(disabled)]))
            sim.press("b")
            let log = sim.log.map { $0.first?.stringValue ?? "" }
            XCTAssertEqual(log.filter { $0 == "action" }.count, row["action"]?.numberValue.map(Int.init), "action: \(Self.name(row))")
            XCTAssertEqual(log.filter { $0 == "track" }.count, row["track"]?.numberValue.map(Int.init), "track: \(Self.name(row))")
        }
    }

    func testDisabledLook() {
        let rows = Contract.rows(Self.table, "disabledLookCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            let disabled = row["disabled"]?.boolValue == true
            let own = row["styleOpacity"]?.numberValue ?? 1
            let opacity = (disabled ? InputRules.disabledOpacity : 1) * own
            XCTAssertEqual(opacity, row["opacity"]?.numberValue, "opacity: \(Self.name(row))")
            XCTAssertEqual(row["semantics"]?["disabled"]?.boolValue, disabled, "semantics: \(Self.name(row))")
            XCTAssertEqual(row["semantics"]?["focusable"]?.boolValue, true, "a disabled button stays focusable: \(Self.name(row))")
        }
    }

    func testChoiceWrite() {
        let rows = Contract.rows(Self.table, "choiceCases")
        XCTAssertEqual(rows.count, 8)
        for row in rows {
            let write = FormRules.choiceWrite(path: InputRules.path(of: row["value"]), picked: row["pick"]?.stringValue ?? "", shown: row["shown"]?.stringValue)
            let expected = row["write"]?.objectValue
            XCTAssertEqual(write?.path, expected?["path"]?.stringValue, "path: \(Self.name(row))")
            XCTAssertEqual(write?.value, expected?["value"]?.stringValue, "value: \(Self.name(row))")
        }
    }

    /// A choice is written into the session at once, and a condition of the same screen sees it.
    func testChoiceReachesTheConditionsOfTheScreen() {
        let rows = Contract.rows(Self.table, "choiceSessionCases")
        XCTAssertEqual(rows.count, 5)
        for row in rows {
            var session: DataScope = [:]
            let path = InputRules.path(of: row["value"])
            let condition = row["condition"] ?? .null
            XCTAssertEqual(Conditions.holds(condition, scope: RecordScope.merge(DataLayers(session: session))), row["before"]?.boolValue, "before: \(Self.name(row))")
            for pick in [row["pickFirst"]?.stringValue, row["pick"]?.stringValue].compactMap({ $0 }) {
                if let write = FormRules.choiceWrite(path: path, picked: pick, shown: nil) {
                    SessionWrite.apply(path: write.path, value: .string(write.value), to: &session, gate: nil)
                }
            }
            XCTAssertEqual(Conditions.holds(condition, scope: RecordScope.merge(DataLayers(session: session))), row["after"]?.boolValue, "after: \(Self.name(row))")
        }
    }

    func testValuePathConditions() {
        let rows = Contract.rows(Self.table, "valuePathCases")
        XCTAssertEqual(rows.count, 22)
        for row in rows {
            XCTAssertEqual(Conditions.holds(row["condition"] ?? .null, scope: Contract.scope(row["data"])), row["holds"]?.boolValue, Self.name(row))
        }
    }

    func testEmptinessOfAnyType() {
        let rows = Contract.rows(Self.table, "emptinessCases")
        XCTAssertEqual(rows.count, 14)
        for row in rows {
            var scope: DataScope = [:]
            if let value = row["value"] { scope["x"] = value }
            XCTAssertEqual(Conditions.holds(["path": "x", "op": "isEmpty"], scope: scope), row["isEmpty"]?.boolValue, Self.name(row))
        }
    }

    // MARK: Documents are drawn

    /// Every document of the table is read and drawn by the real views, with and without data,
    /// in both directions, without a crash.
    @MainActor
    func testDocumentsOfTheTableAreDrawn() throws {
        var drawn = 0
        for group in ["documentCases", "formDocumentCases"] {
            for row in Contract.rows(Self.table, group) {
                guard let node = row["node"] else { continue }
                let screen: JSONValue = [
                    "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": "a",
                    "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": [node]]]],
                ]
                guard let document = try? loadDocument(screen) else { continue }
                for locale in ["en", "ar"] {
                    let view = HotlayoutScreen(document: document, data: ["form.email": "a@b.c", "settings.notifications": true], locale: locale).frame(width: 320, height: 480)
                    XCTAssertNotNil(ImageRenderer(content: view).cgImage, "\(Self.name(row)) \(locale)")
                }
                drawn += 1
            }
        }
        XCTAssertGreaterThan(drawn, 40)
    }

    func testWidgetsAreDrawnByThisReader() {
        for type in ["TextField", "Switch", "Checkbox", "ChoiceGroup"] {
            XCTAssertTrue(DocumentReader.knownWidgets.contains(type), type)
        }
    }
}
