import SwiftUI

/// Equal columns with the number of columns named by the document, cells at the top
/// (`x-style.layout`, grid): a cell is `(width − gaps) ÷ columns` wide, so the cells missing
/// from the last row keep the width of the others, and the row's height is the tallest cell.
struct GridCellsLayout: Layout {
    var columns: Int
    var gap: CGFloat

    private func cellWidth(_ width: CGFloat) -> CGFloat {
        CGFloat(GridGeometry.cellWidth(total: Double(width), columns: columns, gap: Double(gap)))
    }

    /// The cells that take a place: a cell that may be absent (a fading node out of the layout)
    /// and has no size is left out, so the others close up without a hole.
    private func present(_ subviews: Subviews) -> [LayoutSubview] {
        subviews.filter { !$0[CellMayBeAbsent.self] || $0.sizeThatFits(.unspecified) != .zero }
    }

    private func rowHeights(_ cells: [LayoutSubview], cell: CGFloat) -> [CGFloat] {
        stride(from: 0, to: cells.count, by: columns).map { start in
            cells[start..<min(start + columns, cells.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cells = present(subviews)
        guard !cells.isEmpty else { return .zero }
        let width: CGFloat
        if let proposed = proposal.width {
            width = proposed
        } else {
            let widest = cells.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            width = widest * CGFloat(columns) + gap * CGFloat(columns - 1)
        }
        let heights = rowHeights(cells, cell: cellWidth(width))
        return CGSize(width: width, height: heights.reduce(0, +) + gap * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cells = present(subviews)
        guard !cells.isEmpty else { return }
        let cell = cellWidth(bounds.width)
        let heights = rowHeights(cells, cell: cell)
        for (index, subview) in cells.enumerated() {
            let row = index / columns
            let column = index % columns
            let top = heights[..<row].reduce(0, +) + gap * CGFloat(row)
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(column) * (cell + gap), y: bounds.minY + top),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cell, height: heights[row])
            )
        }
    }
}

/// A child in a slot that sets its size itself (a `Grid` cell, an instance of a `Repeater` with
/// `columns`): a node of natural width, or with an own width, takes its natural width and stands
/// at the logical start, at the top; every other node takes the width of the cell.
struct TightSlot: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int

    var body: some View {
        if VisibilityFade.reads(node) {
            // The node fades in a cell of its own: while it is out of the layout the cell has no size.
            FadingNode(shown: context.isShown(node), context: context.fadeContext) { cell(fadeOutside: true) }
                .layoutValue(key: CellMayBeAbsent.self, value: true)
        } else {
            cell(fadeOutside: false)
        }
    }

    @ViewBuilder
    private func cell(fadeOutside: Bool) -> some View {
        if takesNaturalWidth(node) {
            NodeView(node: node, context: context, placement: .natural, depth: depth, fadeOutside: fadeOutside)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            NodeView(node: node, context: context, placement: .stretched, depth: depth, fadeOutside: fadeOutside)
        }
    }
}

/// `Grid`: the visible children in rows of `columns` cells.
struct GridWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int

    var body: some View {
        let columns = gridColumns(node.props["columns"], overridden: node.columnsFromOverride) ?? 2
        let gap = context.resolver.spacing(node.props["gap"] ?? "sm") ?? 0
        // A node that fades stays among the cells: it decides by itself when it leaves the layout.
        let cells = node.children.filter { context.isShown($0) || VisibilityFade.reads($0) }
        GridCellsLayout(columns: columns, gap: gap) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, child in
                TightSlot(node: child, context: context, depth: depth + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
