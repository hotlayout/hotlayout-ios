import SwiftUI

/// What the host's window leaves the screen: the platform insets, in points. A host that has
/// already accounted for them gives zero.
struct ScreenInsets: Equatable {
    var top = 0.0
    var bottom = 0.0
}

private struct ScrollTopKey: PreferenceKey {
    static let defaultValue = 0.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}

private struct ZoneHeightKey: PreferenceKey {
    static let defaultValue = 0.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value += nextValue() }
}

private final class ScrollMemory {
    var top = 0.0
}

/// A screen as the contract gives it anatomy (`x-style.layout.screen`): the app bar and the
/// bottom zone are fixed and only the body scrolls; the background of the root lies under every
/// zone; the paddings of the root are shared between the zones.
struct ScreenRootView: View {
    let root: DocumentNode
    let context: RenderContext
    /// A modal layer: as tall as its content.
    var shrinks = false
    var insets = ScreenInsets()
    /// The host turned autofill hints off.
    var autofill = true
    /// A sheet shown as a window in a wide place: the corners it did not name at the bottom take
    /// the radius of the top ones.
    var sheetWindow = false

    /// Which text field has the keyboard (by node id); the screen owns it so that the «next» key
    /// can move it and a focused field can be brought into view above the keyboard.
    @State private var focusedField: String?

    @State private var barHeight = 0.0
    @State private var barScrolled = false
    @State private var floatTail = 0.0
    @State private var keyboard = 0.0
    @State private var memory = ScrollMemory()

    private static let scrollSpace = "hotlayout-screen-body"

    var body: some View {
        let style = rootStyle()
        let look = context.resolver.box(style, scope: context.scope)
        let inner = withForm(context.with(inherited: NodeStyle.inherited(context.inherited, style: style, resolver: context.resolver)))
        let plan = Plan(root: root, context: context, look: look, insets: insets, shrinks: shrinks)

        ZStack {
            BackgroundView(
                background: look.background, shadow: [], shape: LogicalCornersShape(corners: look.radius ?? Corners(), rightToLeft: context.rightToLeft),
                context: inner
            )
            .ignoresSafeArea()
            ScreenZonesLayout(settings: plan.settings(keyboard: keyboard)) {
                if plan.bodyAtScreenTop {
                    bodyZone(plan, look: look, inner: inner)
                    barZone(plan, inner: inner)
                } else {
                    topNavZone(plan, inner: inner)
                    barZone(plan, inner: inner)
                    topZone(plan, inner: inner)
                    bodyZone(plan, look: look, inner: inner)
                }
                pinnedZone(plan, inner: inner)
                navZone(plan, inner: inner)
            }
        }
        .overlay {
            // The border of the root (a window shows it) lies on the inner edge of its box.
            if let color = look.borderColor, let width = look.borderWidth, width > 0 {
                LogicalCornersShape(corners: look.radius ?? Corners(), rightToLeft: context.rightToLeft).inset(by: width / 2).stroke(color.color, lineWidth: width)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        // The shadow of the root lies outside its box, so it is drawn behind the clipped screen (a window shows it).
        .shadowLayers(look.shadow, shape: LogicalCornersShape(corners: look.radius ?? Corners(), rightToLeft: context.rightToLeft))
        .keyboardOverlap($keyboard)
        .onPreferenceChange(ZoneHeightKey.self) { height in if plan.floats, height != floatTail { floatTail = height } }
        .onChange(of: barHeight) { _ in refreshScrolled(plan) }
    }

    /// The effective style of the root; a sheet shown as a window gets the corners it did not name.
    private func rootStyle() -> JSONObject {
        var style = NodeStyle.effective(root, scope: context.scope)
        if sheetWindow { style["radius"] = WideChrome.sheetWindowRadius(style["radius"]) }
        return style
    }

    private func withForm(_ context: RenderContext) -> RenderContext {
        var copy = context
        copy.form = ScreenForm(
            root: root, scope: context.scope, order: InputOrder.fields(of: root, scope: context.scope, widthClass: context.widthClass),
            autofill: autofill, focus: $focusedField, widthClass: context.widthClass
        )
        return copy
    }

    // MARK: Zones

    @ViewBuilder
    private func barZone(_ plan: Plan, inner: RenderContext) -> some View {
        if let bar = plan.bar {
            let view = NodeView(node: bar, context: barContext(inner, plan), placement: .stretched, depth: 1, parentType: "Screen")
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { barHeight = Double(proxy.size.height) }.onChange(of: proxy.size.height) { barHeight = Double($0) }
                    })
            if plan.bodyAtScreenTop {
                // The box of the bar takes the presses in it; the body under it does not.
                view.contentShape(Rectangle()).onTapGesture {}.layoutValue(key: ScreenZoneKey.self, value: .bar)
            } else {
                view.layoutValue(key: ScreenZoneKey.self, value: .bar)
            }
        }
    }

