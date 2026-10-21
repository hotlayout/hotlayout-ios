import Foundation

/// The list budget of one screen (`x-listBudget`).
///
/// The bound of one list (50 records) multiplies with nesting, and a document the builder did not
/// make may nest deeper. A screen draws at most `perScreen` instances of list templates, nested
/// ones included, counted in document order depth first: an instance counts before the lists
/// inside it, then the next instance of the same list, then the next list. The instance that would
/// exceed the budget is not drawn, nor anything inside it, nor any instance after it on the screen.
///
/// The count follows the TREE of the screen for its width class, not what is shown now: a list
/// hidden by `visibleIf` or `showOn`, in an inactive tab or a folded accordion costs the same, so
/// switching a tab never moves the cut of another list. The records are those a list draws (after
/// `where` and `limit`). A group header is not an instance; the lists inside it count.
enum ListBudget {
    /// `x-listBudget.perScreen`: 50 × (1 + 50).
    static let perScreen = 2550
    /// Counting what was not drawn stops here: the report then says «at least».
    static let countCeiling = 1_000_000

    /// How many instances each list of a screen may draw, worked out before anything is drawn.
    struct Plan {
        fileprivate struct Key: Hashable {
            let node: String
            let path: [Int]
        }

        fileprivate var allowedCounts: [Key: Int] = [:]
        /// Instances drawn per list node, summed over the instances of the lists around it.
        fileprivate(set) var drawnByList: [String: Int] = [:]
        fileprivate(set) var total = 0
        /// Instances the lists would draw without the budget and do not draw (at most the counting ceiling).
        fileprivate(set) var notDrawn = 0

        /// How many of its records the list `node` at the instance path `path` may draw; a list the
        /// walk never reached stands in an instance that is not drawn.
        func allowed(node: String, path: [Int]) -> Int { allowedCounts[Key(node: node, path: path)] ?? 0 }

        /// The sentence of the report of the screen, or `nil` when the budget was not reached.
        func report(screenId: String) -> (location: String, reason: String)? {
            guard notDrawn > 0 else { return nil }
            let count = notDrawn >= ListBudget.countCeiling ? "at least \(notDrawn)" : "\(notDrawn)"
            return (
                "screen “\(screenId)”",
                "the list budget of \(ListBudget.perScreen) instances per screen was reached: \(count) instances of list templates were not drawn"
            )
        }
    }

    /// The parts of one instance: the header of a group when it stands above, then the template.
    private struct Instance {
        let scope: DataScope
        let parts: [DocumentNode]
    }

    private static func instances(of node: DocumentNode, outer: DataScope) -> [Instance] {
        let plan = RepeaterPlan(node: node, scope: outer)
        let template = node.children.first
        let isRow = node.props["direction"]?.stringValue == "row" || node.props["carousel"] != nil
        let columns = RepeaterPlan.columns(node.props, overridden: node.columnsFromOverride)
        let header =
            node.children.count > RecordGroups.headerChild && RepeaterPlan.groupBy(node.props) != nil && columns == nil && !isRow
            ? node.children[RecordGroups.headerChild] : nil
        return plan.instances.map { instance in
            Instance(scope: instance.scope, parts: [instance.headerBefore ? header : nil, template].compactMap { $0 })
        }
    }

    /// The plan of one screen: who draws how many, in document order depth first.
    static func plan(root: DocumentNode, scope: DataScope, budget: Int = perScreen) -> Plan {
        var plan = Plan()
        var used = 0

        func countAll(_ node: DocumentNode, _ outer: DataScope) {
            if plan.notDrawn >= countCeiling { return }
            guard node.widget == .repeater else {
                for child in node.children { countAll(child, outer) }
                return
            }
            for instance in instances(of: node, outer: outer) {
                plan.notDrawn += 1
                for part in instance.parts { countAll(part, instance.scope) }
            }
        }

        func walk(_ node: DocumentNode, _ outer: DataScope, _ path: [Int]) {
            guard node.widget == .repeater else {
                for child in node.children { walk(child, outer, path) }
                return
            }
            if plan.drawnByList[node.id] == nil { plan.drawnByList[node.id] = 0 }
            let all = instances(of: node, outer: outer)
            var index = 0
            while index < all.count, used < budget {
                used += 1
                plan.drawnByList[node.id, default: 0] += 1
                for part in all[index].parts { walk(part, all[index].scope, path + [index]) }
                index += 1
            }
            plan.allowedCounts[Plan.Key(node: node.id, path: path)] = index
            // What did not fit: these instances and everything inside them.
            for instance in all.dropFirst(index) {
                if plan.notDrawn >= countCeiling { break }
                plan.notDrawn += 1
                for part in instance.parts { countAll(part, instance.scope) }
            }
        }

        walk(root, scope, [])
        plan.total = used
        return plan
    }
}
