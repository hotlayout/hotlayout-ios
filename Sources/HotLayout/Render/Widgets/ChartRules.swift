import Foundation

/// `Chart` (`x-chart`): how a record becomes a point, the scale, the highlighted point, the bars, the line, the
/// monotone curve and the label boxes. Pure numbers, no views.
///
/// Units are points in the content box of the node. `width` is the width the parent gave (the chart fills it);
/// `height` is the height of the PLOT AREA, the content box without the band of labels. The origin is the top-left
/// corner and y grows downwards.
enum ChartRules {
    /// At least two points make a chart, and at most 31 are read.
    static let pointsMin = 2
    static let pointsMax = 31
    /// The height of a chart without `style.height`.
    static let defaultHeight = 120.0
    static let lineWidthRange = 1.0...8.0
    static let defaultLineWidth = 2.0
    /// The opacity of the area under the line at the top of the plot area.
    static let areaTopOpacity = 0.24
    /// The dot of a highlighted point is the stroke plus this.
    static let dotExtra = 2.0
    /// A label slot narrower than this thins the labels out.
    static let labelMinWidth = 28.0
    /// The tokens of the fields that name none.
    static let defaultColor = "primary"
    static let defaultHighlightColor = "accent"
    static let defaultBarRadius = "sm"
    static let defaultBarGap = "xs"
    static let labelTypography = "caption"
    static let labelColor = "muted"
    static let labelGap = "xs"

    struct Point: Equatable {
        var value: Double
        var label: String
    }

    /// The value of a point: a finite number is itself, a negative one is zero, anything else is zero. The point keeps
    /// its place, so labels and neighbours do not move and the line has no gaps.
    static func value(_ raw: JSONValue?) -> Double {
        guard let number = raw?.numberValue, number.isFinite else { return 0 }
        return Swift.max(0, number)
    }

    /// The label of a point: a string is itself, anything else is an empty label.
    static func label(_ raw: JSONValue?) -> String { raw?.stringValue ?? "" }

    /// The points of the `data` field. A collection gives the first 31 records in the order of the data, and a record that
    /// is not an object is a record without fields. Fewer than two points, or a shape of `data` this reader does not
    /// know, is an EMPTY chart: nothing is drawn and the box stays.
    static func points(_ data: JSONValue?, collection: (String) -> [JSONValue]?) -> [Point] {
        let kept = Array(rawPoints(data, collection: collection).prefix(pointsMax))
        return kept.count < pointsMin ? [] : kept
    }

    private static func rawPoints(_ data: JSONValue?, collection: (String) -> [JSONValue]?) -> [Point] {
        guard let data = data?.objectValue else { return [] }
        switch data["kind"]?.stringValue {
        case "literal":
            guard let points = data["points"]?.arrayValue else { return [] }
            return points.prefix(pointsMax).map { point in
                guard let point = point.objectValue else { return Point(value: 0, label: "") }
                return Point(value: value(point["value"]), label: label(point["label"]))
            }
        case "collection":
            guard let source = data["source"]?.stringValue, let item = data["item"]?.stringValue, let valueField = data["valueField"]?.stringValue else {
                return []
            }
            let labelField = data["labelField"]?.stringValue
            return (collection(source) ?? []).prefix(pointsMax).map { record in
                let scope = RecordScope.instanceRecord(item: item, fields: record.objectValue ?? JSONObject())
                return Point(value: value(scope[valueField]), label: labelField.map { label(scope[$0]) } ?? "")
            }
        default:
            return []
        }
    }

    /// The shares of the height: each value divided by the largest value. All values zero gives all shares zero (an
    /// empty chart without a division by zero). `shown` is the share of the appearance (`animateIn`, 0 to 1): the top
    /// of the scale stands at once and the values grow.
    static func ratios(_ values: [Double], shown: Double = 1) -> [Double] {
        let top = values.max() ?? 0
        return values.map { top > 0 ? $0 / top * shown : 0 }
    }

    /// The highlighted point: `last` is the last one; `max` is the LAST of the largest values (the fresher of equals),
    /// and only when it is above zero; `none` and any other word give none.
    static func highlightIndex(_ values: [Double], _ highlight: String?) -> Int? {
        guard !values.isEmpty else { return nil }
        if highlight == "last" { return values.count - 1 }
        guard highlight == "max", let top = values.max(), top > 0 else { return nil }
        return values.lastIndex(of: top)
    }

