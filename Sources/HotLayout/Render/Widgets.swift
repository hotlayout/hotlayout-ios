import SwiftUI

/// A run of text set in a theme style: the font, the colour, the letter spacing and the line
/// box of the contract (`lineHeight` × size, shared equally above and below the glyphs).
struct StyledText: View {
    let text: String
    let style: TextStyleValue
    let color: RGBA
    let theme: HotlayoutTheme
    var italic = false
    var decoration: String?
    var alignment: TextAlignment = .leading
    var maxLines: Int?
    var truncate = true
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.paintsTabularDigits) private var tabularDigits

    var body: some View {
        let family = theme.fontFamilies[style.role == "heading" ? "heading" : "body"]
        var base = styledRun(text, style: style, family: family, italic: italic, rightToLeft: layoutDirection == .rightToLeft, leadsParagraph: true)
        if tabularDigits { base = base.monospacedDigit() }
        if decoration == "underline" { base = base.underline() }
        if decoration == "lineThrough" { base = base.strikethrough() }
        return
            base
            .foregroundColor(color.color)
            .lineBoxed(style.lineBox, natural: style.naturalLineHeight(in: theme))
            .multilineTextAlignment(alignment)
            .lineLimit(maxLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            // The mark that leads the paragraph is drawn only; assistive technology reads the string.
            .accessibilityLabel(Text(verbatim: BidiText.limited(text)))
    }
}

extension View {
    /// Every line of the text is `box` points tall, as a CSS line box is: the glyphs stand in the middle of it.
    /// Where the system can set the line height itself it does (a line SHORTER than the font's own is
    /// possible, also in the second line); before that the leading is added or taken from the first and the
    /// last line only, and a text of several lines keeps the font's own pitch when the box is smaller.
    @ViewBuilder
    func lineBoxed(_ box: Double, natural: Double) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // The system puts the extra room (or takes the shortage) under the line; CSS shares it above and below.
            self.lineHeight(.exact(points: CGFloat(box))).offset(y: CGFloat((box - natural) / 2))
        } else {
            let extra = box - natural
            self.lineSpacing(extra).padding(.vertical, extra / 2)
        }
    }
}

func textAlignment(_ word: String?) -> TextAlignment {
    switch word {
    case "center": return .center
    case "end": return .trailing
    default: return .leading
    }
}

/// `Text`: a document string in the inherited colour and style.
struct TextWidget: View {
    let node: DocumentNode
    let context: RenderContext

    var body: some View {
        let align = node.props["align"]?.stringValue
        let maxLines = node.props["maxLines"]?.numberValue.map { SafeInt.clamped(min(20, max(1, $0))) }
        StyledText(
            text: context.text(node, field: "content"),
            style: context.inherited.typography,
            color: context.inherited.color,
            theme: context.theme,
            italic: context.inherited.fontStyleItalic,
            decoration: context.inherited.decoration,
            alignment: textAlignment(align),
            maxLines: node.props["overflow"]?.stringValue == "visible" ? nil : maxLines
        )
        .frame(maxWidth: .infinity, alignment: horizontalAlignment(align))
    }
}

/// The glyph box of an icon size word (`iconGlyphTypography`): as wide as the font size and as
/// tall as the line of the text style; `glyphSize` names the glyph itself and the box grows.
func iconBox(size word: String?, glyphSize: Double?, theme: HotlayoutTheme) -> (glyph: Double, box: CGSize) {
    let token = ["sm": "bodyS", "md": "titleM", "lg": "displayL"][word ?? "md"] ?? "titleM"
    let style = theme.coreTypography(token)
    if let glyphSize {
        let glyph = min(128, max(8, glyphSize))
        return (glyph, CGSize(width: glyph, height: glyph))
    }
    return (style.fontSize, CGSize(width: style.fontSize, height: style.lineBox))
}

/// `Icon`: a glyph of the set in the inherited colour.
struct IconWidget: View {
    let node: DocumentNode
    let context: RenderContext
    /// The box look of the node: a named side makes the content box and clamps an own glyph size.
    var look = BoxLook()

