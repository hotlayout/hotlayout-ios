#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest

@testable import HotLayout

/// The text field on the real screen, driven through the native control it is made of (iOS): while a
/// character is composed (marked text) nothing is written, and the committed text is written once.
/// The macOS stand-in has no marked text, so these run in the iOS simulator only.
@MainActor
final class ScreenCompositionTests: XCTestCase {
    final class Recorder {
        var writes: [String] = []
    }

    func document(props: JSONValue = [:]) throws -> HotlayoutDocument {
        var field: JSONObject = ["label": ["kind": "literal", "value": "Name"], "value": ["kind": "binding", "path": "form.name"]]
        for (key, value) in props.objectValue ?? JSONObject() { field[key] = value }
        return try HotlayoutDocument.load([
            "schemaVersion": "9.27.0", "documentId": "d", "name": "n", "initialScreenId": "a",
            "screens": [["screenId": "a", "name": "A", "root": ["id": "r", "type": "Screen", "props": [:], "children": [["id": "f", "type": "TextField", "props": .object(field)]]]]],
        ])
    }

    func host(_ document: HotlayoutDocument, recorder: Recorder, data: [String: JSONValue] = [:]) -> UIWindow {
        let screen = HotlayoutScreen(document: document, data: data, locale: "en", onWrite: { path, value in recorder.writes.append("\(path)=\(value)") })
        let controller = UIHostingController(rootView: screen)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        spin()
        return window
    }

    /// The control reports a change of its text to the coordinator, as UIKit does on a real edit
    /// (a programmatic edit does not send the control event, so the report is made by hand).
    func report(_ field: UITextField) {
        (field.delegate as? InputTextCoordinator)?.editingChanged(field)
    }

    func spin(_ seconds: Double = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }

    /// What a person's keyboard does with a composition: marked text, then the committed text. The
    /// system reports each as a change of the control.
    func compose(_ control: UITextInput & UIView, marked: [String], commit: String, report: () -> Void) {
        for step in marked {
            control.setMarkedText(step, selectedRange: NSRange(location: step.utf16.count, length: 0))
            report()
            spin(0.1)
        }
        control.setMarkedText(commit, selectedRange: NSRange(location: commit.utf16.count, length: 0))
        control.unmarkText()
        report()
        spin(0.3)
    }

    func testSingleLineWritesTheCommittedTextOnce() throws {
        let recorder = Recorder()
        let window = host(try document(), recorder: recorder)
        let field = try XCTUnwrap(find(UITextField.self, in: window))
        XCTAssertTrue(field.becomeFirstResponder())
        spin()
        compose(field, marked: ["n", "ni", "に"], commit: "にほん") { report(field) }
        XCTAssertEqual(recorder.writes, ["form.name=string(\"にほん\")"], "nothing is written while composing; the committed text once")
        XCTAssertEqual(field.text, "にほん")
    }

    func testPlainTypingStillWritesEveryChange() throws {
        let recorder = Recorder()
        let window = host(try document(), recorder: recorder)
        let field = try XCTUnwrap(find(UITextField.self, in: window))
        XCTAssertTrue(field.becomeFirstResponder())
        spin()
        field.insertText("A")
        report(field)
        field.insertText("l")
        report(field)
        spin(0.3)
        XCTAssertEqual(recorder.writes, ["form.name=string(\"A\")", "form.name=string(\"Al\")"])
    }

    func testTheLimitCountsCodePointsAndCutsWhatTheControlHolds() throws {
        let recorder = Recorder()
        let window = host(try document(props: ["maxLength": 4, "counter": true]), recorder: recorder)
        let field = try XCTUnwrap(find(UITextField.self, in: window))
        XCTAssertTrue(field.becomeFirstResponder())
        spin()
        field.insertText("abcdef")
        report(field)
        spin(0.4)
        XCTAssertEqual(recorder.writes, ["form.name=string(\"abcd\")"])
        XCTAssertEqual(field.text, "abcd", "the control shows the text cut to the limit")
    }

    func testKeystrokesPastTheLimitAreCutOneByOne() throws {
        let recorder = Recorder()
        let window = host(try document(props: ["maxLength": 6]), recorder: recorder, data: ["form.name": "0790 0"])
        let field = try XCTUnwrap(find(UITextField.self, in: window))
        XCTAssertTrue(field.becomeFirstResponder())
        spin()
        for digit in "123456" {
            field.insertText(String(digit))
            report(field)
            spin(0.05)
        }
        spin(0.4)
        XCTAssertEqual(field.text, "0790 0", "the limit of six is reached: the rest is cut")
    }

    func testMultiLineFieldIsComposedLikeTheSingleLine() throws {
        let recorder = Recorder()
        let window = host(try document(props: ["lines": 3]), recorder: recorder)
        let view = try XCTUnwrap(find(UITextView.self, in: window))
        XCTAssertTrue(view.becomeFirstResponder())
        spin()
        compose(view, marked: ["k", "ka"], commit: "か") { view.delegate?.textViewDidChange?(view) }
        XCTAssertEqual(recorder.writes, ["form.name=string(\"か\")"])
        XCTAssertEqual(view.text, "か")
    }

    /// A control the platform focused (a tap) keeps the focus through an update drawn before the screen has heard of
    /// it: only a change of what the screen asks moves the focus. Otherwise the stale ask resigns the control, and an
    /// open composition is committed and written character by character.
    func testAFocusThePlatformGaveIsNotUndoneByAStaleAsk() throws {
        let coordinator = InputTextCoordinator()
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        view.delegate = coordinator
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.addSubview(view)
        window.makeKeyAndVisible()
        coordinator.applyFocus(false, to: view)
        XCTAssertTrue(view.becomeFirstResponder())
        coordinator.applyFocus(false, to: view)
        spin(0.2)
        XCTAssertTrue(view.isFirstResponder, "the screen asked for no change")
        coordinator.applyFocus(true, to: view)
        coordinator.applyFocus(false, to: view)
        spin(0.2)
        XCTAssertFalse(view.isFirstResponder, "the screen asked the focus away")
    }

    func testAValueThatArrivesBeforeTheFirstTouchIsNotWritten() throws {
        let recorder = Recorder()
        let window = host(try document(), recorder: recorder)
        let field = try XCTUnwrap(find(UITextField.self, in: window))
        // The platform fills the field (autofill) without a touch: not kept, not written.
        field.text = "Saved"
        report(field)
        spin(0.3)
        XCTAssertEqual(recorder.writes, [])
    }

    func testDisabledFieldDoesNotTakeInput() throws {
        let recorder = Recorder()
        let doc = try document(props: ["disabledIf": ["path": "form.locked", "op": "isTrue"]])
        let window = host(doc, recorder: recorder, data: ["form.locked": true])
        let field = try XCTUnwrap(find(UITextField.self, in: window))
        XCTAssertFalse(field.isEnabled)
        XCTAssertFalse(field.becomeFirstResponder(), "a disabled field cannot take the focus")
    }
}
#endif
