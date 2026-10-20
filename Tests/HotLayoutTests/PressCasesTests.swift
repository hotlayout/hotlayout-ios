import SwiftUI
import XCTest

@testable import HotLayout

/// Who takes a press, the long press, the feedback of a pressed node and the haptic request,
/// against the shared tables (`long-press/`, `composition/`, `press-feedback/`, `actions/`).
@MainActor
final class PressCasesTests: XCTestCase {
    static let longPress = try! Contract.json("fixtures/long-press/long-press-cases.json")
    static let composition = try! Contract.json("fixtures/composition/composition-cases.json")
    static let feedback = try! Contract.json("fixtures/press-feedback/press-feedback-cases.json")
    static let actions = try! Contract.json("fixtures/actions/action-cases.json")

    /// Groups this reader does not run, each with the reason. The test fails when a group of a
    /// table is neither run nor named here, and when a name here is no longer a group.
    static let notRun: [String: String] = [
        "long-press/documentCases": "rules of the validator (what may be published); the reader draws any document it can read",
        "composition/nestingCases": "the registry of allowed children belongs to the validator; the reader draws any tree of its parse depth",
        "composition/depthCases": "the depth the builder publishes (8) is the validator's; the reader's own limit is checked by DocumentTests",
        "composition/documentCases": "verdicts of the schema and the validator on whole documents",
        "actions/formCases": "run by ActionCasesTests", "actions/schemaCases": "verdicts of the schema",
        "actions/documentCases": "verdicts of the validator", "actions/handedCases": "run by ActionCasesTests",
        "actions/flowCases": "run by ActionCasesTests", "actions/writeCases": "run by WriteCasesTests",
        "actions/writeControlCases": "run by WriteCasesTests", "actions/writeSchemaCases": "verdicts of the schema",
        "actions/writeDocumentCases": "verdicts of the validator", "actions/writeTreeCases": "run by WriteCasesTests",
        "actions/writePressCases": "run by WriteCasesTests", "actions/hapticSchemaCases": "verdicts of the schema",
    ]

    func testEveryGroupIsRunOrNamed() {
        let run: Set<String> = [
            "long-press/gestureCases", "long-press/keyCases", "long-press/nodeCases", "long-press/receiverCases", "long-press/ruleCases",
            "long-press/keyRepeatCases", "long-press/clickAfterFireCases", "long-press/onceRuleCases",
            "composition/pressableCases", "composition/pressCases", "composition/nameCases",
            "press-feedback/kindCases", "press-feedback/poseCases", "press-feedback/ruleCases", "actions/hapticCases",
        ]
        var groups: Set<String> = []
        for (name, table) in [("long-press", Self.longPress), ("composition", Self.composition), ("press-feedback", Self.feedback), ("actions", Self.actions)] {
            for (key, value) in table.objectValue ?? JSONObject() where key.hasSuffix("Cases") && value.arrayValue != nil {
                groups.insert("\(name)/\(key)")
            }
        }
        let known = run.union(Self.notRun.keys)
        XCTAssertEqual(groups.subtracting(known), [], "groups of the tables that are neither run nor named")
        XCTAssertEqual(known.subtracting(groups), [], "names that are no longer groups")
    }

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    private func rows(_ table: JSONValue, _ group: String, _ count: Int) -> [JSONObject] {
        let list = Contract.rows(table, group)
        XCTAssertEqual(list.count, count, "\(group): the table has \(list.count) rows")
        return list
    }

    private func node(_ value: JSONValue?) throws -> DocumentNode {
        try Harness.node(try XCTUnwrap(value))
    }

    private func text(_ node: DocumentNode, _ field: String) -> String {
        Harness.context(rightToLeft: false).text(node, field: field)
    }

    // MARK: Long press

