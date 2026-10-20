import Foundation

/// Conversions from a `Double` that came from a document, a theme or data. `Int(_:)` ends the
/// process when its argument is not finite or not representable, so every such conversion goes
/// through here.
enum SafeInt {
    /// The whole number a value is, or nil when it is not finite, has a fraction, or is out of
    /// the range of `Int`.
    static func exactly(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value)
    }

    /// The value rounded toward zero and saturated to `limit` in magnitude; NaN is 0.
    static func clamped(_ value: Double, limit: Int = 1 << 53) -> Int {
        guard !value.isNaN else { return 0 }
        let bound = Double(limit)
        return Int(Swift.min(bound, Swift.max(-bound, value)).rounded(.towardZero))
    }
}
