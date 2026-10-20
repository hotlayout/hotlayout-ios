import SwiftUI

/// What stands in the box of an icon: nothing (the node names no icon), a drawing of the set,
/// or an empty box of the same size (a name outside the set, a value that is not a string).
enum IconBoxState: String, Equatable {
    case none, drawn, empty
}

/// The icon of a node after the data was asked (`x-iconFromData`).
struct IconResolution: Equatable {
    /// The value taken as the icon name; `nil` when the node has no icon at all.
    var resolved: JSONValue?
    var box: IconBoxState

    /// The name of a drawn icon.
    var name: String? { box == .drawn ? resolved?.stringValue : nil }

}

/// A part of a text with an icon beside it.
enum BesidePart: String, Equatable {
    case text, icon
}

/// The rules of an icon beside a text: one rule for a button caption, a badge caption and the
/// trailing text of a list row (`x-style.layout.iconBesideText`).
enum IconBesideTextRules {
    static let gapToken = "xs"

    /// The icon of a node. The document's icon is read first: without it the node has no icon
    /// and the path is not read. Data replaces the name when it holds a value (`null`, absence
    /// and the empty string are «no value»); whatever the value is, it is the name, and a
    /// value that is not a drawable name gives an empty box.
    static func resolve(props: JSONObject, field: String = "icon", scope: DataScope) -> IconResolution {
        guard let own = props[field], !own.isNull else { return IconResolution(resolved: nil, box: .none) }
        var value = own
        if let path = props["iconPath"]?.stringValue, let fromData = scope[path], !fromData.isNull, fromData.stringValue != "" {
            value = fromData
        }
        let drawable = value.stringValue.map { IconSet.elements($0) != nil } ?? false
        return IconResolution(resolved: value, box: drawable ? .drawn : .empty)
    }

    /// The parts in reading order. A position word the reader does not know is `start`. SwiftUI
    /// lays them out in the reading direction of the screen.
    static func logicalOrder(icon: IconResolution, position: String?) -> [BesidePart] {
        guard icon.box != .none else { return [.text] }
        return position == "end" ? [.text, .icon] : [.icon, .text]
    }

    /// The icon box beside a text: as wide as the font size, as tall as the text line; it does
    /// not make the widget taller.
    static func glyphBox(_ typography: TextStyleValue) -> (glyph: Double, box: CGSize) {
        (typography.fontSize, CGSize(width: typography.fontSize, height: typography.lineBox))
    }
}

/// `Button` and `IconButton` sizes (`x-style.layout.buttonSizes`, `iconButton`).
enum ButtonGeometry {
    struct Size: Equatable {
        var paddingBlock: Double
        var paddingInline: Double
        var typography: String
        var paddingBlockToken: String
        var paddingInlineToken: String
    }

    static let sizes: [String: (block: String, inline: String, typography: String)] = [
        "sm": ("xs", "md", "bodyM"),
        "md": ("sm", "md", "titleS"),
        "lg": ("md", "lg", "titleM"),
    ]

    /// The size word, or `md` for no word and for a word of a newer minor.
    static func size(_ word: String?, theme: HotlayoutTheme) -> Size {
        let entry = sizes[word ?? "md"] ?? sizes["md"]!
        return Size(
            paddingBlock: theme.coreSpacing(entry.block), paddingInline: theme.coreSpacing(entry.inline),
            typography: entry.typography, paddingBlockToken: entry.block, paddingInlineToken: entry.inline
        )
    }

    /// The height of a button: the line of its text, the vertical padding and the border twice.
    static func height(_ size: Size, theme: HotlayoutTheme, border: Double) -> Double {
        theme.coreTypography(size.typography).lineBox + 2 * size.paddingBlock + 2 * border
    }

    /// The icon button: a square whose content box is the font line (or the number of
    /// `glyphSize`), padded by the vertical padding of the same size on all sides.
    static func iconButton(size word: String?, glyphSize: Double?, theme: HotlayoutTheme, border: Double) -> (side: Double, glyph: Double, padding: Double) {
        let size = size(word, theme: theme)
        let typography = theme.coreTypography(size.typography)
        let content = glyphSize.map { min(128, max(8, $0)) } ?? typography.lineBox
        return (content + 2 * size.paddingBlock + 2 * border, glyphSize.map { min(128, max(8, $0)) } ?? typography.fontSize, size.paddingBlock)
    }

    /// The accessible name of an icon button: the label, else the name of the icon in words.
    static func iconButtonName(label: String, iconName: JSONValue?) -> String {
        if !TextHeard.isSilent(label) { return label }
        guard let name = iconName?.stringValue else { return "" }
        return name.replacingOccurrences(of: "-", with: " ")
    }
}

/// Text nobody can see or hear (`heard-text`): spaces, format and control characters, combining
/// marks without a base, and the fillers that Unicode counts as letters.
enum TextHeard {
    static func isSilent(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(isSilentScalar)
    }

    static func isSilentScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .format, .control, .nonspacingMark, .enclosingMark: return true
        default: break
        }
        return [0x3164, 0x115F, 0x1160, 0xFFA0, 0x2800].contains(scalar.value)
    }
}

/// An icon beside a text, in the colour of the text, with the gap between, the box centred on
/// the line of the text. The order is logical: SwiftUI puts the parts in reading direction.
struct IconBesideText<Label: View>: View {
    let icon: IconResolution
    let position: String?
    let glyph: Double
    let box: CGSize
    let gap: Double
    let color: Color
    let rightToLeft: Bool
    @ViewBuilder let label: Label

    var body: some View {
        if icon.box == .none {
            label
        } else {
            let picture = IconGlyph(name: icon.name, glyph: glyph, box: box, color: color, rightToLeft: rightToLeft)
            HStack(spacing: gap) {
                if IconBesideTextRules.logicalOrder(icon: icon, position: position).first == .icon {
                    picture
                    label
                } else {
                    label
                    picture
                }
            }
        }
    }
}
