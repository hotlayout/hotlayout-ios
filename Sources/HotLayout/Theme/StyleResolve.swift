import Foundation

/// Logical sides: `start` and `end` follow the writing direction (`x-style.sides: 'logical'`).
struct Sides: Equatable, Sendable {
    var top: Double = 0
    var start: Double = 0
    var bottom: Double = 0
    var end: Double = 0

    static let zero = Sides()

    var horizontal: Double { start + end }
    var vertical: Double { top + bottom }
}

struct Corners: Equatable, Sendable {
    var topStart: Double = 0
    var topEnd: Double = 0
    var bottomEnd: Double = 0
    var bottomStart: Double = 0

    var isUniform: Bool { topStart == topEnd && topEnd == bottomEnd && bottomEnd == bottomStart }
}

enum BackgroundValue: Equatable, Sendable {
    case color(RGBA)
    case gradient(GradientValue)
    case image(source: JSONValue, fit: String)
}

/// The box look of a node after tokens were resolved: what the `style` of a node draws.
struct BoxLook: Equatable, Sendable {
    /// The widget draws its own surface and its shadow reaches outside the box: the box does not cut it.
    var surfaceDrawnByWidget = false
    var padding = Sides.zero
    var margin = Sides.zero
    var width: Double?
    var height: Double?
    var minWidth: Double?
    var maxWidth: Double?
    var minHeight: Double?
    var maxHeight: Double?
    var radius: Corners?
    var borderWidth: Double?
    var borderColor: RGBA?
    /// `style.border.style: 'dashed'`; any other word is a solid line.
    var borderDashed = false
    var background: BackgroundValue?
    var shadow: [ShadowLayer] = []
    var opacity: Double?
    /// `style.backdropBlur` (glass): the standard deviation of the blur under the box, 1…40.
    var backdropBlur: Int?
}

/// Text look that a node passes to its descendants (`x-style.inherited`: color and typography).
struct InheritedLook: Equatable, Sendable {
    var color: RGBA
    var typography: TextStyleValue
    var fontStyleItalic: Bool = false
    var decoration: String?
    /// The reference of the colour a node or an ancestor NAMED for its text; `nil` while nobody
    /// has (parts of composite widgets then keep their built-in colours: `colorNamed`).
    var colorRef: JSONValue?
}

/// Turns references of a document (a token, a token with opacity, an own value) into values of
/// a theme. Literal values are clamped to the bounds of the schema (`literalOutOfRange:
/// 'clamp'`); an unknown token gives `nil`, and the field default applies (`unknownToken`).
struct StyleResolver {
    let theme: HotlayoutTheme

