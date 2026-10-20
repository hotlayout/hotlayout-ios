import Foundation

/// The geometry of a picture (`x-style.layout.image`): the proportion of its box, the box itself,
/// where the file lies in it and the corner radius that clips it. Pure functions, run against the
/// shared tables; the views only draw what these say.
enum ImageRules {
    static let ratioWords: [String: Double] = ["1:1": 1, "16:9": 16.0 / 9, "4:3": 4.0 / 3]
    static let ratioFallback = 16.0 / 9
    static let ratioRange: ClosedRange<Double> = 0.125...8

    /// "Width over height" of the value of `aspectRatio`: a word of the list, or an own pair of
    /// positive finite sides clamped to the range; anything else is the field default.
    static func ratio(of value: JSONValue?) -> Double {
        switch value {
        case .string(let word)?:
            return ratioWords[word] ?? ratioFallback
        case .object(let pair)?:
            guard case .number(let width)? = pair["width"], case .number(let height)? = pair["height"],
                width.isFinite, height.isFinite, width > 0, height > 0
            else { return ratioFallback }
            return min(max(width / height, ratioRange.lowerBound), ratioRange.upperBound)
        default:
            return ratioFallback
        }
    }

    struct Box: Equatable {
        var width: Double
        var height: Double
        /// The height came from the proportion (no named height).
        var byRatio: Bool
    }

    /// The box of a picture. The width comes from the place; the height is the named one or
    /// width over the proportion (the proportion is never read beside a named height). The
    /// limits of the height act in both cases and the minimum beats the maximum.
    static func box(aspectRatio: JSONValue?, width: Double, height: Double?, minHeight: Double?, maxHeight: Double?) -> Box {
        let byRatio = height == nil
        let raw = height ?? width / ratio(of: aspectRatio)
        let capped = maxHeight.map { min(raw, $0) } ?? raw
        let floored = minHeight.map { max(capped, $0) } ?? capped
        return Box(width: width, height: floored, byRatio: byRatio)
    }

    struct Rect: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// Where a file of the proportion `natural` (width over height) lies in a box, centred:
    /// `contain` inside it, anything else (the field default is `cover`) over it.
    static func paintRect(boxWidth: Double, boxHeight: Double, natural: Double, fit: String?) -> Rect {
        guard boxWidth > 0, boxHeight > 0, natural > 0, natural.isFinite else { return Rect(x: 0, y: 0, width: boxWidth, height: boxHeight) }
        let boxRatio = boxWidth / boxHeight
        let widthBound = fit == "contain" ? natural >= boxRatio : natural <= boxRatio
        let width = widthBound ? boxWidth : boxHeight * natural
        let height = widthBound ? boxWidth / natural : boxHeight
        return Rect(x: (boxWidth - width) / 2, y: (boxHeight - height) / 2, width: width, height: height)
    }

    /// The radius a corner really has: the named one, held to half of the shorter side.
    static func effectiveRadius(boxWidth: Double, boxHeight: Double, radius: Double) -> Double {
        max(0, min(radius, boxWidth / 2, boxHeight / 2))
    }

    /// A circle is a square whose effective radius is half the side. The token `pill` is a
    /// number of the theme (72), so a larger square with `pill` is a rounded square.
}