    @ViewBuilder
    private func topZone(_ plan: Plan, inner: RenderContext) -> some View {
        if !plan.topPinned.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: CGFloat(plan.topLead))
                ColumnView(children: plan.topPinned, gap: plan.gap, node: root, context: inner, depth: 0, ignoresFirstPull: true)
                    .contentColumn(plan.contentMax)
            }
            .layoutValue(key: ScreenZoneKey.self, value: .top)
        }
    }

    @ViewBuilder
    private func bodyZone(_ plan: Plan, look: BoxLook, inner: RenderContext) -> some View {
        Group {
            if plan.fillsArea {
                GeometryReader { area in
                    scroll(plan, look: look, inner: inner, minBlock: max(0, area.size.height - plan.lead - plan.tail))
                }
            } else {
                scroll(plan, look: look, inner: inner, minBlock: nil)
            }
        }
        // The body is cut at the edge of its area (the bottom edge of the inset or of the app bar), not at the edge of the screen.
        .clipped()
        .layoutValue(key: ScreenZoneKey.self, value: .body)
    }

    private func scroll(_ plan: Plan, look: BoxLook, inner: RenderContext, minBlock: CGFloat?) -> some View {
        ScrollViewReader { reader in
            scrollView(plan, look: look, inner: inner, minBlock: minBlock)
                .onChange(of: focusedField) { id in
                    // The field with the keyboard stays in the body area above it.
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(id, anchor: .center) }
                }
        }
    }

    private func scrollView(_ plan: Plan, look: BoxLook, inner: RenderContext, minBlock: CGFloat?) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear.frame(height: CGFloat(plan.lead))
                ColumnView(
                    children: plan.body, gap: plan.gap, node: root, space: HostSpace(block: nil, minBlock: minBlock, fills: false), context: inner, depth: 0
                )
                .contentColumn(plan.contentMax)
                .padding(EdgeInsets(top: 0, leading: CGFloat(look.padding.start), bottom: 0, trailing: CGFloat(look.padding.end)))
                Color.clear.frame(height: CGFloat(plan.tail + (plan.floats ? floatTail : 0)))
            }
            .reportsModalBodyScroll()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ScrollTopKey.self, value: -Double(proxy.frame(in: .named(Self.scrollSpace)).minY))
                })
            .reportsScrollTop { top in
                memory.top = top
                refreshScrolled(plan)
            }
        }
        .coordinateSpace(name: Self.scrollSpace)
        .modalBodyScrollSpace()
        .scrollDismissesKeyboard(.interactively)
        .onPreferenceChange(ScrollTopKey.self) { top in
            memory.top = top
            refreshScrolled(plan)
        }
    }

    @ViewBuilder
    private func pinnedZone(_ plan: Plan, inner: RenderContext) -> some View {
        if let pinned = plan.pinned {
            ColumnView(children: [pinned], gap: 0, node: root, context: inner, depth: 0, ignoresFirstPull: true)
                .contentColumn(plan.contentMax)
                .modifier(ZoneHeightReporter(active: plan.floats, extra: plan.paddingBottom))
                .layoutValue(key: ScreenZoneKey.self, value: .pinned)
        }
    }

    /// The bar of navigation of its own at the top of the screen (`wideNav.ownBar`).
    @ViewBuilder
    private func topNavZone(_ plan: Plan, inner: RenderContext) -> some View {
        if let nav = plan.topNav {
            NodeView(
                node: nav, context: navContext(inner, floats: false, atTop: true, contentMax: plan.contentMax), placement: .stretched, depth: 1,
                parentType: "Screen"
            )
            .layoutValue(key: ScreenZoneKey.self, value: .topNav)
        }
    }

    @ViewBuilder
    private func navZone(_ plan: Plan, inner: RenderContext) -> some View {
        if let nav = plan.nav {
            NodeView(
                node: nav, context: navContext(inner, floats: plan.floats, atTop: false, contentMax: plan.contentMax), placement: .stretched, depth: 1,
                parentType: "Screen"
            )
            .modifier(ZoneHeightReporter(active: plan.floats, extra: insets.bottom))
            .layoutValue(key: ScreenZoneKey.self, value: .nav)
        }
    }

    private func barContext(_ inner: RenderContext, _ plan: Plan) -> RenderContext {
        var copy = inner
        copy.barInset = insets.top
        copy.barScrolled = barScrolled
        copy.contentMaxWidth = plan.contentMax
        copy.barNav = plan.barNav
        return copy
    }

    /// The bar holds the inset under its items, unless it floats: then the inset lies under its box.
    private func navContext(_ inner: RenderContext, floats: Bool, atTop: Bool, contentMax: Double?) -> RenderContext {
        var copy = inner
        copy.navInset = atTop ? 0 : floats ? 0 : insets.bottom
        copy.navAtTop = atTop
        // A bar of its own is drawn under the status bar of the platform: the inset lies inside its box, as in an app bar.
        if atTop { copy.barInset = insets.top }
        copy.contentMaxWidth = contentMax
        return copy
    }

    // MARK: Scrolled

    /// Whether the bar is scrolled: strictly past the part of the bar zone that lies below the
    /// top of the body area.
    private func refreshScrolled(_ plan: Plan) {
        guard plan.bar != nil, barHeight > 0 else {
            if barScrolled { barScrolled = false }
            return
        }
        let barBottom = plan.paddingTop + barHeight
        let bodyTop = plan.bodyAtScreenTop ? 0 : barBottom - plan.raise
        let scrolled = AppBarRules.isScrolled(scrollTop: memory.top, barBottom: barBottom, bodyTop: bodyTop)
        if scrolled != barScrolled { barScrolled = scrolled }
    }
}

