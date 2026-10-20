import Foundation

/// Decimal arithmetic over the shortest round-trip string of a number
/// (`numberRounding: 'half-away-from-zero-over-shortest-decimal'`).
///
/// `1.0005` as a binary double is slightly below 1.0005, so rounding the double gives 1.000;
/// every reader of the contract rounds the SHORTEST decimal string the number prints as,
/// which gives 1.001. The work happens on digit strings, never on the double.
enum DecimalText {
    /// The plain decimal digits of a finite non-negative number: no exponent, no sign.
    static func plain(_ value: Double) -> String {
        let magnitude = abs(value)
        var text = "\(magnitude)"
        guard let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            if text.hasSuffix(".0") { text.removeLast(2) }
            return text
        }
        let exponent = Int(text[text.index(after: e)...]) ?? 0
        let mantissa = String(text[..<e])
        let dot = mantissa.firstIndex(of: ".")
        let integerDigits = dot.map { String(mantissa[..<$0]) } ?? mantissa
        let fractionDigits = dot.map { String(mantissa[mantissa.index(after: $0)...]) } ?? ""
        var digits = integerDigits + fractionDigits
        var point = integerDigits.count + exponent
        if point <= 0 {
            digits = String(repeating: "0", count: -point + 1) + digits
            point = 1
        } else if point > digits.count {
            digits += String(repeating: "0", count: point - digits.count)
        }
        var integer = String(digits.prefix(point))
        var fraction = String(digits.dropFirst(point))
        while fraction.hasSuffix("0") { fraction.removeLast() }
        while integer.count > 1, integer.hasPrefix("0") { integer.removeFirst() }
        return fraction.isEmpty ? integer : "\(integer).\(fraction)"
    }

    /// The number rounded half away from zero to at most `digits` fraction digits, as parts.
    /// Trailing zeros of the fraction are kept up to `digits` only when the input had them;
    /// callers that want a fixed count pad themselves.
    static func rounded(_ value: Double, fractionDigits digits: Int) -> (negative: Bool, integer: String, fraction: String) {
        let negative = value < 0
        let text = plain(value)
        let dot = text.firstIndex(of: ".")
        var integer = dot.map { String(text[..<$0]) } ?? text
        var fraction = dot.map { String(text[text.index(after: $0)...]) } ?? ""
        if fraction.count > digits {
            let roundUp = fraction[fraction.index(fraction.startIndex, offsetBy: digits)] >= "5"
            fraction = String(fraction.prefix(digits))
            if roundUp {
                var all = Array(integer + fraction)
                var index = all.count - 1
                var carry = true
                while carry, index >= 0 {
                    if all[index] == "9" {
                        all[index] = "0"
                        index -= 1
                    } else {
                        all[index] = Character(String((all[index].wholeNumberValue ?? 0) + 1))
                        carry = false
                    }
                }
                if carry { all.insert("1", at: 0) }
                let joined = String(all)
                integer = String(joined.prefix(joined.count - digits))
                fraction = String(joined.suffix(digits))
            }
        }
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return (negative, integer.isEmpty ? "0" : integer, fraction)
    }

    /// The rounded number back as a decimal string (`-12.5`), for `NSDecimalNumber`.
    static func roundedString(_ value: Double, fractionDigits digits: Int) -> String {
        let parts = rounded(value, fractionDigits: digits)
        let body = parts.fraction.isEmpty ? parts.integer : "\(parts.integer).\(parts.fraction)"
        let isZero = body.allSatisfy { $0 == "0" || $0 == "." }
        return parts.negative && !isZero ? "-\(body)" : body
    }
}
