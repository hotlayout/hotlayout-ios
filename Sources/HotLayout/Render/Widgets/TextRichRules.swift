import Foundation

// Rules of composed text, text emphasis, list markers and the gradient on glyphs. Everything
// here is a plain function of document values and numbers, so the shared case tables run
// against it without a view; the SwiftUI drawing is in `TextRichWidget.swift`.

// MARK: - Emphasis (9.17.0)

/// The slant and the line of a text at a point of the tree: both words are resolved. The root
/// is `normal` and `none`.
struct TextEmphasis: Equatable {
    var fontStyle = "normal"
    var textDecoration = "none"

    static let root = TextEmphasis()
}

/// The emphasis of one run: the text emphasis with the fields of the part laid over it, and the
/// number of the part's weight word (`nil`: the font style of the run gives the weight).
struct RunEmphasis: Equatable {
    var fontStyle: String
    var textDecoration: String
    var weight: Int?
}

enum TextEmphasisRules {
    static let weights: [String: Int] = ["regular": 400, "medium": 500, "semibold": 600, "bold": 700]

    /// A word of `fontStyle`, or `nil` (`unknownWord: 'field-not-applied'`).
    static func fontStyle(_ value: JSONValue?) -> String? {
        guard let word = value?.stringValue, word == "normal" || word == "italic" else { return nil }
        return word
    }

    static func decoration(_ value: JSONValue?) -> String? {
        guard let word = value?.stringValue, word == "none" || word == "underline" || word == "lineThrough" else { return nil }
        return word
    }

    static func weightWord(_ value: JSONValue?) -> String? {
        guard let word = value?.stringValue, weights[word] != nil else { return nil }
        return word
    }

    /// The emphasis after a node: each field is the nearest named one.
    static func inherit(_ parent: TextEmphasis, style: JSONObject?) -> TextEmphasis {
        TextEmphasis(
            fontStyle: fontStyle(style?["fontStyle"]) ?? parent.fontStyle,
            textDecoration: decoration(style?["textDecoration"]) ?? parent.textDecoration
        )
    }

    /// The emphasis of a run: the part replaces each of its fields on its own.
    static func run(_ text: TextEmphasis, span: TextSpanStyle?) -> RunEmphasis {
        RunEmphasis(
            fontStyle: span?.fontStyle ?? text.fontStyle,
            textDecoration: span?.textDecoration ?? text.textDecoration,
            weight: span?.weightWord.flatMap { weights[$0] }
        )
    }
}

// MARK: - Composed text (9.6.0, parts 9.19.0)

/// The own style of a part of a text. A `nil` field is «not named»: it stays as the text has it.
struct TextSpanStyle: Equatable {
    var color: JSONValue?
    var typography: JSONValue?
    var weightWord: String?
    var fontStyle: String?
    var textDecoration: String?
    var parts: [FormatPart: TextSpanStyle] = [:]

    /// This style with the fields of `part` laid over it.
    func overlaid(_ part: TextSpanStyle) -> TextSpanStyle {
        TextSpanStyle(
            color: part.color ?? color,
            typography: part.typography ?? typography,
            weightWord: part.weightWord ?? weightWord,
            fontStyle: part.fontStyle ?? fontStyle,
            textDecoration: part.textDecoration ?? textDecoration
        )
    }

    var namesColor: Bool { color != nil }

    /// What the reader has read, in the form the artifact and the case tables use.
    var json: JSONValue {
        var object = JSONObject()
        if let color { object["color"] = color }
        if let typography { object["typography"] = typography }
        if let weightWord { object["weight"] = .string(weightWord) }
        if let fontStyle { object["fontStyle"] = .string(fontStyle) }
        if let textDecoration { object["textDecoration"] = .string(textDecoration) }
        if !parts.isEmpty {
            var inner = JSONObject()
            for part in [FormatPart.fraction, .currency] { if let style = parts[part] { inner[part.rawValue] = style.json } }
            object["parts"] = .object(inner)
        }
        return .object(object)
    }
}

/// A piece of rich text: what is written, the place whose style it takes and, inside a number,
/// the part whose own style it takes.
struct TextSpanRun: Equatable {
    var text: String
    var span: String?
    var part: FormatPart?
}

