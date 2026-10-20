import Foundation

/// The rules of the parts of a list row (`x-style.layout.listTileParts`, `partStyle`): pure
/// functions over the values of the document, measured by the shared table of cases.
enum ListTileRules {
    // MARK: Lines

    static let linesRange = 1...5

    /// The line limit the reader understands: a whole number in range; anything else is «no limit».
    static func lineLimit(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue, number.isFinite, let whole = SafeInt.exactly(number), linesRange.contains(whole) else { return nil }
        return whole
    }

    /// How many lines are drawn out of the natural ones, and whether the text is cut.
    static func shownLines(natural: Int, limit: JSONValue?) -> (lines: Int, cut: Bool) {
        guard let max = lineLimit(limit), natural > max else { return (natural, false) }
        return (max, true)
    }

    // MARK: Tile under the leading icon

    static let tileSize = 40.0
    static let tileSizeRange = 24.0...96.0
    static let tileDefaultRadius: JSONValue = "sm"

    struct Tile: Equatable {
        var color: JSONValue
        var radius: JSONValue
        var size: Double
    }

    /// The tile of a leading slot: only under an icon, only with a colour that can be read;
    /// a radius or a side of the wrong form is the default.
    static func tile(of leading: JSONValue?) -> Tile? {
        guard let leading = leading?.objectValue, leading["kind"]?.stringValue == "icon", let tile = leading["tile"]?.objectValue,
            let color = tile["color"], PartStyleRules.isColorRef(color)
        else { return nil }
        var radius = tileDefaultRadius
        if let value = tile["radius"] {
            if let token = value.stringValue, PartStyleRules.isTokenName(token) { radius = value }
            if let number = value.numberValue, number == number.rounded(), (0...256).contains(number) { radius = value }
        }
        var size = tileSize
        if let value = tile["size"]?.numberValue, value == value.rounded(), tileSizeRange.contains(value) { size = value }
        return Tile(color: color, radius: radius, size: size)
    }

    struct LeadingBox: Equatable {
        var inline: Double
        var block: Double
        var glyphInline: Double
        var glyphBlock: Double
    }

    /// The box of the leading icon: the box of the glyph, or the square of the tile with the
    /// glyph in its centre (a larger glyph is clipped: negative offsets).
    static func leadingBox(leading: JSONValue?, glyph: (inline: Double, block: Double)) -> LeadingBox {
        guard let tile = tile(of: leading) else { return LeadingBox(inline: glyph.inline, block: glyph.block, glyphInline: 0, glyphBlock: 0) }
        return LeadingBox(inline: tile.size, block: tile.size, glyphInline: (tile.size - glyph.inline) / 2, glyphBlock: (tile.size - glyph.block) / 2)
    }

    // MARK: The trailing column

    struct TrailingColumn: Equatable {
        var inline: Double
        var block: Double
        var textStart: Double
        var captionStart: Double?
    }

    /// The text line over the caption, both pushed to the end; no gap between them.
    static func trailingColumn(textInline: Double, textLine: Double, caption: (inline: Double, line: Double)?) -> TrailingColumn {
        let inline = max(textInline, caption?.inline ?? 0)
        return TrailingColumn(
            inline: inline, block: textLine + (caption?.line ?? 0), textStart: inline - textInline, captionStart: caption.map { inline - $0.inline })
    }

    // MARK: Three columns of a row

    struct Rect: Equatable {
        var x: Double, y: Double, width: Double, height: Double
    }

    struct RowRects: Equatable {
        var block: Double
        var leading: Rect?
        var body: Rect
        var trailing: Rect?
    }

    /// The leading and the trailing column take their own width, the texts take the rest (not
    /// less than zero); each is centred on the height of the row. `x` counts from the left edge:
    /// in right-to-left text the row is mirrored as a whole.
    static func rowRects(
        rowInline: Double, gap: Double, leading: (inline: Double, block: Double)?, trailing: (inline: Double, block: Double)?,
        bodyBlock: Double, rightToLeft: Bool
    ) -> RowRects {
        let block = max(leading?.block ?? 0, bodyBlock, trailing?.block ?? 0)
        let before = leading.map { $0.inline + gap } ?? 0
        let after = trailing.map { $0.inline + gap } ?? 0
        let bodyInline = max(0, rowInline - before - after)
        func place(_ start: Double, _ inline: Double, _ height: Double) -> Rect {
            Rect(x: rightToLeft ? rowInline - start - inline : start, y: (block - height) / 2, width: inline, height: height)
        }
        return RowRects(
            block: block,
            leading: leading.map { place(0, $0.inline, $0.block) },
            body: place(before, bodyInline, bodyBlock),
            trailing: trailing.map { place(before + bodyInline + gap, $0.inline, $0.block) }
        )
    }

    // MARK: Built-in look and the look of the parts

    static let leadingIconColor = "primary"
    static let trailingTextColor = "onSurface"
    static let trailingTextTypography = "bodyM"
    static let captionColor = "muted"
    static let captionTypography = "bodyS"
    /// The opacity of a secondary part under a named colour.
    static let secondaryOpacity = 0.6

