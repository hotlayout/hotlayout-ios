import SwiftUI

/// A dashed border (`style.border.style: 'dashed'`, `x-style.layout.borderDash`): the centre
/// line of the border, dashes of three widths and gaps of two, the count rounded so that the
/// loop closes evenly. Not the system dash: the pattern is the contract's.
enum DashedBorderRules {
    static let word = "dashed"
    static let dash = 3.0
    static let gap = 2.0

    struct Radii: Equatable {
        var topStart = 0.0
        var topEnd = 0.0
        var bottomEnd = 0.0
        var bottomStart = 0.0
    }

    struct Box: Equatable {
        var width: Double
        var height: Double
        var border: Double
        var radii: Radii
    }

    struct Line: Equatable {
        var radii: Radii
        var perimeter: Double
        var count: Int
        var dash: Double
        var gap: Double
    }

    struct Frame: Equatable {
        var left: Double
        var top: Double
        var right: Double
        var bottom: Double
        var radii: Radii
    }

    /// Only the word `dashed` changes the line; any other word is solid.
    static func isDashed(_ border: JSONValue?) -> Bool {
        border?["style"]?.stringValue == word
    }

    /// The outer radii scaled down as CSS does when they do not fit.
    private static func fitted(_ box: Box) -> Radii {
        func clamp(_ value: Double) -> Double { value.isFinite && value > 0 ? value : 0 }
        let r = box.radii
        let topStart = clamp(r.topStart)
        let topEnd = clamp(r.topEnd)
        let bottomEnd = clamp(r.bottomEnd)
        let bottomStart = clamp(r.bottomStart)
        func ratio(_ side: Double, _ a: Double, _ b: Double) -> Double { a + b > side ? side / (a + b) : 1 }
        let factor =
            [
                ratio(box.width, topStart, topEnd), ratio(box.width, bottomStart, bottomEnd),
                ratio(box.height, topStart, bottomStart), ratio(box.height, topEnd, bottomEnd),
            ].min() ?? 1
        return Radii(topStart: topStart * factor, topEnd: topEnd * factor, bottomEnd: bottomEnd * factor, bottomStart: bottomStart * factor)
    }

    static func line(_ box: Box) -> Line {
        let border = max(0, box.border)
        let outer = fitted(box)
        let half = border / 2
        func inner(_ radius: Double) -> Double { max(0, radius - half) }
        let radii = Radii(
            topStart: inner(outer.topStart), topEnd: inner(outer.topEnd), bottomEnd: inner(outer.bottomEnd), bottomStart: inner(outer.bottomStart))
        let width = max(0, box.width - border)
        let height = max(0, box.height - border)
        let sum = radii.topStart + radii.topEnd + radii.bottomEnd + radii.bottomStart
        let perimeter = max(0, 2 * (width + height) - 2 * sum + (Double.pi / 2) * sum)
        let step = (dash + gap) * border
        guard step > 0, perimeter > 0 else { return Line(radii: radii, perimeter: perimeter, count: 0, dash: 0, gap: 0) }
        // `Math.round` of the reference is half up; the quotient is positive.
        let count = max(1, SafeInt.clamped((perimeter / step + 0.5).rounded(.down), limit: 100_000))
        let stretch = perimeter / (Double(count) * step)
        return Line(radii: radii, perimeter: perimeter, count: count, dash: dash * border * stretch, gap: gap * border * stretch)
    }

    /// The centre line as a rectangle: half a width inside the outer edge.
    static func frame(_ box: Box) -> Frame {
        let half = max(0, box.border) / 2
        return Frame(left: half, top: half, right: max(half, box.width - half), bottom: max(half, box.height - half), radii: line(box).radii)
    }

}

/// The dashes of a border: the centre line stroked with the pattern of the contract. Right to
/// left mirrors the drawing, so the line still starts at the inline start.
struct DashedBorderShape: Shape {
    let box: DashedBorderRules.Box
    let rightToLeft: Bool

    /// The mirror is done in `path`; the environment must not mirror it again.
    @available(iOS 17.0, macOS 14.0, *)
    var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }

    func path(in rect: CGRect) -> Path {
        let frame = DashedBorderRules.frame(box)
        let line = DashedBorderRules.line(box)
        guard line.count > 0 else { return Path() }
        let r = frame.radii
        var path = Path()
        let (l, t, rt, b) = (CGFloat(frame.left), CGFloat(frame.top), CGFloat(frame.right), CGFloat(frame.bottom))
        func arc(center: CGPoint, radius: Double, from: Double, to: Double) {
            if radius > 0 { path.addArc(center: center, radius: CGFloat(radius), startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false) }
        }
        path.move(to: CGPoint(x: l + CGFloat(r.topStart), y: t))
        path.addLine(to: CGPoint(x: rt - CGFloat(r.topEnd), y: t))
        arc(center: CGPoint(x: rt - CGFloat(r.topEnd), y: t + CGFloat(r.topEnd)), radius: r.topEnd, from: -90, to: 0)
        path.addLine(to: CGPoint(x: rt, y: b - CGFloat(r.bottomEnd)))
        arc(center: CGPoint(x: rt - CGFloat(r.bottomEnd), y: b - CGFloat(r.bottomEnd)), radius: r.bottomEnd, from: 0, to: 90)
        path.addLine(to: CGPoint(x: l + CGFloat(r.bottomStart), y: b))
        arc(center: CGPoint(x: l + CGFloat(r.bottomStart), y: b - CGFloat(r.bottomStart)), radius: r.bottomStart, from: 90, to: 180)
        path.addLine(to: CGPoint(x: l, y: t + CGFloat(r.topStart)))
        arc(center: CGPoint(x: l + CGFloat(r.topStart), y: t + CGFloat(r.topStart)), radius: r.topStart, from: 180, to: 270)
        path.closeSubpath()
        if rightToLeft {
            path = path.applying(CGAffineTransform(translationX: CGFloat(box.width), y: 0).scaledBy(x: -1, y: 1))
        }
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
            .strokedPath(StrokeStyle(lineWidth: CGFloat(box.border), lineCap: .butt, dash: [CGFloat(line.dash), CGFloat(line.gap)]))
    }
}

/// The border of a box drawn as dashes, sized by its own box.
struct DashedBorderOverlay: View {
    let width: Double
    let color: RGBA
    let radius: Corners?
    let rightToLeft: Bool

    var body: some View {
        GeometryReader { proxy in
            let corners = radius ?? Corners()
            DashedBorderShape(
                box: .init(
                    width: Double(proxy.size.width), height: Double(proxy.size.height), border: width,
                    radii: .init(topStart: corners.topStart, topEnd: corners.topEnd, bottomEnd: corners.bottomEnd, bottomStart: corners.bottomStart)
                ),
                rightToLeft: rightToLeft
            )
            .fill(color.color)
        }
        .allowsHitTesting(false)
    }
}