    func testGestures() {
        for row in rows(Self.longPress, "gestureCases", 11) {
            let outcome = LongPressRules.outcome(
                heldMs: row["heldMs"]?.numberValue ?? 0, moved: row["moved"]?.numberValue ?? 0, cancelled: row["cancelled"]?.boolValue ?? false,
                hasLongPress: row["hasLongPress"]?.boolValue ?? false, hasAction: row["hasAction"]?.boolValue ?? false
            )
            XCTAssertEqual(outcome.rawValue, row["expect"]?.stringValue, name(row))
        }
    }

    func testKeys() {
        for row in rows(Self.longPress, "keyCases", 6) {
            XCTAssertEqual(LongPressRules.isLongPressKey(row["key"]?.stringValue ?? "", shift: row["shiftKey"]?.boolValue ?? false), row["expect"]?.boolValue, name(row))
        }
        for row in rows(Self.longPress, "keyRepeatCases", 6) {
            XCTAssertEqual(LongPressRules.keyPerforms(row["key"]?.stringValue ?? "", shift: row["shiftKey"]?.boolValue ?? false, repeating: row["repeat"]?.boolValue ?? false), row["expect"]?.boolValue, name(row))
        }
    }

    func testClickAfterFire() {
        for row in rows(Self.longPress, "clickAfterFireCases", 8) {
            let swallowed = LongPressRules.swallowsClick(
                fired: row["fired"]?.boolValue ?? false, released: row["released"]?.boolValue ?? false,
                sinceReleaseMs: row["sinceReleaseMs"]?.numberValue ?? 0, newPointerDown: row["newPointerDown"]?.boolValue ?? false
            )
            XCTAssertEqual(swallowed, row["expect"]?.boolValue, name(row))
        }
    }

    func testRules() throws {
        for row in rows(Self.longPress, "ruleCases", 5) {
            switch row["rule"]?.stringValue {
            case "thresholdMs": XCTAssertEqual(row["expect"]?.numberValue, LongPressRules.thresholdMs)
            case "touchSlop": XCTAssertEqual(row["expect"]?.numberValue, LongPressRules.touchSlop)
            case "order": XCTAssertEqual((row["expect"]?.arrayValue ?? []).compactMap(\.stringValue), LongPressRules.order)
            case "props": XCTAssertEqual(row["expect"]?["action"]?.stringValue, "longPress"); XCTAssertEqual(row["expect"]?["label"]?.stringValue, "longPressLabel")
            case "accessibility.keys": XCTAssertEqual(row["expect"]?.arrayValue?.count, 2)
            default: XCTFail("unknown rule \(name(row))")
            }
        }
        for row in rows(Self.longPress, "onceRuleCases", 3) where row["rule"]?.stringValue == "clickAfterFire.windowMs" {
            XCTAssertEqual(row["expect"]?.numberValue, LongPressRules.clickAfterFireWindowMs)
        }
        // The same numbers as the artifact says.
        let block = try Contract.json("screen-schema.json")["x-longPress"]
        XCTAssertEqual(block?["thresholdMs"]?.numberValue, LongPressRules.thresholdMs)
        XCTAssertEqual(block?["touchSlop"]?.numberValue, LongPressRules.touchSlop)
        XCTAssertEqual((block?["order"]?.arrayValue ?? []).compactMap(\.stringValue), LongPressRules.order)
        let once = try Contract.json("screen-schema.json")["x-longPressOnce"]
        XCTAssertEqual(once?["clickAfterFire"]?["windowMs"]?.numberValue, LongPressRules.clickAfterFireWindowMs)
    }

    func testNodes() throws {
        for row in rows(Self.longPress, "nodeCases", 9) {
            let expect = row["expect"]
            if let nodeJSON = row["node"] {
                let node = try Harness.node(nodeJSON)
                XCTAssertEqual(PressTarget.acceptsLongPress(node.type), expect?["accepts"]?.boolValue, name(row))
                XCTAssertEqual(PressTarget.longPress(node) != nil, expect?["longPress"]?.boolValue, name(row))
                XCTAssertEqual(PressTarget.actsOnPress(node), expect?["acts"]?.boolValue, name(row))
            } else {
                XCTAssertEqual(PressTarget.acceptsLongPress(row["type"]?.stringValue ?? ""), expect?["accepts"]?.boolValue, name(row))
            }
        }
    }

