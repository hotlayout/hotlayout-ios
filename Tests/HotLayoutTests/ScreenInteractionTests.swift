#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest

@testable import HotLayout

/// The real screen, pressed through the accessibility interface of the platform: what a person
/// using VoiceOver does. A write goes to `onWrite` and to the session of the screen, and a
/// control that is disabled does nothing.
@MainActor
final class ScreenInteractionTests: XCTestCase {
    final class Recorder {
        var log: [String] = []
    }

    func document(_ children: JSONValue) throws -> HotlayoutDocument {
        try loadDocument([
            "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": "a",
            "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": children]]],
        ])
    }

    func testPressWritesToTheHostInOrder() throws {
        let recorder = Recorder()
        let doc = try document([
            ["id": "month", "type": "Button", "props": [
                "label": ["kind": "literal", "value": "Month"], "variant": "ghost", "fullWidth": false,
                "action": ["type": "setValue", "params": ["path": "account.period", "value": "month"], "track": ["event": "period_changed"], "haptic": "selection"],
            ]],
        ])
        let view = host(HotlayoutScreen(
            document: doc, locale: "en",
            onTrack: { event, _ in recorder.log.append("track \(event.event)") },
            onHaptic: { word, _ in recorder.log.append("haptic \(word.rawValue)") },
            onWrite: { path, value in recorder.log.append("write \(path) \(value)") }
        ))
        guard let button = find(view, label: "Month") else { return XCTFail("no button; tree: \(elements(view).map { "\(type(of: $0)) \(text($0, "accessibilityLabel") ?? "-")" })") }
        XCTAssertTrue(press(button))
        spin()
        XCTAssertEqual(recorder.log, ["haptic selection", "track period_changed", "write account.period string(\"month\")"])
    }

    func button(_ id: String, _ label: String, _ action: JSONValue, extra: JSONObject = JSONObject()) -> JSONValue {
        var props: JSONObject = ["label": ["kind": "literal", "value": .string(label)], "variant": "ghost", "fullWidth": false, "action": action]
        for (key, value) in extra { props[key] = value }
        return ["id": .string(id), "type": "Button", "props": .object(props)]
    }

    func testToggleActionFlipsWhatIsShown() throws {
        let recorder = Recorder()
        let doc = try document([button("eye", "Eye", ["type": "toggleValue", "params": ["path": "account.hidden"]])])
        let view = host(HotlayoutScreen(document: doc, locale: "en", onWrite: { path, value in recorder.log.append("\(path) \(value)") }))
        let eye = try XCTUnwrap(find(view, label: "Eye"))
        for _ in 0..<3 {
            XCTAssertTrue(press(eye))
            spin(0.2)
        }
        XCTAssertEqual(recorder.log, ["account.hidden bool(true)", "account.hidden bool(false)", "account.hidden bool(true)"])
    }

    func testGateRefusesAPathAndWritesNothing() throws {
        let recorder = Recorder()
        let doc = try document([
            button("ok", "Allowed", ["type": "setValue", "params": ["path": "account.period", "value": "week"]]),
            button("no", "Refused", ["type": "setValue", "params": ["path": "account.secret", "value": "x"]]),
        ])
        let view = host(HotlayoutScreen(
            document: doc, locale: "en", onWrite: { path, _ in recorder.log.append(path) }, writablePaths: WritablePaths(["account.period"])
        ))
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Refused"))))
        spin(0.2)
        XCTAssertEqual(recorder.log, [], "a refused path reaches neither the session nor the host")
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Allowed"))))
        spin(0.2)
        XCTAssertEqual(recorder.log, ["account.period"])
    }

    func testDisabledButtonDoesNothingUntilTheFormIsFilled() throws {
        let recorder = Recorder()
        let doc = try document([
            ["id": "agree", "type": "Checkbox", "props": ["label": ["kind": "literal", "value": "Agree"], "value": ["kind": "binding", "path": "form.agreed"], "required": true]],
            button("next", "Next", ["type": "go", "track": ["event": "next_pressed"]], extra: ["requiresFilled": true]),
        ])
        let view = host(HotlayoutScreen(
            document: doc, locale: "en",
            onAction: { action, _ in recorder.log.append("action \(action.type)") },
            onTrack: { event, _ in recorder.log.append("track \(event.event)") },
            onWrite: { path, value in recorder.log.append("write \(path) \(value)") }
        ))
        let next = try XCTUnwrap(find(view, label: "Next"))
        _ = press(next)
        spin(0.2)
        XCTAssertEqual(recorder.log, [], "a disabled button sends neither the action nor the event")
        let agree = try XCTUnwrap(find(view, label: "Agree"))
        XCTAssertTrue(press(agree))
        spin(0.3)
        XCTAssertEqual(recorder.log, ["write form.agreed bool(true)"])
        recorder.log = []
        let again = try XCTUnwrap(find(view, label: "Next"))
        XCTAssertTrue(press(again))
        spin(0.2)
        XCTAssertEqual(recorder.log, ["track next_pressed", "action go"], "the form is filled: the button acts, the event first")
    }

    func testChoiceGroupRowWritesItsPath() throws {
        let recorder = Recorder()
        let doc = try document([
            ["id": "group", "type": "ChoiceGroup", "props": ["value": ["kind": "binding", "path": "survey.goal", "fallback": ""], "gap": "none"], "children": [
                ["id": "gold", "type": "ListTile", "props": ["leading": ["kind": "none"], "title": ["kind": "literal", "value": "Gold"], "trailing": ["kind": "radio", "optionValue": "gold"]]],
                ["id": "silver", "type": "ListTile", "props": ["leading": ["kind": "none"], "title": ["kind": "literal", "value": "Silver"], "trailing": ["kind": "radio", "optionValue": "silver"]]],
            ]],
        ])
        let view = host(HotlayoutScreen(document: doc, locale: "en", onWrite: { path, value in recorder.log.append("\(path) \(value)") }))
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Gold"))))
        spin(0.3)
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Gold"))), "pressing the chosen row again")
        spin(0.3)
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Silver"))))
        spin(0.3)
        XCTAssertEqual(recorder.log, ["survey.goal string(\"gold\")", "survey.goal string(\"silver\")"], "the same option is not written twice")
    }

    func testTypingIntoAFieldWritesAndFillsTheForm() throws {
        let recorder = Recorder()
        let doc = try document([
            ["id": "name", "type": "TextField", "props": ["label": ["kind": "literal", "value": "Name"], "value": ["kind": "binding", "path": "form.name"], "required": true]],
            button("next", "Next", ["type": "go"], extra: ["requiresFilled": true]),
        ])
        let view = host(HotlayoutScreen(
            document: doc, locale: "en",
            onAction: { action, _ in recorder.log.append("action \(action.type)") },
            onWrite: { path, value in recorder.log.append("write \(path) \(value)") }
        ))
        let roles = elements(view).map { "\(type(of: $0)) \(text($0, "accessibilityRole") ?? "-") \(text($0, "accessibilityLabel") ?? "-")" }
        let field = try XCTUnwrap(elements(view).first { text($0, "accessibilityRole") == "AXTextField" }, "no text field: \(roles)")
        // A value that arrives before the person touched the field is filled in by the platform:
        // it is not kept and not written.
        field.perform(NSSelectorFromString("setAccessibilityValue:"), with: "Saved")
        spin(0.3)
        XCTAssertEqual(recorder.log, [])
        field.setValue(true, forKey: "accessibilityFocused")
        spin(0.4)
        field.perform(NSSelectorFromString("setAccessibilityValue:"), with: "Al")
        spin(0.3)
        XCTAssertEqual(recorder.log, ["write form.name string(\"Al\")"])
        recorder.log = []
        XCTAssertTrue(press(try XCTUnwrap(find(view, label: "Next"))))
        spin(0.2)
        XCTAssertEqual(recorder.log, ["action go"], "the typed text fills the form")
    }

    func testSwitchPressWritesAFlag() throws {
        let recorder = Recorder()
        let doc = try document([
            ["id": "push", "type": "Switch", "props": ["label": ["kind": "literal", "value": "Push"], "value": ["kind": "binding", "path": "settings.push"]]],
        ])
        let view = host(HotlayoutScreen(document: doc, locale: "en", onWrite: { path, value in recorder.log.append("\(path) \(value)") }))
        let toggle = try XCTUnwrap(find(view, label: "Push"))
        XCTAssertTrue(press(toggle))
        spin(0.3)
        XCTAssertEqual(recorder.log, ["settings.push bool(true)"])
    }
}
#endif