enum TextSpans {
    private static let tokenName = try! NSRegularExpression(pattern: "^[a-z][a-zA-Z0-9]{0,39}$")
    private static let placeName = try! NSRegularExpression(pattern: "^\(BindableText.namePattern)$")
    private static let hexColor = try! NSRegularExpression(pattern: "^#[0-9a-fA-F]{6}$")

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func isTokenName(_ value: JSONValue?) -> Bool {
        value?.stringValue.map { matches(tokenName, $0) } ?? false
    }

    /// A readable colour reference by SHAPE (whether the theme has the token is another question).
    static func readableColor(_ value: JSONValue?) -> JSONValue? {
        guard let value else { return nil }
        if isTokenName(value) { return value }
        guard let object = value.objectValue else { return nil }
        if let own = object["value"], !own.isNull {
            guard let hex = own.stringValue, matches(hexColor, hex) else { return nil }
            if let opacity = object["opacity"], !opacity.isNull, !(opacity.numberValue.map { (0...1).contains($0) } ?? false) { return nil }
            return value
        }
        guard isTokenName(object["token"]), let opacity = object["opacity"]?.numberValue, (0...1).contains(opacity) else { return nil }
        return value
    }

    static func readableTypography(_ value: JSONValue?) -> JSONValue? {
        guard let value else { return nil }
        if isTokenName(value) { return value }
        guard let object = value.objectValue, isTokenName(object["token"]) else { return nil }
        return value
    }

    /// The five fields of a style, each read on its own; `nil` when none is readable.
    private static func fields(_ object: JSONObject) -> TextSpanStyle? {
        let style = TextSpanStyle(
            color: readableColor(object["color"]),
            typography: readableTypography(object["typography"]),
            weightWord: TextEmphasisRules.weightWord(object["weight"]),
            fontStyle: TextEmphasisRules.fontStyle(object["fontStyle"]),
            textDecoration: TextEmphasisRules.decoration(object["textDecoration"])
        )
        if style.color == nil && style.typography == nil && style.weightWord == nil && style.fontStyle == nil && style.textDecoration == nil { return nil }
        return style
    }

    private static func readParts(_ value: JSONValue?) -> [FormatPart: TextSpanStyle] {
        guard let object = value?.objectValue else { return [:] }
        var parts: [FormatPart: TextSpanStyle] = [:]
        for (name, entry) in object {
            guard let part = FormatPart(rawValue: name), let style = entry.objectValue.flatMap(fields) else { continue }
            parts[part] = style
        }
        return parts
    }

    /// `Text.spans` as the reader reads it: tolerantly, field by field, never failing. A key that
    /// is not a place name, or a style with nothing readable, is not a part.
    static func read(_ value: JSONValue?) -> [String: TextSpanStyle] {
        guard let object = value?.objectValue else { return [:] }
        var spans: [String: TextSpanStyle] = [:]
        for (name, entry) in object {
            guard matches(placeName, name), let style = entry.objectValue else { continue }
            let own = fields(style)
            let parts = readParts(style["parts"])
            if own == nil && parts.isEmpty { continue }
            var read = own ?? TextSpanStyle()
            read.parts = parts
            spans[name] = read
        }
        return spans
    }

    /// The styles that apply: only for places `content` declares among its own `values`.
    static func active(content: JSONValue?, spans: [String: TextSpanStyle]) -> [String: TextSpanStyle] {
        guard !spans.isEmpty, content?["kind"]?.stringValue == "template", let values = content?["values"]?.objectValue else { return [:] }
        return spans.filter { values[$0.key] != nil }
    }

    /// Styled runs: empty ones dropped, neighbours of the same place (and part) merged. Merging
    /// is part of the rule: the number of runs is observable.
    static func runs(_ runs: [TemplateRun], active: [String: TextSpanStyle]) -> [TextSpanRun] {
        var result: [TextSpanRun] = []
        for run in runs where !run.text.isEmpty {
            let span = run.place.flatMap { active[$0] != nil ? $0 : nil }
            let part = span.flatMap { name in run.part.flatMap { active[name]?.parts[$0] != nil ? $0 : nil } }
            if let last = result.last, last.span == span, last.part == part {
                result[result.count - 1].text += run.text
            } else {
                result.append(TextSpanRun(text: run.text, span: span, part: part))
            }
        }
        return result
    }

