import SwiftUI

// `Text` with parts of its own style, emphasis, a list marker or a gradient on the glyphs. A text
// with none of these is drawn by the plain `TextWidget`.

// MARK: - Siblings of a list item

/// The markers and the visibility of the children of ONE parent, in document order: what a
/// numbered item needs to know about its neighbours.
struct ListSiblings {
    let markers: [DrawnMarker?]
    let visible: [Bool]

    init(children: [DocumentNode], scope: DataScope, widthClass: WidthClass = .compact) {
        markers = children.map { $0.widget == .text ? ListMarkerRules.drawn($0.props["marker"]) : nil }
        visible = children.map { WidthRules.isShown($0, widthClass, scope: scope) }
    }

    init(children: [DocumentNode], context: RenderContext) {
        self.init(children: children, scope: context.scope, widthClass: context.widthClass)
    }
}

struct ListPosition {
    let siblings: ListSiblings
    let index: Int

    var number: Int? { ListMarkerRules.number(siblings.markers, at: index, visible: siblings.visible) }
    var groupSize: Int? { ListMarkerRules.groupSize(siblings.markers, at: index) }
}

extension RenderContext {
    /// The context for the descendants of a node: its own place among siblings is not theirs.
    func withoutPosition() -> RenderContext {
        var copy = self
        copy.listPosition = nil
        return copy
    }

    /// The context of the child at `index` among `siblings`.
    func at(_ siblings: ListSiblings, _ index: Int) -> RenderContext {
        var copy = self
        copy.listPosition = ListPosition(siblings: siblings, index: index)
        return copy
    }
}

// MARK: - The shown text of runs

extension TextRichPlan {
    /// The shown text rule over runs (`x-style.layout.shownText`): runs of space, tab, LF and CR
    /// become one space across the whole string, the edges are trimmed.
    static func shown(_ runs: [TextSpanRun]) -> [TextSpanRun] {
        var result: [TextSpanRun] = []
        var written = false
        var afterSpace = false
        for run in runs {
            var text = ""
            for scalar in run.text.unicodeScalars {
                if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                    // The space stays with the run where the whitespace begins.
                    if written && !afterSpace { text.append(" ") }
                    afterSpace = written
                } else {
                    text.unicodeScalars.append(scalar)
                    written = true
                    afterSpace = false
                }
            }
            guard !text.isEmpty else { continue }
            if let last = result.last, last.span == run.span, last.part == run.part {
                result[result.count - 1].text += text
            } else {
                result.append(TextSpanRun(text: text, span: run.span, part: run.part))
            }
        }
        // A space at the very end is an edge: trimmed.
        if afterSpace, var last = result.popLast() {
            last.text.removeLast()
            if !last.text.isEmpty { result.append(last) }
        }
        return result
    }
}

// MARK: - What is drawn

/// A run with its look resolved: the typography with the weight of the part, the colour, and
/// the emphasis.
struct DrawnRun: Equatable {
    var text: String
    var typography: TextStyleValue
    var color: RGBA
    /// The part names a colour of its own (it keeps it under a gradient).
    var namesColor: Bool
    var emphasis: RunEmphasis
}

/// Everything the drawing of a paragraph needs, resolved against the theme.
struct TextRichPlan {
    var runs: [DrawnRun]
    var base: TextStyleValue
    /// The pitch of every line (`x-style.layout.richText.linePitch: 'uniform'`).
    var lineBlock: Double
    /// The tallest natural line among the base and all declared parts.
    var naturalBlock: Double

