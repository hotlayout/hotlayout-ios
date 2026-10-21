import Foundation

/// Translation keys and lookups of a document (`localization.strings`).
enum Localization {
    /// The key of a string field of a node: `<screenId>/<nodeId>/<field>`.
    static func key(screenId: String, nodeId: String, field: String) -> String {
        "\(screenId)/\(nodeId)/\(field)"
    }

    /// The translation under `key` in the shown language, or `nil` (`missingTranslation`:
    /// the text of the document). The source language has no table of its own.
    static func translate(_ localization: DocumentLocalization?, translation: String?, key: String) -> String? {
        guard let localization, let translation, translation != localization.defaultLocale else { return nil }
        return localization.strings[translation]?[key]
    }

    /// The language a document is shown in for the host's locale. A language counts as
    /// available only if its table holds at least one string; a partly translated language
    /// is shown, and the rest falls back to the source text.
    static func resolve(_ localization: DocumentLocalization?, requested: String?) -> LocaleResolution {
        guard let localization else { return LocaleResolution.resolve(requested, available: [], source: nil) }
        let available = localization.locales.filter { locale in
            locale == localization.defaultLocale || !(localization.strings[locale]?.isEmpty ?? true)
        }
        return LocaleResolution.resolve(requested, available: available, source: localization.defaultLocale)
    }
}