    init(theme: HotlayoutTheme) {
        self.theme = theme
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, value)) }

    func color(_ ref: JSONValue?) -> RGBA? {
        switch ref {
        case .string(let token)?:
            return theme.colorValue(token)
        case .object(let object)?:
            if let hex = object["value"]?.stringValue {
                guard let color = RGBA(hex: hex) else { return nil }
                return object["opacity"]?.numberValue.map { color.withOpacity(Self.clamp($0, 0, 1)) } ?? color
            }
            if let token = object["token"]?.stringValue, let color = theme.colorValue(token) {
                return color.withOpacity(Self.clamp(object["opacity"]?.numberValue ?? 1, 0, 1))
            }
            return nil
        default:
            return nil
        }
    }

    func spacing(_ ref: JSONValue?) -> Double? {
        switch ref {
        case .number(let value)?: return Self.clamp(value, 0, 128)
        case .string(let token)?: return token == "none" ? 0 : theme.spacing[token]
        default: return nil
        }
    }

    func radius(_ ref: JSONValue?) -> Double? {
        switch ref {
        case .number(let value)?: return Self.clamp(value, 0, 256)
        case .string(let token)?: return token == "none" ? 0 : theme.radius[token]
        default: return nil
        }
    }

    /// A box spacing: one reference for all sides, or named sides (an unnamed side is zero).
    func sides(_ ref: JSONValue?) -> Sides? {
        guard let ref else { return nil }
        if let object = ref.objectValue {
            return Sides(
                top: spacing(object["top"]) ?? 0, start: spacing(object["start"]) ?? 0,
                bottom: spacing(object["bottom"]) ?? 0, end: spacing(object["end"]) ?? 0
            )
        }
        guard let all = spacing(ref) else { return nil }
        return Sides(top: all, start: all, bottom: all, end: all)
    }

    func corners(_ ref: JSONValue?) -> Corners? {
        guard let ref else { return nil }
        if let object = ref.objectValue {
            return Corners(
                topStart: radius(object["topStart"]) ?? 0, topEnd: radius(object["topEnd"]) ?? 0,
                bottomEnd: radius(object["bottomEnd"]) ?? 0, bottomStart: radius(object["bottomStart"]) ?? 0
            )
        }
        guard let all = radius(ref) else { return nil }
        return Corners(topStart: all, topEnd: all, bottomEnd: all, bottomStart: all)
    }

    func typography(_ ref: JSONValue?) -> TextStyleValue? {
        switch ref {
        case .string(let token)?:
            return theme.typography[token]
        case .object(let object)?:
            guard let token = object["token"]?.stringValue, var style = theme.typography[token] else { return nil }
            if let size = object["fontSize"]?.numberValue { style.fontSize = Self.clamp(size, 8, 96) }
            if let weight = object["fontWeight"]?.numberValue { style.fontWeight = SafeInt.clamped(Self.clamp(weight, 100, 900)) }
            if let line = object["lineHeight"]?.numberValue { style.lineHeight = Self.clamp(line, 0.8, 3) }
            if let spacing = object["letterSpacing"]?.numberValue { style.letterSpacing = Self.clamp(spacing, -2, 8) }
            return style
        default:
            return nil
        }
    }

    func shadow(_ ref: JSONValue?) -> [ShadowLayer]? {
        switch ref {
        case .string(let token)?:
            return theme.elevation[token]
        case .array(let layers)?:
            guard layers.count <= 4 else { return nil }
            var result: [ShadowLayer] = []
            for layer in layers {
                guard let layer = layer.objectValue, let color = color(layer["color"]) else { return nil }
                result.append(
                    ShadowLayer(
                        offsetX: Self.clamp(layer["offsetX"]?.numberValue ?? 0, -64, 64),
                        offsetY: Self.clamp(layer["offsetY"]?.numberValue ?? 0, -64, 64),
                        blur: Self.clamp(layer["blur"]?.numberValue ?? 0, 0, 128),
                        spread: Self.clamp(layer["spread"]?.numberValue ?? 0, -64, 64),
                        color: color
                    ))
            }
            return result
        default:
            return nil
        }
    }

    func gradient(_ ref: JSONValue?) -> GradientValue? {
        switch ref {
        case .string(let token)?:
            return theme.gradient[token]
        case .object(let object)?:
            guard let angle = object["angle"]?.numberValue, let stops = object["stops"]?.arrayValue, (2...8).contains(stops.count) else { return nil }
            var result: [GradientValue.Stop] = []
            for stop in stops {
                guard let stop = stop.objectValue, let color = color(stop["color"]), let position = stop["position"]?.numberValue else { return nil }
                result.append(GradientValue.Stop(color: color, position: Self.clamp(position, 0, 1)))
            }
            // Stops out of order are not drawn (`unorderedGradient: 'do-not-draw'`).
            guard zip(result, result.dropFirst()).allSatisfy({ $0.position <= $1.position }) else { return nil }
            return GradientValue(angle: angle, stops: result)
        default:
            return nil
        }
    }

    /// A size of the box: a number in 1…1200, or a binding whose value out of range gives the
    /// fallback (`boundSizeOutOfRange: 'use-fallback'`).
    func dimension(_ ref: JSONValue?, scope: DataScope) -> Double? {
        switch ref {
        case .number(let value)?: return Self.clamp(value, 1, 1200)
        case .object(let object)?:
            guard object["kind"]?.stringValue == "binding" else { return nil }
            let fallback = object["fallback"]?.numberValue.map { Self.clamp($0, 1, 1200) }
            if let path = object["path"]?.stringValue, let value = scope[path]?.numberValue, (1...1200).contains(value) { return value }
            return fallback
        default:
            return nil
        }
    }

    /// The box look of an effective style.
    func box(_ style: JSONObject, scope: DataScope) -> BoxLook {
        var look = BoxLook()
        look.padding = sides(style["padding"]) ?? .zero
        look.margin = sides(style["margin"]) ?? .zero
        look.width = dimension(style["width"], scope: scope)
        look.height = dimension(style["height"], scope: scope)
        look.minWidth = dimension(style["minWidth"], scope: scope)
        look.maxWidth = dimension(style["maxWidth"], scope: scope)
        look.minHeight = dimension(style["minHeight"], scope: scope)
        look.maxHeight = dimension(style["maxHeight"], scope: scope)
        // An inverted range: the minimum wins (`invertedSizeRange: 'min-wins'`).
        if let low = look.minWidth, let high = look.maxWidth, high < low { look.maxWidth = low }
        if let low = look.minHeight, let high = look.maxHeight, high < low { look.maxHeight = low }
        look.radius = corners(style["radius"])
        if let border = style["border"]?.objectValue, let color = color(border["color"]), let width = border["width"]?.numberValue {
            look.borderWidth = Self.clamp(width, 0.5, 16)
            look.borderColor = color
            look.borderDashed = DashedBorderRules.isDashed(.object(border))
        }
        if let background = style["background"]?.objectValue {
            switch background["kind"]?.stringValue {
            case "color": look.background = color(background["color"]).map(BackgroundValue.color)
            case "gradient": look.background = gradient(background["gradient"]).map(BackgroundValue.gradient)
            case "image":
                if let source = background["source"] {
                    look.background = .image(source: source, fit: background["fit"]?.stringValue == "contain" ? "contain" : "cover")
                }
            default: break
            }
        }
        look.shadow = ShadowTint.apply(shadow(style["shadow"]) ?? [], style: style, resolver: self)
        look.opacity = style["opacity"]?.numberValue.map { Self.clamp($0, 0, 1) }
        look.backdropBlur = ModalRules.blurRadius(style["backdropBlur"])
        return look
    }
}

