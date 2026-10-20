import SwiftUI

/// Which part of the app bar a child of `AppBarRowLayout` is.
enum AppBarPart: Hashable {
    case back, leadingNode, title, action, navItem
}

struct AppBarPartKey: LayoutValueKey {
    static let defaultValue = AppBarPart.title
}

/// The row of the app bar: the leading zone, the title block, the actions (`x-style.layout.appBar`).
/// The children say which part they are (`AppBarPartKey`). The formula is `AppBarRules.zones`;
/// this type measures the children and puts them. Coordinates are logical: SwiftUI mirrors the
/// placement in right-to-left text.
struct AppBarRowLayout: Layout {
    var backSide: CGFloat
    var gap: CGFloat
    var actionGap: CGFloat
    var titleAlign: JSONValue?
    /// The numbers of the navigation items that stand in this bar (`wideNav.inAppBar`); `nil`: none.
    var nav: WideChrome.NavMetrics?

    private struct Measured {
        var leading: LayoutSubview?
        var leadingNatural: CGSize
        var isNode: Bool
        var title: LayoutSubview?
        var titleNatural: CGSize
        var actions: [LayoutSubview]
        var actionSizes: [CGSize]
        var navItems: [LayoutSubview] = []
        var navSizes: [CGSize] = []
    }

    private func measure(_ subviews: Subviews) -> Measured {
        let leading = subviews.first { $0[AppBarPartKey.self] == .back || $0[AppBarPartKey.self] == .leadingNode }
        let title = subviews.first { $0[AppBarPartKey.self] == .title }
        let actions = subviews.filter { $0[AppBarPartKey.self] == .action }
        let navItems = subviews.filter { $0[AppBarPartKey.self] == .navItem }
        let natural = ProposedViewSize.unspecified
        return Measured(
            leading: leading, leadingNatural: leading?.sizeThatFits(natural) ?? .zero, isNode: leading?[AppBarPartKey.self] == .leadingNode,
            title: title, titleNatural: title?.sizeThatFits(natural) ?? .zero, actions: Array(actions), actionSizes: actions.map { $0.sizeThatFits(natural) },
            navItems: Array(navItems), navSizes: navItems.map { $0.sizeThatFits(natural) }
        )
    }

    private func zonesInput(_ measured: Measured, width: Double) -> AppBarRules.ZonesInput {
        AppBarRules.ZonesInput(
            width: width, showBack: measured.leading != nil && !measured.isNode, backSide: Double(backSide),
            actionSides: measured.actionSizes.map { Double($0.width) }, gap: Double(gap), actionGap: Double(actionGap),
            titleNatural: Double(measured.titleNatural.width), leadingNatural: measured.isNode ? Double(measured.leadingNatural.width) : nil,
            titleAlign: titleAlign
        )
    }

    /// The bar with the navigation items in it, when it has any.
    private func wide(_ measured: Measured, width: Double) -> WideChrome.WideAppBarZones? {
        guard let nav, !measured.navItems.isEmpty else { return nil }
        let fixed = 2 * nav.paddingInline + nav.iconWidth + nav.gap
        let labels = measured.navSizes.map { max(0, Double($0.width) - fixed) }
        return WideChrome.appBarZones(WideChrome.WideAppBarInput(bar: zonesInput(measured, width: width), navLabels: labels, nav: nav))
    }

    private func zones(_ measured: Measured, width: Double) -> AppBarRules.Zones {
        wide(measured, width: width)?.zones ?? AppBarRules.zones(zonesInput(measured, width: width))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = measure(subviews)
        var width = proposal.width.flatMap { $0.isFinite ? Double($0) : nil }
        if width == nil {
            let natural = zones(measured, width: .infinity)
            width = natural.leading + Double(measured.titleNatural.width) + natural.trailing
        }
        let layout = zones(measured, width: width ?? 0)
        var height = 0.0
        if let leading = measured.leading {
            height =
                measured.isNode ? Double(leading.sizeThatFits(ProposedViewSize(width: CGFloat(layout.leadingWidth), height: nil)).height) : Double(backSide)
        }
        height = max(height, Double(measured.title?.sizeThatFits(ProposedViewSize(width: CGFloat(layout.titleWidth), height: nil)).height ?? 0))
        for size in measured.actionSizes { height = max(height, Double(size.height)) }
        for size in measured.navSizes { height = max(height, Double(size.height)) }
        return CGSize(width: width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = measure(subviews)
        let layout = zones(measured, width: Double(bounds.width))
        func put(_ view: LayoutSubview, start: Double, size: CGSize) {
            let y = bounds.minY + (bounds.height - size.height) / 2
            view.place(at: CGPoint(x: bounds.minX + CGFloat(start), y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
        if let leading = measured.leading {
            // A node wider than half the bar gets exactly half and lays its content out inside it;
            // the arrow is a square of its own side.
            let width = measured.isNode ? layout.leadingWidth : Double(backSide)
            let size = leading.sizeThatFits(ProposedViewSize(width: CGFloat(width), height: nil))
            put(leading, start: 0, size: CGSize(width: CGFloat(width), height: size.height))
        }
        if let title = measured.title {
            let size = title.sizeThatFits(ProposedViewSize(width: CGFloat(layout.titleWidth), height: nil))
            put(title, start: layout.titleStart, size: CGSize(width: CGFloat(layout.titleWidth), height: size.height))
        }
        for (index, action) in measured.actions.enumerated() where index < layout.actionStarts.count {
            put(action, start: layout.actionStarts[index], size: measured.actionSizes[index])
        }
        if let wide = wide(measured, width: Double(bounds.width)) {
            // An item stands at its natural width; its box may be narrower than its content (icons
            // only): the label is then outside the box and clipped away by the item.
            for (index, item) in measured.navItems.enumerated() where index < wide.navItemStarts.count {
                put(item, start: wide.navItemStarts[index], size: CGSize(width: CGFloat(wide.navItemWidths[index]), height: measured.navSizes[index].height))
            }
        }
    }
}
