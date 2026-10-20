import Foundation

/// Conditions of the contract: `visibleIf`, the cases of `styleWhen`, `disabledIf`, the
/// filter of a list (`where`).
///
/// Rules (`x-compatibility.policy`, `x-conditions`):
///  - a condition that is not an object or has no path or operator is «no condition»;
///  - an unknown operator is visible (`unknownVisibilityOp: 'visible'`), and that is stronger
///    than the next rule: «I do not know the question» is not «I have no answer»;
///  - a missing value is EMPTY (`missingConditionValue: 'absent-is-empty'`): `isEmpty` holds,
///    every other operator does not;
///  - emptiness judges the VALUE: absent, `null`, the empty string and a list without records
///    are empty; zero, `false` and a string of spaces are not.
enum Conditions {
    static let knownOps: Set<String> = ["isTrue", "isFalse", "isEmpty", "isNotEmpty", "eq", "neq", "gt", "gte", "lt", "lte"]

    /// Whether a node with this `visibleIf` is shown.
    static func isVisible(_ condition: JSONValue?, scope: DataScope) -> Bool {
        guard let condition, !condition.isNull else { return true }
        return holds(condition, scope: scope, filterable: true)
    }

    /// Whether a condition holds. Used by `styleWhen` too: the first case that holds applies.
    static func holds(_ condition: JSONValue, scope: DataScope) -> Bool {
        holds(condition, scope: scope, filterable: true)
    }

    /// For `disabledIf`: only a condition the reader UNDERSTANDS can disable a control; an
    /// unknown operator does not.
    static func understoodHolds(_ condition: JSONValue?, scope: DataScope) -> Bool {
        guard let object = condition?.objectValue, object["path"]?.stringValue != nil,
            let op = object["op"]?.stringValue, knownOps.contains(op)
        else { return false }
        return holds(condition!, scope: scope, filterable: true)
    }

    /// An operand from another path that is absent, `null` or the empty string.
    static func isOperandMissing(_ value: JSONValue?) -> Bool {
        switch value {
        case nil, .null?: return true
        case .string(let text)?: return text.isEmpty
        default: return false
        }
    }

    /// The filter of a list: a record passes when the operand from another path is missing
    /// (`listFilter.valuePath.operandMissing.inWhere`), otherwise by the condition.
    static func wherePasses(_ condition: JSONValue, scope: DataScope) -> Bool {
        guard let object = condition.objectValue, object["path"]?.stringValue != nil, let op = object["op"]?.stringValue else { return true }
        if let other = object["valuePath"]?.stringValue, knownOps.contains(op), isOperandMissing(scope[other]) { return true }
        return holds(condition, scope: scope, filterable: false)
    }

    private static func holds(_ condition: JSONValue, scope: DataScope, filterable: Bool) -> Bool {
        guard let object = condition.objectValue, let path = object["path"]?.stringValue, let op = object["op"]?.stringValue else { return true }
        // Emptiness of a FILTERED list (9.23.0): the records that pass are counted, without `limit`.
        if filterable, op == "isEmpty" || op == "isNotEmpty", let filter = object["where"], filter.objectValue != nil {
            return somePasses(scope: scope, path: path, filter: filter, item: object["item"]?.stringValue ?? "") == (op == "isNotEmpty")
        }
        guard knownOps.contains(op) else { return true }
        guard let value = scope[path], !value.isNull else { return op == "isEmpty" }
        switch op {
        case "isTrue": return asBoolean(value)
        case "isFalse": return !asBoolean(value)
        case "isEmpty": return isEmpty(value)
        case "isNotEmpty": return !isEmpty(value)
        default: return compare(op, value: value, object: object, scope: scope)
        }
    }

    private static func somePasses(scope: DataScope, path: String, filter: JSONValue, item: String) -> Bool {
        guard let records = scope[path]?.arrayValue else { return false }
        return records.contains { record in
            let fields = record.objectValue ?? JSONObject()
            let inner = RecordScope.overlay(scope, RecordScope.instanceRecord(item: item, fields: fields)) ?? scope
            return wherePasses(filter, scope: inner)
        }
    }

    static func isEmpty(_ value: JSONValue) -> Bool {
        switch value {
        case .null: return true
        case .array(let items): return items.isEmpty
        case .string(let text): return text.isEmpty
        case .object: return false
        default: return false
        }
    }

    static func asBoolean(_ value: JSONValue) -> Bool {
        switch value {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .string(let text): return !text.isEmpty
        default: return false
        }
    }

    private static func compare(_ op: String, value: JSONValue, object: JSONObject, scope: DataScope) -> Bool {
        let operand: JSONValue?
        if let other = object["valuePath"]?.stringValue {
            operand = scope[other]
            if isOperandMissing(operand) { return false }
        } else {
            operand = object["value"]
        }
        switch op {
        case "eq": return equals(value, operand)
        case "neq": return !equals(value, operand)
        default:
            guard let a = comparable(value), let b = comparable(operand) else { return false }
            switch op {
            case "gt": return a > b
            case "gte": return a >= b
            case "lt": return a < b
            default: return a <= b
            }
        }
    }

    /// Equality without type coercion; values of different types compare as text (a date is
    /// an ISO string in the contract).
    private static func equals(_ left: JSONValue, _ right: JSONValue?) -> Bool {
        switch (left, right) {
        case (.string(let a), .string(let b)?): return a == b
        case (.number(let a), .number(let b)?): return a == b
        case (.bool(let a), .bool(let b)?): return a == b
        default: return conditionText(left) == conditionText(right)
        }
    }

    private static func conditionText(_ value: JSONValue?) -> String {
        switch value {
        case nil, .null?: return ""
        case .array?, .object?: return "[object]"
        default: return BindableText.asText(value)
        }
    }

    /// A number for an order comparison. A string of spaces (a cleared field) is NOT zero.
    private static func comparable(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number)?: return number
        case .bool(let flag)?: return flag ? 1 : 0
        case .string(let text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return javaScriptNumberParse(trimmed)
        case .null?: return 0
        default: return nil
        }
    }

    /// `Number(text)` for the shapes a data value takes: decimal, with exponent, hex.
    private static func javaScriptNumberParse(_ text: String) -> Double? {
        if text.hasPrefix("0x") || text.hasPrefix("0X") { return UInt64(text.dropFirst(2), radix: 16).map(Double.init) }
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || "+-.eE".contains($0)) }) else {
            return text == "Infinity" || text == "+Infinity" ? .infinity : text == "-Infinity" ? -.infinity : nil
        }
        return Double(text)
    }
}

/// The records a list from data draws (`Repeater.where`, `limit`; `x-listFilter`): each record
/// is judged in ITS scope — the record under its prefix over the outer scope; `limit` counts
/// the records that passed.
enum ListFilter {
    static func passedIndexes(records: [JSONValue], item: String, filter: JSONValue?, outer: DataScope, limit: Int? = nil) -> [Int] {
        var passed: [Int] = []
        for (index, record) in records.enumerated() {
            if let limit, passed.count >= limit { break }
            guard let filter, filter.objectValue != nil else {
                passed.append(index)
                continue
            }
            let scope = RecordScope.overlay(outer, RecordScope.instanceRecord(item: item, fields: record.objectValue ?? JSONObject())) ?? outer
            if Conditions.wherePasses(filter, scope: scope) { passed.append(index) }
        }
        return passed
    }
}
