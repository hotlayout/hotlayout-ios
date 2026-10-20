import SwiftUI

extension ProgressRules {
    /// A `BindableNumber`: a literal, or a binding whose value is a number, else its fallback.
    /// A string is not a number.
    static func number(_ ref: JSONValue?, scope: DataScope) -> Double? {
        guard let object = ref?.objectValue else { return ref?.numberValue }
        if object["kind"]?.stringValue == "literal" { return object["value"]?.numberValue }
        guard object["kind"]?.stringValue == "binding", let path = object["path"]?.stringValue else { return nil }
        return scope[path]?.numberValue ?? object["fallback"]?.numberValue
    }

    /// The value of a scale at this frame: the number the engine shows for a literal one, else
    /// the data read through the shown scope.
    static func shownNumber(_ ref: JSONValue?, scope: DataScope, literal: Double?, isValue: Bool) -> Double? {
        if isValue, ref?["kind"]?.stringValue == "literal", let literal { return literal }
        return number(ref, scope: scope)
    }
}

/// `ProgressBar`: a track under the whole scale, the fill over it, optionally cut into steps,
/// with round ends, a glow and a label at the end of the row.
struct ProgressBarWidget: View {
    let node: DocumentNode
    let context: RenderContext

    var body: some View {
        ValueTransitioned(node: node, context: context) { shown in
            ProgressBarContent(node: node, context: context, shown: shown)
        }
    }
}

struct ProgressBarContent: View {
    let node: DocumentNode
    let context: RenderContext
    let shown: ValueTransitionEngine.Shown

