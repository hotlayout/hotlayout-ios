import SwiftUI

/// `Repeater`: one template drawn once per record of a collection. An empty list is an empty
/// space — what to show instead is the document's business (a neighbour with `isEmpty`).
struct RepeaterWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int
    /// The padding of the node when it is a carousel (drawn inside the scroll).
    var carouselPadding: Sides?

    private enum Entry: Hashable {
        case header(Int)
        case record(Int)
    }

    var body: some View {
        // The screen's budget says how many of the records this list may draw (all of them when no screen asks).
        let allowed = context.listBudget?.allowed(node: node.id, path: context.instancePath) ?? .max
        let plan = RepeaterPlan(node: node, scope: context.scope, widthClass: context.widthClass, allowed: allowed)
        if plan.instances.isEmpty || node.children.isEmpty {
            EmptyView()
        } else {
            list(plan)
        }
    }

    private func list(_ plan: RepeaterPlan) -> some View {
        let template = node.children[0]
        let header = node.children.count > RecordGroups.headerChild && RepeaterPlan.groupBy(node.props) != nil ? node.children[RecordGroups.headerChild] : nil
        let columns = RepeaterPlan.columns(node.props, overridden: node.columnsFromOverride)
        let gap = context.resolver.spacing(node.props["gap"] ?? "sm") ?? 0
        let numbered = template.widget == .text && template.props["marker"]?.stringValue == "number"
        let item = node.props["item"]?.stringValue ?? ""
        let source = node.props["source"]?.stringValue ?? ""

        func itemContext(_ index: Int) -> RenderContext {
            let instance = plan.instances[index]
            let number = numbered ? instance.number.map { ListNumber(number: $0, groupSize: plan.instances.count) } : nil
            return context.inListInstance(
                scope: instance.scope, instance: ListInstance(item: item, fields: instance.fields, source: source), number: number, index: index)
        }

        // A header goes before the first record of each group, in the scope of that record; one
        // hidden by its own condition takes no place and no gap. Groups exist in a column only.
        let grouped = columns == nil && node.props["direction"]?.stringValue != "row" && node.props["carousel"] == nil
        let keeps = Set(plan.drawn(templateFades: VisibilityFade.reads(template)))
        var entries: [Entry] = []
        for (index, instance) in plan.instances.enumerated() {
            if grouped, instance.headerBefore, let header, context.isShown(header, scope: instance.scope) {
                entries.append(.header(index))
            }
            if keeps.contains(index) { entries.append(.record(index)) }
        }

        return Group {
            if let columns {
                GridCellsLayout(columns: columns, gap: gap) {
                    ForEach(entries, id: \.self) { entry in
                        if case .record(let index) = entry {
                            TightSlot(node: template, context: itemContext(index), depth: depth + 1)
                        }
                    }
                }
            } else if let spec = CarouselRules.of(node) {
                // A carousel: the instances are its cards.
                let records = entries.compactMap { entry -> Int? in
                    if case .record(let index) = entry { return index }
                    return nil
                }
                let gapPoints = gap
                CarouselView(
                    setup: CarouselSetup.make(spec: spec, node: node, gap: gapPoints, padding: carouselPadding ?? .zero, vertical: .center, context: context),
                    count: records.count
                ) { position, width in
                    NodeView(node: template, context: itemContext(records[position]), placement: RowView.cardPlacement(width: width), depth: depth + 1)
                }
            } else if node.props["direction"]?.stringValue == "row" || node.props["carousel"] != nil {
                // A row of natural-width instances. A `carousel` the reader cannot read is a plain scroll.
                let row = RowLayout(gap: gap, justify: .start, align: .center) {
                    ForEach(entries, id: \.self) { entry in
                        if case .record(let index) = entry {
                            NodeView(node: template, context: itemContext(index), placement: .natural, depth: depth + 1)
                        }
                    }
                }
                if node.props["carousel"] != nil {
                    ScrollView(.horizontal, showsIndicators: false) { row.fixedSize(horizontal: true, vertical: false) }
                } else {
                    row
                }
            } else {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(entries, id: \.self) { entry in
                        switch entry {
                        case .header(let index):
                            if let header { NodeView(node: header, context: itemContext(index).with(numbered: nil), placement: .stretched, depth: depth + 1) }
                        case .record(let index):
                            instanceView(template, itemContext(index))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// An instance in a column is stretched to the column, except a node with its own width,
    /// which stands at the logical start (`sizedChildInTightSlot`, the column rule of a list).
    @ViewBuilder
    private func instanceView(_ template: DocumentNode, _ itemContext: RenderContext) -> some View {
        if template.style?["width"] != nil {
            NodeView(node: template, context: itemContext, placement: .natural, depth: depth + 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            NodeView(node: template, context: itemContext, placement: .stretched, depth: depth + 1)
        }
    }
}

extension RenderContext {
    /// The same context with the list number replaced (a group header is not a list item).
    func with(numbered number: ListNumber?) -> RenderContext {
        var copy = self
        copy.listNumber = number
        return copy
    }
}
