import SwiftUI

/// A named width (`style.width`). In a column it is not wider than the column
/// (`column.childWidth`: a named width stands at the width of its parent at most), which a
/// plain fixed frame cannot do; elsewhere it is exactly the named width.
struct NamedWidth: ViewModifier {
    var width: CGFloat?
    var height: CGFloat?
    var alignment: Alignment
    var clampsToParent: Bool

    func body(content: Content) -> some View {
        if let width, clampsToParent {
            ClampedWidthLayout(width: width, alignment: alignment) { content }
                .frame(height: height, alignment: alignment)
        } else {
            content.frame(width: width, height: height, alignment: alignment)
        }
    }
}

/// One child at `width`, or at the width it is offered when that is smaller.
struct ClampedWidthLayout: Layout {
    var width: CGFloat
    var alignment: Alignment

    private func used(_ proposal: ProposedViewSize) -> CGFloat {
        guard let offered = proposal.width, offered.isFinite else { return width }
        return max(0, min(width, offered))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let inline = used(proposal)
        let height = subviews.first?.sizeThatFits(ProposedViewSize(width: inline, height: proposal.height)).height ?? 0
        return CGSize(width: inline, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        // The content may be narrower than the box (a ring of its own diameter): it stands by
        // the box's alignment, as it does under a plain fixed frame.
        let proposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        let size = child.sizeThatFits(proposal)
        let free = max(0, bounds.width - min(size.width, bounds.width))
        let shift: CGFloat
        switch alignment.horizontal {
        case .center: shift = free / 2
        case .trailing: shift = free
        default: shift = 0
        }
        child.place(at: CGPoint(x: bounds.minX + shift, y: bounds.minY), anchor: .topLeading, proposal: proposal)
    }
}