/// Tells the screen how tall a floating zone is: the body adds that much at its end.
private struct ZoneHeightReporter: ViewModifier {
    let active: Bool
    let extra: Double

    func body(content: Content) -> some View {
        if active {
            content.background(GeometryReader { proxy in Color.clear.preference(key: ZoneHeightKey.self, value: Double(proxy.size.height) + extra) })
        } else {
            content
        }
    }
}

/// What the zones of a screen are, worked out from the document and the data: who is in which
/// zone, the lead and tail of the body, and the settings of the layout.
private struct Plan {
    let bar: DocumentNode?
    let topPinned: [DocumentNode]
    let body: [DocumentNode]
    let pinned: DocumentNode?
    let nav: DocumentNode?
    /// The bar of navigation of its own at the top (`navPlace == .top`).
    let topNav: DocumentNode?
    /// The bar of navigation whose items stand in the app bar (`navPlace == .appBar`).
    let barNav: DocumentNode?
    /// The widest content (`Screen.contentMaxWidth`), in points.
    let contentMax: Double?
    let bodyEmpty: Bool
    let firstPull: Double
    let gap: Double
    let paddingTop: Double
    let paddingBottom: Double
    let paddingStart: Double
    let paddingEnd: Double
    let bodyAtScreenTop: Bool
    let bodyTop: JSONValue?
    let floats: Bool
    let fillsArea: Bool
    let shrinks: Bool
    let insets: ScreenInsets