/// The style of a node (`style`, `styleWhen`).
enum NodeStyle {
    /// The effective style: the base style with the FIRST case whose condition holds laid over
    /// it, field by top-level field (`caseSelection: 'first-match'`, `caseMerge: 'top-level-fields'`).
    static func effective(_ node: DocumentNode, scope: DataScope) -> JSONObject {
        var style = node.style?.objectValue ?? JSONObject()
        for item in node.styleWhen?.arrayValue ?? [] {
            guard let entry = item.objectValue, let condition = entry["when"], Conditions.holds(condition, scope: scope) else { continue }
            for (key, value) in entry["style"]?.objectValue ?? JSONObject() { style[key] = value }
            break
        }
        return style
    }

    /// The text look a node passes down: its own color and typography where it names them,
    /// the parent's otherwise (an unknown token keeps the parent's: `unknownInheritedToken`).
    static func inherited(_ parent: InheritedLook, style: JSONObject, resolver: StyleResolver) -> InheritedLook {
        var look = parent
        if let color = resolver.color(style["color"]) {
            look.color = color
            look.colorRef = style["color"]
        }
        if let typography = resolver.typography(style["typography"]) { look.typography = typography }
        // A word outside the lists is no field: the inherited one stays (`unknownWord`).
        let emphasis = TextEmphasisRules.inherit(look.emphasis, style: style)
        look.fontStyleItalic = emphasis.fontStyle == "italic"
        look.decoration = emphasis.textDecoration == "none" ? nil : emphasis.textDecoration
        return look
    }

    static let rootColor = "onSurface"
    static let rootTypography = "bodyM"

    /// The look at the screen root (`x-style.root`): `onSurface` text in `bodyM`.
    static func root(_ resolver: StyleResolver) -> InheritedLook {
        InheritedLook(color: resolver.theme.coreColor(rootColor), typography: resolver.theme.coreTypography(rootTypography))
    }
}

extension InheritedLook {
    /// The emphasis of the text this look passes down (`x-style.layout.textEmphasis`).
    var emphasis: TextEmphasis {
        TextEmphasis(fontStyle: fontStyleItalic ? "italic" : "normal", textDecoration: decoration ?? "none")
    }
}
