import SwiftUI

/// `Badge` (and the «chip» of layouts: a badge with an icon and its own style): a pill of a tone
/// of the theme (`roles.badgeTone`) with a caption and, by the rule of an icon beside a text,
/// an icon. A badge is text, not a control: it has no action.
struct BadgeWidget: View {
    let node: DocumentNode
    let style: JSONObject
    let context: RenderContext

    /// Padding of a badge (`x-style.layout.badgePadding`) and its radius when nothing else is named.
    static let paddingBlockToken = "xs"
    static let paddingInlineToken = "sm"

    var body: some View {
        let theme = context.theme
        let surface = RoleSurface.resolve(group: "badgeTone", name: node.props["tone"]?.stringValue ?? "neutral", style: style, context: context)
        let typography = surface.typography ?? theme.typography["caption"] ?? context.inherited.typography
        let padding =
            surface.padding
            ?? Sides(
                top: theme.coreSpacing(Self.paddingBlockToken), start: theme.coreSpacing(Self.paddingInlineToken),
                bottom: theme.coreSpacing(Self.paddingBlockToken), end: theme.coreSpacing(Self.paddingInlineToken)
            )
        let shape = LogicalCornersShape(corners: surface.corners ?? RoleSurface.corners(all: theme.coreRadius("pill")), rightToLeft: context.rightToLeft)
        let icon = IconBesideTextRules.resolve(props: node.props, field: "icon", scope: context.scope)
        let label = context.text(node, field: "label")

        IconBesideText(
            icon: icon, position: node.props["iconPosition"]?.stringValue, glyph: IconBesideTextRules.glyphBox(typography).glyph,
            box: IconBesideTextRules.glyphBox(typography).box, gap: theme.coreSpacing(IconBesideTextRules.gapToken),
            color: surface.foreground.color, rightToLeft: context.rightToLeft
        ) {
            StyledText(text: label, style: typography, color: surface.foreground, theme: theme, maxLines: 1)
        }
        .padding(
            EdgeInsets(
                top: padding.top + surface.borderWidth, leading: padding.start + surface.borderWidth,
                bottom: padding.bottom + surface.borderWidth, trailing: padding.end + surface.borderWidth
            )
        )
        .roleBox(surface, shape: shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
