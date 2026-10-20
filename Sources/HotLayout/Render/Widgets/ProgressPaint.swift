import Foundation

/// The paint of a scale resolved against the theme (`resolveProgressPaint`): the thickness, the
/// track under the WHOLE scale and the fill over it, a gradient or a solid colour.
struct ProgressPaint: Equatable {
    enum Fill: Equatable {
        case color(RGBA)
        case gradient([GradientValue.Stop])
    }

    var thickness: Double
    var track: RGBA
    var fill: Fill
}

/// The label of a ring: the style it is drawn with (`progressLabel`).
struct ProgressLabelStyle: Equatable {
    var token: String
    var typography: TextStyleValue
    var color: RGBA
}

extension ProgressRules {
    /// A spacing token or a whole number; a fraction, an unknown token or another shape gives
    /// `nil` and the default applies.
    static func thickness(_ ref: JSONValue?, resolver: StyleResolver) -> Double? {
        switch ref {
        case .number(let value)?:
            guard value.isFinite, value == value.rounded() else { return nil }
            return resolver.spacing(.number(value))
        case .string?:
            return resolver.spacing(ref)
        default:
            return nil
        }
    }

    static func paint(_ props: JSONObject, resolver: StyleResolver) -> ProgressPaint {
        let thickness =
            thickness(props["thickness"], resolver: resolver)
            ?? resolver.spacing(.string(defaultThickness)) ?? 0
        let track =
            resolver.color(props["trackColor"])
            ?? resolver.theme.coreColor(defaultTrackColor)
        if let gradient = resolver.gradient(props["gradient"]) {
            return ProgressPaint(thickness: thickness, track: track, fill: .gradient(gradient.stops))
        }
        let color = resolver.color(props["color"]) ?? resolver.theme.coreColor(defaultColor)
        return ProgressPaint(thickness: thickness, track: track, fill: .color(color))
    }

    /// The colour of the current step: none when absent or unresolved, so it looks unfilled.
    static func currentColor(_ props: JSONObject, resolver: StyleResolver) -> RGBA? {
        resolver.color(props["currentColor"])
    }

    /// `labelTypography` / `labelColor` where they resolve, `caption` / `onSurface` otherwise. A
    /// token the theme does not know gives the default style WHOLE; the label inherits nothing.
    static func labelStyle(_ props: JSONObject, resolver: StyleResolver) -> ProgressLabelStyle {
        let theme = resolver.theme
        let ref = props["labelTypography"]
        var token = defaultLabelTypography
        var typography = theme.coreTypography(defaultLabelTypography)
        if let named = resolver.typography(ref) {
            typography = named
            token = ref?.stringValue ?? ref?["token"]?.stringValue ?? defaultLabelTypography
        }
        let color = resolver.color(props["labelColor"]) ?? theme.coreColor(defaultLabelColor)
        return ProgressLabelStyle(token: token, typography: typography, color: color)
    }

    /// `percent` is the SHOWN share; `valueOfMax` writes the numbers it is given, in one string
    /// with its spaces. `none` (and a word not known) draws nothing.
    static func labelText(format: String?, value: Double, max: Double, ratio: Double) -> String? {
        switch format {
        case "percent": return "\(SafeInt.clamped((ratio * 100 + 0.5).rounded(.down)))%"
        case "valueOfMax": return "\(signed(value)) / \(signed(max))"
        default: return nil
        }
    }

    /// A number as JavaScript writes it: shortest digits, no exponent, a minus sign.
    static func signed(_ value: Double) -> String {
        (value < 0 ? "-" : "") + DecimalText.plain(value)
    }

    /// The colour of a gradient along a filled part at `share` (0…1 of the fill): before the first
    /// stop the first colour, after the last the last; between them a straight blend.
    static func gradientColor(_ stops: [GradientValue.Stop], at share: Double) -> RGBA {
        guard let first = stops.first, let last = stops.last else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        if share <= first.position { return first.color }
        if share >= last.position { return last.color }
        for (low, high) in zip(stops, stops.dropFirst()) where share >= low.position && share <= high.position {
            let span = high.position - low.position
            let weight = span > 0 ? (share - low.position) / span : 1
            return RGBA(
                red: low.color.red + (high.color.red - low.color.red) * weight,
                green: low.color.green + (high.color.green - low.color.green) * weight,
                blue: low.color.blue + (high.color.blue - low.color.blue) * weight,
                alpha: low.color.alpha + (high.color.alpha - low.color.alpha) * weight
            )
        }
        return last.color
    }
}

extension RGBA {
    /// `#rrggbb` of the colour (the alpha is read apart).
    var hex: String {
        func byte(_ value: Double) -> Int { SafeInt.clamped((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }
}