    init(root: DocumentNode, context: RenderContext, look: BoxLook, insets: ScreenInsets, shrinks: Bool) {
        func shown(_ node: DocumentNode?) -> DocumentNode? {
            guard let node, Conditions.isVisible(node.visibleIf, scope: context.scope) else { return nil }
            return node
        }
        let chrome = WideChrome.screenChrome(root.children, widthClass: context.widthClass, rootProps: root.props, isShown: { shown($0) != nil })
        let parts = chrome.zones
        let barShown = shown(parts.appBar)
        // A navigation bar is not drawn in a modal layer, nor when it is hidden.
        let navShown = shrinks ? nil : shown(parts.navBar)
        let place = navShown == nil ? nil : chrome.navPlace
        let visibleBody = parts.body.filter { shown($0) != nil }
        let firstPull =
            visibleBody.first.flatMap { child in
                FlowPull.read(node: child, parentType: "Screen", parentProps: root.props).flatMap { context.resolver.spacing($0.by.json) }
            } ?? 0
        self.bar = barShown
        self.topPinned = parts.topPinned.filter { shown($0) != nil }
        self.body = parts.body
        self.pinned = shown(parts.pinned)
        self.nav = place == .bottom ? navShown : nil
        self.topNav = place == .top ? navShown : nil
        self.barNav = place == .appBar && barShown != nil ? navShown : nil
        self.contentMax = WidthRules.contentMaxWidth(root.props["contentMaxWidth"])
        self.bodyEmpty = visibleBody.isEmpty
        self.firstPull = firstPull
        self.gap = context.resolver.spacing(root.props["gap"] ?? "sm") ?? 0
        self.paddingTop = look.padding.top
        self.paddingBottom = look.padding.bottom
        self.paddingStart = look.padding.start
        self.paddingEnd = look.padding.end
        self.bodyTop = root.props["bodyTop"]
        self.bodyAtScreenTop = ScreenAnatomy.bodyStartsAtScreenTop(
            bodyTop: root.props["bodyTop"], owner: ScreenAnatomy.topZoneOwner(navBar: place == .top, appBar: barShown != nil))
        self.floats = place == .bottom ? (navShown.map { NavBarRules.floats(place: "bottom", props: $0.props) } ?? false) : false
        self.fillsArea = !shrinks && AlignRules.read(type: root.type, props: root.props)?.justify != .start
        self.shrinks = shrinks
        self.insets = insets
    }

    var hasHeader: Bool { bar != nil || !topPinned.isEmpty }

    /// What lies above the first child of the body inside the scroll: the gap of the screen under
    /// the header, or the top padding of the root without one.
    var lead: Double {
        let base: Double
        if bodyAtScreenTop { base = bar == nil ? paddingTop : 0 } else { base = hasHeader ? (bodyEmpty ? 0 : gap) : paddingTop }
        // A pulled first child lifts the body area onto the header; the lift is part of the lead.
        return hasHeader && !bodyAtScreenTop ? max(base, firstPull) : base
    }

    var raise: Double { hasHeader && !bodyAtScreenTop ? max(0, firstPull - (bodyEmpty ? 0 : gap)) : 0 }

    /// What lies under the last child: the gap of the screen above a pinned block, or the bottom
    /// padding of the root.
    var tail: Double { pinned != nil ? (bodyEmpty ? 0 : gap) : paddingBottom }

    /// The lead of the top zone: the gap under the bar, or the inset and the top padding.
    var topLead: Double { bar != nil ? gap : (topNav != nil ? 0 : insets.top) + paddingTop }

    func settings(keyboard: Double) -> ScreenZonesSettings {
        ScreenZonesSettings(
            shrink: shrinks, paddingTop: paddingTop, paddingBottom: paddingBottom, paddingStart: paddingStart, paddingEnd: paddingEnd, gap: gap,
            bodyEmpty: bodyEmpty, firstPull: firstPull, bodyTop: bodyTop, safeTop: topNav != nil ? 0 : insets.top, safeBottom: insets.bottom,
            keyboard: keyboard, navFloat: floats
        )
    }
}
