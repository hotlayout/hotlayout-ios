import Foundation

/// The box and the drawing of a widget that may name its own glyph size
/// (`x-style.layout.ownGlyphSize`; reference `iconGeometryOf` / `iconButtonGeometryOf`).
struct GlyphGeometry: Equatable {
    /// The side of the square the drawing is drawn in.
    var glyph: Double
    /// The content box, without padding and border.
    var content: CGSize
    /// The box of the node, with padding and border.
    var box: CGSize

    struct Input {
        var glyphSize: Double?
        var fontSize: Double
        /// The sum of the padding on both sides of each axis.
        var paddingInline: Double
        var paddingBlock: Double
        var borderWidth: Double
        var width: Double?
        var height: Double?
        /// The content box the word of the size gives (no own number).
        var word: CGSize
    }

    /// A whole number in 8…128, else no field (`unreadable: 'no-field'`).
    static func own(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value == value.rounded(), value >= 8, value <= 128 else { return nil }
        return value
    }

    static func of(_ input: Input) -> GlyphGeometry {
        let own = own(input.glyphSize)
        let insetInline = input.paddingInline + 2 * input.borderWidth
        let insetBlock = input.paddingBlock + 2 * input.borderWidth
        let natural = own.map { CGSize(width: $0, height: $0) } ?? input.word
        let content = CGSize(
            width: input.width.map { max(0, $0 - insetInline) } ?? natural.width,
            height: input.height.map { max(0, $0 - insetBlock) } ?? natural.height
        )
        let box = CGSize(width: input.width ?? content.width + insetInline, height: input.height ?? content.height + insetBlock)
        // With a word the drawing is the font size and a named box does not constrain it.
        guard let own else { return GlyphGeometry(glyph: input.fontSize, content: content, box: box) }
        let glyph = min(own, input.width == nil ? own : content.width, input.height == nil ? own : content.height)
        return GlyphGeometry(glyph: glyph, content: content, box: box)
    }
}
