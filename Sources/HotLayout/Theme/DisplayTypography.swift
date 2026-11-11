import Foundation

/// Display typography: how a large font size meets the system text scale, and tracking as a share
/// of the font size.
enum DisplayTypography {
    /// The largest font size of an override on a node. The theme keeps its own, smaller bound for its
    /// tokens (`ThemeNumbers.fontSize`): the theme names roles of text, a poster size is one node's decision.
    static let maxOverrideFontSize = 400.0
    /// A font size above this is not multiplied directly by the system text scale.
    static let scaleCeiling = 96.0
    static let minTrackingShare = -0.1
    static let maxTrackingShare = 0.5
    static let maxTextShadowLayers = 2

    /// The font size after the system text scale `scale`: `s <= 1 ? f * s : max(f, min(f, 96) * s)`. Up to the
    /// ceiling it is exactly `f * s`; above it the size grows no further than `96 * s` and is never below `f`.
    ///
    /// The reader draws with the sizes of the document as they are and does not multiply them by a system
    /// scale, which is the scale 1 of this rule.
    static func scaledFontSize(_ fontSize: Double, scale: Double) -> Double {
        if scale <= 1 { return fontSize * scale }
        return Swift.max(fontSize, Swift.min(fontSize, scaleCeiling) * scale)
    }

    /// The tracking in points for the EFFECTIVE font size: a share of it when the style gives
    /// `letterSpacingEm` (the share wins), else the pixels as written, which the scale does not multiply.
    static func trackingPx(letterSpacing: Double? = nil, letterSpacingEm: Double? = nil, effectiveFontSize: Double) -> Double {
        if let letterSpacingEm { return letterSpacingEm * effectiveFontSize }
        return letterSpacing ?? 0
    }

    /// The line block: the effective font size times the line height multiplier.
    static func lineBlock(fontSize: Double, lineHeight: Double, scale: Double) -> Double {
        scaledFontSize(fontSize, scale: scale) * lineHeight
    }
}

/// One layer of the shadow of a text: no spread, no inner form.
struct TextShadowLayer: Equatable, Sendable {
    var offsetX: Double
    var offsetY: Double
    var blur: Double
    var color: RGBA
}

/// `style.textShadow` (the field is read by `Text` only).
enum TextShadowRules {
    /// The layers a node paints: only `Text` reads the field.
    static func layers(type: String, style: JSONObject, resolver: StyleResolver) -> [TextShadowLayer]? {
        guard WidgetType(type) == .text, let value = style["textShadow"], !value.isNull else { return nil }
        return resolver.textShadow(value)
    }

    /// The layers from the one nearest to the text and on top, to the one nearest the page: the order a
    /// painter that draws the list from the bottom takes (`bottomFirst` of the table).
    static func bottomFirst(_ layers: [TextShadowLayer]) -> [TextShadowLayer] { Array(layers.reversed()) }
}
