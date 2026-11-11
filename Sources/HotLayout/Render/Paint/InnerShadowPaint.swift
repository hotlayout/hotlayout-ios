import SwiftUI

/// The geometry of an inner layer of a shadow, for a box of this size.
///
/// The layer is clipped to the padding box (the box inside its border, corners smaller by the border),
/// and what is painted is everything OUTSIDE a hole: the clip moved by the offset and narrowed by the
/// spread on every side (a positive spread makes the shadow thicker, a negative one thinner), its corners
/// smaller by the spread, a square corner staying square. As in CSS `box-shadow: inset`.
enum InsetShadowGeometry {
    struct Rect: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var corners: Corners
    }

    /// The padding box: the box inside the border, its corners smaller by the border width.
    static func clip(width: Double, height: Double, border: Double, corners: Corners) -> Rect {
        func inner(_ radius: Double) -> Double { Swift.max(0, radius - border) }
        return Rect(
            x: border, y: border, width: Swift.max(0, width - 2 * border), height: Swift.max(0, height - 2 * border),
            corners: Corners(
                topStart: inner(corners.topStart), topEnd: inner(corners.topEnd), bottomEnd: inner(corners.bottomEnd), bottomStart: inner(corners.bottomStart)))
    }

    /// The hole of a layer inside the clip.
    static func hole(clip: Rect, offsetX: Double, offsetY: Double, spread: Double) -> Rect {
        func narrowed(_ radius: Double) -> Double { radius > 0 ? Swift.max(0, radius - spread) : 0 }
        let corners = clip.corners
        return Rect(
            x: clip.x + spread + offsetX, y: clip.y + spread + offsetY, width: Swift.max(0, clip.width - 2 * spread),
            height: Swift.max(0, clip.height - 2 * spread),
            corners: Corners(
                topStart: narrowed(corners.topStart), topEnd: narrowed(corners.topEnd), bottomEnd: narrowed(corners.bottomEnd),
                bottomStart: narrowed(corners.bottomStart)))
    }
}

/// Everything around a hole, so a fill with the even-odd rule paints the outside only.
private struct OutsideHole: Shape {
    let hole: InsetShadowGeometry.Rect
    let rightToLeft: Bool

    /// How far past the box the painted outside reaches: far enough for the largest blur and offset.
    private static let reach: CGFloat = 600

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -Self.reach, dy: -Self.reach))
        let shape = LogicalCornersShape(corners: hole.corners, rightToLeft: rightToLeft)
        path.addPath(shape.path(in: CGRect(x: hole.x, y: hole.y, width: hole.width, height: hole.height)))
        return path
    }
}

/// The inner layers of a shadow: inside the border, over the background, under the content. The first layer lies
/// nearest to the element and on top. A layer is the outside of its hole filled with its colour, blurred by half the
/// blur (as the outer layers are) and cut to the padding box; the offset is physical.
struct InnerShadowPaint: View {
    let layers: [ShadowLayer]
    let shape: LogicalCornersShape
    let borderWidth: Double

    var body: some View {
        GeometryReader { proxy in
            let width = Double(proxy.size.width), height = Double(proxy.size.height)
            let clip = InsetShadowGeometry.clip(width: width, height: height, border: borderWidth, corners: shape.corners)
            ZStack {
                ForEach(Array(layers.reversed().enumerated()), id: \.offset) { _, layer in
                    OutsideHole(
                        hole: InsetShadowGeometry.hole(clip: clip, offsetX: layer.offsetX, offsetY: layer.offsetY, spread: layer.spread),
                        rightToLeft: shape.rightToLeft
                    )
                    .fill(layer.color.color, style: FillStyle(eoFill: true))
                    .blur(radius: layer.blur / 2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(InsetCorners(base: shape, amount: CGFloat(borderWidth)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The inner layers of a shadow laid over this view (the background of a box), under what the box holds.
    @ViewBuilder
    func innerShadows(_ layers: [ShadowLayer], shape: LogicalCornersShape, borderWidth: Double) -> some View {
        let inner = layers.filter(\.inset)
        if inner.isEmpty {
            self
        } else {
            self.overlay { InnerShadowPaint(layers: inner, shape: shape, borderWidth: borderWidth) }
        }
    }
}
