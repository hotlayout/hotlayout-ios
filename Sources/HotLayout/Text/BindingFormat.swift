import Foundation

/// What turns a data value into text: the data, the format locale, the zone and «now».
struct TextEnvironment: Sendable {
    var scope: DataScope
    /// The format locale (`formatting` of `LocaleResolution.resolve`); `nil` means the device language.
    var formattingLocale: String?
    /// The language of the shown text, used when the platform rejects the format locale.
    var fallbackLocale: String?
    var timeZone: TimeZone?
    /// «Now» in epoch milliseconds (`readerClock: 'injectable-read-at-render'`).
    var now: Double?
    /// Direction of the shown text; `true` is right to left.
    var rightToLeft: Bool

    init(
        scope: DataScope, formattingLocale: String? = nil, fallbackLocale: String? = nil, timeZone: TimeZone? = nil, now: Double? = nil,
        rightToLeft: Bool? = nil
    ) {
        self.scope = scope
        self.formattingLocale = formattingLocale
        self.fallbackLocale = fallbackLocale
        self.timeZone = timeZone
        self.now = now
        self.rightToLeft = rightToLeft ?? TextDirectionRule.isRightToLeft(fallbackLocale) ?? false
    }
}

/// A part of a formatted number that a text span may style.
enum FormatPart: String, Sendable {
    case fraction, currency
}

/// A piece of a formatted value: the text and which part of the number it is.
struct FormattedPiece: Equatable, Sendable {
    let text: String
    let part: FormatPart?

    init(_ text: String, part: FormatPart? = nil) {
        self.text = text
        self.part = part
    }
}

/// Format of a data-bound value (`binding.format`).
///
/// The document names an INTENT; the locale supplies the look. `nil` from a function here
/// means «the format did not apply»: the value is then shown AS IS (`unknownBindingFormat`,
/// `unparsableBoundValue`, `missingCurrencyCode`, `missingNumberLocaleData`,
/// `numberBeyondSafeInteger`).
enum BindingFormat {
    /// `x-template.number`: groups always, fraction 0…3 digits, up to 2^53 − 1.
    static let maximumAbsoluteValue = 9_007_199_254_740_991.0
    static let maximumFractionDigits = 3
    /// `x-template.daysUntil`: a day is exactly 24 hours.
    static let dayMilliseconds = 86_400_000.0
    /// Formats under which a value is a NUMBER for plural selection.
    static let countable: Set<String> = ["number", "currency", "daysUntil", "countdownPart"]
    static let currencySeparator = "\u{00A0}"
    private static let currencyCode = try! NSRegularExpression(pattern: "^[A-Z]{3}$")

    static func isCurrencyCode(_ value: JSONValue?) -> Bool {
        guard let text = value?.stringValue else { return false }
        return matches(currencyCode, text)
    }

    /// The NUMBER a value becomes under a format: what is printed and what picks a plural form.
    /// The string «12» is not a number; a date is one only under `daysUntil` / `countdownPart`.
    static func numericValue(_ value: JSONValue?, format: String?, now: Double?, unit: JSONValue? = nil) -> Double? {
        switch format {
        case "countdownPart":
            guard let moment = DateText.moment(value), let now, now.isFinite else { return nil }
            return countdownPart(moment: moment, now: now, unit: unit?.stringValue)
        case "daysUntil":
            guard let moment = DateText.moment(value), let now, now.isFinite else { return nil }
            return max(0, ((moment - now) / dayMilliseconds).rounded(.up))
        case nil, "number", "currency":
            guard let number = value?.numberValue, abs(number) <= maximumAbsoluteValue else { return nil }
            return number
        default:
            return nil
        }
    }

