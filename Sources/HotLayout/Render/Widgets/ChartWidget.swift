import SwiftUI

/// `Chart`: bars or a line over a row of points, with the labels in a band under the plot area. The numbers come
/// from `ChartRules`; this view turns the node into theme values (colours, radius, gap, label font) and draws them in
/// the box the parent gave.
///
/// It is ONE picture for assistive technology, named by `alt`: the drawing and the labels are not read, and a chart
/// without a name is hidden as a decorative picture. The points are not read out as a table.
struct ChartWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let look: BoxLook

    var body: some View {
        let props = node.props
        let theme = context.theme
        let resolver = context.resolver
        let source: (String) -> [JSONValue]? = { context.scope[$0]?.arrayValue }
        let labelStyle = theme.coreTypography(ChartRules.labelTypography)
        let spec = ChartSpec(
            points: ChartRules.points(props["data"], collection: source),
            line: props["variant"]?.stringValue == "line",
            smooth: ChartRules.readSmooth(props["curve"]),
            area: props["area"]?.boolValue == true,
            labels: props["labels"]?.boolValue == true,
            highlight: ChartRules.readHighlight(props["highlight"]),
            lineWidth: ChartRules.readLineWidth(props["lineWidth"]),
            color: resolver.color(props["color"]) ?? theme.coreColor(ChartRules.defaultColor),
            highlightColor: resolver.color(props["highlightColor"]) ?? theme.coreColor(ChartRules.defaultHighlightColor),
            barRadius: resolver.radius(props["barRadius"]) ?? theme.coreRadius(ChartRules.defaultBarRadius),
            barGap: resolver.spacing(props["barGap"]) ?? theme.coreSpacing(ChartRules.defaultBarGap),
            labelStyle: labelStyle,
            labelColor: theme.coreColor(ChartRules.labelColor),
            labelGap: theme.coreSpacing(ChartRules.labelGap),
            rightToLeft: context.rightToLeft,
            theme: theme
        )
        ChartAppear(animates: props["animateIn"]?.boolValue == true && !spec.points.isEmpty) { shown in
            ChartBoxLayout(fillsHeight: look.height != nil) {
                ChartDrawing(spec: spec, shown: shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(altText)
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(altText.isEmpty)
    }

    /// `alt` is a string or a string of the document (a binding or a template); an empty one hides the chart from
    /// assistive technology.
    private var altText: String {
        guard let alt = node.props["alt"] else { return "" }
        if let literal = alt.stringValue { return ShownText.of(literal) }
        return context.text(node, field: "alt")
    }
}

/// Everything the drawing needs, resolved from the node and the theme.
struct ChartSpec {
    var points: [ChartRules.Point]
    var line: Bool
    var smooth: Bool
    var area: Bool
    var labels: Bool
    var highlight: String
    var lineWidth: Double
    var color: RGBA
    var highlightColor: RGBA
    var barRadius: Double
    var barGap: Double
    var labelStyle: TextStyleValue
    var labelColor: RGBA
    var labelGap: Double
    var rightToLeft: Bool
    var theme: HotlayoutTheme
}

/// The size of a chart: the width the parent gives (it fills it, as a progress bar does; no width on offer gives
/// nothing to draw on) and the height the parent fixes, else 120.
struct ChartBoxLayout: Layout {
    /// The node box named a height: the chart takes the whole of it.
    let fillsHeight: Bool

    private func box(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 0
        let offered = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        let height = offered.map { fillsHeight ? $0 : Swift.min(CGFloat(ChartRules.defaultHeight), $0) } ?? CGFloat(ChartRules.defaultHeight)
        return CGSize(width: width, height: height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { box(proposal) }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews { view.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

/// The plot area and the band of labels, laid out in the box the parent gave.
struct ChartDrawing: View {
    let spec: ChartSpec
    let shown: Double

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let width = Double(size.width)
            let labelLine = spec.labels ? spec.labelStyle.lineBox : 0
            let plot = ChartRules.plotHeight(height: Double(size.height), labels: spec.labels, labelLine: labelLine, labelGap: spec.labelGap)
            let shape = ChartShape(spec: spec, width: width, plot: plot, shown: shown)
            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in shape.draw(&context, size: canvasSize) }
                    .frame(width: size.width, height: CGFloat(plot))
                if spec.labels {
                    ForEach(shape.labelBoxes, id: \.index) { box in
                        let left = spec.rightToLeft ? width - box.left - box.width : box.left
                        StyledText(
                            text: spec.points[box.index].label, style: spec.labelStyle, color: spec.labelColor, theme: spec.theme, alignment: .center,
                            maxLines: 1
                        )
                        .frame(width: CGFloat(box.width), height: CGFloat(labelLine))
                        .clipped()
                        .position(
                            x: CGFloat(left + box.width / 2),
                            y: CGFloat(Swift.min(plot + spec.labelGap, Double(size.height)) + labelLine / 2))
                        .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

/// The numbers of one frame of a chart and the way they are painted.
struct ChartShape {
    let spec: ChartSpec
    let width: Double
    let plot: Double
    let shown: Double

    private var values: [Double] { spec.points.map(\.value) }
    private var highlight: Int? { ChartRules.highlightIndex(values, spec.highlight) }
    private var ratios: [Double] { ChartRules.ratios(values, shown: shown) }

    var bars: [ChartRules.Bar]? {
        guard !spec.points.isEmpty, !spec.line else { return nil }
        return ChartRules.bars(ratios: ratios, width: width, height: plot, gap: spec.barGap, radius: spec.barRadius, highlight: highlight)
    }

    var line: ChartRules.Line? {
        guard !spec.points.isEmpty, spec.line else { return nil }
        return ChartRules.line(ratios: ratios, width: width, height: plot, lineWidth: spec.lineWidth, highlight: highlight)
    }

    var labelBoxes: [ChartRules.LabelBox] {
        guard spec.labels, !spec.points.isEmpty else { return [] }
        return ChartRules.labelBoxes(centers: ChartRules.labelCenters(bars: bars, line: line), width: width)
    }

    func draw(_ context: inout GraphicsContext, size: CGSize) {
        // Right-to-left writing mirrors the whole drawing: the first point stands at the start of the reading direction.
        if spec.rightToLeft {
            context.translateBy(x: size.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        if let bars { drawBars(&context, bars) }
        if let line, !line.points.isEmpty { drawLine(&context, line) }
    }

    private func drawBars(_ context: inout GraphicsContext, _ bars: [ChartRules.Bar]) {
        for bar in bars where bar.height > 0 {
            let rect = CGRect(x: bar.x, y: bar.y, width: bar.width, height: bar.height)
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: CGFloat(bar.radius), bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: CGFloat(bar.radius))
            context.fill(shape.path(in: rect), with: .color((bar.highlighted ? spec.highlightColor : spec.color).color))
        }
    }

    /// The line through the points: segments, or one cubic Bezier per pair for the smooth curve (never a quadratic one or
    /// a Catmull-Rom spline: those overshoot the values).
    private func linePath(_ points: [ChartRules.XY]) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        if spec.smooth, points.count >= 3 {
            for segment in ChartRules.smoothSegments(points) {
                path.addCurve(
                    to: CGPoint(x: segment.to.x, y: segment.to.y), control1: CGPoint(x: segment.c1.x, y: segment.c1.y),
                    control2: CGPoint(x: segment.c2.x, y: segment.c2.y))
            }
        } else {
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        }
        return path
    }

    private func drawLine(_ context: inout GraphicsContext, _ line: ChartRules.Line) {
        let path = linePath(line.points)
        if spec.area, let first = line.points.first, let last = line.points.last {
            var fill = path
            fill.addLine(to: CGPoint(x: last.x, y: line.baseline))
            fill.addLine(to: CGPoint(x: first.x, y: line.baseline))
            fill.closeSubpath()
            // From the colour of the line at 0.24 of its opacity at the top of the plot area to the same colour at zero
            // opacity at the bottom, so the middle of the fade is not tinted grey.
            let gradient = Gradient(colors: [spec.color.withOpacity(ChartRules.areaTopOpacity).color, spec.color.withOpacity(0).color])
            context.fill(fill, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: line.baseline)))
        }
        context.stroke(
            path, with: .color(spec.color.color), style: StrokeStyle(lineWidth: CGFloat(spec.lineWidth), lineCap: .round, lineJoin: .round))
        if let dot = line.dot {
            let rect = CGRect(x: dot.x - dot.radius, y: dot.y - dot.radius, width: dot.radius * 2, height: dot.radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(spec.highlightColor.color))
        }
    }
}

/// The appearance (`animateIn`): the values grow from zero when the chart is shown, with the curve and the time of a
/// number that leads; the top of the scale stands at once. "Reduce motion" gives the final chart at once, and so does
/// a change of data under a chart that is already shown (the growth is a function of time alone).
struct ChartAppear<Content: View>: View {
    let animates: Bool
    let content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.valueTransitionElapsedMs) private var fixedElapsed
    @State private var appeared = Date()
    @State private var finished = false

    private func share(_ milliseconds: Double) -> Double { ValueTransition.ease(milliseconds / ValueTransition.durationMs) }

    var body: some View {
        if !animates || reduceMotion {
            content(1)
        } else if let fixedElapsed {
            content(share(fixedElapsed))
        } else if finished {
            content(1)
        } else {
            TimelineView(.animation) { timeline in
                content(share(timeline.date.timeIntervalSince(appeared) * 1000))
            }
            .onAppear { appeared = Date() }
            .task {
                try? await Task.sleep(nanoseconds: UInt64((ValueTransition.durationMs + 50) * 1_000_000))
                finished = true
            }
        }
    }
}
