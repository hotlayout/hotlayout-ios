import Foundation

/// Where the navigation bar stands on a screen (`x-style.layout.wideNav.place`).
enum NavPlace: String {
    /// The bottom zone, as on a phone.
    case bottom
    /// The items stand inside the app bar, in one row with the title.
    case appBar
    /// A bar of its own in the app bar zone (the screen has no shown app bar).
    case top
}

/// The children of the root of a screen by zone in a width class, and where the navigation bar
/// stands there.
struct ScreenChrome {
    var zones: ScreenAnatomy.ChildrenByZone
    /// `nil`: the screen has no navigation bar.
    var navPlace: NavPlace?
}

/// The wide places (`x-style.layout.wideNav`, `wideModal`): where the navigation bar stands and what
/// a modal sheet becomes on a medium or an expanded class. The document does not change: the place
/// is chosen by the reader from the width class of the place the screen is shown in.
enum WideChrome {
    // MARK: Who stands where

    /// The word of `NavBar.widePlacement`: `bottom` keeps the bar down on every width; any other
    /// word, and no field, is `top`.
    static func keepsBottom(_ props: JSONObject) -> Bool {
        props["widePlacement"]?.stringValue == "bottom"
    }

    /// Who stands where in a class. The zones are the document's; a class does not move children
    /// between them. What is new is the place of the bar: down on `compact` and with
    /// `widePlacement: bottom`, otherwise up — into the app bar when the screen has one that is
    /// SHOWN (class and condition), else as a bar of its own. A hidden app bar is no zone, and items
    /// left in it would vanish with it.
    static func screenChrome(
        _ children: [DocumentNode], widthClass: WidthClass, rootProps: JSONObject = JSONObject(), isShown: (DocumentNode) -> Bool = { _ in true }
    ) -> ScreenChrome {
        let zones = ScreenAnatomy.childrenByZone(children, rootProps: rootProps)
        guard let nav = zones.navBar else { return ScreenChrome(zones: zones, navPlace: nil) }
        if !widthClass.isWide || keepsBottom(nav.props) { return ScreenChrome(zones: zones, navPlace: .bottom) }
        let appBarShown = zones.appBar.map(isShown) ?? false
        return ScreenChrome(zones: zones, navPlace: appBarShown ? .appBar : .top)
    }

    // MARK: Navigation items at the top

    /// The most a title keeps while the labels of the items are still shown.
    static let titleKeeps = 120.0
    /// The widest label of an item at the top; a longer one is cut with an ellipsis.
    static let labelMax = 160.0

    enum NavMode: String { case labels, icons }

    /// Spacing and widths of an item at the top, in points of the theme.
    struct NavMetrics: Equatable {
        /// `item.paddingInline`.
        var paddingInline: Double
        /// The width of the box of the glyph.
        var iconWidth: Double
        /// The gap between the glyph and the label.
        var gap: Double
        /// The gap between items.
        var between: Double
    }

    /// The width of one item: padding, glyph, (gap, label at most `labelMax`), padding.
    static func navItemWidth(labelWidth: Double, _ metrics: NavMetrics, _ mode: NavMode) -> Double {
        let box = metrics.paddingInline + metrics.iconWidth + metrics.paddingInline
        if mode == .icons { return box }
        return box + metrics.gap + min(max(0, labelWidth), labelMax)
    }

    /// The width of the group of items with the gaps; without items, zero.
    static func navGroupWidth(labels: [Double], _ metrics: NavMetrics, _ mode: NavMode) -> Double {
        if labels.isEmpty { return 0 }
        return labels.reduce(0) { $0 + navItemWidth(labelWidth: $1, metrics, mode) } + Double(labels.count - 1) * metrics.between
    }

    static func navItemHeight(paddingBlock: Double, iconBox: Double, labelLine: Double) -> Double {
        paddingBlock + max(iconBox, labelLine) + paddingBlock
    }

    static func navBarHeight(paddingBlock: Double, iconBox: Double, labelLine: Double, borderBottom: Double) -> Double {
        navItemHeight(paddingBlock: paddingBlock, iconBox: iconBox, labelLine: labelLine) + borderBottom
    }

    private static func itemStarts(from: Double, labels: [Double], _ metrics: NavMetrics, _ mode: NavMode) -> (starts: [Double], widths: [Double]) {
        var cursor = from
        let widths = labels.map { navItemWidth(labelWidth: $0, metrics, mode) }
        let starts = widths.map { width -> Double in
            let start = cursor
            cursor += width + metrics.between
            return start
        }
        return (starts, widths)
    }

    struct WideAppBarInput {
        var bar: AppBarRules.ZonesInput
        /// Natural widths of the labels of the DRAWN items, in document order.
        var navLabels: [Double]
        var nav: NavMetrics
    }

