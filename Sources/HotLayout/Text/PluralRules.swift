import Foundation

/// CLDR plural categories (`x-template.pluralCategories`).
enum PluralCategory: String, CaseIterable, Sendable {
    case zero, one, two, few, many, other
}

/// CLDR cardinal plural rules (`pluralCategory: 'cldr-cardinal-categories-not-exact-numbers'`).
///
/// Foundation has no API that answers «which category is this number in this
/// language», so the rules are carried here as CLDR states them. The operands are computed
/// from the number rounded to three fraction digits (`pluralNumber`,
/// `pluralFractionOperands: 'cldr-with-fraction-digits'`): `n` absolute value, `i` integer
/// digits, `v` count of visible fraction digits, `f` and `t` the fraction digits.
enum PluralRules {
    static let maximumFractionDigits = 3

    struct Operands {
        let n: Double
        let i: Int
        let v: Int
        let f: Int
        var t: Int { f }

        func mod(_ value: Double, _ m: Double) -> Double { value.truncatingRemainder(dividingBy: m) }
        func n(_ m: Double) -> Double { mod(n, m) }
        func nIn(_ m: Double, _ values: ClosedRange<Int>) -> Bool {
            let r = n(m)
            return r == r.rounded() && values.contains(Int(r))
        }
        func nIs(_ m: Double, _ values: Int...) -> Bool {
            let r = n(m)
            return r == r.rounded() && values.contains(Int(r))
        }
    }

    typealias Rule = (Operands) -> PluralCategory

    /// The category of a number in a language. A language without rules, a non-tag or a
    /// non-finite number gives `other`, never the rules of the device language.
    static func category(of value: Double, locale: String?) -> PluralCategory {
        guard let locale, locale.utf16.count <= LocaleTags.maxLength, value.isFinite, let rule = rule(for: locale) else { return .other }
        let rounded = DecimalText.rounded(abs(value), fractionDigits: maximumFractionDigits)
        let fraction = rounded.fraction
        let n = Double(rounded.fraction.isEmpty ? rounded.integer : "\(rounded.integer).\(fraction)") ?? abs(value)
        let operands = Operands(n: n, i: Int(rounded.integer) ?? Int.max, v: fraction.count, f: Int(fraction) ?? 0)
        return rule(operands)
    }

    static func rule(for locale: String) -> Rule? {
        guard let tag = LocaleTags.normalize(locale) else { return nil }
        for candidate in LocaleTags.lookupChain(tag) {
            if let rule = rules[candidate] { return rule }
        }
        return nil
    }

    // MARK: - Rules (CLDR cardinal)

    private static let otherOnly: Rule = { _ in .other }
    private static let oneIfIntegerOne: Rule = { $0.i == 1 && $0.v == 0 ? .one : .other }
    private static let oneIfNOne: Rule = { $0.n == 1 ? .one : .other }
    private static let oneIfIZeroOrNOne: Rule = { $0.i == 0 || $0.n == 1 ? .one : .other }
    private static let oneIfIZeroOrOne: Rule = { $0.i == 0 || $0.i == 1 ? .one : .other }
    private static let oneIfNZeroOrOne: Rule = { $0.n == 0 || $0.n == 1 ? .one : .other }