    static func make(
        runs templateRuns: [TemplateRun], active: [String: TextSpanStyle], base: TextStyleValue, color: RGBA, emphasis: TextEmphasis, resolver: StyleResolver
    ) -> TextRichPlan {
        let merged = shown(TextSpans.runs(templateRuns, active: active))
        var drawn: [DrawnRun] = []
        for run in merged {
            let span = TextSpans.style(of: run, active: active)
            let runEmphasis = TextEmphasisRules.run(emphasis, span: span)
            var typography = span?.typography.flatMap { resolver.typography($0) } ?? base
            if let weight = runEmphasis.weight { typography.fontWeight = weight }
            let own = span?.color.flatMap { resolver.color($0) }
            drawn.append(DrawnRun(text: run.text, typography: typography, color: own ?? color, namesColor: span?.namesColor ?? false, emphasis: runEmphasis))
        }
        // The pitch counts every declared part, shown or not.
        var metrics: [String: LineMetric] = [:]
        let theme = resolver.theme
        var naturals = [base.naturalLineHeight(in: theme)]
        for (key, style) in TextSpans.declared(active) {
            let typography = style.typography.flatMap { resolver.typography($0) } ?? base
            metrics[key] = LineMetric(fontSize: typography.fontSize, lineHeight: typography.lineHeight)
            naturals.append(typography.naturalLineHeight(in: theme))
        }
        let strut = RichText.strut(base: LineMetric(fontSize: base.fontSize, lineHeight: base.lineHeight), spans: metrics)
        return TextRichPlan(runs: drawn, base: base, lineBlock: strut.lineBlock, naturalBlock: naturals.max() ?? base.naturalLineHeight(in: theme))
    }
}

// MARK: - The widget

struct TextRichWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let position: ListPosition?

    /// A text that counts: the clock of its time left ticks (`countdownPart`), and its numbers may
    /// lead (`animateChanges`, `animateIn`). Both stand aside from a text without them.
    var body: some View {
        CountdownTicking(node: node, context: context) { ticked in
            ValueTransitioned(node: node, context: ticked) { shown in
                var shownContext = ticked
                shownContext.scope = shown.stepped
                return TextRichContent(node: node, context: shownContext, position: position)
            }
        }
    }
}

struct TextRichContent: View {
    let node: DocumentNode
    let context: RenderContext
    let position: ListPosition?

    var body: some View {
        let marker = ListMarkerRules.drawn(node.props["marker"])
        let style = NodeStyle.effective(node, scope: context.scope)
        let gradient = TextGradientRules.reference(type: node.type, style: style).flatMap { context.resolver.gradient($0) }
        let active = TextSpans.active(content: node.props["content"], spans: TextSpans.read(node.props["spans"]))
        if marker == nil && active.isEmpty && gradient == nil {
            TextWidget(node: node, context: context)
        } else {
            rich(marker: marker, gradient: gradient, active: active)
        }
    }

    private var emphasis: TextEmphasis { context.inherited.emphasis }

    private func rich(marker: DrawnMarker?, gradient: GradientValue?, active: [String: TextSpanStyle]) -> some View {
        let location = "screen “\(context.screenId)”: node “\(node.id)”: content"
        let runs = BindableText.runs(
            node.props["content"], language: context.language(node: node, field: "content"), environment: context.textEnvironment, sink: context.sink,
            location: location)
        let plan = TextRichPlan.make(
            runs: runs, active: active, base: context.inherited.typography, color: context.inherited.color, emphasis: emphasis, resolver: context.resolver)
        let align = node.props["align"]?.stringValue
        let maxLines = node.props["overflow"]?.stringValue == "visible" ? nil : node.props["maxLines"]?.numberValue.map { SafeInt.clamped(min(20, max(1, $0))) }
        let paragraph = RichParagraph(
            plan: plan, theme: context.theme, fallback: context.inherited.color, gradient: gradient, alignment: textAlignment(align), maxLines: maxLines,
            rightToLeft: context.rightToLeft)
        return Group {
            if let marker {
                markerRow(marker, plan: plan, paragraph: paragraph, align: align)
            } else {
                paragraph.frame(maxWidth: .infinity, alignment: horizontalAlignment(align))
            }
        }
    }