    /// A bar: its box and the radius of its TOP corners (the bottom corners are square, a bar stands on zero).
    struct Bar: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var radius: Double
        var highlighted: Bool
    }

    /// The bars: n equal slots over the whole width with `gap` between them only. A gap that would make a bar narrower
    /// than one point becomes zero. The height is the share of `height`; a bar of height zero is not drawn. The radius of
    /// the top corners is no more than half the width and no more than the height of the bar.
    static func bars(ratios: [Double], width: Double, height: Double, gap: Double, radius: Double, highlight: Int?) -> [Bar] {
        let count = ratios.count
        guard count > 0, width > 0 else { return [] }
        let wanted = Swift.max(0, gap)
        let usedGap = (width - wanted * Double(count - 1)) / Double(count) < 1 ? 0 : wanted
        let barWidth = (width - usedGap * Double(count - 1)) / Double(count)
        let plot = Swift.max(0, height)
        return ratios.enumerated().map { index, ratio in
            let barHeight = Swift.max(0, ratio) * plot
            return Bar(
                x: Double(index) * (barWidth + usedGap), y: plot - barHeight, width: barWidth, height: barHeight,
                radius: Swift.max(0, Swift.min(radius, Swift.min(barWidth / 2, barHeight))), highlighted: index == highlight)
        }
    }

    struct XY: Equatable {
        var x: Double
        var y: Double
    }

    struct Dot: Equatable {
        var x: Double
        var y: Double
        var radius: Double
    }

    /// The line: the points, the inset from the edges, the dot and the bottom of the area under it.
    struct Line: Equatable {
        var points: [XY]
        /// The distance from the edges, so that the stroke and the dot are not cut by the box.
        var inset: Double
        /// The dot of the highlighted point; `nil` when nothing is highlighted.
        var dot: Dot?
        /// The bottom of the fill under the line: the lower edge of the plot area.
        var baseline: Double
    }

    /// The line. The inset is half the stroke, or with a highlight the radius of the dot (the stroke plus `dotExtra`)
    /// when that is larger. The points run from edge to edge: `x_k = i + k (W - 2i) / (n - 1)` and
    /// `y_k = i + (1 - share_k) (H - 2i)`; zero lies at `H - i` and the top at `i`.
    static func line(ratios: [Double], width: Double, height: Double, lineWidth: Double, highlight: Int?) -> Line {
        let count = ratios.count
        let plot = Swift.max(0, height)
        let dotRadius = lineWidth + dotExtra
        let inset = highlight == nil ? lineWidth / 2 : Swift.max(lineWidth / 2, dotRadius)
        guard count >= pointsMin, width > 0 else { return Line(points: [], inset: inset, dot: nil, baseline: plot) }
        let step = (width - 2 * inset) / Double(count - 1)
        let span = Swift.max(0, plot - 2 * inset)
        let points = ratios.enumerated().map { XY(x: inset + Double($0.offset) * step, y: inset + (1 - Swift.max(0, $0.element)) * span) }
        let lit = highlight.flatMap { points.indices.contains($0) ? points[$0] : nil }
        return Line(points: points, inset: inset, dot: lit.map { Dot(x: $0.x, y: $0.y, radius: dotRadius) }, baseline: plot)
    }

    private static func sign(_ value: Double) -> Double { value > 0 ? 1 : (value < 0 ? -1 : 0) }

    /// The tangents of the monotone cubic spline (Steffen: the same as `curveMonotoneX` of d3). The step h is equal; the
    /// secant is `s_k = (y_{k+1} - y_k) / h`. Inside: `m_k = (sign s_{k-1} + sign s_k) min(|s_{k-1}|, |s_k|,
    /// |s_{k-1} + s_k| / 4)`. At the ends: `m_0 = (3 s_0 - m_1) / 2` and `m_{n-1} = (3 s_{n-2} - m_{n-2}) / 2`. Secants of
    /// opposite signs give a zero tangent, so a peak lies exactly on its point.
    static func tangents(_ points: [XY]) -> [Double] {
        let count = points.count
        guard count >= 3 else { return Array(repeating: 0, count: count) }
        let step = points[1].x - points[0].x
        let secants = (0..<(count - 1)).map { step == 0 ? 0 : (points[$0 + 1].y - points[$0].y) / step }
        var result = Array(repeating: 0.0, count: count)
        for index in 1..<(count - 1) {
            let before = secants[index - 1]
            let after = secants[index]
            result[index] = (sign(before) + sign(after)) * Swift.min(abs(before), Swift.min(abs(after), abs(before + after) / 4))
        }
        result[0] = (3 * secants[0] - result[1]) / 2
        result[count - 1] = (3 * secants[count - 2] - result[count - 2]) / 2
        return result
    }

    /// A cubic Bezier segment of the smooth curve: two control points and the end.
    struct Cubic: Equatable {
        var c1: XY
        var c2: XY
        var to: XY
    }

    /// The smooth curve: a cubic Bezier between neighbours, `c1 = (x_k + h/3, y_k + m_k h/3)` and
    /// `c2 = (x_{k+1} - h/3, y_{k+1} - m_{k+1} h/3)`. A monotone spline never leaves the values of its neighbours, so the
    /// curve does not dive below zero or rise above the top. Two points are a straight segment.
    static func smoothSegments(_ points: [XY]) -> [Cubic] {
        guard points.count >= 3 else { return points.indices.dropFirst().map { Cubic(c1: points[$0 - 1], c2: points[$0], to: points[$0]) } }
        let slopes = tangents(points)
        return points.indices.dropFirst().map { index in
            let from = points[index - 1]
            let to = points[index]
            let third = (to.x - from.x) / 3
            return Cubic(
                c1: XY(x: from.x + third, y: from.y + slopes[index - 1] * third),
                c2: XY(x: to.x - third, y: to.y - slopes[index] * third), to: to)
        }
    }

    /// The box of one label: the index of its point, where it starts and how wide it is.
    struct LabelBox: Equatable {
        var index: Int
        var left: Double
        var width: Double
    }

    /// The label boxes. Each is `W / n` wide, centred under the middle of the bar or under the point of the line, and
    /// shifted inside `[0, W]`. When `W / n` is narrower than `labelMinWidth`, every k-th point is labelled,
    /// `k = ceil(min / (W / n))`, counting from the LAST point (it is "today").
    static func labelBoxes(centers: [Double], width: Double) -> [LabelBox] {
        let count = centers.count
        guard count > 0, width > 0 else { return [] }
        let slot = width / Double(count)
        let every = Swift.max(1, Int((labelMinWidth / slot - 1e-9).rounded(.up)))
        return centers.indices.compactMap { index in
            guard (count - 1 - index) % every == 0 else { return nil }
            return LabelBox(index: index, left: Swift.min(Swift.max(centers[index] - slot / 2, 0), width - slot), width: slot)
        }
    }

    /// The centres of the points for the labels: the middle of a bar, or the point of the line.
    static func labelCenters(bars: [Bar]? = nil, line: Line? = nil) -> [Double] {
        if let bars { return bars.map { $0.x + $0.width / 2 } }
        return (line?.points ?? []).map(\.x)
    }

    /// The height of the plot area: the content box without the band of labels (a line of label text plus the gap),
    /// never below zero.
    static func plotHeight(height: Double, labels: Bool, labelLine: Double, labelGap: Double) -> Double {
        Swift.max(0, height - (labels ? labelLine + labelGap : 0))
    }

    /// The word of `highlight` as the reader reads it: an unknown word is `none`.
    static func readHighlight(_ value: JSONValue?) -> String {
        let word = value?.stringValue
        return word == "last" || word == "max" ? word! : "none"
    }

    /// Whether the curve is smooth: any other word is a straight line.
    static func readSmooth(_ value: JSONValue?) -> Bool { value?.stringValue == "smooth" }

    /// The stroke of the line within its range; anything that is not a finite number is the default.
    static func readLineWidth(_ value: JSONValue?) -> Double {
        guard let number = value?.numberValue, number.isFinite else { return defaultLineWidth }
        return Swift.min(lineWidthRange.upperBound, Swift.max(lineWidthRange.lowerBound, number))
    }
}
