import SwiftUI

/// How a parent places a child: stretched to its width or at its natural width.
struct Placement {
    var stretchWidth: Bool
    /// Where the content sits inside a stretched box.
    var contentAlignment: Alignment = .topLeading
    /// A layer on the whole stack (`fill`): the size of the stack, not the node's own.
    var fillsStack = false
    /// A child of a column: a named width is not wider than the column.
    var clampsWidth = false
    /// A card of a carousel with `perView`: this box width, whatever the card says about its own.
    var cardWidth: Double?

    static let natural = Placement(stretchWidth: false)
    static let stretched = Placement(stretchWidth: true)
    static let fillingStack = Placement(stretchWidth: true, fillsStack: true)
}

extension BoxLook {
    /// The same look without its margin (the margin stands outside the press target and the motion).
    var withoutMargin: BoxLook {
        var copy = self
        copy.margin = .zero
        return copy
    }
}

extension Sides {
    var edgeInsets: EdgeInsets { EdgeInsets(top: top, leading: start, bottom: bottom, trailing: end) }
}

/// Rounded corners named logically (`topStart`…); the shape mirrors in right-to-left text.
struct LogicalCornersShape: Shape {
    var corners: Corners
    var rightToLeft: Bool
    /// How far the shape reaches past the rect it is drawn in (a shadow's spread); 0 for a box.
    var spread: Double = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: -CGFloat(spread), dy: -CGFloat(spread))
        let limit = min(rect.width, rect.height) / 2
        func r(_ value: Double) -> CGFloat { min(CGFloat(value), limit) }
        let topLeft = r(rightToLeft ? corners.topEnd : corners.topStart)
        let topRight = r(rightToLeft ? corners.topStart : corners.topEnd)
        let bottomRight = r(rightToLeft ? corners.bottomStart : corners.bottomEnd)
        let bottomLeft = r(rightToLeft ? corners.bottomEnd : corners.bottomStart)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight), radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0),
            clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight), radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90),
            clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft), radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180),
            clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(
            center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft), radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270),
            clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The box of a node: size, padding, background, border, radius, shadow, opacity and margin,
/// in the order CSS draws them (`sizeIncludes: border, padding`; the radius clips the
/// background and the content).
struct NodeBoxModifier: ViewModifier {
    let givenLook: BoxLook
    let placement: Placement
    let context: RenderContext

    /// A layer on the whole stack takes the size of the stack: its own sizes do not apply
    /// (`x-style.fillOverridesSize`).
    private var look: BoxLook {
        if let card = placement.cardWidth {
            var copy = givenLook
            copy.width = card
            copy.minWidth = nil
            copy.maxWidth = nil
            return copy
        }
        guard placement.fillsStack else { return givenLook }
        var copy = givenLook
        copy.width = nil
        copy.height = nil
        copy.minWidth = nil
        copy.maxWidth = nil
        copy.minHeight = nil
        copy.maxHeight = nil
        return copy
    }

    init(look: BoxLook, placement: Placement, context: RenderContext) {
        self.givenLook = look
        self.placement = placement
        self.context = context
    }

    func body(content: Content) -> some View {
        let shape = LogicalCornersShape(corners: look.radius ?? Corners(), rightToLeft: context.rightToLeft)
        let rounded = look.radius != nil
        let border = look.borderWidth ?? 0
        let inner =
            content
            .padding(
                EdgeInsets(
                    top: look.padding.top + border, leading: look.padding.start + border, bottom: look.padding.bottom + border,
                    trailing: look.padding.end + border)
            )
            .frame(
                minWidth: look.minWidth.map { CGFloat($0) },
                maxWidth: look.maxWidth.map { CGFloat($0) } ?? (placement.stretchWidth && look.width == nil ? .infinity : nil),
                alignment: placement.contentAlignment
            )
            .frame(maxHeight: placement.fillsStack ? .infinity : nil, alignment: placement.contentAlignment)
            .modifier(
                NamedWidth(
                    width: look.width.map { CGFloat($0) }, height: look.height.map { CGFloat($0) }, alignment: placement.contentAlignment,
                    clampsToParent: placement.clampsWidth)
            )
            .frame(minHeight: look.minHeight.map { CGFloat($0) }, maxHeight: look.maxHeight.map { CGFloat($0) }, alignment: placement.contentAlignment)
        let clipsContent = !look.surfaceDrawnByWidget && (rounded || look.width != nil || look.height != nil)
        return
            inner
            // The content is clipped by the inner edge of the border (the padding box, as in CSS): the
            // background shows in the corner between the two radii.
            .clipped(to: InsetCorners(base: shape, amount: border), when: clipsContent && border > 0 && rounded)
            .background(BackgroundView(background: look.background, shadow: look.shadow, shape: shape, context: context))
            .clipped(to: shape, when: clipsContent)
            .overlay {
                if let color = look.borderColor, border > 0 {
                    if look.borderDashed {
                        DashedBorderOverlay(width: border, color: color, radius: look.radius, rightToLeft: context.rightToLeft)
                    } else {
                        shape.inset(by: border / 2).stroke(color.color, lineWidth: border)
                    }
                }
            }
            .compositingGroup()
            .shadowLayers(look.shadow, shape: shape)
            .glass(look.backdropBlur, shape: shape)
            .opacity(look.opacity ?? 1)
            .padding(EdgeInsets(top: look.margin.top, leading: look.margin.start, bottom: look.margin.bottom, trailing: look.margin.end))
    }
}

