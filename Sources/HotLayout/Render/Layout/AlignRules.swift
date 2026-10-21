import Foundation

/// The main axis of a host of alignment: `block` runs top to bottom, `inline` along the line of
/// the script.
enum MainAxis: Equatable {
    case block
    case inline
}

/// The words of the cross axis (`align`).
enum AlignWord: String, CaseIterable {
    case start, center, end
}

/// The words of the main axis (`justify`), the words of a row.
enum JustifyWord: String, CaseIterable {
    case start, center, end, between
}

/// What gives a column a height larger than its content (`x-style.layout.alignment.main.column`).
enum HeightSource: String {
    case height = "style.height"
    case minHeight = "style.minHeight"
    case fill
}

/// The two words that act on a host and the main axis they belong to.
struct AlignmentRead: Equatable {
    var mainAxis: MainAxis
    var align: AlignWord
    var justify: JustifyWord
}

/// The alignment rules of `x-style.layout.alignment` as pure functions: which node is a host,
/// which words act, how far a child moves along the main axis, where a child stands on the
/// cross axis. Placement code reads these and nothing else.
enum AlignRules {
    /// The host of a node (`Screen`, `Column`, a `Container` with a direction); `nil` for a node
    /// that has no fields of 9.15.0. A `Row` is not a host: its fields are older and have schema
    /// defaults. A container without `direction` is a column.
    static func read(type: String, props: JSONObject) -> AlignmentRead? {
        let axis: MainAxis
        switch WidgetType(type) {
        case .screen, .column: axis = .block
        case .container: axis = props["direction"]?.stringValue == "row" ? .inline : .block
        default: return nil
        }
        // No field or an unknown word acts as without the field: `start` on the main axis, and
        // `start` (column) or `center` (row) on the cross axis.
        let align = props["align"]?.stringValue.flatMap(AlignWord.init(rawValue:)) ?? (axis == .block ? .start : .center)
        let justify = props["justify"]?.stringValue.flatMap(JustifyWord.init(rawValue:)) ?? .start
        return AlignmentRead(mainAxis: axis, align: align, justify: justify)
    }

    /// Whether a layer fills the stack it stands in: `fill` is read only as `true` on a direct
    /// child of a `Stack`.
    static func fills(fields: JSONObject, parent: String?) -> Bool {
        WidgetType(parent) == .stack && fields["fill"]?.boolValue == true
    }

    /// What gives a column host a height larger than its content; `nil` — it is as tall as its
    /// content and has no free space. `ownHeight` / `ownMinHeight` are the effective values after
    /// states.
    static func heightSource(fields: JSONObject, parent: String?, ownHeight: Bool, ownMinHeight: Bool) -> HeightSource? {
        if fills(fields: fields, parent: parent) { return .fill }
        if ownHeight { return .height }
        if ownMinHeight { return .minHeight }
        return nil
    }

    /// How far each of `count` children moves along the main axis from the place it has with
    /// `start`. `free` ≤ 0 is no free space; the gap is not part of it and is not touched; the
    /// numbers are not rounded; `between` with one child is `start`.
    static func shifts(free: Double, count: Int, justify: JustifyWord) -> [Double] {
        let space = free.isFinite ? max(0, free) : 0
        return (0..<max(0, count)).map { index in
            switch justify {
            case .center: return space / 2
            case .end: return space
            case .between: return count > 1 ? space * Double(index) / Double(count - 1) : 0
            case .start: return 0
            }
        }
    }

    /// The offset of a child of `size` from the START of a cross axis of `available`.
    static func crossOffset(available: Double, size: Double, align: AlignWord) -> Double {
        let space = max(0, available - size)
        switch align {
        case .center: return space / 2
        case .end: return space
        case .start: return 0
        }
    }
}
