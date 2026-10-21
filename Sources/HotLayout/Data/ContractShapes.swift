import Foundation

/// Shapes the contract names once and several rules share: a token name, a whole number, an
/// absent value. A rule keeps its own bounds and passes them in.
enum ContractShapes {
    /// A token name, `^[a-z][a-zA-Z0-9]{0,39}$`: a lower-case letter and up to 39 letters and digits.
    static func isTokenName(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.first, scalars.count <= 40, first.value >= 97, first.value <= 122 else { return false }
        return scalars.allSatisfy { ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
    }

    /// A JSON number that is a whole number with an absolute value below `limit`.
    static func wholeNumber(_ value: JSONValue?, below limit: Double) -> Int? {
        guard let number = value?.numberValue, number.isFinite, number == number.rounded(.towardZero), abs(number) < limit else { return nil }
        return Int(number)
    }

    /// "Absent": missing, `null` or the empty string.
    static func isAbsent(_ value: JSONValue?) -> Bool {
        switch value {
        case nil, .null?: return true
        case .string(let text)?: return text.isEmpty
        default: return false
        }
    }
}

/// Whether an anchored expression matches the WHOLE string. ICU's `$` also matches before a
/// final line feed, JavaScript's does not; the contract's expressions are JavaScript's, so the
/// match must cover every character.
func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
    let whole = NSRange(text.startIndex..., in: text)
    guard let match = expression.firstMatch(in: text, range: whole) else { return false }
    return match.range == whole
}