extension LogicalCornersShape: InsettableShape {
    func inset(by amount: CGFloat) -> some InsettableShape {
        InsetCorners(base: self, amount: amount)
    }
}

struct InsetCorners: InsettableShape {
    var base: LogicalCornersShape
    var amount: CGFloat

    func path(in rect: CGRect) -> Path {
        var corners = base.corners
        let d = Double(amount)
        corners.topStart = max(0, corners.topStart - d)
        corners.topEnd = max(0, corners.topEnd - d)
        corners.bottomEnd = max(0, corners.bottomEnd - d)
        corners.bottomStart = max(0, corners.bottomStart - d)
        return LogicalCornersShape(corners: corners, rightToLeft: base.rightToLeft).path(in: rect.insetBy(dx: amount, dy: amount))
    }

    func inset(by more: CGFloat) -> InsetCorners { InsetCorners(base: base, amount: amount + more) }
}

extension View {
    /// CSS shadows, drawn outside the box (`ShadowPaint`).
    @ViewBuilder
    func shadowLayers(_ layers: [ShadowLayer], shape: LogicalCornersShape) -> some View {
        if layers.isEmpty {
            self
        } else {
            self.background(ShadowPaint(layers: layers, shape: shape))
        }
    }
}

struct BackgroundView: View {
    let background: BackgroundValue?
    let shadow: [ShadowLayer]
    let shape: LogicalCornersShape
    let context: RenderContext

    var body: some View {
        switch background {
        case .color(let color)?:
            shape.fill(color.color)
        case .gradient(let gradient)?:
            GradientFill(gradient: gradient).clipShape(shape)
        case .image(let source, let fit)?:
            RemoteImage(
                url: ImageSource.url(source, context: context), fit: fit,
                placeholder: context.theme.colorValue("muted")?.withOpacity(0.15).color ?? .gray.opacity(0.15), sink: context.sink)
        case nil:
            Color.clear
        }
    }
}

/// Start and end of a CSS linear gradient in normalised box coordinates ((0, 0) top left, y down).
/// The axis angles are CSS degrees; 45 / 135 / 225 / 315 are exactly CSS `to <corner>`
/// (`diagonalGradientGeometry: 'css-to-corner'`): the line runs through the centre perpendicular to
/// the diagonal joining the other two corners, so the target corner gets position 1. Any other angle
/// has CSS semantics (the line is `|w sin a| + |h cos a|` long). The direction is physical: it is not
/// mirrored in right-to-left scripts.
func gradientPoints(angle degrees: Double, size: CGSize) -> (start: UnitPoint, end: UnitPoint) {
    var angle = degrees.truncatingRemainder(dividingBy: 360)
    if angle < 0 { angle += 360 }
    let w = Double(size.width), h = Double(size.height)
    let radians = angle * .pi / 180
    if let signs = [45.0: (1.0, -1.0), 135: (1, 1), 225: (-1, 1), 315: (-1, -1)][angle] {
        let squares = w * w + h * h
        guard squares > 0 else { return (UnitPoint(x: 0, y: 0), UnitPoint(x: 1, y: 1)) }
        let dx = signs.0 * h * h / squares
        let dy = signs.1 * w * w / squares
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
    let dx = sin(radians), dy = -cos(radians)
    guard w > 0, h > 0 else { return (UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2), UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)) }
    let length = abs(w * dx) + abs(h * dy)
    let ex = dx * length / 2 / w, ey = dy * length / 2 / h
    return (UnitPoint(x: 0.5 - ex, y: 0.5 - ey), UnitPoint(x: 0.5 + ex, y: 0.5 + ey))
}

/// A CSS linear gradient for a box of this size.
func linearGradient(_ gradient: GradientValue, size: CGSize) -> LinearGradient {
    let stops = gradient.stops.map { Gradient.Stop(color: $0.color.color, location: $0.position) }
    let points = gradientPoints(angle: gradient.angle, size: size)
    return LinearGradient(stops: stops, startPoint: points.start, endPoint: points.end)
}

/// The gradient filling the box it is given: the line depends on the laid-out size, so it is drawn
/// from the proposed size and not from fixed unit points.
struct GradientFill: View {
    let gradient: GradientValue

    var body: some View {
        GeometryReader { proxy in
            Rectangle().fill(linearGradient(gradient, size: proxy.size))
        }
    }
}

extension View {
    @ViewBuilder
    func clipped<S: Shape>(to shape: S, when condition: Bool) -> some View {
        if condition { self.clipShape(shape) } else { self }
    }
}
