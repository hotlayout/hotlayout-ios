import SwiftUI

/// The surface of a widget that takes its look from a role of the theme (`roles.buttonVariant`,
/// `roles.badgeTone`): every slot the node's own style names replaces the slot of the role.
struct RoleSurface {
    var background: RGBA?
    /// The node's own gradient background: it lies over the colour of the role.
    var gradient: GradientValue?
    /// Glass (`style.backdropBlur`): lies on the surface of the role.
    var backdropBlur: Int?
    var foreground: RGBA
    var borderColor: RGBA?
    var borderWidth: Double
    var borderDashed = false
    var typography: TextStyleValue?
    var padding: Sides?
    var corners: Corners?
    var shadow: [ShadowLayer]

    /// A role border is one point wide (`kRoleBorderWidth`).
    static let roleBorderWidth = 1.0

    static func resolve(group: String, name: String, style: JSONObject, context: RenderContext) -> RoleSurface {
        let theme = context.theme
        let resolver = context.resolver
        let role = theme.roles[group]?[name]
        let ownBackground = style["background"]?["kind"]?.stringValue == "color" ? resolver.color(style["background"]?["color"]) : nil
        let look = resolver.box(style, scope: context.scope)
        let ownGradient: GradientValue? = { if case .gradient(let value)? = look.background { return value } else { return nil } }()
        let ownBorder = style["border"]?.objectValue
        return RoleSurface(
            background: ownBackground ?? role?.background.flatMap(theme.colorValue),
            gradient: ownGradient,
            backdropBlur: look.backdropBlur,
            foreground: resolver.color(style["color"]) ?? role?.foreground.flatMap(theme.colorValue) ?? context.inherited.color,
            borderColor: ownBorder.flatMap { resolver.color($0["color"]) } ?? role?.border.flatMap(theme.colorValue),
            borderWidth: ownBorder?["width"]?.numberValue ?? (role?.border != nil ? roleBorderWidth : 0),
            borderDashed: DashedBorderRules.isDashed(style["border"]),
            typography: resolver.typography(style["typography"]),
            padding: resolver.sides(style["padding"]),
            corners: resolver.corners(style["radius"]),
            shadow: ShadowTint.apply(resolver.shadow(style["shadow"]) ?? [], style: style, resolver: resolver)
        )
    }

    /// The fill of the surface: the node's own gradient, else the colour of the role or of the style.
    @ViewBuilder
    func fill(shape: LogicalCornersShape, rightToLeft: Bool) -> some View {
        if let gradient {
            GradientFill(gradient: gradient).clipShape(shape)
        } else {
            shape.fill(background?.color ?? .clear)
        }
    }

    /// The same radius on every corner.
    static func corners(all radius: Double) -> Corners {
        Corners(topStart: radius, topEnd: radius, bottomEnd: radius, bottomStart: radius)
    }
}

extension View {
    /// Draws the box of a role surface around the content: background, border, shadow, shape.
    func roleBox(_ surface: RoleSurface, shape: LogicalCornersShape) -> some View {
        self
            .background(surface.fill(shape: shape, rightToLeft: shape.rightToLeft))
            .overlay {
                if let color = surface.borderColor, surface.borderWidth > 0 {
                    if surface.borderDashed {
                        DashedBorderOverlay(width: surface.borderWidth, color: color, radius: surface.corners ?? shape.corners, rightToLeft: shape.rightToLeft)
                    } else {
                        shape.inset(by: surface.borderWidth / 2).stroke(color.color, lineWidth: surface.borderWidth)
                    }
                }
            }
            .shadowLayers(surface.shadow, shape: shape)
            .glass(surface.backdropBlur, shape: shape, cover: surface.gradient == nil ? surface.background?.alpha ?? 0 : 0)
            .contentShape(shape)
    }
}
