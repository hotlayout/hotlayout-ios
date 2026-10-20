import Foundation

/// `style.shadowColor: background` (`x-shadowColor`): the shadow takes the hue of the node's own
/// background and keeps the opacity, offset, blur and spread of every layer.
enum ShadowTint {
    static let word = "background"

    /// The index of the stop whose position is nearest to the middle; the earlier one on a tie.
    static func middleStop(_ positions: [Double]) -> Int? {
        var best: Int?
        var bestDistance = Double.infinity
        for (index, position) in positions.enumerated() {
            let distance = abs(position - 0.5)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// The hue of a background: a solid colour, or the stop of a gradient nearest to the middle;
    /// `nil` for no background, an image or a colour that does not resolve. Its own opacity does
    /// not count: the layer carries the opacity.
    static func hue(of background: JSONValue?, resolver: StyleResolver) -> RGBA? {
        guard let object = background?.objectValue else { return nil }
        switch object["kind"]?.stringValue {
        case "color":
            return resolver.color(object["color"])
        case "gradient":
            guard let gradient = resolver.gradient(object["gradient"]), let index = middleStop(gradient.stops.map(\.position)) else { return nil }
            return gradient.stops[index].color
        default:
            return nil
        }
    }

    /// The layers as drawn: with the hue of the background when the field asks for it.
    static func apply(_ layers: [ShadowLayer], style: JSONObject, resolver: StyleResolver) -> [ShadowLayer] {
        guard style["shadowColor"]?.stringValue == word, !layers.isEmpty, let hue = hue(of: style["background"], resolver: resolver) else { return layers }
        return layers.map { layer in
            var tinted = layer
            tinted.color = RGBA(red: hue.red, green: hue.green, blue: hue.blue, alpha: layer.color.alpha)
            return tinted
        }
    }
}