    /// A part of the time left (`x-countdown`): whole days, hours 0–23, minutes 0–59 or
    /// seconds 0–59, rounded DOWN; a past moment gives zeros.
    static func countdownPart(moment: Double, now: Double, unit: String?) -> Double? {
        let seconds = (max(0, moment - now) / 1000).rounded(.down)
        switch unit {
        case "days": return (seconds / 86_400).rounded(.down)
        case "hours": return ((seconds / 3_600).rounded(.down)).truncatingRemainder(dividingBy: 24)
        case "minutes": return ((seconds / 60).rounded(.down)).truncatingRemainder(dividingBy: 60)
        case "seconds": return seconds.truncatingRemainder(dividingBy: 60)
        default: return nil
        }
    }

    /// The text of a value under the format of its binding, as pieces, or `nil` when the
    /// format did not apply.
    static func pieces(_ value: JSONValue, binding: JSONObject, environment: TextEnvironment) -> [FormattedPiece]? {
        guard let format = binding["format"]?.stringValue else { return nil }
        let located = NumberText.usableLocale(environment.formattingLocale, fallback: environment.fallbackLocale)
        switch format {
        case "number", "currency":
            guard let locale = located else { return nil }
            return MoneyFormat.pieces(value, binding: binding, locale: locale, environment: environment)
        case "daysUntil":
            guard let days = numericValue(value, format: format, now: environment.now) else { return nil }
            // No locale data: counted days are plain digits (an ISO string mid-sentence is worse).
            guard let locale = located, let text = NumberText.text(days, locale: locale, minimumFraction: 0, maximumFraction: maximumFractionDigits) else {
                return [FormattedPiece(DecimalText.plain(days))]
            }
            return [FormattedPiece(text)]
        case "countdownPart":
            guard let part = numericValue(value, format: format, now: environment.now, unit: binding["unit"]) else { return nil }
            let digits = binding["pad"]?.numberValue == 2 ? 2 : 1
            let plain = String(repeating: "0", count: max(0, digits - DecimalText.plain(part).count)) + DecimalText.plain(part)
            guard let locale = located, let text = NumberText.text(part, locale: locale, minimumFraction: 0, maximumFraction: 0, minimumInteger: digits) else {
                return [FormattedPiece(plain)]
            }
            return [FormattedPiece(text)]
        case "date", "dateTime", "time":
            guard let moment = DateText.moment(value) else { return nil }
            // A locale without date data shows the value as is (`missingDateLocaleData`).
            guard let locale = located else { return nil }
            let parts = format == "date" ? binding["dateParts"]?.stringValue : nil
            return DateText.format(moment, format: format, dateParts: parts, locale: locale, timeZone: environment.timeZone).map { [FormattedPiece($0)] }
        default:
            return nil
        }
    }
}

/// Money as money (`x-money`) and the compact number (`x-compactNumber`):
/// the pieces of `number` and `currency`.
enum MoneyFormat {
    static let symbols: [String: String] = [
        "UAH": "₴", "USD": "$", "EUR": "€", "GBP": "£", "PLN": "zł", "JPY": "¥",
        "CZK": "Kč", "TRY": "₺", "INR": "₹", "ILS": "₪", "KZT": "₸", "GEL": "₾",
    ]
    static let plus = "+"
    static let minus = "\u{2212}"
    static let isolateOpen = "\u{2066}"
    static let isolateClose = "\u{2069}"

