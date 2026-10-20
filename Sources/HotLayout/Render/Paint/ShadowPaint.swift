import SwiftUI

/// The shadow layers of a box, drawn outside its shape the way CSS draws `box-shadow`: the
/// shape filled with the colour of the layer (its opacity included), blurred by half the blur
/// and moved by the offset along the screen axes. Nothing is drawn inside the box, so a
/// translucent background does not show the shadow through. The spread grows the shape of the
/// layer by that much on every side (a corner that was square stays square, a round one grows by
/// the spread), and a negative spread shrinks it.
struct ShadowPaint: View {
    let layers: [ShadowLayer]
    let shape: LogicalCornersShape

    @Environment(\.layoutDirection) private var layoutDirection

    /// The shape of a layer: the box's own grown by the spread, as CSS grows the shadow of `box-shadow`.
    static func spread(_ shape: LogicalCornersShape, by spread: Double) -> LogicalCornersShape {
        guard spread != 0 else { return shape }
        func grown(_ radius: Double) -> Double { radius > 0 ? max(0, radius + spread) : 0 }
        var corners = shape.corners
        corners.topStart = grown(corners.topStart)
        corners.topEnd = grown(corners.topEnd)
        corners.bottomEnd = grown(corners.bottomEnd)
        corners.bottomStart = grown(corners.bottomStart)
        return LogicalCornersShape(corners: corners, rightToLeft: shape.rightToLeft, spread: spread)
    }

    var body: some View {
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                Self.spread(shape, by: layer.spread).fill(layer.color.color)
                    .blur(radius: layer.blur / 2)
                    // An offset is mirrored by SwiftUI in right-to-left text; the shadow's is physical.
                    .offset(x: layoutDirection == .rightToLeft ? -layer.offsetX : layer.offsetX, y: layer.offsetY)
            }
        }
        .mask {
            Rectangle().fill(Color.black).padding(-400)
                .overlay { shape.fill(Color.black).blendMode(.destinationOut) }
                .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}
