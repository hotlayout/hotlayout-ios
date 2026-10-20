import SwiftUI

/// A column (a `Column`, a column `Container`, the body of a `Screen`) of a finite width
/// (`x-style.layout.column`, `x-style.layout.alignment`):
///  - a child that stretches takes the full width of the column; one that does not stands where
///    `align` puts it (`column.naturalWidthAlign`);
///  - `justify` distributes the free height along the main axis, and the free height exists
///    only when the column has a source of height: a named content height, a minimal one, or a
///    proposal it must fill (`columnHeightSourceOf`); the gap stays the smallest distance and
///    positions are not rounded;
///  - SwiftUI mirrors the placement of a layout in right-to-left text, so logical `start` and
///    `end` need nothing more.
struct ColumnLayout: Layout {
    var gap: CGFloat
    var align: AlignWord
    var justify: JustifyWord
    /// The named height of the content box (`style.height`).
    var block: CGFloat?
    /// The minimal height of the content box (`style.minHeight`, or the visible body of a screen).
    var minBlock: CGFloat?
    /// A layer that fills its stack takes the height it is proposed.
    var fillsProposal = false

    struct Cache {
        var ideal: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(ideal: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    private func sizes(inline: CGFloat, subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: inline, height: nil)) }
    }

    private func ownBlock(content: CGFloat, proposal: ProposedViewSize) -> CGFloat {
        if fillsProposal, let height = proposal.height, height.isFinite { return max(height, content) }
        if let block { return block }
        return max(minBlock ?? 0, content)
    }

    private func pullTotal(_ subviews: Subviews) -> CGFloat {
        subviews.reduce(0) { $0 + $1[FlowPullAmount.self] }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let inline = proposal.width ?? cache.ideal.reduce(0) { max($0, $1.width) }
        let heights = sizes(inline: inline, subviews: subviews).map(\.height)
        let content = max(0, heights.reduce(0, +) + gap * CGFloat(max(0, subviews.count - 1)) - pullTotal(subviews))
        return CGSize(width: inline, height: ownBlock(content: content, proposal: proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let measured = sizes(inline: bounds.width, subviews: subviews)
        // The free height is the column's OWN (a source of height), never whatever the parent
        // happens to give it: a column as tall as its content has none.
        let pulls = subviews.map { $0[FlowPullAmount.self] }
        let content = max(0, measured.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, measured.count - 1)) - pulls.reduce(0, +))
        let own = ownBlock(content: content, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        let box = AlignRules.alignedChildRects(
            AlignedBoxInput(
                axis: .block, inline: Double(bounds.width), block: Double(own), minBlock: nil,
                gap: Double(gap), align: align, justify: justify, rightToLeft: false,
                // `pull`: a child advances the flow by its height less its pull, and stands that much earlier.
                children: measured.enumerated().map { AlignedChild(width: Double($0.element.width), height: Double($0.element.height - pulls[$0.offset])) }
            ))
        for (index, subview) in subviews.enumerated() {
            let rect = box.rects[index]
            subview.place(
                at: CGPoint(x: bounds.minX + rect.x, y: bounds.minY + rect.y - pulls[index]), anchor: .topLeading,
                proposal: ProposedViewSize(width: rect.width, height: measured[index].height)
            )
        }
    }
}
