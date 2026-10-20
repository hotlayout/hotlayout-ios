import Foundation

/// The bounds of every number of a theme (`x-themeNumbers.bounds`, the same as the schema of
/// `theme.json`) and what the reader does with a number outside them (`x-themeNumbers.replacement`).
enum ThemeNumbers {
    struct Bounds {
        let low: Double
        let high: Double

        func contains(_ value: Double) -> Bool { value >= low && value <= high }

        func nearest(_ value: Double) -> Double {
            if value.isNaN { return low }
            return Swift.min(high, Swift.max(low, value))
        }
    }

    static let spacing = Bounds(low: 0, high: 128)
    static let radius = Bounds(low: 0, high: 256)
    static let fontSize = Bounds(low: 8, high: 96)
    static let lineHeight = Bounds(low: 0.8, high: 3)
    static let fontWeight = Bounds(low: 100, high: 900)
    static let letterSpacing = Bounds(low: -2, high: 8)
    static let shadowOffset = Bounds(low: -64, high: 64)
    static let shadowBlur = Bounds(low: 0, high: 128)
    static let shadowSpread = Bounds(low: -64, high: 64)
    static let unit = Bounds(low: 0, high: 1)

    /// A number of a theme as the reader takes it: an infinite one too (a JSON parser reads
    /// `1e309` as infinity), because the reader replaces it and does not skip it.
    static func number(_ value: JSONValue?) -> Double? {
        if case .number(let number)? = value, !number.isNaN { return number }
        return nil
    }

    /// The number the reader draws with. Inside the bounds the number stays. Outside them (or not
    /// finite) it is the value of the same token and field of the built-in theme of the same
    /// brightness when there is one (`builtIn`), otherwise the nearest bound; the replacement is
    /// reported with its place.
    static func fit(_ value: Double, _ bounds: Bounds, builtIn: Double?, place: String, at where: String, sink: ReportSink) -> Double {
        if bounds.contains(value) { return value }
        let borrowed = builtIn.flatMap { bounds.contains($0) ? $0 : nil }
        let result = borrowed ?? bounds.nearest(value)
        sink.add(
            .ignoredInput, "\(place): \(`where`)",
            "a number outside the bounds of the theme schema: replaced by \(borrowed != nil ? "the built-in value" : "the nearest bound") (\(result))")
        return result
    }
}
