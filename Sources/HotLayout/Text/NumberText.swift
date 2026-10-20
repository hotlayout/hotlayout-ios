import Foundation

/// Numbers in a locale, the way every reader of the contract writes them.
///
/// The locale supplies the digits, the decimal sign and the group separator (CLDR, through
/// Foundation). Two things are the contract's and are done here by hand:
///  - groups ALWAYS (`x-template.number.grouping`): CLDR `minimumGroupingDigits` makes
///    Spanish write «1850», while the contract says «1.850»;
///  - rounding half away from zero over the shortest decimal string (`DecimalText`).
enum NumberText {
    private static let lock = NSLock()
    private static var formatters: [String: NumberFormatter] = [:]
    private static var available: Set<String>?
    private static let cacheLimit = 64

    /// Whether the platform has locale data for a tag or any of its shorter forms.
    static func hasData(_ tag: String) -> Bool {
        lock.lock()
        if available == nil { available = Set(Locale.availableIdentifiers.map { $0.lowercased() }) }
        let known = available ?? []
        lock.unlock()
        guard let normalized = LocaleTags.normalize(tag) else { return false }
        return LocaleTags.lookupChain(normalized).contains { known.contains($0.replacingOccurrences(of: "-", with: "_").lowercased()) }
    }

    /// The locale to format in, or `nil` when the format does not apply.
    ///
    /// Two different questions, in this order:
    ///  1. SHAPE: the first tag of the lookup chain of the format locale with a valid shape;
    ///     only if the format locale has none, the language of the shown text;
    ///  2. DATA: whether the platform has data for that tag (or a shorter form of it). A
    ///     language without data shows the value as is (`missingNumberLocaleData`,
    ///     `missingDateLocaleData`), never a number in another language.
    /// `.some(nil)` means nobody named a language: the device language.
    static func usableLocale(_ locale: String?, fallback: String?) -> String?? {
        guard let locale, !locale.isEmpty else { return .some(nil) }
        for candidate in [locale, fallback].compactMap({ $0 }) {
            guard let normalized = LocaleTags.normalize(String(candidate.prefix(LocaleTags.maxLength))),
                let shaped = LocaleTags.wellFormedTag(normalized)
            else { continue }
            return hasData(shaped) ? .some(shaped) : nil
        }
        return nil
    }

    private static func formatter(_ locale: String?, minimumFraction: Int, maximumFraction: Int, minimumInteger: Int) -> NumberFormatter {
        let key = "\(locale ?? "")|\(minimumFraction)|\(maximumFraction)|\(minimumInteger)"
        lock.lock()
        defer { lock.unlock() }
        if let known = formatters[key] { return known }
        let formatter = NumberFormatter()
        formatter.locale = locale.map { Locale(identifier: $0) } ?? Locale.current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minimumFraction
        formatter.maximumFractionDigits = maximumFraction
        formatter.minimumIntegerDigits = minimumInteger
        formatter.roundingMode = .halfUp
        if formatters.count >= cacheLimit { formatters.removeAll() }
        formatters[key] = formatter
        return formatter
    }

    /// A number written in a locale, split at the decimal sign: `integer` carries the sign
    /// and the grouped integer digits, `fraction` the decimal sign and the fraction digits
    /// (empty when there are none).
    static func parts(
        _ value: Double, locale: String?, minimumFraction: Int, maximumFraction: Int, minimumInteger: Int = 1
    ) -> (integer: String, fraction: String)? {
        guard value.isFinite else { return nil }
        let formatter = formatter(locale, minimumFraction: minimumFraction, maximumFraction: maximumFraction, minimumInteger: minimumInteger)
        let decimal = NSDecimalNumber(string: DecimalText.roundedString(value, fractionDigits: maximumFraction), locale: Locale(identifier: "en_US_POSIX"))
        guard decimal != NSDecimalNumber.notANumber, let written = formatter.string(from: decimal) else { return nil }
        let separator = formatter.decimalSeparator ?? "."
        let cut = maximumFraction > 0 ? written.range(of: separator, options: .backwards) : nil
        let integerText = cut.map { String(written[..<$0.lowerBound]) } ?? written
        let fractionText = cut.map { String(written[$0.lowerBound...]) } ?? ""
        let grouped = groupDigits(
            integerText, separator: formatter.groupingSeparator ?? ",", primary: formatter.groupingSize, secondary: formatter.secondaryGroupingSize)
        return (grouped, fractionText)
    }

    static func text(_ value: Double, locale: String?, minimumFraction: Int, maximumFraction: Int, minimumInteger: Int = 1) -> String? {
        parts(value, locale: locale, minimumFraction: minimumFraction, maximumFraction: maximumFraction, minimumInteger: minimumInteger).map {
            $0.integer + $0.fraction
        }
    }

    /// Inserts group separators into the run of decimal digits of the integer part. The
    /// digits may be of any script (Arabic-Indic, Persian): what counts is that they are digits.
    static func groupDigits(_ text: String, separator: String, primary: Int, secondary: Int) -> String {
        guard primary > 0 else { return text }
        let characters = Array(text)
        guard let first = characters.firstIndex(where: { $0.isWholeNumber }) else { return text }
        var last = first
        while last + 1 < characters.count, characters[last + 1].isWholeNumber { last += 1 }
        let digits = Array(characters[first...last])
        guard digits.count > primary else { return text }
        var groups: [String] = []
        var end = digits.count
        var size = primary
        while end > 0 {
            let start = max(0, end - size)
            groups.insert(String(digits[start..<end]), at: 0)
            end = start
            if secondary > 0 { size = secondary }
        }
        return String(characters[..<first]) + groups.joined(separator: separator) + String(characters[(last + 1)...])
    }

    /// Fraction digits of a currency from platform data (ISO 4217 as CLDR carries it);
    /// a code the platform does not know gets two.
    static func currencyFractionDigits(_ code: String) -> Int {
        let key = "currency|\(code)"
        lock.lock()
        defer { lock.unlock() }
        if let known = formatters[key] { return known.maximumFractionDigits }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatters[key] = formatter
        return formatter.maximumFractionDigits
    }

    /// Whether a number is written as zero under the given fraction digits (no digit 1–9).
    static func writtenAsZero(_ magnitude: Double, maximumFraction: Int) -> Bool {
        let parts = DecimalText.rounded(abs(magnitude), fractionDigits: maximumFraction)
        return !(parts.integer + parts.fraction).contains { $0 >= "1" && $0 <= "9" }
    }
}
