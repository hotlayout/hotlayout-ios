import SwiftUI

/// The place an overlay stands in, resolved against the theme.
struct OverlayPlace: Equatable {
    var alignHorizontal: AlignWord
    var alignVertical: AlignWord
    var offsetX: (toward: String, by: Double)?
    var offsetY: (toward: String, by: Double)?
    var rotate: Int

    static func == (lhs: OverlayPlace, rhs: OverlayPlace) -> Bool {
        lhs.alignHorizontal == rhs.alignHorizontal && lhs.alignVertical == rhs.alignVertical && lhs.rotate == rhs.rotate
            && lhs.offsetX?.toward == rhs.offsetX?.toward && lhs.offsetX?.by == rhs.offsetX?.by
            && lhs.offsetY?.toward == rhs.offsetY?.toward && lhs.offsetY?.by == rhs.offsetY?.by
    }
}

/// What a layer of a stack is, as the layout needs it.
enum LayerRole: Equatable {
    case sizing
    case fill
    case overlay(OverlayPlace)
}

/// A layer with no width of its own, which takes the whole width it is offered (a picture).
struct WidthHungryKey: LayoutValueKey {
    static let defaultValue = false
}

struct LayerRoleKey: LayoutValueKey {
    static let defaultValue: LayerRole = .sizing
}

/// A stack of layers in one point; the first is the lowest.
///
///  - layers that size the stack take their own size, and the stack is the largest of them
///    (zero when none is drawn); each stands by the alignment words of the stack;
///  - a layer on the whole stack takes the size of the stack;
///  - an overlay stands against the box of the stack by `LayerGeometry` and never changes it.
///    Its place is a PLACEMENT of this layout, not an offset of the view, so a touch is caught
///    where the layer is drawn. The turn is the one thing the view does itself.
///
/// SwiftUI mirrors the placement of a layout in right-to-left text by itself, so everything
/// here is in logical coordinates (from the start of the line).
struct LayerStackLayout: Layout {
    var alignHorizontal: AlignWord
    var alignVertical: AlignWord
    /// A stack inside a stretching parent takes the proposed width.
    var stretch: Bool

    private func finite(_ value: CGFloat?) -> CGFloat? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// A layer takes its OWN size (`x-style.layout`: only `fill` stretches a layer): its ideal size,
    /// narrowed to the width offered when it does not fit; a layer with no width of its own (a picture)
    /// takes the width offered. A column proposed a width would take all
    /// of it, so the ideal is asked first and the offer is made only when the layer is wider.
    private func ownSize(_ subview: LayoutSubview, offered: CGFloat?) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        // A picture has no width of its own: it fills the place it is offered.
        if let offered, offered > 0, subview[WidthHungryKey.self] {
            return subview.sizeThatFits(ProposedViewSize(width: offered, height: nil))
        }
        guard let offered, ideal.width > offered else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: offered, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizers = subviews.filter { $0[LayerRoleKey.self] == .sizing }
        guard !sizers.isEmpty else { return .zero }
        let sizes = sizers.map { ownSize($0, offered: finite(proposal.width)) }
        let natural = sizes.map(\.width).max() ?? 0
        let width = stretch ? (finite(proposal.width) ?? natural) : natural
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let stack = bounds.size
        for subview in subviews {
            switch subview[LayerRoleKey.self] {
            case .fill:
                subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(stack))
            case .sizing:
                let size = ownSize(subview, offered: stack.width)
                let x = LayerGeometry.along(stack.width, size.width, alignHorizontal)
                let y = LayerGeometry.along(stack.height, size.height, alignVertical)
                subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
            case .overlay(let place):
                let size = ownSize(subview, offered: stack.width)
                let geometry = LayerGeometry.place(
                    .init(
                        stack: stack, layer: size, alignHorizontal: place.alignHorizontal, alignVertical: place.alignVertical,
                        offsetX: place.offsetX, offsetY: place.offsetY, rotate: place.rotate, rightToLeft: false
                    ))
                subview.place(
                    at: CGPoint(x: bounds.minX + geometry.rect.minX, y: bounds.minY + geometry.rect.minY), anchor: .topLeading, proposal: ProposedViewSize(size)
                )
            }
        }
    }
}
