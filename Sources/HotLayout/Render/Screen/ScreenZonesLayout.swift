import SwiftUI

/// The zone of the screen a child of `ScreenZonesLayout` stands in.
enum ScreenZone: Hashable {
    case bar, top, body, pinned, nav
    /// The bar of navigation of its own at the top of the screen (`wideNav.ownBar`).
    case topNav
}

struct ScreenZoneKey: LayoutValueKey {
    static let defaultValue = ScreenZone.body
}

/// What the zones of one screen depend on, besides the sizes of the children.
struct ScreenZonesSettings: Equatable {
    /// A modal layer is as tall as its content, not taller than the area it is given.
    var shrink = false
    var paddingTop: Double = 0
    var paddingBottom: Double = 0
    var paddingStart: Double = 0
    var paddingEnd: Double = 0
    var gap: Double = 0
    /// The body has no visible child.
    var bodyEmpty = false
    var firstPull: Double = 0
    var bodyTop: JSONValue?
    var safeTop: Double = 0
    var safeBottom: Double = 0
    var keyboard: Double = 0
    var navFloat = false
}

/// Where the zones of a screen stand, measured: the heights come from the children, the
/// numbers from `ScreenAnatomy.zones`.
struct ScreenZonePlan {
    var zones: AnatomyZones
    var barTop: Double?
    var barHeight: Double
    var topZoneTop: Double?
    var topZoneHeight: Double
    var width: Double
    /// The height of the bar of navigation of its own; zero without one.
    var topNavHeight = 0.0
    /// The inset of the platform under the root of a sheet that has no bottom zone: room inside its box.
    var rootInset = 0.0
}

/// The layout of a screen: the app bar, the top zone, the body, the pinned block and the
/// navigation bar. Only the body scrolls; the other zones stand where the numbers put them
/// (`x-style.layout.screen`). Placement is logical: SwiftUI mirrors it for right-to-left text.
struct ScreenZonesLayout: Layout {
    var settings: ScreenZonesSettings

    private func child(_ subviews: Subviews, _ zone: ScreenZone) -> LayoutSubview? {
        subviews.first { $0[ScreenZoneKey.self] == zone }
    }

