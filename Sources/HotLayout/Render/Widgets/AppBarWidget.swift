import SwiftUI

/// `AppBar`: the back arrow or the node of the leading zone, the title block, and up to two
/// actions (`x-style.layout.appBar`, `appBarLeading`, `appBarTitle`).
///
/// The arrow is `navigate.back`: in the contract `showBack` is a flag without an action, so the
/// reader defines «back» by the only action that invents nothing new — the same one a button
/// performs, with the same degradation. The bar has no background of its own: it is the style of
/// the node, drawn by the shared box, so a bar without a style is transparent.
struct AppBarWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int

    private var theme: HotlayoutTheme { context.theme }

    var body: some View {
        let children = node.children
        let leadingIndex = AppBarRules.leadingIndex(children)
        let leadingNode = leadingIndex.map { children[$0] }
        let leadingVisible = leadingNode.map { context.isShown($0) }
        let shown = AppBarRules.leadingShown(nodeVisible: leadingVisible, showBack: node.props["showBack"]?.boolValue == true)
        let actionNodes = AppBarRules.actionIndexes(children).map { children[$0] }.filter { context.isShown($0) }
        let side = theme.coreSpacing(AppBarRules.backSideToken)
        let gap = theme.coreSpacing(AppBarRules.gapToken)
        let actionGap = theme.coreSpacing(AppBarRules.actionGapToken)
        let child = childContext()
        let titleHidden = AppBarRules.titleShownOnlyWhenScrolled(node.props) && !context.barScrolled
        let navItems = (context.barNav?.children ?? []).filter { $0.type == "NavItem" && context.isShown($0) }.prefix(NavBarRules.maxItems)
        let navContext = itemsContext()

        AppBarRowLayout(
            backSide: CGFloat(side), gap: CGFloat(gap), actionGap: CGFloat(actionGap), titleAlign: node.props["titleAlign"],
            nav: navItems.isEmpty ? nil : WideChrome.metrics(theme: theme)
        ) {
            switch shown {
            case .node:
                if let leadingNode {
                    NodeView(node: naturalWidth(leadingNode), context: child, placement: .natural, depth: depth + 1, parentType: "AppBar")
                        .layoutValue(key: AppBarPartKey.self, value: .leadingNode)
                }
            case .back:
                backArrow(side: side).layoutValue(key: AppBarPartKey.self, value: .back)
            case .none:
                EmptyView()
            }
            titleBlock
                .opacity(titleHidden ? 0 : 1)
                .layoutValue(key: AppBarPartKey.self, value: .title)
            ForEach(Array(actionNodes.prefix(AppBarRules.maxDrawnActions).enumerated()), id: \.offset) { _, action in
                NodeView(node: action, context: child, placement: .natural, depth: depth + 1, parentType: "AppBar")
                    .layoutValue(key: AppBarPartKey.self, value: .action)
            }
            ForEach(Array(navItems.enumerated()), id: \.offset) { _, item in
                NodeView(node: item, context: navContext, placement: .natural, depth: depth + 1, parentType: "NavBar")
                    .layoutValue(key: AppBarPartKey.self, value: .navItem)
            }
        }
        .frame(maxWidth: .infinity)
        .clippedWhen(!navItems.isEmpty)
        .contentColumn(context.contentMaxWidth)
    }

    /// The context of the navigation items in this bar: the box of the navigation bar is not drawn,
    /// but the colour and the font it names pass to its items.
    private func itemsContext() -> RenderContext {
        var copy = childContext()
        copy.contentMaxWidth = nil
        copy.navAtTop = true
        if let nav = context.barNav {
            let style = NodeStyle.effective(nav, scope: context.scope)
            copy = copy.with(inherited: NodeStyle.inherited(context.inherited, style: style, resolver: context.resolver))
        }
        copy.barNav = nil
        return copy
    }

    /// What the children of the bar read: not the inset of the bar itself, not its scrolled state.
    private func childContext() -> RenderContext {
        var copy = context
        copy.barInset = 0
        copy.barScrolled = false
        copy.contentMaxWidth = nil
        copy.barNav = nil
        return copy
    }

    /// The width of the node of the leading zone is natural, even for a button that would fill:
    /// «full width» has nothing to mean in a zone as wide as the node.
    private func naturalWidth(_ leading: DocumentNode) -> DocumentNode {
        guard leading.type == "Button", leading.props["fullWidth"]?.boolValue != false else { return leading }
        var props = leading.props
        props["fullWidth"] = .bool(false)
        return DocumentNode(id: leading.id, type: leading.type, props: props, fields: leading.fields, children: leading.children)
    }

    // MARK: Title

    private var titleBlock: some View {
        let start = AppBarRules.titleAlign(node.props["titleAlign"]) == .start
        let title = context.text(node, field: "title")
        let subtitle = node.props["subtitle"] == nil ? "" : context.text(node, field: "subtitle")
        let titleStyle = theme.typography["titleM"] ?? context.inherited.typography
        let subtitleStyle = theme.typography["bodyS"] ?? context.inherited.typography
        let named = context.inherited.colorRef
        let subtitleColor =
            (named.map { context.resolver.color(PartStyleRules.withOpacity($0, ListTileRules.secondaryOpacity)) } ?? theme.colorValue("muted"))
            ?? context.inherited.color
        let alignment: HorizontalAlignment = start ? .leading : .center
        return VStack(alignment: alignment, spacing: CGFloat(theme.coreSpacing(AppBarRules.subtitleGapToken))) {
            StyledText(text: title, style: titleStyle, color: context.inherited.color, theme: theme, alignment: start ? .leading : .center, maxLines: 1)
                .accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty {
                StyledText(text: subtitle, style: subtitleStyle, color: subtitleColor, theme: theme, alignment: start ? .leading : .center, maxLines: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: start ? .leading : .center)
    }

    // MARK: Back

    /// The arrow is a square of the `xl` step with the `chevron` glyph of size `md` turned half
    /// a turn. The set mirrors the chevron by itself in right-to-left text, so the turned arrow
    /// points toward where the user came from in both directions.
    private func backArrow(side: Double) -> some View {
        let box = iconBox(size: "md", glyphSize: nil, theme: theme)
        return Button {
            context.press(["type": "navigate.back"], node)
        } label: {
            IconGlyph(name: "chevron", glyph: box.glyph, box: box.box, color: context.inherited.color.color, rightToLeft: context.rightToLeft)
                .rotationEffect(.degrees(180))
                .frame(width: CGFloat(side), height: CGFloat(side))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedOpacity())
        .accessibilityLabel(context.backLabel)
    }
}

extension View {
    /// Cuts what stands outside the box, when asked.
    @ViewBuilder
    func clippedWhen(_ condition: Bool) -> some View {
        if condition { self.clipped() } else { self }
    }
}