    var body: some View {
        let word = iconBox(size: node.props["size"]?.stringValue, glyphSize: nil, theme: context.theme)
        let border = (look.borderWidth ?? 0)
        let geometry = GlyphGeometry.of(
            .init(
                glyphSize: node.props["glyphSize"]?.numberValue, fontSize: word.glyph,
                paddingInline: look.padding.start + look.padding.end, paddingBlock: look.padding.top + look.padding.bottom, borderWidth: border,
                width: look.width, height: look.height, word: word.box
            ))
        let name = iconName(node, context: context)
        IconGlyph(name: name, glyph: geometry.glyph, box: geometry.content, color: context.inherited.color.color, rightToLeft: context.rightToLeft)
    }
}

/// The drawable name of the icon of a node, after the data was asked (`x-iconFromData`): the
/// name from `iconPath` when the data holds a value, else the document's own. A value that is
/// not a name of the set draws an empty box (see `IconBesideTextRules.resolve`).
func iconName(_ node: DocumentNode, context: RenderContext, field: String = "name") -> String? {
    IconBesideTextRules.resolve(props: node.props, field: field, scope: context.scope).name
}

/// `Button`: the surface of a role of the theme (`roles.buttonVariant`), each slot overridable
/// by the node's own style; padding and text style by size (`x-style.layout.buttonSizes`).
struct ButtonWidget: View {
    let node: DocumentNode
    let style: JSONObject
    let context: RenderContext

    var body: some View {
        let resolver = context.resolver
        let theme = context.theme
        let size = ButtonGeometry.size(node.props["size"]?.stringValue, theme: theme)
        let variant = node.props["variant"]?.stringValue ?? "primary"
        let role = theme.roles["buttonVariant"]?[variant]
        let background =
            resolver.color(style["background"]?["kind"]?.stringValue == "color" ? style["background"]?["color"] : nil)
            ?? role?.background.flatMap(theme.colorValue)
        // A gradient of the node's own style lies over the colour of the role.
        let ownLook = resolver.box(style, scope: context.scope)
        let gradient: GradientValue? = { if case .gradient(let value)? = ownLook.background { return value } else { return nil } }()
        let foreground = resolver.color(style["color"]) ?? role?.foreground.flatMap(theme.colorValue) ?? context.inherited.color
        let borderColor = style["border"]?.objectValue.flatMap { resolver.color($0["color"]) } ?? role?.border.flatMap(theme.colorValue)
        let borderWidth = style["border"]?["width"]?.numberValue ?? (role?.border != nil ? 1 : 0)
        let typography = resolver.typography(style["typography"]) ?? theme.typography[size.typography] ?? context.inherited.typography
        let padding =
            resolver.sides(style["padding"])
            ?? Sides(
                top: size.paddingBlock, start: size.paddingInline, bottom: size.paddingBlock, end: size.paddingInline
            )
        let corners =
            resolver.corners(style["radius"])
            ?? {
                let md = theme.coreRadius("md")
                return Corners(topStart: md, topEnd: md, bottomEnd: md, bottomStart: md)
            }()
        let shape = LogicalCornersShape(corners: corners, rightToLeft: context.rightToLeft)
        let label = context.text(node, field: "label")
        let fullWidth = node.props["fullWidth"]?.boolValue ?? true
        let action = node.props["action"]?.objectValue ?? ["type": .string(ActionType.none.rawValue)]
        let icon = IconBesideTextRules.resolve(props: node.props, field: "icon", scope: context.scope)
        let gap = theme.coreSpacing(IconBesideTextRules.gapToken)
        let disabled = WritePress.isDisabled(
            node, scope: context.scope, screenRoot: context.form?.root, screenScope: context.form?.scope ?? context.scope, widthClass: context.widthClass)

        if SwipeConfirmRules.confirmsBySwipe(node.props) {
            SwipeConfirmButton(
                node: node, context: context,
                look: SwipeConfirmLook(
                    label: label, typography: typography, theme: theme, trackFill: background, labelColor: foreground,
                    thumbFill: role?.background.flatMap(theme.colorValue) ?? theme.colorValue("primary") ?? foreground,
                    glyphColor: role?.foreground.flatMap(theme.colorValue) ?? theme.colorValue("onPrimary") ?? foreground,
                    borderColor: borderColor, borderWidth: borderWidth, dashedBorder: DashedBorderRules.isDashed(style["border"]),
                    padding: padding, shape: shape, corners: corners,
                    shadow: ShadowTint.apply(resolver.shadow(style["shadow"]) ?? [], style: style, resolver: resolver),
                    fullWidth: fullWidth, icon: icon.name
                ), disabled: disabled)
        } else {
            Button {
                context.press(action, node)
            } label: {
                IconBesideText(
                    icon: icon, position: node.props["iconPosition"]?.stringValue, glyph: IconBesideTextRules.glyphBox(typography).glyph,
                    box: IconBesideTextRules.glyphBox(typography).box, gap: gap, color: foreground.color, rightToLeft: context.rightToLeft
                ) {
                    if label.isEmpty {
                        Color.clear.frame(width: 0, height: 0)
                    } else {
                        StyledText(text: label, style: typography, color: foreground, theme: theme, alignment: .center)
                    }
                }
                .padding(
                    EdgeInsets(
                        top: padding.top + borderWidth, leading: padding.start + borderWidth, bottom: padding.bottom + borderWidth,
                        trailing: padding.end + borderWidth)
                )
                .frame(maxWidth: fullWidth ? .infinity : nil)
                // A named height (or a least one) of the node is the box the button fills: the box itself is drawn
                // by the node's own box (`NodeView.boxLook`).
                .frame(maxHeight: ownLook.height != nil || ownLook.minHeight != nil ? .infinity : nil)
                .background {
                    if let gradient {
                        GradientFill(gradient: gradient).clipShape(shape)
                    } else {
                        AnyShapeStyleFill(shape: shape, style: AnyShapeStyle(background?.color ?? .clear))
                    }
                }
                .overlay {
                    if let borderColor, borderWidth > 0 {
                        if DashedBorderRules.isDashed(style["border"]) {
                            DashedBorderOverlay(width: borderWidth, color: borderColor, radius: corners, rightToLeft: context.rightToLeft)
                        } else {
                            shape.inset(by: borderWidth / 2).stroke(borderColor.color, lineWidth: borderWidth)
                        }
                    }
                }
                .shadowLayers(ShadowTint.apply(resolver.shadow(style["shadow"]) ?? [], style: style, resolver: resolver), shape: shape)
                .glass(ownLook.backdropBlur, shape: shape, cover: gradient == nil ? background?.alpha ?? 0 : 0)
                .contentShape(shape)
            }
            .buttonStyle(PressFeedbackStyle(kind: PressFeedbackRules.kind(node)))
            .accessibilityLabel(label)
            .disabledControl(disabled)
        }
    }
}

