import Foundation

/// The parts of a text field (`x-style.layout.inputParts`): the look of the field's own box
/// (`fieldRadius`, `fieldBackground`, `fieldBorderColor`, `fieldBorderWidth`, `fieldHeight`),
/// a mark at each end of the box (`prefix`, `suffix`) and the character counter (`counter`).
/// The `style` of the node stays the box of the whole widget.
enum InputPartsRules {
    static let borderWidthRange = 1...4
    static let heightRange = 32...120
    /// The longest text of a mark, in code points; the reader draws the first ones.
    static let affixTextMax = 8
    static let counterSeparator = " / "
    static let defaultRadius = "sm"
    static let defaultBackground = "surface"
    static let defaultBorderColor = "border"
    static let gapToken = "sm"
    static let affixTypography = "bodyM"
    static let counterTypography = "bodyS"
    static let quietColor = "muted"

    private static func whole(_ value: JSONValue?, in range: ClosedRange<Int>) -> Int? {
        guard let number = value?.numberValue, number == number.rounded(), abs(number) < 1e15 else { return nil }
        guard let integer = Int(exactly: number) else { return nil }
        return range.contains(integer) ? integer : nil
    }

    /// The border the reader draws: a whole number from 1 to 4, else the built-in 1.
    static func borderWidth(_ value: JSONValue?) -> Double {
        Double(whole(value, in: borderWidthRange) ?? 1)
    }

    /// The named height of a field of one line (a whole number from 32 to 120); else natural.
    static func namedHeight(_ value: JSONValue?, lines: Int) -> Double? {
        guard lines == 1, let height = whole(value, in: heightRange) else { return nil }
        return Double(height)
    }

    /// The height of the box with its border: the named one, or two borders, two paddings and the lines.
    static func boxHeight(textLine: Double, paddingBlock: Double, lines: Int, height: JSONValue?, borderWidth: JSONValue?) -> Double {
        if let named = namedHeight(height, lines: lines) { return named }
        return 2 * Self.borderWidth(borderWidth) + 2 * paddingBlock + Double(lines) * textLine
    }

    /// The text of a mark as drawn: the first code points up to the limit.
    static func affixText(_ text: String) -> String {
        InputRules.clamp(text, maxLength: .number(Double(affixTextMax)))
    }

    /// A mark of a field.
    enum Affix: Equatable {
        case text(JSONValue?)
        case icon(String)
    }

    /// The mark a prop names: a text or an icon; any other form is no mark.
    static func affix(_ value: JSONValue?) -> Affix? {
        guard let object = value?.objectValue else { return nil }
        switch object["kind"]?.stringValue {
        case "text": return object["text"].map { .text($0) }
        case "icon": return object["icon"]?.stringValue.map { .icon($0) }
        default: return nil
        }
    }

    struct AffixRow: Equatable {
        var prefixStart: Double?
        var textStart: Double
        var textInline: Double
        var suffixStart: Double?
    }

    /// The row inside the box: edge, mark, gap, text, gap, mark, edge. A mark never shrinks; the
    /// text takes the rest. Starts are from the logical start of the box.
    static func affixRow(boxInline: Double, border: Double, paddingInline: Double, gap: Double, prefix: Double?, suffix: Double?) -> AffixRow {
        let edge = border + paddingInline
        let before = prefix.map { $0 + gap } ?? 0
        let after = suffix.map { $0 + gap } ?? 0
        let textStart = edge + before
        let textInline = max(0, boxInline - 2 * edge - before - after)
        return AffixRow(
            prefixStart: prefix == nil ? nil : edge, textStart: textStart, textInline: textInline,
            suffixStart: suffix == nil ? nil : textStart + textInline + gap
        )
    }

    /// The counter `3 / 280`, or nil when the word `counter` is not the literal `true` or there is no
    /// limit (a whole number from 1). The count is code points of the SHOWN text, cut by the limit.
    static func counterText(counter: JSONValue?, maxLength: JSONValue?, shown: String) -> String? {
        guard counter?.boolValue == true, let number = maxLength?.numberValue, number == number.rounded(), number >= 1, number < 1e15 else { return nil }
        let count = InputRules.clamp(shown, maxLength: maxLength).unicodeScalars.count
        return "\(count)\(counterSeparator)\(Int(number))"
    }

    struct NoteRow: Equatable {
        var noteInline: Double
        var counterStart: Double?
    }

    /// The row under the box: the note from the start, the counter at the end. The counter does not
    /// shrink; the note takes the rest.
    static func noteRow(rowInline: Double, gap: Double, counter: Double?) -> NoteRow {
        guard let counter else { return NoteRow(noteInline: rowInline, counterStart: nil) }
        return NoteRow(noteInline: max(0, rowInline - gap - counter), counterStart: max(0, rowInline - counter))
    }
}

/// Turns what a native text control reports (its text and whether part of it is still being
/// composed, `markedTextRange`) into the events of `InputRules`: while a character is composed the
/// intermediate text is only kept, and the committed text arrives once as `compositionEnd`.
struct CompositionTracker: Equatable {
    private(set) var composing = false

    /// The text of the control changed.
    mutating func changed(text: String, marked: Bool) -> [InputRules.Event] {
        switch (marked, composing) {
        case (true, false):
            composing = true
            return [.compositionStart, .input(text)]
        case (true, true):
            return [.input(text)]
        case (false, true):
            composing = false
            return [.compositionEnd(text)]
        case (false, false):
            return [.input(text)]
        }
    }

    /// The control lost the focus: a composition still open is committed by the platform.
    mutating func ended(text: String) -> [InputRules.Event] {
        guard composing else { return [] }
        composing = false
        return [.compositionEnd(text)]
    }
}
