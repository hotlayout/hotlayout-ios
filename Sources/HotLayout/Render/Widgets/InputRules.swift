import Foundation

/// Input fields (`TextField`, `Switch`, `Checkbox`): everything the readers must do identically
/// and that could be read two ways. No views here, so the shared table runs against it directly
/// (`x-style.layout.inputs`, `x-style.layout.form.number`).
///
/// There is no second write mechanism: the value of a field is a data path, reading goes through
/// the data layers, writing goes to the session of the reader and to the host at the same moment.
enum InputRules {
    // MARK: Value

    /// The path of a field: an object with `kind: "binding"` and a non-empty string `path`. Extra
    /// keys do not matter. Anything else means «no path»: the field works locally.
    static func path(of value: JSONValue?) -> String? {
        guard let object = value?.objectValue, object["kind"]?.stringValue == "binding",
            let path = object["path"]?.stringValue, !path.isEmpty
        else { return nil }
        return path
    }

    /// The field text of a layer value: a string as is, everything else is an empty field.
    static func text(of value: JSONValue?) -> String {
        value?.stringValue ?? ""
    }

    /// The flag of a layer value: on only for `true`.
    static func flag(of value: JSONValue?) -> Bool {
        value?.boolValue == true
    }

    /// `required` / `requiresFilled` count only as the literal `true`.
    static func isLiteralTrue(_ value: JSONValue?) -> Bool {
        value?.boolValue == true
    }

    /// The `fallback` string of a binding.
    static func fallback(of value: JSONValue?) -> String? {
        guard let object = value?.objectValue, object["kind"]?.stringValue == "binding" else { return nil }
        return object["fallback"]?.stringValue
    }

    // MARK: Limits

    static let minLines = 1
    static let maxLines = 8

