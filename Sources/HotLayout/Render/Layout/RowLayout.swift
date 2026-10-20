import SwiftUI

/// The share a child of a row takes (`node.weight`); `nil` keeps its natural width.
struct RowWeight: LayoutValueKey {
    static let defaultValue: Double? = nil
}

/// A row of a finite width (`x-style.layout.row`):
///  - children without a weight take their natural width and, when the row is too narrow,
///    shrink in proportion to it (`unweightedRowChild: 'natural-shrink-proportionally'`);
///  - children with a weight share what is left, in proportion to their weights; a weight
///    overrides the child's own width;
///  - with no weights, `justify` distributes the free space (`start`, `center`, `end`,
///    `between`); the gap stays the smallest distance;
///  - `align` places every child on the cross axis.
/// SwiftUI mirrors the placement of a layout in right-to-left text, so `start` and `end` are
/// logical without more. A child is placed at the width it really takes, so a child that cannot
/// shrink keeps its size and the row does not claim free space it does not have.
struct RowLayout: Layout {
    var gap: CGFloat
    var justify: JustifyWord
    var align: AlignWord
    /// The named height of the content box (`style.height`): the cross axis stands inside it.
    var block: CGFloat?
    /// A layer that fills its stack takes the height it is proposed.
    var fillsProposal = false

    struct Cache {
        var natural: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(natural: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    /// The widths of the children of a row of this size. `pull` of a child draws it earlier and
    /// everything after it follows, so the row has room for exactly that much more
    /// (`x-style.layout.pull`); a weight wins over a pull, so a weighted child never has one.
    static func widths(natural: [CGFloat], weights: [Double?], gap: CGFloat, pullTotal: CGFloat = 0, available: CGFloat?) -> [CGFloat] {
        let gaps = gap * CGFloat(max(0, natural.count - 1))
        var widths = natural.enumerated().map { index, width in weights[index] == nil ? width : 0 }
        guard let available else { return widths }
        let fixed = widths.reduce(0, +)
        let room = available - gaps + pullTotal
        let totalWeight = weights.compactMap { $0 }.reduce(0, +)
        if totalWeight > 0 {
            let remainder = max(0, room - fixed)
            if fixed > room, fixed > 0 {
                let ratio = max(0, room) / fixed
                widths = widths.map { $0 * ratio }
            }
            for (index, weight) in weights.enumerated() {
                if let weight { widths[index] = remainder * CGFloat(weight / totalWeight) }
            }
        } else if fixed > room, fixed > 0 {
            let ratio = max(0, room) / fixed
            widths = widths.map { $0 * ratio }
        }
        return widths
    }

    private func widths(for available: CGFloat?, subviews: Subviews, cache: Cache) -> [CGFloat] {
        Self.widths(
            natural: cache.natural.map(\.width), weights: subviews.map { $0[RowWeight.self] }, gap: gap, pullTotal: pullTotal(subviews), available: available)
    }

    private func pullTotal(_ subviews: Subviews) -> CGFloat {
        subviews.reduce(0) { $0 + $1[FlowPullAmount.self] }
    }

    private func ownBlock(tallest: CGFloat, proposal: ProposedViewSize) -> CGFloat {
        if fillsProposal, let height = proposal.height, height.isFinite { return max(height, tallest) }
        return block ?? tallest
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let widths = widths(for: proposal.width, subviews: subviews, cache: cache)
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            height = max(height, subview.sizeThatFits(ProposedViewSize(width: widths[index], height: nil)).height)
        }
        let gaps = gap * CGFloat(max(0, subviews.count - 1))
        let natural = max(0, widths.reduce(0, +) + gaps - pullTotal(subviews))
        return CGSize(width: proposal.width ?? natural, height: ownBlock(tallest: height, proposal: proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let weights = subviews.map { $0[RowWeight.self] }
        let proposed = widths(for: bounds.width, subviews: subviews, cache: cache)
        let sizes = subviews.enumerated().map { index, subview in
            subview.sizeThatFits(ProposedViewSize(width: proposed[index], height: nil))
        }
        // A weighted child takes its share; any other takes the width it really has.
        let widths = sizes.enumerated().map { index, size in weights[index] == nil ? size.width : proposed[index] }
        let hasWeights = weights.contains { $0 != nil }
        let pulls = subviews.map { $0[FlowPullAmount.self] }
        let block = ownBlock(tallest: sizes.reduce(0) { max($0, $1.height) }, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        // Positions come from the shared rules; a row with weights has no free space to distribute.
        let box = AlignRules.alignedChildRects(
            AlignedBoxInput(
                axis: .inline, inline: Double(bounds.width), block: Double(block), minBlock: nil,
                gap: Double(gap), align: align, justify: hasWeights ? .start : justify, rightToLeft: false,
                // `pull`: a child advances the flow by its width less its pull, and stands that much earlier.
                children: sizes.enumerated().map { AlignedChild(width: Double(widths[$0.offset] - pulls[$0.offset]), height: Double($0.element.height)) }
            ))
        for (index, subview) in subviews.enumerated() {
            let rect = box.rects[index]
            subview.place(
                at: CGPoint(x: bounds.minX + rect.x - pulls[index], y: bounds.minY + rect.y), anchor: .topLeading,
                proposal: ProposedViewSize(width: widths[index], height: sizes[index].height)
            )
        }
    }
}