    /// The style a run is drawn with over the text's: the place, with the style of its part laid
    /// over it; `nil` for the style of the text itself.
    static func style(of run: TextSpanRun, active: [String: TextSpanStyle]) -> TextSpanStyle? {
        guard let span = run.span, let place = active[span] else { return nil }
        guard let part = run.part, let own = place.parts[part] else { return place }
        return place.overlaid(own)
    }

    /// The key a style has in the line strut: `place` or `place.part`.
    static func key(_ place: String, _ part: FormatPart?) -> String {
        part.map { "\(place).\($0.rawValue)" } ?? place
    }

    /// Every declared style (a place and each of its parts, the part over the place) by strut key.
    static func declared(_ active: [String: TextSpanStyle]) -> [(key: String, style: TextSpanStyle)] {
        var result: [(key: String, style: TextSpanStyle)] = []
        for name in active.keys.sorted() {
            let place = active[name]!
            result.append((name, place))
            for part in [FormatPart.fraction, .currency] {
                if let own = place.parts[part] { result.append((key(name, part), place.overlaid(own))) }
            }
        }
        return result
    }
}

// MARK: - Line pitch

/// A font size in logical points and the multiplier of the line it sets.
struct LineMetric: Equatable {
    var fontSize: Double
    var lineHeight: Double
    var block: Double { fontSize * lineHeight }
}

struct RichTextStrut: Equatable {
    var span: String?
    var lineBlock: Double
}

enum RichText {
    /// The pitch of EVERY line of the paragraph: the tallest line (size × multiplier) among the
    /// base style and ALL declared parts, whether or not the shown string mentions them. A tie
    /// goes to the larger font size, then to the base style, then to the name in ascending order.
    static func strut(base: LineMetric, spans: [String: LineMetric]) -> RichTextStrut {
        var best: (span: String?, metric: LineMetric) = (nil, base)
        for name in spans.keys.sorted(by: { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }) {
            let metric = spans[name]!
            if metric.block > best.metric.block || (metric.block == best.metric.block && metric.fontSize > best.metric.fontSize) {
                best = (name, metric)
            }
        }
        return RichTextStrut(span: best.span, lineBlock: best.metric.block)
    }
}

// MARK: - List marker (9.17.0)

enum DrawnMarker: Equatable {
    case bullet, number
}

/// Column, gap and hanging indent of a list item, in points.
struct ListMarkerGeometry: Equatable {
    var column: Double
    var gap: Double
    var indent: Double
}

/// Where the marker box and the text column lie along the line, measured from the LEFT edge of
/// the node, whatever the writing direction.
struct ListMarkerLayout: Equatable {
    var markerFrom: Double
    var markerTo: Double
    var textFrom: Double
    var textTo: Double
    var textInline: Double
    var markerOnRight: Bool
    var block: Double?
    var markerDrawn: Bool
}

enum ListMarkerRules {
    static let bullet = "\u{2022}"
    static let suffix = "."
    static let bulletColumn = 1.0
    static let digit = 0.6
    static let suffixColumn = 0.4
    static let minColumn = 1.0
    static let gap = 0.5

    /// The marker the field draws: `none`, an unknown word and a non-string are no marker.
    static func drawn(_ value: JSONValue?) -> DrawnMarker? {
        switch value?.stringValue {
        case "bullet": return .bullet
        case "number": return .number
        default: return nil
        }
    }

    private static func round6(_ value: Double) -> Double { (value * 1e6).rounded() / 1e6 }