    private static let arabic: Rule = { o in
        if o.n == 0 { return .zero }
        if o.n == 1 { return .one }
        if o.n == 2 { return .two }
        if o.nIn(100, 3...10) { return .few }
        if o.nIn(100, 11...99) { return .many }
        return .other
    }
    private static let belarusian: Rule = { o in
        if o.nIs(10, 1), !o.nIs(100, 11) { return .one }
        if o.nIn(10, 2...4), !o.nIn(100, 12...14) { return .few }
        if o.nIs(10, 0) || o.nIn(10, 5...9) || o.nIn(100, 11...14) { return .many }
        return .other
    }
    private static let breton: Rule = { o in
        if o.nIs(10, 1), !o.nIs(100, 11, 71, 91) { return .one }
        if o.nIs(10, 2), !o.nIs(100, 12, 72, 92) { return .two }
        if o.nIs(10, 3, 4, 9), !(o.nIn(100, 10...19) || o.nIn(100, 70...79) || o.nIn(100, 90...99)) { return .few }
        if o.n != 0, o.nIs(1_000_000, 0) { return .many }
        return .other
    }
    private static let bosnian: Rule = { o in
        if (o.v == 0 && o.i % 10 == 1 && o.i % 100 != 11) || (o.f % 10 == 1 && o.f % 100 != 11) { return .one }
        if (o.v == 0 && (2...4).contains(o.i % 10) && !(12...14).contains(o.i % 100))
            || ((2...4).contains(o.f % 10) && !(12...14).contains(o.f % 100))
        {
            return .few
        }
        return .other
    }
    private static let catalan: Rule = { o in
        if o.i == 1 && o.v == 0 { return .one }
        if o.i != 0 && o.i % 1_000_000 == 0 && o.v == 0 { return .many }
        return .other
    }
    private static let czech: Rule = { o in
        if o.i == 1 && o.v == 0 { return .one }
        if (2...4).contains(o.i) && o.v == 0 { return .few }
        if o.v != 0 { return .many }
        return .other
    }
    private static let welsh: Rule = { o in
        switch o.n {
        case 0: return .zero
        case 1: return .one
        case 2: return .two
        case 3: return .few
        case 6: return .many
        default: return .other
        }
    }
    private static let danish: Rule = { o in o.n == 1 || (o.t != 0 && (o.i == 0 || o.i == 1)) ? .one : .other }
    private static let spanish: Rule = { o in
        if o.n == 1 { return .one }
        if o.i != 0 && o.i % 1_000_000 == 0 && o.v == 0 { return .many }
        return .other
    }
    private static let filipino: Rule = { o in
        if (o.v == 0 && (1...3).contains(o.i)) || (o.v == 0 && ![4, 6, 9].contains(o.i % 10)) || (o.v != 0 && ![4, 6, 9].contains(o.f % 10)) {
            return .one
        }
        return .other
    }
    private static let french: Rule = { o in
        if o.i == 0 || o.i == 1 { return .one }
        if o.i != 0 && o.i % 1_000_000 == 0 && o.v == 0 { return .many }
        return .other
    }
    private static let irish: Rule = { o in
        if o.n == 1 { return .one }
        if o.n == 2 { return .two }
        if [3.0, 4, 5, 6].contains(o.n) { return .few }
        if [7.0, 8, 9, 10].contains(o.n) { return .many }
        return .other
    }
    private static let hebrew: Rule = { o in
        if (o.i == 1 && o.v == 0) || (o.i == 0 && o.v != 0) { return .one }
        if o.i == 2 && o.v == 0 { return .two }
        return .other
    }
    private static let icelandic: Rule = { o in
        (o.t == 0 && o.i % 10 == 1 && o.i % 100 != 11) || (o.t % 10 == 1 && o.t % 100 != 11) ? .one : .other
    }
    private static let lithuanian: Rule = { o in
        if o.nIs(10, 1), !o.nIn(100, 11...19) { return .one }
        if o.nIn(10, 2...9), !o.nIn(100, 11...19) { return .few }
        if o.f != 0 { return .many }
        return .other
    }
    private static let latvian: Rule = { o in
        if o.nIs(10, 0) || o.nIn(100, 11...19) || (o.v == 2 && (11...19).contains(o.f % 100)) { return .zero }
        if (o.nIs(10, 1) && !o.nIs(100, 11)) || (o.v == 2 && o.f % 10 == 1 && o.f % 100 != 11) || (o.v != 2 && o.f % 10 == 1) { return .one }
        return .other
    }
    private static let macedonian: Rule = { o in
        (o.v == 0 && o.i % 10 == 1 && o.i % 100 != 11) || (o.f % 10 == 1 && o.f % 100 != 11) ? .one : .other
    }
    private static let maltese: Rule = { o in
        if o.n == 1 { return .one }
        if o.n == 2 { return .two }
        if o.n == 0 || o.nIn(100, 3...10) { return .few }
        if o.nIn(100, 11...19) { return .many }
        return .other
    }
    private static let polish: Rule = { o in
        if o.i == 1 && o.v == 0 { return .one }
        if o.v == 0 && (2...4).contains(o.i % 10) && !(12...14).contains(o.i % 100) { return .few }
        if (o.v == 0 && o.i != 1 && (0...1).contains(o.i % 10)) || (o.v == 0 && (5...9).contains(o.i % 10)) || (o.v == 0 && (12...14).contains(o.i % 100)) {
            return .many
        }
        return .other
    }
    private static let romanian: Rule = { o in
        if o.i == 1 && o.v == 0 { return .one }
        if o.v != 0 || o.n == 0 || (o.n != 1 && o.nIn(100, 1...19)) { return .few }
        return .other
    }
    private static let russian: Rule = { o in
        if o.v == 0 && o.i % 10 == 1 && o.i % 100 != 11 { return .one }
        if o.v == 0 && (2...4).contains(o.i % 10) && !(12...14).contains(o.i % 100) { return .few }
        if (o.v == 0 && o.i % 10 == 0) || (o.v == 0 && (5...9).contains(o.i % 10)) || (o.v == 0 && (11...14).contains(o.i % 100)) { return .many }
        return .other
    }
    private static let sinhala: Rule = { o in o.n == 0 || o.n == 1 || (o.i == 0 && o.f == 1) ? .one : .other }
    private static let slovenian: Rule = { o in
        if o.v == 0 && o.i % 100 == 1 { return .one }
        if o.v == 0 && o.i % 100 == 2 { return .two }
        if (o.v == 0 && (3...4).contains(o.i % 100)) || o.v != 0 { return .few }
        return .other
    }