    /// The item: a column for the marker at the start, the gap, and the text hanging under its
    /// own first line (`x-style.layout.listMarker`).
    private func markerRow(_ marker: DrawnMarker, plan: TextRichPlan, paragraph: RichParagraph, align: String?) -> some View {
        let geometry = ListMarkerRules.geometry(marker, fontSize: plan.base.fontSize, groupSize: context.listNumber?.groupSize ?? position?.groupSize ?? 1)
        let text = ListMarkerRules.text(marker, number: context.listNumber?.number ?? position?.number ?? 1, formattingLocale: context.locale.formatting)
        let glyph = DrawnRun(
            text: text, typography: plan.base, color: context.inherited.color, namesColor: false,
            emphasis: RunEmphasis(fontStyle: "normal", textDecoration: "none", weight: nil))
        let markerPlan = TextRichPlan(runs: [glyph], base: plan.base, lineBlock: plan.lineBlock, naturalBlock: plan.naturalBlock)
        return HStack(alignment: .firstTextBaseline, spacing: geometry.gap) {
            RichParagraph(
                plan: markerPlan, theme: context.theme, fallback: context.inherited.color, gradient: nil, alignment: .trailing, maxLines: 1,
                rightToLeft: context.rightToLeft, wraps: false
            )
            .frame(width: geometry.column, alignment: .trailing)
            paragraph.frame(maxWidth: .infinity, alignment: horizontalAlignment(align))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A paragraph of runs. Under a gradient the paragraph is drawn twice over the same glyphs: the
/// gradient through a mask of the parts that take it, and the parts with their own colour and
/// every line in plain colours (a line is never painted by the gradient).
struct RichParagraph: View {
    let plan: TextRichPlan
    let theme: HotlayoutTheme
    let fallback: RGBA
    let gradient: GradientValue?
    let alignment: TextAlignment
    let maxLines: Int?
    let rightToLeft: Bool
    var wraps = true

    private enum Layer { case plain, gradientMask, gradientOwn }

    var body: some View {
        if let gradient {
            text(.gradientOwn)
                .overlay { GradientFill(gradient: gradient).mask { text(.gradientMask) } }
        } else {
            text(.plain)
        }
    }

    private func segment(_ run: DrawnRun, _ layer: Layer, first: Bool) -> Text {
        let typography = run.typography
        let family = theme.fontFamilies[typography.role == "heading" ? "heading" : "body"]
        var piece = styledRun(
            run.text, style: typography, family: family, italic: run.emphasis.fontStyle == "italic", rightToLeft: rightToLeft, leadsParagraph: first)
        let line = run.emphasis.textDecoration
        let takes = gradient != nil && !run.namesColor
        switch layer {
        case .plain:
            piece = piece.foregroundColor(run.color.color)
            piece = decorated(piece, line, run.color)
        case .gradientMask:
            // Only the glyphs that take the gradient, opaque; no lines, they come from the other layer.
            piece = piece.foregroundColor(takes ? .black : .clear)
        case .gradientOwn:
            piece = piece.foregroundColor(takes ? .clear : run.color.color)
            piece = decorated(piece, line, takes ? fallback : run.color)
        }
        return piece
    }

    private func decorated(_ piece: Text, _ line: String, _ color: RGBA) -> Text {
        switch line {
        case "underline": return piece.underline(true, color: color.color)
        case "lineThrough": return piece.strikethrough(true, color: color.color)
        default: return piece
        }
    }

    private func text(_ layer: Layer) -> some View {
        let joined = plan.runs.enumerated().map { segment($1, layer, first: $0 == 0) }.reduce(Text("")) { $0 + $1 }
        return
            joined
            .lineBoxed(plan.lineBlock, natural: plan.naturalBlock)
            .multilineTextAlignment(alignment)
            .lineLimit(maxLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: !wraps, vertical: true)
            // The mark that leads the paragraph is drawn only; assistive technology reads the string.
            .accessibilityLabel(Text(verbatim: plan.runs.map { BidiText.limited($0.text) }.joined()))
            .accessibilityHidden(layer == .gradientMask)
    }
}