    static func pieces(_ value: JSONValue, binding: JSONObject, locale: String?, environment: TextEnvironment) -> [FormattedPiece]? {
        let format = binding["format"]?.stringValue
        let money = format == "currency"
        guard let number = BindingFormat.numericValue(value, format: format, now: environment.now) else { return nil }
        let code: String? = money && BindingFormat.isCurrencyCode(binding["currency"]) ? binding["currency"]?.stringValue : nil
        if money, code == nil { return nil }

        let symbolDisplay = money && binding["currencyDisplay"]?.stringValue == "symbol"
        let before = money && binding["currencyPosition"]?.stringValue == "before"
        let signAlways = binding["sign"]?.stringValue == "always"
        let compact = format == "number" && binding["notation"]?.stringValue == "compact" ? CompactNumber.parts(of: number) : nil

        let digits: (min: Int, max: Int)
        if compact != nil {
            digits = (0, 1)
        } else if let code {
            let count = number == number.rounded() ? 0 : NumberText.currencyFractionDigits(code)
            digits = (count, count)
        } else {
            digits = (0, BindingFormat.maximumFractionDigits)
        }
        let composed = signAlways || symbolDisplay || before
        let shown = compact.map { (number < 0 ? -1 : 1) * $0.mantissa } ?? number
        guard let amount = NumberText.parts(composed ? abs(shown) : shown, locale: locale, minimumFraction: digits.min, maximumFraction: digits.max) else {
            return nil
        }

        var around = (before: "", after: "")
        if let code {
            let symbol = symbolDisplay ? symbols[code] : nil
            if before {
                around.before = symbol ?? "\(code)\(BindingFormat.currencySeparator)"
            } else {
                around.after = "\(BindingFormat.currencySeparator)\(symbol ?? code)"
            }
        }
        var sign = ""
        if composed, !NumberText.writtenAsZero(abs(number), maximumFraction: digits.max) {
            sign = number < 0 ? minus : (signAlways ? plus : "")
        }
        var pieces = merged([
            FormattedPiece(sign),
            FormattedPiece(around.before, part: .currency),
            FormattedPiece(amount.integer),
            FormattedPiece(amount.fraction, part: .fraction),
            FormattedPiece(compact.map { CompactNumber.suffix($0.step, locale: locale) } ?? ""),
            FormattedPiece(around.after, part: .currency),
        ])
        if composed, environment.rightToLeft, !pieces.isEmpty {
            pieces[0] = FormattedPiece(isolateOpen + pieces[0].text, part: pieces[0].part)
            let last = pieces.count - 1
            pieces[last] = FormattedPiece(pieces[last].text + isolateClose, part: pieces[last].part)
        }
        return pieces
    }

    /// Empty pieces dropped, neighbours of the same part merged.
    static func merged(_ pieces: [FormattedPiece]) -> [FormattedPiece] {
        var result: [FormattedPiece] = []
        for piece in pieces where !piece.text.isEmpty {
            if let last = result.last, last.part == piece.part {
                result[result.count - 1] = FormattedPiece(last.text + piece.text, part: last.part)
            } else {
                result.append(piece)
            }
        }
        return result
    }
}

/// The compact number (`x-compactNumber`): 1.2K, 3.4M — the contract's own arithmetic and
/// suffix table, not the platform's compact style (which differs between platforms).
enum CompactNumber {
    enum Step: String { case thousand, million, billion }
    static let steps: [(Step, Double)] = [(.thousand, 1_000), (.million, 1_000_000), (.billion, 1_000_000_000)]
    typealias Suffixes = (gap: String, thousand: String, million: String, billion: String)
    private static let english: Suffixes = ("", "K", "M", "B")
    private static let ukrainian: Suffixes = ("\u{00A0}", "тис.", "млн", "млрд")
    static let suffixes: [String: Suffixes] = ["en": english, "uk": ukrainian]

    static func parts(of value: Double) -> (mantissa: Double, step: Step)? {
        let magnitude = abs(value)
        guard magnitude.isFinite, magnitude >= steps[0].1 else { return nil }
        var index = steps.count - 1
        while index > 0, magnitude < steps[index].1 { index -= 1 }
        func tenths(_ at: Int) -> Double {
            (((magnitude * 10) / steps[at].1 * 1e6).rounded() / 1e6 + 0.5).rounded(.down)
        }
        var count = tenths(index)
        if count >= 10_000, index < steps.count - 1 {
            index += 1
            count = tenths(index)
        }
        return (count / 10, steps[index].0)
    }

    static func suffix(_ step: Step, locale: String?) -> String {
        let language = (locale ?? "en").split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? "en"
        let table = language == "uk" ? ukrainian : english
        switch step {
        case .thousand: return table.gap + table.thousand
        case .million: return table.gap + table.million
        case .billion: return table.gap + table.billion
        }
    }
}
