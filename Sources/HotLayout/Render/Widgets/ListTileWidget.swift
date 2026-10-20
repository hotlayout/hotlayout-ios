import SwiftUI

/// `ListTile`: a leading slot, the texts and a trailing slot in one row. The row has one gap,
/// `sm`, on both sides; the trailing column never shrinks, the texts give way.
struct ListTileWidget: View {
    let node: DocumentNode
    let context: RenderContext

    /// The side of a thumbnail in a row, in `xl` units of the theme.
    static let thumbnailScale = 2.0

    private var theme: HotlayoutTheme { context.theme }
    private var resolver: StyleResolver { context.resolver }
    private var named: ListTileRules.NamedColor {
        ListTileRules.NamedColor(ref: context.inherited.colorRef ?? .null, named: context.inherited.colorRef != nil)
    }

    var body: some View {
        let gap = theme.coreSpacing("sm")
        let title = context.text(node, field: "title")
        let subtitle = node.props["subtitle"] == nil ? "" : context.text(node, field: "subtitle")
        let trailingKind = node.props["trailing"]?["kind"]?.stringValue ?? "chevron"
        let hasLeading = ["icon", "image"].contains((node.props["leading"] ?? ["kind": "icon"])["kind"]?.stringValue ?? "")
        let row = ListTileRowLayout(gap: gap) {
            if hasLeading { leading.layoutValue(key: ListTileColumnKey.self, value: .leading) }
            texts(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutValue(key: ListTileColumnKey.self, value: .body)
            if trailingKind != "none" { trailing(kind: trailingKind).layoutValue(key: ListTileColumnKey.self, value: .trailing) }
        }
        .frame(maxWidth: .infinity)

        if trailingKind == "radio" {
            // An option row belongs to the choice, period: its tap selects, and an `action` of the
            // row is not run. Outside a group the circle is drawn but nothing answers.
            if let choice = context.choice, let option = node.props["trailing"]?["optionValue"]?.stringValue {
                Button {
                    choice.select(option)
                } label: {
                    row.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel([title, subtitle].filter { !$0.isEmpty }.joined(separator: ", "))
                .accessibilityAddTraits(choice.selected == option ? .isSelected : [])
            } else {
                row.accessibilityElement(children: .combine)
            }
        } else if PressTarget.actsOnPress(node) {
            PressableCard(node: node, context: context, content: row)
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    // MARK: Colours and fonts

    private func color(_ ref: JSONValue) -> Color {
        (resolver.color(ref) ?? context.inherited.color).color
    }

    private func typography(_ ref: JSONValue, fallback: String) -> TextStyleValue {
        resolver.typography(ref) ?? theme.typography[fallback] ?? context.inherited.typography
    }

    private func isMet(_ condition: JSONValue) -> Bool {
        Conditions.holds(condition, scope: context.scope)
    }

    // MARK: Texts

    @ViewBuilder
    private func texts(title: String, subtitle: String) -> some View {
        let titleStyle = theme.typography["titleS"] ?? context.inherited.typography
        let subtitleStyle = theme.typography["bodyS"] ?? context.inherited.typography
        let subtitleColor =
            named.named
            ? PartStyleRules.withOpacity(named.ref, ListTileRules.secondaryOpacity)
            : JSONValue.string("muted")
        VStack(alignment: .leading, spacing: 0) {
            StyledText(
                text: title, style: titleStyle, color: context.inherited.color, theme: theme,
                maxLines: ListTileRules.lineLimit(node.props["titleMaxLines"])
            )
            if !subtitle.isEmpty {
                StyledText(
                    text: subtitle, style: subtitleStyle, color: resolver.color(subtitleColor) ?? context.inherited.color, theme: theme,
                    maxLines: ListTileRules.lineLimit(node.props["subtitleMaxLines"])
                )
            }
        }
    }

    // MARK: Leading

    @ViewBuilder
    private var leading: some View {
        let slot = node.props["leading"] ?? ["kind": "icon", "icon": "chevron"]
        switch slot["kind"]?.stringValue {
        case "icon":
            leadingIcon(slot)
        case "image":
            let side = Self.thumbnailScale * (theme.coreSpacing("xl"))
            let placeholder = theme.colorValue("muted")?.withOpacity(0.15).color ?? Color.gray.opacity(0.15)
            RemoteImage(url: ImageSource.url(slot["source"], context: context), fit: "cover", placeholder: placeholder, sink: context.sink)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: theme.coreRadius("sm")))
                .accessibilityHidden(true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func leadingIcon(_ slot: JSONValue) -> some View {
        let geometry = iconBox(size: "md", glyphSize: nil, theme: theme)
        let colorRef = ListTileRules.leadingIconColor(slot, context: named)
        let name = IconBesideTextRules.resolve(props: ["icon": slot["icon"] ?? .null], scope: [:]).name
        let glyph = IconGlyph(name: name, glyph: geometry.glyph, box: geometry.box, color: color(colorRef), rightToLeft: context.rightToLeft)
        if let tile = ListTileRules.tile(of: slot) {
            let box = ListTileRules.leadingBox(leading: slot, glyph: (Double(geometry.box.width), Double(geometry.box.height)))
            let radius = resolver.radius(tile.radius) ?? resolver.radius(ListTileRules.tileDefaultRadius) ?? 0
            ZStack(alignment: .topLeading) {
                glyph.fixedSize().offset(x: CGFloat(box.glyphInline), y: CGFloat(box.glyphBlock))
            }
            .frame(width: CGFloat(box.inline), height: CGFloat(box.block), alignment: .topLeading)
            .background(color(tile.color))
            .clipShape(RoundedRectangle(cornerRadius: radius))
        } else {
            glyph
        }
    }

    // MARK: Trailing

    @ViewBuilder
    private func trailing(kind: String) -> some View {
        let slot = node.props["trailing"] ?? ["kind": "chevron"]
        switch kind {
        case "text":
            trailingText(slot)
        case "radio":
            let size = iconBox(size: "md", glyphSize: nil, theme: theme).glyph
            let option = slot["optionValue"]?.stringValue
            let selected = option != nil && context.choice?.selected == option
            ChoiceOptionMark(
                selected: selected, size: size,
                selectedColor: (theme.coreColor("primary")).color,
                mutedColor: (theme.coreColor("muted")).color
            )
        case "none":
            EmptyView()
        default:
            let geometry = iconBox(size: "md", glyphSize: nil, theme: theme)
            let chevron = named.named ? PartStyleRules.withOpacity(named.ref, ListTileRules.secondaryOpacity) : JSONValue.string("muted")
            IconGlyph(name: "chevron", glyph: geometry.glyph, box: geometry.box, color: color(chevron), rightToLeft: context.rightToLeft)
        }
    }

    /// The trailing text with its icon beside it, over the caption; both stand at the end.
    @ViewBuilder
    private func trailingText(_ slot: JSONValue) -> some View {
        let look = ListTileRules.trailingTextLook(slot, context: named, isMet: isMet)
        let style = typography(look.typography, fallback: "bodyM")
        let textColor = resolver.color(look.color) ?? context.inherited.color
        let icon = IconBesideTextRules.resolve(props: slot.objectValue ?? JSONObject(), scope: context.scope)
        let iconBox = iconBox(size: "sm", glyphSize: nil, theme: theme)
        let caption = slot["caption"] == nil ? "" : captionText(slot)
        ListTileTrailingLayout {
            IconBesideText(
                icon: icon, position: "end", glyph: iconBox.glyph, box: iconBox.box, gap: theme.coreSpacing(IconBesideTextRules.gapToken),
                color: textColor.color, rightToLeft: context.rightToLeft
            ) {
                StyledText(text: context.text(node, subfield: "trailing.text"), style: style, color: textColor, theme: theme, maxLines: 1)
                    .fixedSize(horizontal: true, vertical: true)
            }
            if !caption.isEmpty {
                let captionLook = ListTileRules.captionLook(slot, context: named, isMet: isMet)
                StyledText(
                    text: caption, style: typography(captionLook.typography, fallback: "bodyS"),
                    color: resolver.color(captionLook.color) ?? context.inherited.color, theme: theme, maxLines: 1
                )
                .fixedSize(horizontal: true, vertical: true)
            }
        }
    }

    private func captionText(_ slot: JSONValue) -> String {
        context.text(node, subfield: "trailing.caption")
    }
}

extension RenderContext {
    /// The shown text of a string that lies in a slot of a node (`trailing.text`,
    /// `trailing.caption`); the translation key is `<screen>/<node>/<slot>.<field>`.
    func text(_ node: DocumentNode, subfield path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        let slot = parts.first ?? ""
        let field = parts.dropFirst().joined(separator: ".")
        let value = node.props[slot]?[field]
        let key = Localization.key(screenId: screenId, nodeId: node.id, field: path)
        let localization = self.localization
        let translation = locale.translation
        let language = TemplateLanguage(
            translationLocale: translation,
            sourceLocale: localization?.defaultLocale,
            translated: { sub in Localization.translate(localization, translation: translation, key: sub.isEmpty ? key : "\(key).\(sub)") }
        )
        return ShownText.of(
            BindableText.text(
                value, language: language, environment: textEnvironment, sink: sink, location: "screen “\(screenId)”: node “\(node.id)”: \(path)")
        )
    }
}