    /// The nodes under the point, from the root of the tree down to the node `target`.
    private func chain(_ tree: DocumentNode, to target: String) -> [DocumentNode]? {
        if tree.id == target { return [tree] }
        for child in tree.children {
            if let found = chain(child, to: target) { return [tree] + found }
        }
        return nil
    }

    func testReceivers() throws {
        for row in rows(Self.longPress, "receiverCases", 5) {
            let nodes = try (row["chain"]?.arrayValue ?? []).map { try Harness.node($0) }
            let receiver = PressTarget.receiver(chain: nodes)
            let runs = receiver.flatMap { PressTarget.longPress($0) != nil ? $0.id : nil }
            XCTAssertEqual(runs, row["expect"]?.stringValue, name(row))
        }
    }

    // MARK: Composition

    func testPressable() throws {
        for row in rows(Self.composition, "pressableCases", 19) {
            let node = try node(row["node"])
            XCTAssertEqual(PressTarget.isPressHost(node), row["pressable"]?.boolValue, name(row) + ": pressable")
            XCTAssertEqual(PressTarget.ownsPress(node), row["ownsPress"]?.boolValue, name(row) + ": ownsPress")
            XCTAssertEqual(PressTarget.actsOnPress(node), row["acts"]?.boolValue, name(row) + ": acts")
        }
    }

    func testReceiverAndRunner() throws {
        for row in rows(Self.composition, "pressCases", 21) {
            let tree = try node(row["tree"])
            let path = try XCTUnwrap(chain(tree, to: row["press"]?.stringValue ?? ""), name(row))
            let receiver = PressTarget.receiver(chain: path)
            XCTAssertEqual(receiver?.id, row["receiver"]?.stringValue, name(row) + ": receiver")
            let disabled = Set((row["disabled"]?.arrayValue ?? []).compactMap(\.stringValue))
            let runs = receiver.flatMap { PressTarget.actsOnPress($0) && !disabled.contains($0.id) ? $0.id : nil }
            XCTAssertEqual(runs, row["runs"]?.stringValue, name(row) + ": runs")
        }
    }

    func testNames() throws {
        for row in rows(Self.composition, "nameCases", 35) {
            let tree = try node(row["tree"])
            let heard = PressTarget.name(of: tree, text: text)
            XCTAssertEqual(!heard.isEmpty, row["hasName"]?.boolValue, name(row) + ": hasName (\(heard))")
            if let start = row["startsWith"]?.stringValue { XCTAssertTrue(heard.hasPrefix(start), name(row) + ": starts with the first text (\(heard))") }
            for text in (row["heard"]?.arrayValue ?? []).compactMap(\.stringValue) { XCTAssertTrue(heard.contains(text), name(row) + ": heard “\(text)” in “\(heard)”") }
            for text in (row["described"]?.arrayValue ?? []).compactMap(\.stringValue) { XCTAssertTrue(heard.contains(text), name(row) + ": described “\(text)”") }
        }
    }

    // MARK: Feedback

    func testFeedbackKinds() throws {
        for row in rows(Self.feedback, "kindCases", 10) {
            let node = try node(row["node"])
            let kind = PressFeedbackRules.kind(node, disabled: row["disabled"]?.boolValue ?? false, swipe: row["swipe"]?.boolValue ?? false)
            XCTAssertEqual(kind?.rawValue, row["expect"]?.stringValue, name(row))
        }
    }