    func plan(width: Double, height: Double?, subviews: Subviews) -> ScreenZonePlan {
        let s = settings
        let inner = max(0, width - s.paddingStart - s.paddingEnd)
        let inside = ProposedViewSize(width: CGFloat(inner), height: nil)
        let hasBar = child(subviews, .bar) != nil
        let hasTop = child(subviews, .top) != nil
        let barHeight = Double(child(subviews, .bar)?.sizeThatFits(inside).height ?? 0)
        let topHeight = Double(child(subviews, .top)?.sizeThatFits(inside).height ?? 0)
        let pinnedHeight = child(subviews, .pinned).map { Double($0.sizeThatFits(inside).height) }
        let topNavHeight = child(subviews, .topNav).map { Double($0.sizeThatFits(ProposedViewSize(width: CGFloat(width), height: nil)).height) } ?? 0
        let navHeight = child(subviews, .nav).map { Double($0.sizeThatFits(ProposedViewSize(width: CGFloat(width), height: nil)).height) }
        let floats = s.navFloat && navHeight != nil
        // The bar holds the inset inside its box; a floating bar does not: the inset lies under it.
        let navContent = navHeight.map { floats ? $0 : max(0, $0 - s.safeBottom) }

        // A sheet without a bottom zone holds the inset under its content (`sheetSafeBottom`); with a zone it lies under the zone.
        let rootInset = s.shrink && pinnedHeight == nil && navContent == nil ? SheetSafeBottom.inset(s.safeBottom) : 0
        // The bar of its own takes the top of the screen; everything else is counted in what is left under it.
        var input = AnatomyInput(
            height: (height ?? .infinity) - topNavHeight - rootInset, shrink: s.shrink || height == nil, appBarHeight: nil, paddingTop: s.paddingTop,
            paddingBottom: s.paddingBottom,
            gap: s.gap, bodyContentHeight: s.bodyEmpty ? nil : 0, firstPull: s.firstPull,
            bottom: (pinnedHeight != nil || navContent != nil)
                ? BottomZoneInput(pinnedHeight: pinnedHeight, navBarHeight: navContent, safeBottom: s.safeBottom) : nil,
            navFloat: floats, bodyTop: s.bodyTop, safeTop: s.safeTop, keyboard: s.keyboard
        )
        var barTop: Double?
        var topZoneTop: Double?
        if hasTop {
            // The top zone holds the inset and the root padding itself; the bar above it holds the inset in its box.
            let header = (hasBar ? s.paddingTop + barHeight : 0) + topHeight
            input.appBarHeight = header - s.paddingTop
            input.safeTop = 0
            input.bodyTop = nil
            barTop = hasBar ? s.paddingTop : nil
            topZoneTop = (hasBar ? s.paddingTop + barHeight : 0) + topNavHeight
        } else if hasBar {
            input.appBarHeight = max(0, barHeight - ScreenAnatomy.safeTop(s.safeTop, screenHeight: input.height))
        }
        var zones = ScreenAnatomy.zones(input)
        if s.shrink || height == nil, !s.bodyEmpty, let body = child(subviews, .body) {
            // The body gives its own length: lead, the column, tail. The rest of the length is what the rule adds.
            let measured = Double(body.sizeThatFits(ProposedViewSize(width: CGFloat(width), height: nil)).height)
            input.bodyContentHeight = max(0, measured - zones.contentHeight)
            zones = ScreenAnatomy.zones(input)
        }
        if !hasTop, hasBar { barTop = zones.appBar?.top }
        zones.lower(by: topNavHeight)
        return ScreenZonePlan(
            zones: zones, barTop: barTop, barHeight: barHeight, topZoneTop: topZoneTop, topZoneHeight: topHeight, width: width, topNavHeight: topNavHeight, rootInset: rootInset)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? Double($0) : nil } ?? 393
        let height = proposal.height.flatMap { $0.isFinite ? Double($0) : nil }
        let plan = plan(width: width, height: height, subviews: subviews)
        return CGSize(width: CGFloat(width), height: CGFloat(plan.zones.height + plan.rootInset))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let height = proposal.height.flatMap { $0.isFinite ? Double($0) : nil } ?? Double(bounds.height)
        let plan = plan(width: Double(bounds.width), height: proposal.height == nil ? nil : height, subviews: subviews)
        let s = settings
        let width = Double(bounds.width)
        let inner = max(0, width - s.paddingStart - s.paddingEnd)
        let zones = plan.zones
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: bounds.minX + CGFloat(x), y: bounds.minY + CGFloat(y)) }
        if let nav = child(subviews, .topNav) {
            nav.place(at: at(0, 0), anchor: .topLeading, proposal: ProposedViewSize(width: CGFloat(width), height: CGFloat(plan.topNavHeight)))
        }
        if let bar = child(subviews, .bar), let top = plan.barTop {
            bar.place(at: at(s.paddingStart, top), anchor: .topLeading, proposal: ProposedViewSize(width: CGFloat(inner), height: CGFloat(plan.barHeight)))
        }
        if let zone = child(subviews, .top), let top = plan.topZoneTop {
            zone.place(at: at(s.paddingStart, top), anchor: .topLeading, proposal: ProposedViewSize(width: CGFloat(inner), height: CGFloat(plan.topZoneHeight)))
        }
        if let body = child(subviews, .body) {
            body.place(at: at(0, zones.body.top), anchor: .topLeading, proposal: ProposedViewSize(width: CGFloat(width), height: CGFloat(zones.body.height)))
        }
        if let bottom = zones.bottom {
            if let pinned = child(subviews, .pinned), let box = bottom.pinned {
                pinned.place(
                    at: at(s.paddingStart, box.top), anchor: .topLeading, proposal: ProposedViewSize(width: CGFloat(inner), height: CGFloat(box.height)))
            }
            if let nav = child(subviews, .nav), let box = bottom.navBar {
                nav.place(at: at(0, box.top), anchor: .topLeading, proposal: ProposedViewSize(width: CGFloat(width), height: CGFloat(box.height)))
            }
        }
    }
}
