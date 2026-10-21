import Foundation

/// The language of a string: the locale-rule answers and the translation table of its place.
struct TemplateLanguage {
    /// The shown translation language (`translation`); `nil` for a document without localization.
    var translationLocale: String?
    /// The document's source language.
    var sourceLocale: String?
    /// The translation in the shown language by a path INSIDE the value (`template`,
    /// `values.unit.forms.few`); the empty path is the literal itself.
    var translated: (String) -> String?

    init(translationLocale: String?, sourceLocale: String?, translated: @escaping (String) -> String?) {
        self.translationLocale = translationLocale
        self.sourceLocale = sourceLocale
        self.translated = translated
    }

    static let none = TemplateLanguage(translationLocale: nil, sourceLocale: nil, translated: { _ in nil })

    var showsSource: Bool { translationLocale == sourceLocale }
}

/// A piece of a string's text: what is written and from which declared place.
struct TemplateRun: Equatable, Sendable {
    let text: String
    /// The template value the piece comes from; `nil` is the literal text of the string.
    let place: String?
    let part: FormatPart?

    init(text: String, place: String?, part: FormatPart? = nil) {
        self.text = text
        self.place = place
        self.part = part
    }
}

/// Strings of a document: a literal, a binding or a template, and how each becomes text.
enum BindableText {
    static let namePattern = "[a-z][A-Za-z0-9]{0,23}"
    private static let placeholder = try! NSRegularExpression(pattern: "\\{(\(namePattern))\\}")
    private static let numericFallback = try! NSRegularExpression(pattern: "^-?\\d+(\\.\\d+)?$")

    /// The text of any document string.
    static func text(
        _ value: JSONValue?, language: TemplateLanguage, environment: TextEnvironment, sink: ReportSink? = nil, location: String = "text"
    ) -> String {
        runs(value, language: language, environment: environment, sink: sink, location: location).map(\.text).joined()
    }

    /// The text as runs (composed text): pieces in the logical order of the shown string.
    static func runs(
        _ value: JSONValue?, language: TemplateLanguage, environment: TextEnvironment, sink: ReportSink? = nil, location: String = "text"
    ) -> [TemplateRun] {
        guard let object = value?.objectValue else {
            // A string where a bindable string stands is read as a literal: an older shape.
            if let text = value?.stringValue { return [TemplateRun(text: text, place: nil)] }
            return []
        }
        switch object["kind"]?.stringValue {
        case "literal":
            let own = asText(object["value"])
            let translated = language.showsSource ? nil : language.translated("")
            return [TemplateRun(text: translated ?? own, place: nil)]
        case "binding":
            return boundPieces(object, environment: environment).map { TemplateRun(text: $0.text, place: nil, part: $0.part) }
        case "template":
            return templateRuns(object, language: language, environment: environment, sink: sink, location: location)
        default:
            // A string of an unfamiliar kind is drawn empty (`unknownStringKind: 'render-empty'`).
            sink?.add(.ignoredInput, location, "a string of an unknown kind is drawn empty")
            return []
        }
    }

    /// The text of ONE binding. No data, an empty string or a value that is not a string,
    /// number or flag gives the fallback, which is never formatted (`emptyBoundString`).
    static func boundPieces(_ binding: JSONObject, environment: TextEnvironment) -> [FormattedPiece] {
        let fallback = asText(binding["fallback"])
        guard let path = binding["path"]?.stringValue, let raw = environment.scope[path] else { return [FormattedPiece(fallback)] }
        switch raw {
        case .null, .array, .object: return [FormattedPiece(fallback)]
        case .string(let text) where text.isEmpty: return [FormattedPiece(fallback)]
        default: break
        }
        return BindingFormat.pieces(raw, binding: binding, environment: environment) ?? [FormattedPiece(asText(raw))]
    }

