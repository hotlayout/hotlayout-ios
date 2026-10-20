import SwiftUI

/// `Accordion`: a title row with a chevron over a body that exists only while the block is
/// open. `initiallyExpanded` is the starting state only; after that the user decides. The card
/// (padding, radius, background) is the `style` of the node, not part of the widget.
struct AccordionWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int

    @State private var expanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = context.theme
        let open = expanded ?? (node.props["initiallyExpanded"]?.boolValue ?? false)
        let gap = theme.coreSpacing("sm")
        let title = context.text(node, field: "title")
        let titleStyle = theme.typography["titleS"] ?? context.inherited.typography
        let chevronColor = context.inherited.colorRef.map { PartStyleRules.withOpacity($0, ListTileRules.secondaryOpacity) } ?? "muted"
        let box = iconBox(size: "md", glyphSize: nil, theme: theme)
        // Collapsed the chevron points to the end of the line, open it points down; the drawing
        // is already mirrored in right-to-left text, so «down» turns the other way there.
        let turn: Double = open ? (context.rightToLeft ? -90 : 90) : 0

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { expanded = !open }
            } label: {
                HStack(spacing: gap) {
                    StyledText(text: title, style: titleStyle, color: context.inherited.color, theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconGlyph(
                        name: "chevron", glyph: box.glyph, box: box.box,
                        color: (context.resolver.color(chevronColor) ?? context.inherited.color).color, rightToLeft: context.rightToLeft
                    )
                    .rotationEffect(.degrees(turn))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            if open {
                ColumnView(children: node.children, gap: gap, node: nil, context: context, depth: depth)
                    .padding(.top, gap)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