    /// The column in fractions of the font size; a number is `max(1, 0.6 × digits + 0.4)`.
    static func geometry(_ marker: DrawnMarker, fontSize: Double, groupSize: Int = 1) -> ListMarkerGeometry {
        let size = fontSize.isFinite && fontSize > 0 ? fontSize : 0
        let em: Double
        switch marker {
        case .bullet: em = bulletColumn
        case .number: em = max(minColumn, Double(String(max(1, groupSize)).count) * digit + suffixColumn)
        }
        let column = round6(em * size)
        let space = round6(gap * size)
        return ListMarkerGeometry(column: column, gap: space, indent: round6(column + space))
    }

    /// The first and the last index of the run of numbered items around `index`, or `nil`.
    private static func run(_ markers: [DrawnMarker?], _ index: Int) -> ClosedRange<Int>? {
        guard markers[index] == .number else { return nil }
        var first = index
        while first > 0 && markers[first - 1] == .number { first -= 1 }
        var last = index
        while last < markers.count - 1 && markers[last + 1] == .number { last += 1 }
        return first...last
    }

    /// How many items the group of a numbered item has BY THE DOCUMENT, hidden ones included.
    static func groupSize(_ markers: [DrawnMarker?], at index: Int) -> Int? {
        run(markers, index)?.count
    }

    /// The number of a numbered item: the visible items of its group up to and including it. A
    /// hidden item takes no number; for itself it is the number it would have if shown.
    static func number(_ markers: [DrawnMarker?], at index: Int, visible: [Bool]) -> Int? {
        guard let group = run(markers, index) else { return nil }
        return (group.lowerBound..<index).filter { visible[$0] }.count + 1
    }

    /// What the marker says: «•» or the number in the digits of the formatting language, and a
    /// period. A language the platform has no data for gets plain digits.
    static func text(_ marker: DrawnMarker, number: Int, formattingLocale: String?) -> String {
        if marker == .bullet { return bullet }
        let environment = TextEnvironment(scope: [:], formattingLocale: formattingLocale, fallbackLocale: nil)
        let digits =
            BindingFormat.pieces(.number(Double(number)), binding: ["format": "number"], environment: environment)?.map(\.text).joined() ?? String(number)
        return digits + suffix
    }

    /// The boxes of an item across a place `placeInline` wide.
    static func layout(
        _ marker: DrawnMarker, fontSize: Double, groupSize: Int, placeInline: Double, rightToLeft: Bool, lines: Int? = nil, maxLines: Int? = nil,
        lineBlock: Double? = nil
    ) -> ListMarkerLayout {
        let metrics = geometry(marker, fontSize: fontSize, groupSize: groupSize)
        let textInline = round6(placeInline - metrics.indent)
        var block: Double?
        if let lines, let lineBlock { block = Double(maxLines.map { min(lines, $0) } ?? lines) * lineBlock }
        if rightToLeft {
            return ListMarkerLayout(
                markerFrom: round6(placeInline - metrics.column), markerTo: placeInline, textFrom: 0, textTo: textInline, textInline: textInline,
                markerOnRight: true, block: block, markerDrawn: true)
        }
        return ListMarkerLayout(
            markerFrom: 0, markerTo: metrics.column, textFrom: metrics.indent, textTo: placeInline, textInline: textInline, markerOnRight: false, block: block,
            markerDrawn: true)
    }

    /// The width an item wants in a row: the column, the gap and the text.
    static func naturalInline(_ marker: DrawnMarker, fontSize: Double, groupSize: Int, textNaturalInline: Double) -> Double {
        round6(geometry(marker, fontSize: fontSize, groupSize: groupSize).indent + textNaturalInline)
    }
}

// MARK: - Gradient on glyphs (9.23.0)

enum TextGradientRules {
    /// The gradient reference that paints the letters of a node: `Text` only, from its own
    /// effective style (the field is not inherited). The reference is still to be resolved by the
    /// theme: an unknown token or stops out of order give the colour.
    static func reference(type: String, style: JSONObject) -> JSONValue? {
        guard type == "Text", let value = style["textGradient"], !value.isNull else { return nil }
        return value
    }

    /// Whether the pieces of a place take the gradient: with no gradient none does; a part that
    /// names its own colour keeps it. The text itself (`nil`) always takes it.
    static func takes(gradient: Bool, span: TextSpanStyle?) -> Bool {
        gradient && !(span?.namesColor ?? false)
    }
}
