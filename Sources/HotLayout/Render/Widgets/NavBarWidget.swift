import SwiftUI

/// `NavBar`: the items side by side in equal shares, on the `surface` of the theme with a line
/// on top, unless the node names its own background or border (`x-style.layout.navBar`).
struct NavBarWidget: View {
    let node: DocumentNode
    let style: JSONObject
    let context: RenderContext
    let depth: Int

    var body: some View {
        if context.navAtTop { ownBar } else { bottomBar }
    }

    /// The bar in the bottom zone: equal shares, a line on top.
    @ViewBuilder
    private var bottomBar: some View {
        let theme = context.theme
        let items = node.children.filter { $0.widget == .navItem && context.isShown($0) }.prefix(NavBarRules.maxItems)
        let line = style["border"] == nil ? 1.0 : 0.0
        let surface = style["background"] == nil ? (theme.coreColor("surface")).color : Color.clear
        let borderColor = (theme.coreColor("border")).color
        let child = itemContext(line: line)

        VStack(spacing: 0) {
            EqualSharesLayout {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NodeView(node: item, context: child, placement: .stretched, depth: depth + 1, parentType: WidgetType.navBar.rawValue)
                }
            }
            .contentColumn(context.contentMaxWidth)
            if context.navInset > 0 { Color.clear.frame(height: CGFloat(context.navInset)) }
        }
        .frame(maxWidth: .infinity)
        .background(surface)
        .overlay(alignment: .top) {
            if line > 0 { Rectangle().fill(borderColor).frame(height: CGFloat(line)) }
        }
        .accessibilityElement(children: .contain)
        .modifier(TabBarTrait())
    }
}

extension NavBarWidget {
    /// A bar of its own at the top (`wideNav.ownBar`): the items from the start of the row, natural
    /// widths, with their labels when all fit, else the glyphs alone; the surface is `surface` with a
    /// line UNDER it, unless the node names its own background or border.
    fileprivate var ownBar: some View {
        let theme = context.theme
        let items = node.children.filter { $0.widget == .navItem && context.isShown($0) }.prefix(NavBarRules.maxItems)
        let line = style["border"] == nil ? 1.0 : 0.0
        let surface = style["background"] == nil ? (theme.coreColor("surface")).color : Color.clear
        let borderColor = (theme.coreColor("border")).color
        var child = context
        child.contentMaxWidth = nil
        return VStack(spacing: 0) {
            WideNavRowLayout(metrics: WideChrome.metrics(theme: theme)) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NodeView(node: item, context: child, placement: .natural, depth: depth + 1, parentType: WidgetType.navBar.rawValue)
                }
            }
            .contentColumn(context.contentMaxWidth)
            if line > 0 { Rectangle().fill(borderColor).frame(height: CGFloat(line)) }
        }
        .padding(.top, CGFloat(context.barInset))
        .frame(maxWidth: .infinity)
        .background(surface)
        .clipped()
        .accessibilityElement(children: .contain)
        .modifier(TabBarTrait())
    }
}

/// The bar is a group of its items. It does not take the tab-bar trait: on iOS 17 and later that
/// trait makes the system build a tab button over every item, and each one then shows twice more,
/// as nameless buttons (the glyph and a zero-sized one) beside the item named by its label.
private struct TabBarTrait: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension NavBarWidget {
    /// What the items read: the line they take into their touch area; the inset is the bar's own.
    fileprivate func itemContext(line: Double) -> RenderContext {
        var copy = context
        copy.navLine = line
        copy.navInset = 0
        return copy
    }
}