    struct PartLook: Equatable {
        var color: JSONValue
        var typography: JSONValue
    }

    /// The colour the node names for its text, if it does (`colorNamed`).
    struct NamedColor {
        var ref: JSONValue
        var named: Bool
    }

    /// The trailing text: the colour is the state of the part, the style of the part, the named
    /// colour of the node, then `onSurface`; the font is the state, the style, then `bodyM`.
    static func trailingTextLook(_ trailing: JSONValue?, context: NamedColor, isMet: (JSONValue) -> Bool) -> PartLook {
        let own = PartStyleRules.resolve(trailing?["style"], trailing?["styleWhen"], isMet: isMet)
        return PartLook(
            color: own?.color ?? (context.named ? context.ref : JSONValue.string(trailingTextColor)),
            typography: own?.typography ?? JSONValue.string(trailingTextTypography)
        )
    }

    /// The caption: its own colour, else the named colour with the secondary opacity, else `muted`.
    /// The style of the text does not reach it.
    static func captionLook(_ trailing: JSONValue?, context: NamedColor, isMet: (JSONValue) -> Bool) -> PartLook {
        let own = PartStyleRules.resolve(trailing?["captionStyle"], trailing?["captionStyleWhen"], isMet: isMet)
        return PartLook(
            color: own?.color ?? (context.named ? PartStyleRules.withOpacity(context.ref, secondaryOpacity) : JSONValue.string(captionColor)),
            typography: own?.typography ?? JSONValue.string(captionTypography)
        )
    }

    /// The leading icon: its own colour, the named colour of the node, `primary`.
    static func leadingIconColor(_ leading: JSONValue?, context: NamedColor) -> JSONValue {
        if leading?["kind"]?.stringValue == "icon", let own = PartStyleRules.readColor(leading?["color"]) { return own }
        return context.named ? context.ref : JSONValue.string(leadingIconColor)
    }
}

/// The style of one part of a widget (`x-style.layout.partStyle`): a colour and a typography,
/// and the states that lay over them.
enum PartStyleRules {
    struct Style: Equatable {
        var color: JSONValue?
        var typography: JSONValue?
    }

    /// A token name: a lower-case letter and up to 39 letters and digits.
    static func isTokenName(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard (1...40).contains(scalars.count), let first = scalars.first, first.value >= 97, first.value <= 122 else { return false }
        return scalars.allSatisfy { ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
    }

    static func isColorRef(_ value: JSONValue) -> Bool {
        readColor(value) != nil
    }

    /// A colour of the form of the contract: a token, a token with opacity, an own `#rrggbb[aa]`.
    static func readColor(_ value: JSONValue?) -> JSONValue? {
        switch value {
        case .string(let token)?:
            return isTokenName(token) ? value : nil
        case .object(let object)?:
            let opacityOK = object["opacity"].map { $0.numberValue.map { (0...1).contains($0) } ?? false } ?? true
            if let token = object["token"]?.stringValue {
                return Set(object.keys) == ["token", "opacity"] && isTokenName(token) && opacityOK ? value : nil
            }
            if let hex = object["value"]?.stringValue {
                return Set(object.keys).isSubset(of: ["value", "opacity"]) && RGBA(hex: hex) != nil && opacityOK ? value : nil
            }
            return nil
        default:
            return nil
        }
    }

    static func readTypography(_ value: JSONValue?) -> JSONValue? {
        switch value {
        case .string(let token)?: return isTokenName(token) ? value : nil
        case .object(let object)?: return object["token"]?.stringValue.map(isTokenName) == true ? value : nil
        default: return nil
        }
    }

    /// Only the keys the reader understands; a value of the wrong form gives no key.
    static func read(_ value: JSONValue?) -> Style? {
        guard let object = value?.objectValue else { return nil }
        let style = Style(color: readColor(object["color"]), typography: readTypography(object["typography"]))
        return style.color == nil && style.typography == nil ? nil : style
    }

    /// The base style with the first state whose condition holds laid over it, key by key. A
    /// state that cannot be read is skipped before the choice.
    static func resolve(_ base: JSONValue?, _ cases: JSONValue?, isMet: (JSONValue) -> Bool) -> Style? {
        let own = read(base)
        let active = (cases?.arrayValue ?? []).compactMap { entry -> (when: JSONValue, style: Style)? in
            guard let when = entry["when"], let style = read(entry["style"]) else { return nil }
            return (when, style)
        }.first { isMet($0.when) }
        guard let active else { return own }
        return Style(color: active.style.color ?? own?.color, typography: active.style.typography ?? own?.typography)
    }

    /// A colour with the opacity multiplied: a token becomes a tinted token.
    static func withOpacity(_ ref: JSONValue, _ factor: Double) -> JSONValue {
        switch ref {
        case .string(let token):
            return .object(["token": .string(token), "opacity": .number(factor)])
        case .object(var object):
            object["opacity"] = .number((object["opacity"]?.numberValue ?? 1) * factor)
            return .object(object)
        default:
            return ref
        }
    }
}
