import SwiftUI

/// `CircularProgress`: the same scale bent into an arc. The diameter comes from the box of the
/// node; the arc lies inside the circle, starts at the top and runs clockwise (not mirrored in
/// right-to-left); the label, if any, is one line in the centre that does not size the ring.
struct CircularProgressWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let style: JSONObject
    /// Under a row weight the width fields of the style do not name the diameter.
    let widthApplies: Bool

    var body: some View {
        ValueTransitioned(node: node, context: context) { shown in
            CircularProgressContent(node: node, context: context, style: style, widthApplies: widthApplies, shown: shown)
        }
    }
}

struct CircularProgressContent: View {
    let node: DocumentNode
    let context: RenderContext
    let style: JSONObject
    let widthApplies: Bool
    let shown: ValueTransitionEngine.Shown

    var body: some View {
        let props = node.props
        let resolver = context.resolver
        let theme = context.theme
        let value = ProgressRules.shownNumber(props["value"], scope: shown.smooth, literal: shown.literal?.smooth, isValue: true) ?? 0
        let max = ProgressRules.number(props["max"], scope: shown.smooth) ?? 100
        let ratio = ProgressRules.ratio(value: value, max: max)
        let paint = ProgressRules.paint(props, resolver: resolver)
        let geometry = ProgressRules.ringGeometry(ringBox(paint: paint))
        let diameter = CGFloat(geometry.diameter)
        let ring = ProgressRing(
            paint: paint, ratio: ratio, diameter: geometry.diameter, thickness: geometry.thickness,
            roundEnds: props["cap"]?.stringValue == "round", glow: ProgressRules.Glow(props["glow"])
        )
        let finalRatio = ProgressRules.ratio(
            value: ProgressRules.number(props["value"], scope: context.scope), max: ProgressRules.number(props["max"], scope: context.scope))

        ring
            .frame(width: diameter, height: diameter)
            .overlay { label(props: props, shown: shown, ratio: ratio, theme: theme) }
            .accessibilityElement()
            .accessibilityLabel(context.text(node, field: "label"))
            .accessibilityValue("\(SafeInt.clamped((finalRatio * 100).rounded()))")
    }

    @ViewBuilder
    private func label(props: JSONObject, shown: ValueTransitionEngine.Shown, ratio: Double, theme: HotlayoutTheme) -> some View {
        let steppedValue = ProgressRules.shownNumber(props["value"], scope: shown.stepped, literal: shown.literal?.stepped, isValue: true) ?? 0
        let steppedMax = ProgressRules.number(props["max"], scope: shown.stepped) ?? 100
        if let text = ProgressRules.labelText(format: props["labelFormat"]?.stringValue, value: steppedValue, max: steppedMax, ratio: ratio) {
            let look = ProgressRules.labelStyle(props, resolver: context.resolver)
            let family = theme.fontFamilies[look.typography.role == "heading" ? "heading" : "body"]
            Text(text)
                .font(look.typography.font(family: family))
                .tracking(look.typography.letterSpacing)
                .monospacedDigit()
                .foregroundColor(look.color.color)
                .lineLimit(1)
                // One centred line, never wrapped and never clipped by the ring.
                .fixedSize()
        }
    }

    /// The box of the node as the style names it, seen from the ring (`progress.ring`).
    private func ringBox(paint: ProgressPaint) -> ProgressRules.RingBox {
        let look = context.resolver.box(style, scope: context.scope)
        return ProgressRules.RingBox(
            size: node.props["size"],
            unit: context.theme.coreSpacing(ProgressRules.ringUnit),
            width: widthApplies ? look.width : nil,
            minWidth: widthApplies ? look.minWidth : nil,
            maxWidth: widthApplies ? look.maxWidth : nil,
            height: look.height, minHeight: look.minHeight, maxHeight: look.maxHeight,
            paddingInline: look.padding.horizontal, paddingBlock: look.padding.vertical,
            border: look.borderWidth ?? 0, thickness: paint.thickness
        )
    }
}

/// The arc drawn in a canvas, the glow copy under it.
struct ProgressRing: View {
    let paint: ProgressPaint
    let ratio: Double
    let diameter: Double
    let thickness: Double
    let roundEnds: Bool
    let glow: ProgressRules.Glow?

    var body: some View {
        ZStack {
            if let glow {
                Canvas { context, size in draw(&context, size: size, glowOnly: true) }
                    .blur(radius: glow.sigma)
                    .opacity(glow.opacity)
            }
            Canvas { context, size in draw(&context, size: size, glowOnly: false) }
        }
    }

    private func conic(center: CGPoint, ratio: Double) -> GraphicsContext.Shading {
        switch paint.fill {
        case .color(let color):
            return .color(color.color)
        case .gradient(let stops):
            // The stops lie along the FILLED part: the first colour runs from the start, the last to the end of the fill.
            let on = ProgressRules.gradientStops(stops, ratio: ratio)
            var list: [Gradient.Stop] = []
            if let first = on.first { list.append(Gradient.Stop(color: first.color.color, location: 0)) }
            list += on.map { Gradient.Stop(color: $0.color.color, location: Swift.min(1, Swift.max(0, $0.at))) }
            if let last = on.last { list.append(Gradient.Stop(color: last.color.color, location: Swift.min(1, ratio))) }
            return .conicGradient(Gradient(stops: list), center: center, angle: .degrees(-90))
        }
    }

    private func colorAt(angle: Double, sweep: Double) -> RGBA {
        switch paint.fill {
        case .color(let color): return color
        case .gradient(let stops): return ProgressRules.gradientColor(stops, at: sweep > 0 ? angle / sweep : 0)
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, glowOnly: Bool) {
        guard thickness > 0, diameter > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = (diameter - thickness) / 2
        let style = StrokeStyle(lineWidth: CGFloat(thickness), lineCap: .butt)
        let full = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        if !glowOnly { context.stroke(full, with: .color(paint.track.color), style: style) }
        let share = ProgressRules.clamped(ratio)
        guard share > 0 else { return }
        let shading = conic(center: center, ratio: share)

        func arc(from start: Double, to end: Double) -> Path {
            var path = Path()
            path.addArc(center: center, radius: CGFloat(radius), startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
            return path
        }

        let ring = ProgressRules.ringArc(share)
        guard roundEnds else {
            context.stroke(share >= 1 ? full : arc(from: ring.startDeg, to: ring.startDeg + ring.sweepDeg), with: shading, style: style)
            return
        }
        let cap = ProgressRules.ringCap(ratio: share, diameter: diameter, thickness: thickness)
        let sweep = ring.sweepDeg
        func dot(at angle: Double) {
            let radians = angle * Double.pi / 180
            let point = CGPoint(x: center.x + CGFloat(radius * sin(radians)), y: center.y - CGFloat(radius * cos(radians)))
            let circle = Path(
                ellipseIn: CGRect(
                    x: point.x - CGFloat(thickness / 2), y: point.y - CGFloat(thickness / 2), width: CGFloat(thickness), height: CGFloat(thickness)))
            context.fill(circle, with: .color(colorAt(angle: angle, sweep: sweep).color))
        }
        switch cap.kind {
        case .none:
            break
        case .full:
            context.stroke(full, with: shading, style: style)
        case .dot:
            dot(at: cap.startDeg)
        case .arc:
            context.stroke(arc(from: cap.startDeg, to: cap.endDeg), with: shading, style: style)
            dot(at: cap.startDeg)
            dot(at: cap.endDeg)
        }
    }
}
