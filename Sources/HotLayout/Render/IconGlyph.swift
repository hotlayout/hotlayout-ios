import SwiftUI

/// One icon of the set drawn at `glyph` points inside a box of `box`. An unknown name draws
/// an empty box of the same size (`unknownIcon: 'empty-box-same-size'`); a mirrored name is
/// flipped in right-to-left text.
struct IconGlyph: View {
    let name: String?
    let glyph: Double
    let box: CGSize
    let color: Color
    let rightToLeft: Bool

    var body: some View {
        let elements = name.flatMap(IconSet.elements) ?? []
        let mirrored = IconSet.isMirrored(name, rightToLeft: rightToLeft)
        Canvas { context, size in
            let scale = CGFloat(glyph / IconSet.gridSize)
            let origin = CGPoint(x: (size.width - CGFloat(glyph)) / 2, y: (size.height - CGFloat(glyph)) / 2)
            context.translateBy(x: origin.x, y: origin.y)
            if mirrored {
                context.translateBy(x: CGFloat(glyph), y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            for element in elements {
                let path = Path(element.path.cgPath(scale: scale))
                if element.filled { context.fill(path, with: .color(color)) }
                if element.stroked {
                    context.stroke(
                        path, with: .color(color), style: StrokeStyle(lineWidth: CGFloat(element.strokeWidth) * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: box.width, height: box.height)
        .accessibilityHidden(true)
    }
}
