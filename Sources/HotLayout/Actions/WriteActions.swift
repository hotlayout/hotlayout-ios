import Foundation

/// The write actions (`x-actions.write`): `setValue` puts a literal of the document under a data
/// path, `toggleValue` flips the flag under it. The reader performs both itself, through the same
/// write as a field's: into the session of the screen and to the host (`onWrite`) at the same
/// moment. Neither reaches `onAction`.
///
/// Nothing here reads data except the CURRENT value under the node's own path (the caller passes
/// the lookup of the node's data scope). The path and the value are literals of the document:
/// `paramBindings` and `carryRecord` are not read.
enum WriteActions {
    static let setValue = "setValue"
    static let toggleValue = "toggleValue"
    static let pathParam = "path"
    static let valueParam = "value"
    static let valueTypeParam = "valueType"
    static let pathMaxLength = 128
    static let valueTypes = ["string", "boolean", "number"]
    static let defaultValueType = "string"

    /// Why a write action does nothing (`x-actions.write.problems`).
    enum Problem: String, Equatable, Sendable {
        case missingPath = "missing-path"
        case pathTooLong = "path-too-long"
        case unknownValueType = "unknown-value-type"
        case notAFlag = "not-a-flag"
        case notANumber = "not-a-number"
    }

    /// What a press of a write action does.
    enum Step: Equatable, Sendable {
        /// Put the value under the path.
        case write(path: String, value: JSONValue)
        /// The value is already there: nothing is written, the analytics event still goes.
        case same(path: String, value: JSONValue)
        /// The action is not usable: nothing is written, nothing goes to the host.
        case invalid(Problem)
    }

    static func isWriteType(_ type: String?) -> Bool {
        type == setValue || type == toggleValue
    }

    private static func param(_ action: JSONObject, _ name: String) -> String? {
        action["params"]?[name]?.stringValue
    }

    /// The path of a write action, or the reason there is none. Lengths count UTF-16 units.
    static func path(of action: JSONObject) -> (path: String?, problem: Problem?) {
        guard let path = param(action, pathParam), !path.isEmpty else { return (nil, .missingPath) }
        if path.utf16.count > pathMaxLength { return (nil, .pathTooLong) }
        return (path, nil)
    }

    /// The value a `setValue` writes, typed by `valueType`: a string, a flag or a number; the
    /// empty string for an absent or empty number.
    static func literal(of action: JSONObject) -> (value: JSONValue?, problem: Problem?) {
        let word = param(action, valueTypeParam) ?? defaultValueType
        guard valueTypes.contains(word) else { return (nil, .unknownValueType) }
        let literal = param(action, valueParam) ?? ""
        switch word {
        case "string": return (.string(literal), nil)
        case "boolean":
            if literal == "true" { return (.bool(true), nil) }
            if literal == "false" { return (.bool(false), nil) }
            return (nil, .notAFlag)
        default:
            // A number is parsed by the number field's own rule; empty is a cleared field.
            if literal.isEmpty { return (.string(""), nil) }
            guard let number = InputRules.parseNumber(literal) else { return (nil, .notANumber) }
            return (.number(number), nil)
        }
    }

    /// Whether `current` already IS `value`: equality by type, no conversion. A number is read the
    /// way a number field reads it (`7.0` is `7`), `"7"` is not `7`; the empty string equals an
    /// absent value and `null`.
    static func holdsWritten(_ current: JSONValue?, _ value: JSONValue) -> Bool {
        switch value {
        case .number(let number): return InputRules.readNumber(current) == number
        case .bool: return current == value
        case .string(let text) where text.isEmpty: return current == .string("") || current == nil || current == .null
        default: return current == value
        }
    }

    /// What a press of `action` does with the data it reads through `read`; `nil` when the action
    /// is not a write action.
    static func step(of action: JSONObject, read: (String) -> JSONValue?) -> Step? {
        guard isWriteType(action["type"]?.stringValue) else { return nil }
        let target = path(of: action)
        guard let path = target.path else { return .invalid(target.problem ?? .missingPath) }
        // A toggle writes the negation of what is SHOWN: on only for the flag `true`. It always
        // writes, and it does not read `value` or `valueType`.
        if action["type"]?.stringValue == toggleValue { return .write(path: path, value: .bool(!InputRules.flag(of: read(path)))) }
        let typed = literal(of: action)
        guard let value = typed.value else { return .invalid(typed.problem ?? .notAFlag) }
        return holdsWritten(read(path), value) ? .same(path: path, value: value) : .write(path: path, value: value)
    }

    /// Whether the reader writes under `path` at all (the write gate): the shape of a data path
    /// without a forbidden segment. The host sees every write in `onWrite` and may drop the ones
    /// it does not expect.
    static func isWritablePath(_ path: String) -> Bool {
        ActionCatalog.isDataPath(path)
    }

    // MARK: A node with a write action, as a control

    enum Role: String, Equatable, Sendable { case option, toggle }

    struct Control: Equatable, Sendable {
        let role: Role
        let path: String
        let on: Bool
    }

    /// The control a press of `action` makes of its node, or `nil` for a plain button: not a write
    /// action, an invalid one, or a `setValue` that clears (an empty value is a command, not an
    /// option).
    static func control(of action: JSONObject, read: (String) -> JSONValue?) -> Control? {
        guard isWriteType(action["type"]?.stringValue), let path = path(of: action).path else { return nil }
        if action["type"]?.stringValue == toggleValue { return Control(role: .toggle, path: path, on: InputRules.flag(of: read(path))) }
        guard let value = literal(of: action).value, value != .string("") else { return nil }
        return Control(role: .option, path: path, on: holdsWritten(read(path), value))
    }

    /// The path an option writes: a valid `setValue` with a non-empty value.
    static func optionPath(of action: JSONObject) -> String? {
        guard action["type"]?.stringValue == setValue, let path = path(of: action).path,
            let value = literal(of: action).value, value != .string("")
        else { return nil }
        return path
    }

    /// The types whose `action` is a press (a button, an icon button, a row, a pressable container).
    static let pressTypes: Set<String> = ["Button", "IconButton", "ListTile", "Column", "Row", "Container", "Stack"]

    /// The action a node performs on a press; `nil` for the rest.
    static func pressAction(of node: DocumentNode) -> JSONObject? {
        guard pressTypes.contains(node.type) else { return nil }
        return node.props["action"]?.objectValue
    }

    /// The place of an option in its group: the position (from 1) and the size.
    struct Place: Equatable, Sendable {
        let position: Int
        let size: Int
    }

    /// The place of `node` among its `siblings` (the children of ONE parent in document order):
    /// the group is the SHOWN options that write the same path. One option, a node that is not an
    /// option and an option under another parent have no place.
    static func place(of node: DocumentNode, in siblings: [DocumentNode], isShown: (DocumentNode) -> Bool = { _ in true }) -> Place? {
        guard let action = pressAction(of: node), let path = optionPath(of: action) else { return nil }
        let group = siblings.filter { sibling in
            pressAction(of: sibling).flatMap(optionPath(of:)) == path && isShown(sibling)
        }
        guard let at = group.firstIndex(where: { $0.id == node.id }), group.count >= 2 else { return nil }
        return Place(position: at + 1, size: group.count)
    }
}

/// Whether a press reaches the action of a control: a disabled control does nothing at all —
/// neither the action, nor the analytics event, nor the request for haptic feedback.
enum PressRules {
    /// The haptic request a press hands to the host: the word of an enabled control's action.
    static func haptic(of action: JSONObject, disabled: Bool) -> HapticFeedback? {
        disabled ? nil : ActionCatalog.haptic(action)
    }
}