    /// A document scalar as text: a string as is, a number in its shortest form, a flag as
    /// `true` / `false`; anything else is empty.
    static func asText(_ value: JSONValue?) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number): return javaScriptNumber(number)
        case .bool(let flag): return flag ? "true" : "false"
        default: return ""
        }
    }

    /// A number written the way JavaScript's `String(number)` writes it, so that a value
    /// shown «as is» is the same characters in every reader.
    static func javaScriptNumber(_ number: Double) -> String {
        guard number.isFinite else { return number.isNaN ? "NaN" : (number < 0 ? "-Infinity" : "Infinity") }
        if number == 0 { return "0" }
        let magnitude = abs(number)
        if magnitude >= 1e21 || magnitude < 1e-6 {
            // Exponent form: shortest digits, `e+` / `e-`.
            var text = "\(magnitude)"
            if let e = text.firstIndex(of: "e") {
                var mantissa = String(text[..<e])
                if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
                var exponent = String(text[text.index(after: e)...])
                if !exponent.hasPrefix("-") && !exponent.hasPrefix("+") { exponent = "+" + exponent }
                if exponent.count > 2, exponent.dropFirst().hasPrefix("0") { exponent = String(exponent.prefix(1)) + String(Int(exponent.dropFirst()) ?? 0) }
                text = "\(mantissa)e\(exponent)"
            }
            return (number < 0 ? "-" : "") + text
        }
        return (number < 0 ? "-" : "") + DecimalText.plain(magnitude)
    }

    // MARK: - Template

    static func templateRuns(
        _ value: JSONObject, language: TemplateLanguage, environment: TextEnvironment, sink: ReportSink?, location: String
    ) -> [TemplateRun] {
        let translated = language.showsSource ? nil : language.translated("template")
        guard let template = translated ?? value["template"]?.stringValue else {
            sink?.add(.ignoredInput, "\(location): template", "the template is not a string; the text is drawn empty")
            return []
        }
        guard template.contains("{") else { return [TemplateRun(text: template, place: nil)] }

        let valuesRaw = value["values"]
        if valuesRaw?.objectValue == nil {
            sink?.add(.ignoredInput, "\(location): values", "the values of a template are not an object; every placeholder is drawn as plain text")
        }
        let values = valuesRaw?.objectValue ?? JSONObject()
        var cache: [String: [FormattedPiece]] = [:]
        func pieces(_ name: String) -> [FormattedPiece] {
            if let known = cache[name] { return known }
            let made = valuePieces(name, values: values, language: language, environment: environment, sink: sink, location: location)
            cache[name] = made
            return made
        }

        var runs: [TemplateRun] = []
        let nsTemplate = template as NSString
        var cursor = 0
        for match in placeholder.matches(in: template, range: NSRange(location: 0, length: nsTemplate.length)) {
            let name = nsTemplate.substring(with: match.range(at: 1))
            // Only a declared value is a place; anything else stays literal, braces included.
            guard values[name] != nil else { continue }
            runs.append(TemplateRun(text: nsTemplate.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), place: nil))
            for piece in pieces(name) { runs.append(TemplateRun(text: piece.text, place: name, part: piece.part)) }
            cursor = match.range.location + match.range.length
        }
        runs.append(TemplateRun(text: nsTemplate.substring(from: cursor), place: nil))
        return runs
    }

    private enum ValueKind { case binding, plural, word }

    /// A template value the reader understands; anything else leaves its place empty
    /// (`unknownTemplateValueKind: 'render-empty'`).
    private static func kind(_ entry: JSONValue?) -> ValueKind? {
        guard let object = entry?.objectValue else { return nil }
        switch object["kind"]?.stringValue {
        case "text": return object["text"]?.stringValue != nil ? .word : nil
        case "binding": return object["path"]?.stringValue != nil && object["fallback"]?.stringValue != nil ? .binding : nil
        case "plural":
            guard object["of"]?.stringValue != nil, let forms = object["forms"]?.objectValue, forms["other"]?.stringValue != nil else { return nil }
            return .plural
        default: return nil
        }
    }

    private static func valuePieces(
        _ name: String, values: JSONObject, language: TemplateLanguage, environment: TextEnvironment, sink: ReportSink?, location: String
    ) -> [FormattedPiece] {
        let entry = values[name]
        switch kind(entry) {
        case .binding:
            guard let binding = entry?.objectValue else { return [] }
            return boundPieces(binding, environment: environment)
        case .word:
            let own = entry?["text"]?.stringValue ?? ""
            return [FormattedPiece((language.showsSource ? nil : language.translated("values.\(name).text")) ?? own)]
        case .plural:
            guard let plural = entry?.objectValue else { return [] }
            return [FormattedPiece(pluralText(name, entry: plural, values: values, language: language, environment: environment))]
        case nil:
            let known = ["binding", "plural", "text"].contains(entry?["kind"]?.stringValue ?? "")
            let reason: String
            if entry?.objectValue == nil {
                reason = "a template value is not an object; its place is drawn empty"
            } else if known {
                reason = "a template value of kind “\(entry?["kind"]?.stringValue ?? "")” does not have the shape of that kind; its place is drawn empty"
            } else {
                reason = "a template value of an unknown kind; its place is drawn empty"
            }
            sink?.add(.ignoredInput, "\(location): values.\(name)", reason)
            return [FormattedPiece("")]
        }
    }

    private static func pluralText(_ name: String, entry: JSONObject, values: JSONObject, language: TemplateLanguage, environment: TextEnvironment) -> String {
        // The language of the SHOWN forms (`pluralLanguage`): translated `other` brings the
        // translation's forms and rules; otherwise the document's forms with the source rules.
        var forms: [PluralCategory: String] = [:]
        let other: String
        let rulesLocale: String?
        if !language.showsSource, let translatedOther = language.translated("values.\(name).forms.other") {
            for category in PluralCategory.allCases where category != .other {
                if let form = language.translated("values.\(name).forms.\(category.rawValue)") { forms[category] = form }
            }
            other = translatedOther
            rulesLocale = language.translationLocale
        } else {
            let documentForms = entry["forms"]?.objectValue ?? JSONObject()
            for category in PluralCategory.allCases where category != .other {
                if let form = documentForms[category.rawValue]?.stringValue { forms[category] = form }
            }
            other = documentForms["other"]?.stringValue ?? ""
            rulesLocale = language.sourceLocale
        }
        // The number comes only from a BINDING of the same template (`pluralWithoutNumber`).
        guard let target = entry["of"]?.stringValue, let binding = values[target], kind(binding) == .binding,
            let bindingObject = binding.objectValue, let count = countOf(bindingObject, environment: environment)
        else { return other }
        return forms[PluralRules.category(of: count, locale: rulesLocale)] ?? other
    }

    private static func countOf(_ binding: JSONObject, environment: TextEnvironment) -> Double? {
        let raw = binding["path"]?.stringValue.flatMap { environment.scope[$0] }
        let isTextLike: Bool
        switch raw {
        case .string(let text): isTextLike = !text.isEmpty
        case .number, .bool: isTextLike = true
        default: isTextLike = false
        }
        guard isTextLike, let raw else {
            // No data: the fallback is on screen, and the word agrees with what is shown.
            guard let fallback = binding["fallback"]?.stringValue, matches(numericFallback, fallback), let number = Double(fallback) else { return nil }
            return BindingFormat.numericValue(.number(number), format: nil, now: nil)
        }
        let format = binding["format"]?.stringValue
        if let format, !BindingFormat.countable.contains(format) { return nil }
        if binding["format"] != nil, format == nil { return nil }
        return BindingFormat.numericValue(raw, format: format, now: environment.now, unit: binding["unit"])
    }
}

/// The shown text (`x-style.layout.shownText`): runs of space, tab, LF and CR become one
/// space, the edges are trimmed, U+00A0 and every other character stay.
enum ShownText {
    static func of(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                pendingSpace = false
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
