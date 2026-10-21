import SwiftUI

/// `IconButton`: a round button with a picture and no visible text (`x-style.layout.iconButton`).
/// The side is the height of a button of the same size (28 / 40 / 48); the accessible name is
/// the label, or, with none, the name of the icon in words.
struct IconButtonWidget: View {
    let node: DocumentNode
    let style: JSONObject
    let context: RenderContext

    var body: some View {
        let theme = context.theme
        let surface = RoleSurface.resolve(group: "buttonVariant", name: node.props["variant"]?.stringValue ?? "secondary", style: style, context: context)
        let size = ButtonGeometry.size(node.props["size"]?.stringValue, theme: theme)
        let typography = surface.typography ?? theme.typography[size.typography] ?? context.inherited.typography
        let padding = surface.padding ?? Sides(top: size.paddingBlock, start: size.paddingBlock, bottom: size.paddingBlock, end: size.paddingBlock)
        // A named side (`style.width` / `height`) is the box; it clamps the drawing, which stands
        // in the centre of the content box (`iconButtonGeometryOf`).
        let named = context.resolver.box(style, scope: context.scope)
        let geometry = GlyphGeometry.of(
            .init(
                glyphSize: node.props["glyphSize"]?.numberValue, fontSize: typography.fontSize,
                paddingInline: padding.start + padding.end, paddingBlock: padding.top + padding.bottom, borderWidth: surface.borderWidth,
                width: named.width, height: named.height, word: CGSize(width: typography.lineBox, height: typography.lineBox)
            ))
        let shape = LogicalCornersShape(corners: surface.corners ?? RoleSurface.corners(all: theme.coreRadius("pill")), rightToLeft: context.rightToLeft)
        let icon = IconBesideTextRules.resolve(props: node.props, field: "icon", scope: context.scope)
        let name = ButtonGeometry.iconButtonName(label: context.text(node, field: "label"), iconName: icon.resolved)
        let action = node.props["action"]?.objectValue ?? ["type": .string(ActionType.none.rawValue)]
        let disabled = WritePress.isDisabled(
            node, scope: context.scope, screenRoot: context.form?.root, screenScope: context.form?.scope ?? context.scope, widthClass: context.widthClass)

        Button {
            context.press(action, node)
        } label: {
            IconGlyph(name: icon.name, glyph: geometry.glyph, box: geometry.content, color: surface.foreground.color, rightToLeft: context.rightToLeft)
                .padding(
                    EdgeInsets(
                        top: padding.top + surface.borderWidth, leading: padding.start + surface.borderWidth,
                        bottom: padding.bottom + surface.borderWidth, trailing: padding.end + surface.borderWidth
                    )
                )
                .roleBox(surface, shape: shape)
        }
        .buttonStyle(PressFeedbackStyle(kind: PressFeedbackRules.kind(node)))
        .accessibilityLabel(name)
        .disabledControl(disabled)
    }
}
