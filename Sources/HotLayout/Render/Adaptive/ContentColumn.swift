import SwiftUI

/// The column of the content of a screen (`Screen.contentMaxWidth`): no wider than the number and
/// centred in the width it is given. Half of the remainder stands on each side, not rounded, so the
/// column is in the same place in both writing directions. A box narrower than the number, and no
/// number, change nothing.
struct ContentColumnLayout: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        guard let width = proposal.width, width.isFinite else { return child.sizeThatFits(proposal) }
        let inner = min(width, maxWidth)
        let size = child.sizeThatFits(ProposedViewSize(width: inner, height: proposal.height))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let inner = min(bounds.width, maxWidth)
        let box = WidthRules.contentBox(available: Double(bounds.width), maxWidth: Double(maxWidth))
        child.place(
            at: CGPoint(x: bounds.minX + CGFloat(box.start), y: bounds.minY), anchor: .topLeading,
            proposal: ProposedViewSize(width: inner, height: bounds.height)
        )
    }
}

extension View {
    /// The content of a zone in a column of at most `maxWidth` (`nil`: no column).
    @ViewBuilder
    func contentColumn(_ maxWidth: Double?) -> some View {
        if let maxWidth {
            ContentColumnLayout(maxWidth: CGFloat(maxWidth)) { self }
        } else {
            self
        }
    }
}
