import XCTest

@testable import HotLayout

/// The shared action table (`fixtures/actions/action-cases.json`): forms of parameters, what the
/// host receives, and the screen flow with its events.
final class ActionCasesTests: XCTestCase {
    static let table = try! Contract.json("fixtures/actions/action-cases.json")

    /// `{ "repeat": { prefix, char, length } }` stands for a built string wherever a string may stand.
    static func expand(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            if object.count == 1, let spec = object["repeat"]?.objectValue {
                return .string(built(spec))
            }
            var copy = JSONObject()
            for (key, item) in object { copy[key] = expand(item) }
            return .object(copy)
        case .array(let items):
            return .array(items.map(expand))
        default:
            return value
        }
    }

    static func built(_ spec: JSONObject) -> String {
        let prefix = spec["prefix"]?.stringValue ?? ""
        let char = spec["char"]?.stringValue ?? "a"
        let length = Int(spec["length"]?.numberValue ?? 0)
        return prefix + String(repeating: char, count: max(0, length - prefix.utf16.count))
    }

    func testFormCases() {
        let rows = Contract.rows(Self.table, "formCases")
        XCTAssertEqual(rows.count, 108)
        for row in rows {
            let value: String?
            if let spec = row["repeat"]?.objectValue { value = Self.built(spec) } else { value = row["value"]?.stringValue }
            let problem = ActionCatalog.formProblem(row["form"]?.stringValue ?? "", value)
            XCTAssertEqual(problem?.rawValue, row["problem"]?.stringValue, row["name"]?.stringValue ?? "?")
        }
    }

    func testFormsMirrorTheArtifact() throws {
        let schema = try Contract.json("screen-schema.json")
        let forms = schema["x-actions"]?["forms"]
        XCTAssertEqual(forms?["httpsUrl"]?["pattern"]?.stringValue, ActionCatalog.httpsURLPattern)
        XCTAssertEqual(forms?["appLink"]?["pattern"]?.stringValue, ActionCatalog.appLinkPattern)
        XCTAssertEqual(Set((forms?["appLink"]?["forbiddenSchemes"]?.arrayValue ?? []).compactMap(\.stringValue)), ActionCatalog.forbiddenSchemes)
        XCTAssertEqual(forms?["httpsUrl"]?["maxLength"]?.numberValue, Double(ActionCatalog.urlMaxLength))
    }

    static func handedJSON(_ action: HotlayoutAction?) -> JSONValue {
        guard let action else { return .null }
        var object = JSONObject()
        object["type"] = .string(action.type)
        if let params = action.params {
            var map = JSONObject()
            for key in params.keys.sorted() { map[key] = .string(params[key]!) }
            object["params"] = .object(map)
        }
        switch action.standard {
        case .openURL(let url)?: object["standard"] = ["type": "openUrl", "url": .string(url)]
        case .deeplink(let url, let scheme)?: object["standard"] = ["type": "deeplink", "url": .string(url), "scheme": .string(scheme)]
        case .close?: object["standard"] = ["type": "close"]
        case nil: break
        }
        if let invalid = action.invalid { object["invalid"] = ["param": .string(invalid.param), "problem": .string(invalid.problem.rawValue)] }
        return .object(object)
    }

    func testHandedCases() {
        let rows = Contract.rows(Self.table, "handedCases")
        XCTAssertEqual(rows.count, 55)
        for row in rows {
            let action = Self.expand(row["action"] ?? .null).objectValue ?? JSONObject()
            let handed = ActionCatalog.handed(action, scope: Contract.scope(row["data"]))
            XCTAssertEqual(Self.handedJSON(handed), Self.expand(row["handed"] ?? .null), row["name"]?.stringValue ?? "?")
        }
    }

    static func shownJSON(_ event: ScreenShownEvent?) -> JSONValue {
        guard let event else { return .null }
        var object: JSONObject = JSONObject([
            ("documentId", .string(event.documentId)),
            ("screenId", .string(event.screenId)),
            ("entry", event.entry.map(JSONValue.string) ?? .null),
            ("presentation", .string(event.presentation.rawValue)),
            ("cause", .string(event.cause.rawValue)),
            ("depth", .number(Double(event.depth))),
            ("record", event.record.map(Self.recordJSON) ?? .null),
        ])
        if let placement = event.modalPlacement { object["modalPlacement"] = .string(placement) }
        if let icons = event.statusBarIcons { object["statusBarIcons"] = .string(icons) }
        return .object(object)
    }

    static func recordJSON(_ record: DataScope) -> JSONValue {
        var object = JSONObject()
        for key in record.keys.sorted() { object[key] = record[key] }
        return .object(object)
    }

    static func trackJSON(_ track: TrackEvent?) -> JSONValue {
        guard let track else { return .null }
        var object: JSONObject = JSONObject([("event", .string(track.event))])
        if let params = track.params {
            var map = JSONObject()
            for key in params.keys.sorted() { map[key] = .string(params[key]!) }
            object["params"] = .object(map)
        }
        return .object(object)
    }

    static func flowDocument(_ row: JSONObject, documentId: String) -> FlowDocument {
        let placements = row["modalPlacement"]?.objectValue ?? JSONObject()
        let screens = (row["screens"]?.objectValue ?? JSONObject()).map { id, presentation in
            FlowDocument.Screen(screenId: id, presentation: presentation.stringValue == "modal" ? .modal : .page, modalPlacement: placements[id]?.stringValue)
        }
        var entryPoints: [String: String] = [:]
        for (name, target) in row["entryPoints"]?.objectValue ?? JSONObject() { entryPoints[name] = target.stringValue }
        return FlowDocument(documentId: documentId, screens: screens, initialScreenId: row["initial"]?.stringValue ?? row["start"]?.stringValue, entryPoints: entryPoints)
    }

    static func instances(_ value: JSONValue?) -> [ListInstance] {
        (value?.arrayValue ?? []).compactMap(\.objectValue).map {
            ListInstance(item: $0["item"]?.stringValue ?? "", fields: $0["fields"]?.objectValue ?? JSONObject(), source: $0["source"]?.stringValue ?? "")
        }
    }

    func testFlowCases() {
        let rows = Contract.rows(Self.table, "flowCases")
        XCTAssertEqual(rows.count, 39)
        for row in rows {
            let name = row["name"]?.stringValue ?? "?"
            let documentId = row["documentId"]?.stringValue ?? ""
            var flow = Flow(document: Self.flowDocument(row, documentId: documentId), entry: row["entry"]?.stringValue)
            let start = row["start"]?.objectValue
            XCTAssertEqual(flow.stack.map(\.screenId), (start?["stack"]?.arrayValue ?? []).compactMap(\.stringValue), "start stack: \(name)")
            XCTAssertEqual(Self.shownJSON(flow.shownEvent(cause: .entry)), start?["shown"], "start shown: \(name)")
            let data = Contract.scope(row["data"])
            for (index, step) in (row["steps"]?.arrayValue ?? []).compactMap(\.objectValue).enumerated() {
                let label = "\(name) — step \(index + 1)"
                var outcome = PressOutcome()
                switch step["do"]?.stringValue {
                case "press":
                    // An auto-repeat of a held key is not a press: nothing happens.
                    if step["repeat"]?.boolValue == true { break }
                    let cancelled = step["cancelled"]?.boolValue == true
                    outcome = flow.press(Self.expand(step["action"] ?? .null).objectValue ?? JSONObject(), instances: Self.instances(step["instances"]), data: data, allowNavigation: { _, _, _, _ in !cancelled })
                case "restart":
                    outcome.shown = flow.restart(entry: step["entry"]?.stringValue)
                case "rerender":
                    break
                case "newVersion":
                    var merged = row
                    merged["screens"] = step["screens"]
                    if let initial = step["initial"] { merged["initial"] = initial }
                    if let entries = step["entryPoints"] { merged["entryPoints"] = entries }
                    outcome.shown = flow.update(document: Self.flowDocument(merged, documentId: documentId))
                default:
                    XCTFail("unknown step: \(label)")
                }
                let expect = step["expect"]?.objectValue
                XCTAssertEqual(flow.stack.map(\.screenId), (expect?["stack"]?.arrayValue ?? []).compactMap(\.stringValue), "stack: \(label)")
                XCTAssertEqual(Self.trackJSON(outcome.track), expect?["track"] ?? .null, "track: \(label)")
                XCTAssertEqual(Self.handedJSON(outcome.handed), Self.expand(expect?["handed"] ?? .null), "handed: \(label)")
                XCTAssertEqual(Self.shownJSON(outcome.shown), expect?["shown"] ?? .null, "shown: \(label)")
            }
        }
    }
}
