import SwiftUI

/// Which tab is open (`hiddenInitialTab`, `initialTabOutOfRange`): `initialTab` counts ALL tabs
/// in document order, hidden ones too; a hidden tab, or a number that is not a whole number in
/// range, opens the first visible tab. `nil` means no tab is visible.
enum TabsRules {
    static func openTabIndex(initialTab: JSONValue?, visible: [Bool]) -> Int? {
        if let number = initialTab?.numberValue, number == number.rounded(), number >= 0,
            Int(exactly: number).map({ $0 < visible.count && visible[$0] }) == true
        {
            return Int(exactly: number)
        }
        return visible.firstIndex(of: true)
    }

    /// Gap between the titles, the strip and the panel, from the theme.
    static let titleGapToken = "lg"
    static let titlePaddingToken = "sm"
    static let indicatorToken = "xs"
    static let panelGapToken = "md"
}

/// `Tabs`: a strip of titles over the panels, one of which is drawn. The title lies on the
/// `Tab` child; the strip scrolls and holds only visible tabs; the panel is the `Tab` node
/// itself, so its own style (box, colour) applies to it.
struct TabsWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int

    @State private var selected: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: HotlayoutTheme { context.theme }

    var body: some View {
        let declared = node.children.filter { $0.type == "Tab" }
        let visible = declared.map { context.isShown($0) }
        let tabs = zip(declared, visible).filter(\.1).map(\.0)
        if tabs.isEmpty {
            EmptyView()
        } else {
            let initialIndex =
                TabsRules.openTabIndex(initialTab: node.props["initialTab"], visible: visible).flatMap { index in
                    tabs.firstIndex { $0.id == declared[index].id }
                } ?? 0
            let open = min(max(0, selected ?? initialIndex), tabs.count - 1)
            VStack(alignment: .leading, spacing: theme.coreSpacing(TabsRules.panelGapToken)) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.coreSpacing(TabsRules.titleGapToken)) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                            title(tab, open: index == open) { selected = index }
                        }
                    }
                }
                NodeView(node: tabs[open], context: context, placement: .stretched, depth: depth + 1)
                    .id(tabs[open].id)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: open)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One title. The indicator is always there, transparent while the tab is closed, so the
    /// strip does not change height when a tab opens. The colour is read in the context of the
    /// tab itself: the title is its prop, although the strip draws it.
    private func title(_ tab: DocumentNode, open: Bool, select: @escaping () -> Void) -> some View {
        let tabStyle = NodeStyle.effective(tab, scope: context.scope)
        let look = NodeStyle.inherited(context.inherited, style: tabStyle, resolver: context.resolver)
        let named = look.colorRef
        let colorRef: JSONValue =
            open
            ? (named ?? "primary")
            : (named.map { PartStyleRules.withOpacity($0, ListTileRules.secondaryOpacity) } ?? "muted")
        let color = context.resolver.color(colorRef) ?? look.color
        let style = theme.typography["titleS"] ?? look.typography
        let indicator = theme.coreSpacing(TabsRules.indicatorToken)
        let padding = theme.coreSpacing(TabsRules.titlePaddingToken)
        let primary = theme.colorValue("primary")?.color ?? .accentColor
        return Button(action: select) {
            StyledText(text: context.text(tab, field: "title"), style: style, color: color, theme: theme, maxLines: 1)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.top, padding)
                .padding(.bottom, max(0, padding - indicator))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(open ? primary : .clear).frame(height: indicator)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(context.text(tab, field: "title"))
        .accessibilityAddTraits(open ? [.isSelected] : [])
    }
}
