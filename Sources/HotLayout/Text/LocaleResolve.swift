import Foundation

/// Which language a document is shown in (schema 9.1.0).
///
/// The host passes the DEVICE locale (`ar-EG`, `pt_BR`); the document has translations under
/// short codes. The contract's policy rows:
///  - `localeNormalization`: `_` equals `-`, case does not matter;
///  - `localeMatching: 'bcp47-lookup-truncate'`: exact match, then drop the last part;
///  - `localeChildFallback: 'none'`: `ar` does NOT find `ar-EG`;
///  - `unmatchedLocale: 'use-default-locale'`;
///  - `directionFollows: 'shown-translation-locale'`;
///  - `formattingLocale: 'requested-when-matched-else-default'`.
public struct LocaleResolution: Equatable, Sendable {
    /// The language the texts are shown in: a key of the document's locales as the document
    /// spells it, or its source language. `nil` only for a document without localization.
    public let translation: String?
    /// The locale numbers and dates are written in (canonical BCP 47). `nil`: the device's.
    public let formatting: String?
    /// The tag the writing direction comes from: the language of the SHOWN text.
    public let directionLocale: String?
    /// Whether the requested locale was found, exactly or by dropping subtags.
    public let matched: Bool
}

enum LocaleTags {
    /// The longest string that is considered a language tag at all.
    static let maxLength = 100

    private static func isAlnum(_ part: Substring, _ range: ClosedRange<Int>) -> Bool {
        range.contains(part.utf8.count) && part.utf8.allSatisfy { isASCIILetter($0) || ($0 >= 0x30 && $0 <= 0x39) }
    }
    private static func isAlpha(_ part: Substring, _ range: ClosedRange<Int>) -> Bool {
        range.contains(part.utf8.count) && part.utf8.allSatisfy(isASCIILetter)
    }
    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    /// The tag in canonical form (language lowercase, script capitalized, region uppercase,
    /// everything after a singleton lowercase), or `nil` if it is not a language tag.
    static func normalize(_ raw: String?) -> String? {
        guard let raw, raw.utf16.count <= maxLength else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard let language = parts.first, isAlpha(language, 2...8) else { return nil }
        guard parts.allSatisfy({ isAlnum($0, 1...8) }) else { return nil }
        var afterSingleton = false
        var out: [String] = []
        for (index, part) in parts.enumerated() {
            if index == 0 || afterSingleton {
                out.append(part.lowercased())
            } else if part.utf8.count == 1 {
                afterSingleton = true
                out.append(part.lowercased())
            } else if isAlpha(part, 4...4) {
                out.append(part.prefix(1).uppercased() + part.dropFirst().lowercased())
            } else if isAlpha(part, 2...2) {
                out.append(part.uppercased())
            } else {
                out.append(part.lowercased())
            }
        }
        return out.joined(separator: "-")
    }

    /// The tag and everything left after dropping parts from the end; a single-letter part
    /// is never left last.
    static func lookupChain(_ normalized: String) -> [String] {
        guard normalized.utf16.count <= maxLength else { return [] }
        var parts = normalized.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        var chain: [String] = []
        while !parts.isEmpty {
            chain.append(parts.joined(separator: "-"))
            parts.removeLast()
            while parts.count > 1, parts.last?.utf8.count == 1 { parts.removeLast() }
        }
        return chain
    }

    // Language (2-3 or 5-8 letters), script, region, variants, extensions, private use —
    // applied to the canonical form.
    private static let wellFormed = try! NSRegularExpression(
        pattern:
            "^(?:[a-z]{2,3}|[a-z]{5,8})(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*(?:-[a-wyz0-9](?:-[a-z0-9]{2,8})+)*(?:-x(?:-[a-z0-9]{1,8})+)?$"
    )

    /// The longest prefix of a tag with a valid shape: `ja-JP-JP` → `ja-JP`.
    static func wellFormedTag(_ normalized: String?) -> String? {
        guard let normalized else { return nil }
        return lookupChain(normalized).first { matches(wellFormed, $0) }
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

/// Which language a document is shown in when the host asks for `requested`.
///
/// - Parameters:
///   - requested: the locale of the user, as the platform gives it.
///   - available: the document's `localization.locales`.
///   - source: the document's `localization.defaultLocale`; `nil` — no localization.
public func resolveLocale(_ requested: String?, available: [String], source: String?) -> LocaleResolution {
    let asked = LocaleTags.normalize(requested)
    let askedFormat = LocaleTags.wellFormedTag(asked)

    guard let source else {
        return LocaleResolution(translation: nil, formatting: askedFormat, directionLocale: askedFormat ?? asked, matched: false)
    }
    func canonical(_ locale: String) -> String { LocaleTags.normalize(locale) ?? locale }
    let unmatched = LocaleResolution(
        translation: source,
        formatting: LocaleTags.wellFormedTag(LocaleTags.normalize(source)) ?? canonical(source),
        directionLocale: canonical(source),
        matched: false
    )
    guard let asked else { return unmatched }

    // Comparison key → the DOCUMENT's spelling; the first in the list wins over a case twin.
    var keys: [String: String] = [:]
    for locale in available + [source] {
        if let key = LocaleTags.normalize(locale)?.lowercased(), keys[key] == nil { keys[key] = locale }
    }
    for candidate in LocaleTags.lookupChain(asked) {
        if let found = keys[candidate.lowercased()] {
            let shown = canonical(found)
            return LocaleResolution(
                translation: found, formatting: askedFormat ?? LocaleTags.wellFormedTag(shown) ?? shown, directionLocale: shown, matched: true)
        }
    }
    return unmatched
}

/// Writing direction of a language from platform locale data (CLDR), not from a list of our
/// own. `nil` means "no language": the caller decides (the device direction).
enum TextDirectionRule {
    static func isRightToLeft(_ locale: String?) -> Bool? {
        guard let locale, let tag = LocaleTags.normalize(locale) else { return nil }
        let language = Locale(identifier: tag).language
        return language.characterDirection == .rightToLeft
    }
}
