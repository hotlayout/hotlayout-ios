import SwiftUI

/// `node.pull`: a child of a flow is drawn earlier by this much along the main axis of its
/// parent, and everything after it follows (`x-style.layout.pull`).
enum FlowPull {
    enum Axis: Equatable { case column, row }

    struct Child {
        /// The size along the main axis, with the margins.
        var size: CGFloat
        var pull: CGFloat = 0
    }

    /// Where the children start, measured from the START of the content of the parent along its
    /// main axis, and how long the content is. One arithmetic, no exceptions: a child begins
    /// where the previous one ended, plus the gap, minus its own pull (the first one — from
    /// zero minus its pull); the content is never shorter than nothing.
    static func flow(_ children: [Child], gap: CGFloat) -> (starts: [CGFloat], size: CGFloat) {
        var starts: [CGFloat] = []
        var cursor: CGFloat = 0
        for (index, child) in children.enumerated() {
            let start = cursor + (index == 0 ? 0 : gap) - child.pull
            starts.append(start)
            cursor = start + child.size
        }
        return (starts, max(0, cursor))
    }

    /// How a node is pulled in its parent: a reference to a spacing step and the axis.
    /// `nil` when the field is not read: outside a flow (a wrapping or scrolling row, a grid, a
    /// stack…), on a zone of the screen, beside a weight that acts, or unreadable.
    static func read(node: DocumentNode, parentType: String, parentProps: JSONObject) -> (by: SpacingReference, axis: Axis)? {
        guard let axis = axis(parentType: parentType, parentProps: parentProps) else { return nil }
        if node.type == "AppBar" || node.type == "NavBar" { return nil }
        // A node of the top zone is a node of the column of the screen: the first one pulls nothing (the
        // column of the zone ignores it), the others are pulled as in the body.
        if parentType == "Screen", let pin = node.fields["pin"], pin.stringValue != ScreenAnatomy.topPin { return nil }
        guard let by = SpacingReference(node.fields["pull"]) else { return nil }
        if axis == .row, let weight = node.fields["weight"]?.numberValue, weight >= 1, weight == weight.rounded() { return nil }
        return (by, axis)
    }

    static func axis(parentType: String, parentProps: JSONObject) -> Axis? {
        switch parentType {
        case "Screen", "Column": return .column
        case "Container": return parentProps["direction"]?.stringValue == "row" ? .row : .column
        case "Row": return parentProps["wrap"]?.boolValue != true && parentProps["scrollable"]?.boolValue != true ? .row : nil
        default: return nil
        }
    }
}

/// The pull of a child of a flow in logical pixels.
struct FlowPullAmount: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}