    var body: some View {
        let props = node.props
        let resolver = context.resolver
        let theme = context.theme
        let value = ProgressRules.shownNumber(props["value"], scope: shown.smooth, literal: shown.literal?.smooth, isValue: true) ?? 0
        let max = ProgressRules.number(props["max"], scope: shown.smooth) ?? 100
        let steppedValue = ProgressRules.shownNumber(props["value"], scope: shown.stepped, literal: shown.literal?.stepped, isValue: true) ?? 0
        let steppedMax = ProgressRules.number(props["max"], scope: shown.stepped) ?? 100
        let ratio = ProgressRules.ratio(value: value, max: max)
        // A screen reader hears where the bar is going, not a step of its transition.
        let targetRatio = ProgressRules.ratio(
            value: ProgressRules.number(props["value"], scope: context.scope) ?? 0, max: ProgressRules.number(props["max"], scope: context.scope) ?? 100)
        let paint = ProgressRules.paint(props, resolver: resolver)
        let segments = ProgressRules.segmentsCount(props["segments"])
        let valueKey = props["value"]?["kind"]?.stringValue == "literal" ? ValueTransition.literalKey : props["value"]?["path"]?.stringValue
        let units = segments.flatMap { count -> Double? in
            guard let key = valueKey, let ends = shown.ends[key] else { return nil }
            return ProgressRules.segmentUnits(
                fromRatio: ProgressRules.ratio(value: ends.from, max: max), toRatio: ProgressRules.ratio(value: ends.to, max: max),
                eased: ProgressRules.transitionShare(from: ends.from, to: ends.to, shown: ends.shown), segments: count
            )
        }
        let scale = ProgressBarScale(
            paint: paint, ratio: ratio, rightToLeft: context.rightToLeft, pill: theme.coreRadius("pill"),
            roundEnds: props["cap"]?.stringValue == "round", segments: segments,
            gap: theme.coreSpacing(ProgressRules.segmentGap),
            currentColor: ProgressRules.currentColor(props, resolver: resolver),
            units: units, glow: ProgressRules.Glow(props["glow"])
        )
        let label = ProgressRules.labelText(format: props["labelFormat"]?.stringValue ?? "valueOfMax", value: steppedValue, max: steppedMax, ratio: ratio)
        let gap = theme.coreSpacing(ProgressRules.barLabelGap)

        VStack(alignment: .leading, spacing: gap) {
            scale
                .frame(maxWidth: .infinity)
                .frame(minWidth: segments.map { CGFloat(ProgressRules.segmentsMinInline(segments: $0, gap: scale.gap)) })
                .frame(height: CGFloat(paint.thickness))
                .accessibilityElement()
                .accessibilityLabel(context.text(node, field: "label"))
                .accessibilityValue("\(SafeInt.clamped((targetRatio * 100).rounded()))")
            if let label {
                let style = theme.coreTypography(ProgressRules.defaultLabelTypography)
                let color = theme.coreColor(ProgressRules.barLabelColor)
                Text(label)
                    .font(style.font(family: theme.fontFamilies["body"]))
                    .monospacedDigit()
                    .foregroundColor(color.color)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// The scale of a bar drawn in a canvas: continuous or in steps, glow under it.
struct ProgressBarScale: View {
    let paint: ProgressPaint
    let ratio: Double
    let rightToLeft: Bool
    let pill: Double
    let roundEnds: Bool
    let segments: Int?
    let gap: Double
    let currentColor: RGBA?
    let units: Double?
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

    /// X of a logical offset from the start of the row: mirrored in right-to-left.
    private func x(_ offset: Double, _ width: Double) -> Double { rightToLeft ? width - offset : offset }

    private func rect(start: Double, length: Double, width: Double, height: Double) -> CGRect {
        let origin = rightToLeft ? width - start - length : start
        return CGRect(x: origin, y: 0, width: Swift.max(0, length), height: height)
    }

    /// The paint of a fill whose gradient line runs from the logical start to `line`.
    private func shading(line: Double, width: Double) -> GraphicsContext.Shading {
        switch paint.fill {
        case .color(let color):
            return .color(color.color)
        case .gradient(let stops):
            let gradient = Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color, location: $0.position) })
            return .linearGradient(gradient, startPoint: CGPoint(x: x(0, width), y: 0), endPoint: CGPoint(x: x(line, width), y: 0))
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, glowOnly: Bool) {
        let width = Double(size.width)
        let thickness = paint.thickness
        guard thickness > 0, width > 0 else { return }
        let height = Double(size.height)
        if let segments,
            let geometry = ProgressRules.segmentGeometry(trackInline: width, thickness: thickness, ratio: ratio, segments: segments, gap: gap, pill: pill)
        {
            drawSteps(&context, geometry: geometry, width: width, height: height, glowOnly: glowOnly)
            return
        }
        let geometry = ProgressRules.barGeometry(trackInline: width, thickness: thickness, ratio: ratio, pill: pill)
        let trackRadius = roundEnds ? ProgressRules.barCapRadius(thickness: thickness) : geometry.trackRadius
        let track = Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: CGFloat(trackRadius))
        if !glowOnly { context.fill(track, with: .color(paint.track.color)) }
        let fillInline = roundEnds ? ProgressRules.barCapFillInline(trackInline: width, thickness: thickness, ratio: ratio) : geometry.fillInline
        guard fillInline > 0 else { return }
        let fillRadius = roundEnds ? trackRadius : geometry.fillRadius
        let fill = Path(roundedRect: rect(start: 0, length: fillInline, width: width, height: height), cornerRadius: CGFloat(fillRadius))
        var layer = context
        // The fill is clipped by the track; its glow copy is not.
        if !glowOnly { layer.clip(to: track) }
        layer.fill(fill, with: shading(line: fillInline, width: width))
    }

    private func drawSteps(_ context: inout GraphicsContext, geometry: ProgressRules.SegmentGeometry, width: Double, height: Double, glowOnly: Bool) {
        let count = geometry.boxes.count
        let radius = roundEnds ? ProgressRules.barCapRadius(thickness: paint.thickness) : geometry.radius
        let step = geometry.boxes.first?.inline ?? 0
        let drawnUnits = units ?? Double(geometry.filled)
        let fills = ProgressRules.segmentFills(units: drawnUnits, segments: count)
        let current = ProgressRules.segmentCurrent(fills)
        let line = ProgressRules.segmentFillInline(units: drawnUnits, step: step, gap: gap)
        let fillShading = shading(line: line, width: width)
        let lit = ProgressRules.glowingStep(fills: fills, currentPainted: currentColor != nil)

        for (index, box) in geometry.boxes.enumerated() {
            let frame = rect(start: box.start, length: box.inline, width: width, height: height)
            let shape = Path(roundedRect: frame, cornerRadius: CGFloat(radius))
            let fill = fills[index]
            if glowOnly {
                switch lit {
                case .current(let at) where at == index:
                    if let currentColor { context.fill(shape, with: .color(currentColor.color)) }
                case .front(let at, let share) where at == index:
                    drawFill(&context, shape: shape, frame: frame, share: share, shading: fillShading, start: box.start, length: box.inline, width: width)
                default:
                    break
                }
                continue
            }
            let base: RGBA = fill >= 1 ? paint.track : (index == current ? (currentColor ?? paint.track) : paint.track)
            if fill < 1 { context.fill(shape, with: .color(base.color)) }
            if fill > 0 {
                drawFill(&context, shape: shape, frame: frame, share: fill, shading: fillShading, start: box.start, length: box.inline, width: width)
            }
        }
    }

    /// The fill of a step cut at `share` of its length from the logical start, the step's
    /// rounded shape kept.
    private func drawFill(
        _ context: inout GraphicsContext, shape: Path, frame: CGRect, share: Double, shading: GraphicsContext.Shading, start: Double, length: Double,
        width: Double
    ) {
        var layer = context
        layer.clip(to: shape)
        let cut = rect(start: start, length: length * Swift.min(1, share), width: width, height: Double(frame.height))
        layer.fill(Path(cut), with: shading)
    }
}