    struct WideAppBarZones {
        var zones: AppBarRules.Zones
        var navMode: NavMode
        /// The offset of the group from the START of the row (reading order) and its width.
        var navStart: Double
        var navWidth: Double
        var navItemStarts: [Double]
        var navItemWidths: [Double]
        /// Even with icons alone the row is wider than the bar: the end edge cuts the rest.
        var clipped: Bool
    }

    /// The zones of an app bar with the navigation items. Items and actions are ONE block of the
    /// trailing zone — «items, the gap of the bar, actions» — and the rest is the rule of the bar as
    /// it was; what is new is the look of the items and their places inside the block. The labels
    /// are shown when everything fits together: the leading zone, the title no narrower than
    /// `titleKeeps` (or than itself, when shorter) and the trailing zone with labels. Only natural
    /// widths are read, which do not depend on the chosen look: a measure must not change what it
    /// measures.
    static func appBarZones(_ input: WideAppBarInput) -> WideAppBarZones {
        let bar = input.bar
        let actions = bar.actionSides.reduce(0, +) + Double(max(0, bar.actionSides.count - 1)) * bar.actionGap
        func block(_ mode: NavMode) -> Double {
            let group = navGroupWidth(labels: input.navLabels, input.nav, mode)
            return group + (group > 0 && actions > 0 ? bar.gap : 0) + actions
        }
        var bare = bar
        bare.actionSides = []
        bare.titleNatural = 0
        let plain = AppBarRules.zones(bare)
        let need = min(max(0, bar.titleNatural), titleKeeps)
        func trailing(_ block: Double) -> Double { block > 0 ? block + bar.gap : 0 }
        let mode: NavMode = plain.leading + need + trailing(block(.labels)) <= bar.width ? .labels : .icons
        let total = block(mode)
        let tail = trailing(total)
        // The node of the leading zone shrinks last of what shrinks: when the title has nothing left
        // to give it takes what the items and actions left.
        let leadingRoom = max(0, bar.width - tail - bar.gap)
        var next = bar
        if let natural = bar.leadingNatural { next.leadingNatural = min(natural, leadingRoom) }
        next.actionSides = total > 0 ? [total] : []
        var zones = AppBarRules.zones(next)
        let navWidth = navGroupWidth(labels: input.navLabels, input.nav, mode)
        // The block stands at the END of the row; when it does not fit it starts right after the
        // leading zone and the end edge cuts the rest.
        let navStart = max(bar.width - total, zones.leading)
        let items = itemStarts(from: navStart, labels: input.navLabels, input.nav, mode)
        var cursor = navStart + total - actions
        zones.actionStarts = bar.actionSides.map { side in
            let start = cursor
            cursor += side + bar.actionGap
            return start
        }
        return WideAppBarZones(
            zones: zones, navMode: mode, navStart: navStart, navWidth: navWidth,
            navItemStarts: items.starts, navItemWidths: items.widths, clipped: zones.leading + tail > bar.width
        )
    }

    struct NavBarBox {
        var navMode: NavMode
        var navWidth: Double
        var navItemStarts: [Double]
        var navItemWidths: [Double]
        var clipped: Bool
    }

    /// The items of a bar of its own: from the start; with labels when they fit, else icons; if even
    /// those do not fit the end edge cuts the rest.
    static func navBar(width: Double, labels: [Double], _ metrics: NavMetrics) -> NavBarBox {
        let mode: NavMode = navGroupWidth(labels: labels, metrics, .labels) <= width ? .labels : .icons
        let total = navGroupWidth(labels: labels, metrics, mode)
        let items = itemStarts(from: 0, labels: labels, metrics, mode)
        return NavBarBox(navMode: mode, navWidth: total, navItemStarts: items.starts, navItemWidths: items.widths, clipped: total > width)
    }

    // MARK: Zones with the bar at the top

    struct WideZones {
        var zones: AnatomyZones
        /// The bar of its own at the top; `nil`: the bar is down, in the app bar or absent.
        var topNav: ZoneBox?
    }