    /// Cuts typed text to the limit in code points. A limit that is not a whole number above
    /// zero means no limit. A surrogate pair is never split; a composed character may be.
    static func clamp(_ text: String, maxLength: JSONValue?) -> String {
        guard let limit = ContractShapes.wholeNumber(maxLength, below: 1e15), limit >= 1 else { return text }
        let scalars = text.unicodeScalars
        if scalars.count <= limit { return text }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars.prefix(limit))
        return String(result)
    }

    /// How many lines the field has: a whole number within bounds is itself, otherwise one.
    static func lines(_ value: JSONValue?) -> Int {
        guard let count = ContractShapes.wholeNumber(value, below: 1e15), count >= minLines, count <= maxLines else { return 1 }
        return count
    }

    // MARK: Keyboard

    enum Keyboard: String, CaseIterable {
        case text, email, number, phone, url
    }

    /// The intent for a document word; absent or unknown is `text`.
    static func keyboard(_ word: JSONValue?) -> Keyboard {
        word?.stringValue.flatMap(Keyboard.init(rawValue:)) ?? .text
    }

    /// The effective keyboard: a numeric field is always `number`, a multi-line field reads no
    /// intent (`nil`).
    static func effectiveKeyboard(_ word: JSONValue?, lines: JSONValue?, numeric: Bool) -> Keyboard? {
        if numeric { return .number }
        return Self.lines(lines) > 1 ? nil : keyboard(word)
    }

    static func effectiveLines(_ lines: JSONValue?, numeric: Bool) -> Int {
        numeric ? 1 : Self.lines(lines)
    }

    static func isNumber(valueType: JSONValue?) -> Bool {
        valueType?.stringValue == "number"
    }

    /// Whether the content is left to right whatever the screen says: email, phone, address and
    /// number; text and multi-line follow the screen.
    static func contentIsLeftToRight(_ word: JSONValue?, lines: JSONValue?, numeric: Bool) -> Bool {
        guard let effective = effectiveKeyboard(word, lines: lines, numeric: numeric) else { return false }
        return effective != .text
    }

    // MARK: Keyboard action key

    enum KeyAction: String { case newline, next, done }

    struct Focusable: Equatable {
        var multiline: Bool
        var reachable: Bool
    }

    static func keyAction(_ fields: [Focusable], at index: Int) -> KeyAction {
        guard fields.indices.contains(index) else { return .done }
        if fields[index].multiline { return .newline }
        return nextIndex(fields, after: index) == nil ? .done : .next
    }

    /// The next reachable field after this one; the search never goes backwards.
    static func nextIndex(_ fields: [Focusable], after index: Int) -> Int? {
        guard index + 1 < fields.count else { return nil }
        return ((index + 1)..<fields.count).first { fields[$0].reachable }
    }

    // MARK: Error

    /// The error text that can be heard, in its shown form; `nil` is no error.
    static func error(_ text: String?) -> String? {
        guard let text, !TextHeard.isSilent(text) else { return nil }
        return ShownText.of(text)
    }

    // MARK: Text field state

    /// What a text field remembers between events.
    struct TextState: Equatable {
        var focused = false
        /// The person touched the field (focus or typing); before that it writes nothing.
        var touched = false
        /// A character is being composed (IME): intermediate text is not written.
        var composing = false
        /// What the field showed when the composition started: the committed text is compared with it,
        /// not with the intermediate text (a keyboard often commits the very text it last showed).
        var composeFrom: String?
        var held: Held?
    }

    /// Text typed by a person. `released`: the layer value changed since, so the typed text is
    /// shown while focused and need not be held afterwards.
    struct Held: Equatable {
        var text: String
        var from: String
        var released = false
    }

    enum Event: Equatable {
        case focus, blur, compositionStart
        case input(String)
        case compositionEnd(String)
        /// The platform filled a value without the person (autofill before the first touch).
        case platformFill(String)
    }

    /// One step of a text field: the new state and, maybe, a write.
    static func step(
        _ state: TextState, _ event: Event, bound: String, maxLength: JSONValue? = nil, disabled: Bool = false, hasPath: Bool = true
    ) -> (state: TextState, write: String?) {
        if disabled {
            return (TextState(touched: state.touched), nil)
        }
        let shown = shownText(state, bound: bound)

        func accept(_ raw: String, against before: String? = nil) -> (state: TextState, write: String?) {
            let text = clamp(raw, maxLength: maxLength)
            var next = state
            next.touched = true
            next.composing = false
            next.composeFrom = nil
            next.held = Held(text: text, from: bound)
            return (next, text == (before ?? shown) || !hasPath ? nil : text)
        }

        var next = state
        switch event {
        case .focus:
            next.focused = true
            next.touched = true
            next.held = state.held ?? Held(text: shown, from: bound)
            return (next, nil)
        case .blur:
            next.focused = false
            next.composing = false
            next.composeFrom = nil
            if state.held?.released == true { next.held = nil }
            return (next, nil)
        case .compositionStart:
            next.composing = true
            next.composeFrom = shown
            return (next, nil)
        case .input(let text):
            if state.composing {
                next.touched = true
                next.held = Held(text: text, from: bound)
                return (next, nil)
            }
            return accept(text)
        case .compositionEnd(let text):
            return accept(text, against: state.composeFrom)
        case .platformFill(let text):
            return state.touched ? accept(text) : (state, nil)
        }
    }

    /// What the field shows: while focused, the typed text; without focus, the typed text until
    /// the layer value changes, then the layers.
    static func shownText(_ state: TextState, bound: String) -> String {
        guard let held = state.held else { return bound }
        if state.focused { return held.text }
        return held.released || held.from != bound ? bound : held.text
    }

    /// The layer value CHANGED. Called as an event each time the value under the path becomes
    /// different, not as a comparison at paint time: that could not tell «A, B, A» from «unchanged».
    static func sync(_ state: TextState, bound: String) -> TextState {
        guard let held = state.held, !held.released, held.from != bound else { return state }
        var next = state
        if state.focused {
            next.held = Held(text: held.text, from: held.from, released: true)
        } else {
            next.held = nil
        }
        return next
    }

    // MARK: Switch and checkbox state

    struct ToggleState: Equatable {
        var heldOn: Bool?
        var heldFrom: Bool?
    }

    static func shownToggle(_ state: ToggleState, bound: Bool) -> Bool {
        guard let on = state.heldOn else { return bound }
        return state.heldFrom == bound ? on : bound
    }

    static func syncToggle(_ state: ToggleState, bound: Bool) -> ToggleState {
        guard state.heldOn != nil, state.heldFrom != bound else { return state }
        return ToggleState()
    }

    /// A press: the value flips relative to the SHOWN one and is written at once. A disabled
    /// control neither changes nor writes; without a path it changes but does not write.
    static func pressToggle(_ state: ToggleState, bound: Bool, disabled: Bool = false, hasPath: Bool = true) -> (state: ToggleState, write: Bool?) {
        if disabled { return (state, nil) }
        let on = !shownToggle(state, bound: bound)
        return (ToggleState(heldOn: on, heldFrom: bound), hasPath ? on : nil)
    }

    // MARK: Numeric field

    /// Zeros of the runs of digits a numeric field accepts: ASCII, Arabic-Indic, extended
    /// Arabic-Indic (`number.parse.digitZeros`).
    static let digitZeros: [UInt32] = [0x30, 0x660, 0x6F0]
    static let separators: [UInt32] = [46, 44, 1643]
    static let minus: [UInt32] = [45, 8722]
    static let trimmed: [UInt32] = [32, 160, 8239, 9]
    static let maxDigits = 15
    static let maxSafeInteger = 9_007_199_254_740_991.0

    private static func digit(_ code: UInt32) -> Int? {
        for zero in digitZeros where code >= zero && code <= zero + 9 { return Int(code - zero) }
        return nil
    }

    private static func canonical(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }

    /// Typed text to a number, or `nil` for «not a number». A rule of its own, not `Double(_:)`:
    /// that accepts `1e5` and `NaN` and does not know `1,5` or Arabic digits. Edges trimmed; an
    /// optional minus; digits; an optional single separator and digits; at least one digit; at
    /// most fifteen digits in all. No groups, no exponent. Minus zero is zero.
    static func parseNumber(_ text: String) -> Double? {
        let chars = text.unicodeScalars.map(\.value)
        var start = 0
        var end = chars.count
        while start < end, trimmed.contains(chars[start]) { start += 1 }
        while end > start, trimmed.contains(chars[end - 1]) { end -= 1 }
        var negative = false
        if start < end, minus.contains(chars[start]) {
            negative = true
            start += 1
        }
        var whole = ""
        var fraction = ""
        var separated = false
        for index in start..<max(start, end) {
            let code = chars[index]
            if let digit = digit(code) {
                if separated { fraction += String(digit) } else { whole += String(digit) }
                continue
            }
            if !separated, separators.contains(code) {
                separated = true
                continue
            }
            return nil
        }
        let digits = whole.count + fraction.count
        guard digits > 0, digits <= maxDigits else { return nil }
        let form = "\(whole.isEmpty ? "0" : whole)\(fraction.isEmpty ? "" : "." + fraction)"
        guard let value = Double(form) else { return nil }
        if value == 0 { return 0 }
        return canonical(negative ? -value : value)
    }

    /// A number from a layer value: a finite number within the safe-integer range is itself;
    /// everything else, even `"12"`, is «no number». The field does not convert a string.
    static func readNumber(_ value: JSONValue?) -> Double? {
        guard let number = value?.numberValue, abs(number) <= maxSafeInteger else { return nil }
        return canonical(number)
    }

    /// What a numeric field shows for a number from data: ASCII digits, a full stop, no groups
    /// and no language; a whole number has no `.0`. A value that would need an exponent
    /// (magnitude below 10^-6) and «no number» both give an empty field.
    static func numberText(_ value: JSONValue?) -> String {
        guard let number = readNumber(value) else { return "" }
        if number == number.rounded() { return Int64(exactly: number).map(String.init) ?? "" }
        var text = "\(number)"
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            guard let exponent = Int(text[text.index(after: e)...]) else { return "" }
            if exponent >= 0 || exponent < -6 { return "" }
            var mantissa = String(text[..<e])
            let negative = mantissa.hasPrefix("-")
            if negative { mantissa.removeFirst() }
            let digits = mantissa.replacingOccurrences(of: ".", with: "")
            text = "\(negative ? "-" : "")0.\(String(repeating: "0", count: -exponent - 1))\(digits)"
        }
        return text
    }

    /// The number of typed text, or `""`, as it goes into the record.
    static func writtenNumber(_ text: String) -> JSONValue {
        parseNumber(text).map(JSONValue.number) ?? .string("")
    }

    /// What a numeric field shows. While focused, the typed text. Without focus, the typed text
    /// until its number equals the layers' number; otherwise the layers' number. NUMBERS are
    /// compared, not texts, so a numeric field needs no sync events.
    static func shownNumber(_ state: TextState, bound: JSONValue?) -> String {
        guard let held = state.held else { return numberText(bound) }
        if state.focused { return held.text }
        let layers = readNumber(bound).map(JSONValue.number) ?? .string("")
        return writtenNumber(held.text) == layers ? held.text : numberText(bound)
    }

    /// A numeric field holding a non-number: in the error state when it is not focused and the
    /// shown text is non-empty and not a number. The reader adds no text.
    static func numberInvalid(_ state: TextState, bound: JSONValue?) -> Bool {
        if state.focused { return false }
        let shown = shownNumber(state, bound: bound)
        if shown.unicodeScalars.allSatisfy({ trimmed.contains($0.value) }) { return false }
        return parseNumber(shown) == nil
    }

    /// One step of a numeric field, a mirror of `step`. A number is written when the typed text
    /// is a number, and `""` when the field was erased or the typed text is not a number. The same
    /// number is not written twice.
    static func stepNumber(
        _ state: TextState, _ event: Event, bound: JSONValue?, maxLength: JSONValue? = nil, disabled: Bool = false, hasPath: Bool = true
    ) -> (state: TextState, write: JSONValue?) {
        // `JSONValue` is expressible by `nil` (it is JSON null): «no write» is spelled out.
        let noWrite: JSONValue? = Optional<JSONValue>.none
        if disabled {
            return (TextState(touched: state.touched), noWrite)
        }
        let shown = shownNumber(state, bound: bound)

        func accept(_ raw: String, against before: String? = nil) -> (state: TextState, write: JSONValue?) {
            let text = clamp(raw, maxLength: maxLength)
            var next = state
            next.touched = true
            next.composing = false
            next.composeFrom = nil
            next.held = Held(text: text, from: shown)
            let value = writtenNumber(text)
            return (next, value == writtenNumber(before ?? shown) || !hasPath ? noWrite : value)
        }

        var next = state
        switch event {
        case .focus:
            next.focused = true
            next.touched = true
            next.held = state.held ?? Held(text: shown, from: shown)
            return (next, noWrite)
        case .blur:
            next.focused = false
            next.composing = false
            return (next, noWrite)
        case .compositionStart:
            next.composing = true
            next.composeFrom = shown
            return (next, noWrite)
        case .input(let text):
            if state.composing {
                next.touched = true
                next.held = Held(text: text, from: shown)
                return (next, noWrite)
            }
            return accept(text)
        case .compositionEnd(let text):
            return accept(text, against: state.composeFrom)
        case .platformFill(let text):
            return state.touched ? accept(text) : (state, noWrite)
        }
    }

    // MARK: Disabled

    /// The opacity of a disabled field, button or control: one value, the whole widget.
    static let disabledOpacity = 0.5

    /// Whether `disabledIf` holds. No condition means enabled; an operator the reader does not
    /// know means enabled; a missing value follows `missingConditionValue`.
    static func isDisabled(_ condition: JSONValue?, scope: DataScope) -> Bool {
        Conditions.understoodHolds(condition, scope: scope)
    }

    // MARK: Geometry (`x-style.layout.inputs`)

    static let fieldBorderWidth = 1.0
    static let switchTrackWidth = 52.0
    static let switchTrackHeight = 32.0
    static let switchThumbSize = 24.0
    static let switchThumbInset = 4.0
    static let checkboxBoxSize = 20.0
    static let checkboxBoxRadius = 4.0
    static let checkboxBorderWidth = 2.0
    static let checkboxMarkSize = 16.0

    struct Metrics {
        var labelLine: Double
        var textLine: Double
        var noteLine: Double
        var gap: Double
        var paddingBlock: Double
        var border: Double
    }

    static func boxHeight(_ metrics: Metrics, lines: JSONValue?) -> Double {
        2 * metrics.border + 2 * metrics.paddingBlock + Double(Self.lines(lines)) * metrics.textLine
    }

    static func fieldHeight(_ metrics: Metrics, lines: JSONValue?, labelLines: Int, noteLines: Int) -> Double {
        let label = Double(labelLines) * metrics.labelLine
        let note = noteLines == 0 ? 0 : metrics.gap + Double(noteLines) * metrics.noteLine
        return label + metrics.gap + boxHeight(metrics, lines: lines) + note
    }

    static func switchHeight(labelLine: Double, labelLines: Int) -> Double {
        max(switchTrackHeight, labelLine * Double(labelLines))
    }

    static func switchLabelWidth(row: Double, gap: Double) -> Double {
        max(0, row - switchTrackWidth - gap)
    }

    static func checkboxHeight(labelLine: Double, labelLines: Int) -> Double {
        max(checkboxBoxSize, labelLine * Double(labelLines))
    }

    static func checkboxLabelWidth(row: Double, gap: Double) -> Double {
        max(0, row - checkboxBoxSize - gap)
    }

    /// The offset of the checkbox square from the top: it is centred on the first line of the
    /// label; a shorter line leaves it at the top.
    static func checkboxBoxOffset(labelLine: Double) -> Double {
        max(0, (labelLine - checkboxBoxSize) / 2)
    }

    /// The distance of the thumb from the start of the track in the writing direction.
    static func thumbOffset(on: Bool) -> Double {
        on ? switchTrackWidth - switchThumbInset - switchThumbSize : switchThumbInset
    }
}
