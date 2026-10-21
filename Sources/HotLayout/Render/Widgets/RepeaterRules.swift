import Foundation

/// The number of a node in a numbered list from data and the size of the group.
struct ListNumber: Equatable {
    var number: Int
    var groupSize: Int
}

/// Grouping of a list from data (`Repeater.groupBy`; `x-repeaterGroup`): records that follow
/// one another with the same value under the path form a group, and the second child of the
/// list (the header) is drawn before each group.
enum RecordGroups {
    /// The header is the second child of the list.
    static let headerChild = 1

    /// "Absent" — missing, `null` or the empty string — is one value; otherwise the same JSON
    /// type and equal, without conversion (`1` and `"1"` are two groups). An object or a list
    /// is a group of its own.
    static func isSame(_ left: JSONValue?, _ right: JSONValue?) -> Bool {
        func missing(_ value: JSONValue?) -> Bool { ContractShapes.isAbsent(value) }
        if missing(left) || missing(right) { return missing(left) && missing(right) }
        switch (left!, right!) {
        case (.string(let a), .string(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        default: return false
        }
    }

    /// The groups of the drawn records as the index of the first record and the size.
    static func groups(of values: [JSONValue?]) -> [(start: Int, size: Int)] {
        var groups: [(start: Int, size: Int)] = []
        for index in values.indices {
            if let last = groups.last, isSame(values[last.start], values[index]) {
                groups[groups.count - 1].size += 1
            } else {
                groups.append((index, 1))
            }
        }
        return groups
    }

    static func starts(of values: [JSONValue?]) -> Set<Int> {
        Set(groups(of: values).map(\.start))
    }
}

/// What a `Repeater` draws, worked out from its props and the scope it stands in.
struct RepeaterPlan {
    /// The most records a list draws, whatever the document asks (`maxCollectionItems`).
    static let maxItems = 50

    struct Instance {
        /// The raw record as the host gave it (an object; anything else is a record without fields).
        let fields: JSONObject
        /// The scope of the record: its fields under the prefix over the outer scope.
        let scope: DataScope
        /// Whether the template is shown for this record (`visibleIf` on the template).
        let shown: Bool
        /// The number among the shown instances, from 1 (`nil` when hidden).
        let number: Int?
        /// A group header goes before this record.
        let headerBefore: Bool
    }

    let instances: [Instance]

    static func limit(_ props: JSONObject) -> Int? {
        guard let raw = props["limit"], !raw.isNull else { return nil }
        // A number outside its bounds, or not a number, is the lower bound (`nonNumericLiteral`).
        guard let number = raw.numberValue else { return 1 }
        return SafeInt.clamped(min(Double(maxItems), max(1, number.rounded(.down))))
    }

    /// `columns` of a list: a whole number of cells in a row; a value that is not a number is 2.
    static func columns(_ props: JSONObject, overridden: Bool = true) -> Int? {
        gridColumns(props["columns"], overridden: overridden)
    }

    /// The path of `groupBy`; a value that is not a non-empty string is no field.
    static func groupBy(_ props: JSONObject) -> String? {
        guard let path = props["groupBy"]?.stringValue, !path.isEmpty else { return nil }
        return path
    }

    /// The records a list draws: the filter first, then the limit, then the ceiling of 50 — a
    /// record that did not pass does not exist for the layout.
    static func drawnIndexes(records: [JSONValue], item: String, filter: JSONValue?, outer: DataScope, limit: Int?) -> [Int] {
        Array(ListFilter.passedIndexes(records: records, item: item, filter: filter, outer: outer, limit: limit).prefix(maxItems))
    }

    /// Numbers of the instances of an item template: an instance whose template is shown gets
    /// how many shown ones are drawn up to and including it; a hidden one gets `nil`.
    static func numbers(shown: [Bool]) -> [Int?] {
        var drawn = 0
        return shown.map { flag in
            guard flag else { return nil }
            drawn += 1
            return drawn
        }
    }

    /// `allowed` is how many of the records the screen's list budget leaves this list (`ListBudget`);
    /// every record when no screen asks.
    init(node: DocumentNode, scope: DataScope, widthClass: WidthClass = .compact, allowed: Int = .max) {
        let item = node.props["item"]?.stringValue ?? ""
        let records = scope[node.props["source"]?.stringValue ?? ""]?.arrayValue ?? []
        let drawn = Array(
            Self.drawnIndexes(records: records, item: item, filter: node.props["where"], outer: scope, limit: Self.limit(node.props)).prefix(allowed))
        let template = node.children.first
        let fieldsOf = drawn.map { records[$0].objectValue ?? JSONObject() }
        let scopes = fieldsOf.map { RecordScope.overlay(scope, RecordScope.instanceRecord(item: item, fields: $0)) ?? scope }
        let shown = scopes.map { scope in template.map { WidthRules.isShown($0, widthClass, scope: scope) } ?? false }
        let numbers = Self.numbers(shown: shown)
        var starts: Set<Int> = []
        if node.children.count > RecordGroups.headerChild, let path = Self.groupBy(node.props) {
            starts = RecordGroups.starts(of: fieldsOf.map { RecordScope.instanceRecord(item: item, fields: $0)[path] })
        }
        instances = fieldsOf.indices.map {
            Instance(fields: fieldsOf[$0], scope: scopes[$0], shown: shown[$0], number: numbers[$0], headerBefore: starts.contains($0))
        }
    }
}

/// The number of cells in a row of a grid. A number is a whole count from 1 to 6 (the schema
/// allows 2…4 in the document and 1…6 as a per-width override); a value that is not a number
/// is 2 (`nonNumericLiteral`, the lower bound of the field).
func gridColumns(_ raw: JSONValue?, overridden: Bool = true) -> Int? {
    guard let raw, !raw.isNull else { return nil }
    guard let number = raw.numberValue else { return 2 }
    // The document's own number keeps the bounds of the schema, 2…4; a number from a width layer is 1…6.
    return SafeInt.clamped(min(overridden ? 6 : 4, max(overridden ? 1 : 2, number.rounded(.down))))
}

/// The grid arithmetic shared by `Grid` and a `Repeater` with `columns`: the width of a cell
/// is `(width − gaps) ÷ columns`, so the last row's missing cells keep the others' width.
enum GridGeometry {
    static func cellWidth(total: Double, columns: Int, gap: Double) -> Double {
        (total - gap * Double(columns - 1)) / Double(columns)
    }

    /// (row, column) of each of `count` cells, left to right, top to bottom, no holes.
    static func cells(count: Int, columns: Int) -> [[Int]] {
        (0..<count).map { [$0 / columns, $0 % columns] }
    }
}