    func testFeedbackPoses() {
        for row in rows(Self.feedback, "poseCases", 3) {
            let kind = PressFeedbackRules.Kind(rawValue: row["kind"]?.stringValue ?? "")
            let pose = PressFeedbackRules.pose(try! XCTUnwrap(kind))
            XCTAssertEqual(pose.scale, row["expect"]?["scale"]?.numberValue)
            XCTAssertEqual(pose.opacity, row["expect"]?["opacity"]?.numberValue)
            // "Reduce motion" keeps only the fade.
            XCTAssertEqual(PressFeedbackRules.pose(kind!, reduceMotion: true), PressFeedbackRules.Pose(scale: 1, opacity: 0.7))
        }
    }

    func testFeedbackRules() throws {
        for row in rows(Self.feedback, "ruleCases", 5) {
            let expect = row["expect"]
            switch row["rule"]?.stringValue {
            case "down.durationMs": XCTAssertEqual(expect?.numberValue, PressFeedbackRules.downMs)
            case "up.durationMs": XCTAssertEqual(expect?.numberValue, PressFeedbackRules.upMs)
            case "up.curve": XCTAssertEqual((expect?.arrayValue ?? []).compactMap(\.numberValue), PressFeedbackRules.upCurve)
            case "down.curve": XCTAssertEqual((expect?.arrayValue ?? []).compactMap(\.numberValue), PressFeedbackRules.downCurve)
            case "words": XCTAssertEqual((expect?.arrayValue ?? []).compactMap(\.stringValue), [PressFeedbackRules.offWord])
            default: XCTFail("unknown rule \(name(row))")
            }
        }
        let block = try Contract.json("screen-schema.json")["x-pressFeedback"]
        XCTAssertEqual(block?["pose"]?["card"]?["scale"]?.numberValue, 0.97)
        XCTAssertEqual(block?["pose"]?["button"]?["scale"]?.numberValue, 0.96)
        XCTAssertEqual(block?["pose"]?["fade"]?["opacity"]?.numberValue, PressFeedbackRules.fadeOpacity)
        XCTAssertEqual(block?["down"]?["durationMs"]?.numberValue, PressFeedbackRules.downMs)
        XCTAssertEqual(block?["up"]?["durationMs"]?.numberValue, PressFeedbackRules.upMs)
    }

    // MARK: Haptic

    func testHapticRequests() {
        for row in rows(Self.actions, "hapticCases", 7) {
            let action = row["action"]?.objectValue ?? JSONObject()
            let word = PressRules.haptic(of: action, disabled: row["disabled"]?.boolValue ?? false)
            XCTAssertEqual(word?.rawValue, row["expect"]?.stringValue, name(row))
        }
    }

    func testHapticWordsMirrorTheArtifact() throws {
        let words = try Contract.json("screen-schema.json")["x-haptic"]?["words"]?.arrayValue ?? []
        XCTAssertEqual(words.compactMap(\.stringValue), HapticFeedback.allCases.map(\.rawValue))
    }

    func testDeliveryOrderIsHapticTrackAction() throws {
        var flow = Flow(document: FlowDocument(try loadDocument(.object(JSONObject([
            ("schemaVersion", "9.27.0"), ("documentId", "d"), ("name", "n"), ("initialScreenId", "a"),
            ("screens", [.object(JSONObject([("screenId", "a"), ("name", "A"), ("root", .object(JSONObject([("id", "r"), ("type", "Screen"), ("props", .object(JSONObject())), ("children", [])])))]))]),
        ])))), entry: nil)
        let action: JSONObject = ["type": "redeem", "haptic": "success", "track": ["event": "redeemed"]]
        let outcome = flow.press(action)
        var order: [String] = []
        PressDelivery.deliver(
            outcome, source: ActionSource(nodeId: "n", screenId: "a", record: nil),
            onHaptic: { word, _ in order.append("haptic:\(word.rawValue)") }, onTrack: { event, _ in order.append("track:\(event.event)") },
            onAction: { handed, _ in
                order.append("action:\(handed.type)")
                return nil
            }
        )
        XCTAssertEqual(order, ["haptic:success", "track:redeemed", "action:redeem"])
        // The action handed to the host does not carry the field.
        XCTAssertNil(outcome.handed?.params?["haptic"])
    }
}
