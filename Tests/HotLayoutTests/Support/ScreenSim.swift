import Foundation
import XCTest

@testable import HotLayout

/// A screen of the tables without a view: the nodes of one `screens[]` entry, the data layers and
/// the session. A press goes through the same functions the views call (`WritePress`,
/// `WriteActions`, `FormRules`, `SessionWrite`), so what the table says about a press is checked
/// against the reader's rules and not against a copy of them.
struct ScreenSim {
    let root: DocumentNode
    var layers: DataLayers
    var session: DataScope {
        get { layers.session ?? [:] }
        set { layers.session = newValue }
    }

    /// What the host got, in order: `["track", event]` and `["write", path, value]`.
    var log: [[JSONValue]] = []

    init(nodes: [JSONValue], layers: DataLayers = DataLayers(), id: String = "main") {
        root = DocumentNode(id: "root-\(id)", type: "Screen", children: nodes.map(Self.node))
        self.layers = layers
        if self.layers.session == nil { self.layers.session = [:] }
    }

    /// A node of a table row (`id`, `type`, `props`, `visibleIf`, `children`) as the reader holds it.
    static func node(_ json: JSONValue) -> DocumentNode {
        let object = json.objectValue ?? JSONObject()
        var fields = JSONObject()
        for (key, value) in object where !["id", "type", "props", "children"].contains(key) { fields[key] = value }
        return DocumentNode(
            id: object["id"]?.stringValue ?? "", type: object["type"]?.stringValue ?? "", props: object["props"]?.objectValue ?? JSONObject(),
            fields: fields, children: (object["children"]?.arrayValue ?? []).map(node)
        )
    }

    var scope: DataScope { RecordScope.merge(layers) }

    func isFilled() -> Bool { FormRules.isFormFilled(root: root, scope: scope) }

    func find(_ id: String) -> [DocumentNode]? { WritePress.path(to: id, in: root) }

    func isDisabled(_ id: String) -> Bool {
        guard let node = find(id)?.last else { return false }
        return WritePress.isDisabled(node, scope: scope, screenRoot: root, screenScope: scope)
    }

    /// Whether the node is on the screen: its own `visibleIf` and those of its ancestors hold.
    func isShown(_ id: String) -> Bool {
        guard let path = find(id) else { return false }
        return path.allSatisfy { Conditions.isVisible($0.visibleIf, scope: scope) }
    }

    /// A press of the node `id` (or of a node inside it). `how`: `tap`, `enter`, `space`,
    /// `enter-held` — the auto-repeat of a held key is not a press, so it is one press.
    mutating func press(_ id: String) {
        // The innermost control under the point takes the press (`PressTarget.receiver`); a choice
        // option or an input takes it and runs no action.
        guard let path = find(id), let actor = PressTarget.receiver(chain: path), PressTarget.actsOnPress(actor),
            WriteActions.pressAction(of: actor).map(PressTarget.acts) == true, !PressTarget.isChoiceOption(actor)
        else { return }
        guard !WritePress.isDisabled(actor, scope: scope, screenRoot: root, screenScope: scope) else { return }
        guard let action = WriteActions.pressAction(of: actor) else { return }
        run(action)
    }

    /// The effects of one action, in the order the host sees them.
    mutating func run(_ action: JSONObject) {
        guard let effects = WritePress.effects(of: action, read: { scope[$0] }) else {
            // Any other action: the analytics event goes first, then the action itself.
            if let track = ActionCatalog.track(action) { log.append(["track", .string(track.event)]) }
            log.append(["action", .string(action["type"]?.stringValue ?? "")])
            return
        }
        if let track = effects.track { log.append(["track", .string(track.event)]) }
        if case .write(let path, let value) = effects.step, SessionWrite.apply(path: path, value: value, to: &session, gate: nil) {
            log.append(["write", .string(path), value])
        }
    }

    /// The siblings of a node: the children of its parent in document order.
    func siblings(of id: String) -> [DocumentNode] {
        guard let path = find(id), path.count >= 2 else { return [] }
        return path[path.count - 2].children
    }

    /// What the finished screen says about a node, in the words of the table.
    func control(_ id: String) -> JSONValue {
        guard isShown(id), let path = find(id), let node = path.last else { return "absent" }
        var result = JSONObject()
        let inGroup = path.dropLast().contains { $0.type == "ChoiceGroup" }
        if node.type == "ListTile", node.props["trailing"]?["kind"]?.stringValue == "radio" {
            // A row of a choice group: a radio of the group, without a position.
            let group = path.last { $0.type == "ChoiceGroup" }
            let selected = group.map { groupSelection($0) }
            result["role"] = "radio"
            result["checked"] = .bool(selected != nil && selected! == node.props["trailing"]?["optionValue"]?.stringValue)
            return .object(result)
        }
        _ = inGroup
        if let action = WriteActions.pressAction(of: node), let control = WriteActions.control(of: action, read: { scope[$0] }) {
            switch control.role {
            case .option:
                result["role"] = "radio"
                result["checked"] = .bool(control.on)
                if let place = WriteActions.place(of: node, in: siblings(of: id), isShown: { isShown($0.id) }) {
                    result["position"] = .number(Double(place.position))
                    result["size"] = .number(Double(place.size))
                }
            case .toggle:
                result["role"] = "button"
                result["pressed"] = .bool(control.on)
            }
            if isDisabled(id) { result["disabled"] = true }
            return .object(result)
        }
        if node.type == "Button" || node.type == "IconButton" {
            result["role"] = "button"
            if isDisabled(id) { result["disabled"] = true }
            return .object(result)
        }
        result["role"] = .null
        return .object(result)
    }

    /// The option a group shows as selected: the bound value, or the fallback of the binding.
    func groupSelection(_ group: DocumentNode) -> String? {
        let value = InputRules.path(of: group.props["value"]).flatMap { scope[$0] }
        let text = InputRules.text(of: value)
        let shown = text.isEmpty ? (InputRules.fallback(of: group.props["value"]) ?? "") : text
        return shown.isEmpty ? nil : shown
    }
}