    static let rules: [String: Rule] = [
        "af": oneIfNOne, "am": oneIfIZeroOrNOne, "ar": arabic, "as": oneIfIZeroOrNOne, "az": oneIfNOne,
        "be": belarusian, "bg": oneIfNOne, "bm": otherOnly, "bn": oneIfIZeroOrNOne, "br": breton, "bs": bosnian,
        "ca": catalan, "chr": oneIfNOne, "cs": czech, "cy": welsh, "da": danish, "de": oneIfIntegerOne,
        "el": oneIfNOne, "en": oneIfIntegerOne, "es": spanish, "et": oneIfIntegerOne, "eu": oneIfNOne,
        "fa": oneIfIZeroOrNOne, "fi": oneIfIntegerOne, "fil": filipino, "fr": french, "fur": oneIfNOne,
        "ga": irish, "gl": oneIfIntegerOne, "gsw": oneIfNOne, "gu": oneIfIZeroOrNOne, "haw": oneIfNOne,
        "he": hebrew, "hi": oneIfIZeroOrNOne, "hr": bosnian, "hu": oneIfNOne, "hy": oneIfIZeroOrOne,
        "id": otherOnly, "in": otherOnly, "is": icelandic, "it": catalan, "iw": hebrew, "ja": otherOnly,
        "ka": oneIfNOne, "kk": oneIfNOne, "km": otherOnly, "kn": oneIfIZeroOrNOne, "ko": otherOnly,
        "ky": oneIfNOne, "ln": oneIfNZeroOrOne, "lo": otherOnly, "lt": lithuanian, "lv": latvian,
        "mg": oneIfNZeroOrOne, "mk": macedonian, "ml": oneIfNOne, "mn": oneIfNOne, "mr": oneIfNOne,
        "ms": otherOnly, "mt": maltese, "my": otherOnly, "nb": oneIfNOne, "ne": oneIfNOne, "nl": oneIfIntegerOne,
        "no": oneIfNOne, "nyn": oneIfNOne, "or": oneIfNOne, "pa": oneIfNZeroOrOne, "pl": polish, "ps": oneIfNOne,
        "pt": french, "pt-PT": catalan, "ro": romanian, "mo": romanian, "ru": russian, "si": sinhala,
        "sk": czech, "sl": slovenian, "sq": oneIfNOne, "sr": bosnian, "sv": oneIfIntegerOne,
        "sw": oneIfIntegerOne, "ta": oneIfNOne, "te": oneIfNOne, "th": otherOnly, "tl": filipino,
        "tr": oneIfNOne, "uk": russian, "ur": oneIfIntegerOne, "uz": oneIfNOne, "vi": otherOnly,
        "zh": otherOnly, "zu": oneIfIZeroOrNOne,
    ]
}