    /// The zones of a screen with the place of the bar: `bottom` — the numbers of a phone; `appBar`
    /// — there is no bar in the bottom zone (it is only the pinned block, and without that block no
    /// zone and no safe inset); `top` — the bar takes the top of the screen for its height, and
    /// everything else is counted in what is left under it, the top padding of the root staying with
    /// the body.
    static func zones(_ input: AnatomyInput, navPlace: NavPlace?, navBarHeight: Double?) -> WideZones {
        var input = input
        if navPlace != .top {
            let pinned = input.bottom?.pinnedHeight
            let nav = navPlace == .bottom ? navBarHeight : nil
            input.bottom = pinned == nil && nav == nil ? nil : BottomZoneInput(pinnedHeight: pinned, navBarHeight: nav, safeBottom: input.bottom?.safeBottom)
            return WideZones(zones: ScreenAnatomy.zones(input), topNav: nil)
        }
        let bar = max(0, navBarHeight ?? 0)
        input.appBarHeight = nil
        input.height = max(0, input.height - bar)
        if let bottom = input.bottom {
            input.bottom =
                bottom.pinnedHeight == nil ? nil : BottomZoneInput(pinnedHeight: bottom.pinnedHeight, navBarHeight: nil, safeBottom: bottom.safeBottom)
        }
        var under = ScreenAnatomy.zones(input)
        under.lower(by: bar)
        return WideZones(zones: under, topNav: ZoneBox(top: 0, height: bar))
    }

    // MARK: Modal layer in a wide place

    /// The widest window a sheet becomes on a wide place.
    static let windowMaxWidth = 560.0
    /// The largest share of the height of the area such a window takes.
    static let windowMaxHeightShare = 0.85

    enum ModalShape: String { case sheet, window, sheetWindow }

    /// What shows a layer: `center` is a window on every width; any other word, and no field, is a
    /// sheet on `compact` and a window in a wider place. `areaWidth` is the box the host gave the screen.
    static func modalShape(placement: JSONValue?, areaWidth: Double) -> ModalShape {
        if ModalRules.isWindow(placement) { return .window }
        return WidthClass.of(width: areaWidth).isWide ? .sheetWindow : .sheet
    }

    /// The width of the layer is known before its content is measured, and the class of the width of
    /// the content comes from it.
    static func modalLayerWidth(placement: JSONValue?, areaWidth: Double, margin: Double) -> Double {
        let shape = modalShape(placement: placement, areaWidth: areaWidth)
        if shape != .sheetWindow { return ModalRules.width(window: shape == .window, viewport: areaWidth, margin: margin) }
        return max(0, min(areaWidth - 2 * margin, windowMaxWidth))
    }

    struct LayerBox: Equatable {
        var box: ModalRules.Box
        var shape: ModalShape
        var contentWidthClass: WidthClass
    }

    static func modalLayerBox(placement: JSONValue?, width: Double, height: Double, contentHeight: Double, margin: Double) -> LayerBox {
        let shape = modalShape(placement: placement, areaWidth: width)
        if shape != .sheetWindow {
            let box = ModalRules.box(window: shape == .window, viewportWidth: width, viewportHeight: height, contentHeight: contentHeight, margin: margin)
            return LayerBox(box: box, shape: shape, contentWidthClass: WidthClass.of(width: box.width))
        }
        let layerWidth = modalLayerWidth(placement: placement, areaWidth: width, margin: margin)
        let available = max(0, min(height * windowMaxHeightShare, height - 2 * margin))
        let layerHeight = min(max(0, contentHeight), available)
        let box = ModalRules.Box(
            x: (width - layerWidth) / 2, y: (height - layerHeight) / 2, width: layerWidth, height: layerHeight, scrolls: contentHeight > available)
        return LayerBox(box: box, shape: shape, contentWidthClass: WidthClass.of(width: layerWidth))
    }

    /// The radius of the root of a sheet shown as a window: a bottom corner the style did NOT name
    /// takes the radius of the top corner of its side; a named one (zero too) stays; a single value
    /// for all corners and no radius stay as they are.
    static func sheetWindowRadius(_ radius: JSONValue?) -> JSONValue? {
        guard var corners = radius?.objectValue else { return radius }
        let bottomStart = corners["bottomStart"] ?? corners["topStart"]
        let bottomEnd = corners["bottomEnd"] ?? corners["topEnd"]
        if let bottomStart { corners["bottomStart"] = bottomStart }
        if let bottomEnd { corners["bottomEnd"] = bottomEnd }
        return .object(corners)
    }

    /// The width class of the content of a screen in a place of class `area`: a page takes the class
    /// of the place, a modal layer is always `compact` (its box is narrower than 600 anywhere).
    static func contentWidthClass(presentation: ScreenPresentation, area: WidthClass) -> WidthClass {
        presentation == .modal ? .compact : area
    }
}

extension WideChrome {
    /// The numbers of an item at the top from the theme: the side padding is `md`, the gap between the
    /// glyph and the label `xs`, the gap between items `xs`, the box of the glyph is that of `md`.
    static func metrics(theme: HotlayoutTheme) -> NavMetrics {
        NavMetrics(
            paddingInline: theme.coreSpacing("md"),
            iconWidth: iconBox(size: "md", glyphSize: nil, theme: theme).box.width,
            gap: theme.coreSpacing("xs"),
            between: theme.coreSpacing("xs")
        )
    }
}