/// A shape filled with any shape style (a colour or a gradient).
struct AnyShapeStyleFill: View {
    let shape: LogicalCornersShape
    let style: AnyShapeStyle
    var body: some View { shape.fill(style) }
}

struct PressedOpacity: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// `Spacer`: `horizontal` adds height (the form inside a column), `vertical` adds width and
/// is at least the `lg` step tall.
struct SpacerWidget: View {
    let node: DocumentNode
    let context: RenderContext

    var body: some View {
        let size = context.resolver.spacing(node.props["size"] ?? "md") ?? 12
        if node.props["orientation"]?.stringValue == "vertical" {
            Color.clear.frame(width: size).frame(minHeight: context.theme.coreSpacing("lg"))
        } else {
            Color.clear.frame(height: size)
        }
    }
}

/// `Divider`: a one-point line in its own colour (`props.color`, not the inherited text colour)
/// with its spacing along its axis.
struct DividerWidget: View {
    let node: DocumentNode
    let context: RenderContext

    var body: some View {
        let color = context.resolver.color(node.props["color"] ?? "border") ?? context.theme.coreColor("border")
        let spacing = context.resolver.spacing(node.props["spacing"] ?? "sm") ?? 8
        if node.props["orientation"]?.stringValue == "vertical" {
            Rectangle().fill(color.color).frame(width: 1).frame(minHeight: context.theme.coreSpacing("lg")).padding(.horizontal, spacing)
        } else {
            Rectangle().fill(color.color).frame(height: 1).frame(maxWidth: .infinity).padding(.vertical, spacing)
        }
    }
}

extension View {
    /// A disabled `Button` / `IconButton`: it does nothing (no action, no analytics event, no
    /// haptic request), stays in the order of the screen reader (announced as dimmed), and is drawn
    /// at half opacity whatever its role; its own opacity multiplies.
    func disabledControl(_ disabled: Bool) -> some View {
        self
            .disabled(disabled)
            // One composite at half opacity: without the group SwiftUI fades the fill and the label
            // one by one, and a label drawn over the fill is faded twice.
            .compositingGroup()
            .opacity(disabled ? InputRules.disabledOpacity : 1)
    }
}