/// The items of the bar: equal shares of its width, the first at the start of the reading
/// direction. The shares are not rounded (`NavBarRules.shares`).
struct EqualSharesLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let share = width.map { subviews.isEmpty ? 0 : $0 / CGFloat(subviews.count) }
        var height: CGFloat = 0
        var natural: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: share, height: nil))
            height = max(height, size.height)
            natural = max(natural, size.width)
        }
        return CGSize(width: width ?? natural * CGFloat(subviews.count), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width / CGFloat(subviews.count)
        for (index, view) in subviews.enumerated() {
            view.place(
                at: CGPoint(x: bounds.minX + width * CGFloat(index), y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

/// `NavItem`: the icon above the label, the whole share is the touch area. The item that
/// switches to the shown screen is active (the colour `primary`), the others are `muted`; a dot
/// may sit on the icon (`badgeWhen`).
struct NavItemWidget: View {
    let node: DocumentNode
    let context: RenderContext

    var body: some View {
        let theme = context.theme
        let action = node.props["action"]?.objectValue ?? ["type": .string(ActionType.none.rawValue)]
        let active = NavBarRules.isActive(action, shown: context.screenId)
        let named = context.inherited.colorRef
        let colorRef: JSONValue = active ? (named ?? "primary") : (named.map { PartStyleRules.withOpacity($0, ListTileRules.secondaryOpacity) } ?? "muted")
        let color = context.resolver.color(colorRef) ?? context.inherited.color
        let typography = theme.typography["bodyS"] ?? context.inherited.typography
        let label = context.text(node, field: "label")
        let icon = IconBesideTextRules.resolve(props: node.props, field: "icon", scope: context.scope)
        let box = iconBox(size: "md", glyphSize: nil, theme: theme)
        let block = theme.coreSpacing("sm")
        let side = theme.coreSpacing("xs")
        let name = ButtonGeometry.iconButtonName(label: label, iconName: icon.resolved)
        let showsDot = NavBarRules.badgeShown(node.props, scope: context.scope)

        if context.navAtTop {
            topItem(label: label, name: name, icon: icon, box: box, color: color, active: active, showsDot: showsDot)
        } else {
            Button {
                if !active { context.press(action, node) }
            } label: {
                VStack(spacing: CGFloat(theme.coreSpacing("xs"))) {
                    IconGlyph(name: icon.name, glyph: box.glyph, box: box.box, color: color.color, rightToLeft: context.rightToLeft)
                        .overlay {
                            NavBadgeDot(shown: showsDot, box: box.box, color: (theme.colorValue("accent") ?? color).color, rightToLeft: context.rightToLeft)
                        }
                    StyledText(text: label, style: typography, color: color, theme: theme, alignment: .center, maxLines: 1)
                        .frame(maxWidth: .infinity)
                }
                .padding(EdgeInsets(top: CGFloat(block + context.navLine), leading: CGFloat(side), bottom: CGFloat(block), trailing: CGFloat(side)))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityAddTraits(active ? .isSelected : [])
        }
    }

    /// An item at the top: the glyph and the label in a row, at their natural width. The label is cut
    /// at `labelMax`. The box that is placed may be narrower than the row: then the label is outside it and
    /// clipped away, and stays the accessible name.
    private func topItem(
        label: String, name: String, icon: IconResolution, box: (glyph: Double, box: CGSize), color: RGBA, active: Bool, showsDot: Bool
    ) -> some View {
        let theme = context.theme
        let action = node.props["action"]?.objectValue ?? ["type": .string(ActionType.none.rawValue)]
        let metrics = WideChrome.metrics(theme: theme)
        let typography = theme.typography["bodyM"] ?? context.inherited.typography
        let block = theme.coreSpacing("sm")
        return Button {
            if !active { context.press(action, node) }
        } label: {
            HStack(spacing: CGFloat(metrics.gap)) {
                IconGlyph(name: icon.name, glyph: box.glyph, box: box.box, color: color.color, rightToLeft: context.rightToLeft)
                    .overlay {
                        NavBadgeDot(shown: showsDot, box: box.box, color: (theme.colorValue("accent") ?? color).color, rightToLeft: context.rightToLeft)
                    }
                StyledText(text: label, style: typography, color: color, theme: theme, alignment: .leading, maxLines: 1)
                    .frame(maxWidth: CGFloat(WideChrome.labelMax), alignment: .leading)
            }
            .padding(EdgeInsets(top: CGFloat(block), leading: CGFloat(metrics.paddingInline), bottom: CGFloat(block), trailing: CGFloat(metrics.paddingInline)))
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The items of a bar of its own at the top: from the start of the row, each at its natural width;
/// the labels are shown when all of them fit together, else the glyphs alone
/// (`WideChrome.navBar`). Items that do not fit even so are cut by the end edge.
struct WideNavRowLayout: Layout {
    var metrics: WideChrome.NavMetrics

    private func labels(_ subviews: Subviews) -> [Double] {
        let fixed = 2 * metrics.paddingInline + metrics.iconWidth + metrics.gap
        return subviews.map { max(0, Double($0.sizeThatFits(.unspecified).width) - fixed) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = WideChrome.navGroupWidth(labels: labels(subviews), metrics, .labels)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? CGFloat(natural), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let box = WideChrome.navBar(width: Double(bounds.width), labels: labels(subviews), metrics)
        for (index, view) in subviews.enumerated() where index < box.navItemStarts.count {
            view.place(
                at: CGPoint(x: bounds.minX + CGFloat(box.navItemStarts[index]), y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: CGFloat(box.navItemWidths[index]), height: bounds.height)
            )
        }
    }
}

/// The dot on the icon of an item: 8 points, `accent`, its centre on the top inline-end corner of
/// the glyph, not clipped by the item. It appears with a short flash and fades out when its
/// condition changes its answer on a shown screen; the first show and «reduce motion» are not moved.
struct NavBadgeDot: View {
    let shown: Bool
    let box: CGSize
    let color: Color
    let rightToLeft: Bool

    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var seen = false
    @State private var before = false
    @State private var change = NavBarRules.BadgeChange.none
    @State private var started = Date()

    var body: some View {
        let glyph = Double(box.width)
        let dot = NavBarRules.badgeBox(glyphLeft: 0, glyphTop: (Double(box.height) - glyph) / 2, glyphSize: glyph, rightToLeft: rightToLeft)
        // A timeline only while the dot moves: a paused one still keeps the screen from going idle.
        Group {
            if change == .none {
                dotView(dot, scale: 1, opacity: 1)
            } else {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(started) * 1000
                    dotView(
                        dot,
                        scale: change == .appear ? NavBarRules.appearScale(at: elapsed) : 1,
                        opacity: change == .disappear ? NavBarRules.disappearOpacity(at: elapsed) : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            seen = true
            before = shown
        }
        .onChange(of: shown) { now in
            let moving = NavBarRules.badgeChange(shownBefore: seen, before: before, after: now, reducedMotion: reducedMotion)
            before = now
            started = Date()
            change = moving
        }
        // Each change starts its own motion; a dot that goes away ends it.
        .task(id: started) { await settle() }
    }

    /// The end of a motion: the dot stands still again.
    @MainActor
    private func settle() async {
        guard change != .none else { return }
        let duration = change == .appear ? NavBarRules.appearMs : NavBarRules.disappearMs
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000))
        guard !Task.isCancelled else { return }
        change = .none
    }

    private func dotView(_ dot: (left: Double, top: Double, size: Double), scale: Double, opacity: Double) -> some View {
        GeometryReader { _ in
            if shown || change == .disappear {
                Circle().fill(color)
                    .frame(width: CGFloat(dot.size), height: CGFloat(dot.size))
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .position(x: CGFloat(dot.left + dot.size / 2), y: CGFloat(dot.top + dot.size / 2))
            }
        }
    }
}
