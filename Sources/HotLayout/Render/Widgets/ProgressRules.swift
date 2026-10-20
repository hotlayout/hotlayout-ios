import Foundation

/// The geometry and the rules of the progress scale, as pure functions: the bar and the ring are
/// one scale in two forms (`x-style.layout.progress`, `progressSegments`, `progressCap`,
/// `progressLabel`, `progressGlow`, `segmentsTransition`). Nothing here draws.
enum ProgressRules {
    static let defaultThickness = "sm"
    static let defaultTrackColor = "secondary"
    static let defaultColor = "primary"
    static let ringUnit = "xl"
    static let ringScale: [String: Double] = ["sm": 2, "md": 3, "lg": 4]
    static let defaultRingSize = "md"
    static let segmentGap = "xs"
    static let segmentsRange = 2...12
    static let segmentPrecision = 6.0
    static let minSegmentInline = 1.0
    static let defaultLabelTypography = "caption"
    static let defaultLabelColor = "onSurface"
    static let barLabelColor = "muted"
    static let barLabelGap = "xs"

    // MARK: Ratio

    /// `value / max` clamped to 0…1; no number, no scale (`max` ≤ 0) and not finite give 0.
    static func ratio(value: Double?, max: Double?) -> Double {
        guard let value, let max, value.isFinite, max.isFinite, max > 0 else { return 0 }
        return Swift.min(Swift.max(value / max, 0), 1)
    }

    static func clamped(_ ratio: Double) -> Double { Swift.min(Swift.max(ratio, 0), 1) }

    // MARK: Ring

    static func ringScale(of size: JSONValue?) -> Double {
        if let word = size?.stringValue, let scale = ringScale[word] { return scale }
        return ringScale[defaultRingSize] ?? 3
    }

    /// What the style named and what it consumes inside. Only fields the reader APPLIES are
    /// passed: under a row weight the width fields are not, on a fill layer none are.
    struct RingBox {
        var size: JSONValue?
        var unit: Double
        var width: Double?
        var minWidth: Double?
        var maxWidth: Double?
        var height: Double?
        var minHeight: Double?
        var maxHeight: Double?
        var paddingInline: Double = 0
        var paddingBlock: Double = 0
        var border: Double = 0
        var thickness: Double
    }

    struct RingGeometry: Equatable {
        var diameter: Double
        var thickness: Double
        var boxInline: Double
        var boxBlock: Double
    }

    /// A size bounded by a minimum and a maximum; an inverted range gives the minimum.
    static func constrained(_ size: Double, min low: Double?, max high: Double?) -> Double {
        var result = size
        if let high { result = Swift.min(high, result) }
        if let low { result = Swift.max(low, result) }
        return result
    }

    private static func namedSide(_ size: Double?, _ low: Double?, _ high: Double?, natural: Double) -> Double? {
        if size == nil, low == nil, high == nil { return nil }
        return constrained(size ?? natural, min: low, max: high)
    }

    /// The diameter is the smaller named side of the content box, else the size word; the
    /// unnamed side equals it; the thickness is at most half of it (`progress.ring`).
    static func ringGeometry(_ input: RingBox) -> RingGeometry {
        let bySize = ringScale(of: input.size) * input.unit
        let boxInline = namedSide(input.width, input.minWidth, input.maxWidth, natural: bySize + input.paddingInline + 2 * input.border)
        let boxBlock = namedSide(input.height, input.minHeight, input.maxHeight, natural: bySize + input.paddingBlock + 2 * input.border)
        var content: [Double] = []
        if let boxInline { content.append(Swift.max(0, boxInline - input.paddingInline - 2 * input.border)) }
        if let boxBlock { content.append(Swift.max(0, boxBlock - input.paddingBlock - 2 * input.border)) }
        let diameter = content.min() ?? bySize
        return RingGeometry(
            diameter: diameter,
            thickness: Swift.min(Swift.max(0, input.thickness), diameter / 2),
            boxInline: boxInline ?? diameter + input.paddingInline + 2 * input.border,
            boxBlock: boxBlock ?? diameter + input.paddingBlock + 2 * input.border
        )
    }

    /// The arc starts at the top and runs clockwise; the ring is not mirrored in right-to-left.
    static func ringArc(_ ratio: Double) -> (startDeg: Double, sweepDeg: Double) {
        (0, 360 * clamped(ratio))
    }

    // MARK: Bar

    /// Half of the shorter side, never more than the theme `pill` radius.
    static func barFillRadius(fillInline: Double, thickness: Double, pill: Double) -> Double {
        Swift.max(0, Swift.min(pill, fillInline / 2, thickness / 2))
    }

    struct BarGeometry: Equatable {
        var trackBlock: Double
        var fillInline: Double
        var trackRadius: Double
        var fillRadius: Double
    }

    static func barGeometry(trackInline: Double, thickness: Double, ratio: Double, pill: Double) -> BarGeometry {
        let fill = trackInline * clamped(ratio)
        return BarGeometry(
            trackBlock: thickness,
            fillInline: fill,
            trackRadius: barFillRadius(fillInline: trackInline, thickness: thickness, pill: pill),
            fillRadius: barFillRadius(fillInline: fill, thickness: thickness, pill: pill)
        )
    }

    /// A gradient lies along the FILLED part: a stop at `position` stands at `position × ratio`.
    static func gradientStops(_ stops: [GradientValue.Stop], ratio: Double) -> [(color: RGBA, at: Double)] {
        stops.map { ($0.color, $0.position * ratio) }
    }

    // MARK: Segments

    /// A whole number 2…12; anything else (a string, a fraction, 1, 13) is the continuous bar.
    static func segmentsCount(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue, number.isFinite, let whole = SafeInt.exactly(number), segmentsRange.contains(whole) else { return nil }
        return whole
    }

    /// `floor(round(ratio × segments, 6))`: a step is full or empty.
    static func filledSegments(ratio: Double, segments: Int) -> Int {
        let scale = pow(10, segmentPrecision)
        let units = (clamped(ratio) * Double(segments) * scale + 0.5).rounded(.down) / scale
        return Swift.min(segments, Swift.max(0, SafeInt.clamped(units.rounded(.down))))
    }

    enum SegmentState: String { case filled = "f", current = "c", unfilled = "u" }

    struct SegmentBox: Equatable {
        var start: Double
        var inline: Double
        var state: SegmentState
    }

    struct SegmentGeometry: Equatable {
        var boxes: [SegmentBox]
        var filled: Int
        var current: Int?
        var radius: Double
        var filledInline: Double
        var states: String { boxes.map(\.state.rawValue).joined() }
    }

    /// `nil`: the steps are not drawn and the bar is continuous (a step narrower than 1).
    static func segmentGeometry(trackInline: Double, thickness: Double, ratio: Double, segments: Int, gap: Double, pill: Double) -> SegmentGeometry? {
        guard segmentsKind(placeInline: trackInline, segments: segments, gap: gap) == .steps else { return nil }
        let inline = (trackInline - Double(segments - 1) * gap) / Double(segments)
        let filled = filledSegments(ratio: ratio, segments: segments)
        let current: Int? = filled < segments ? filled : nil
        let boxes = (0..<segments).map { index in
            SegmentBox(start: Double(index) * (inline + gap), inline: inline, state: index < filled ? .filled : (index == current ? .current : .unfilled))
        }
        return SegmentGeometry(
            boxes: boxes, filled: filled, current: current,
            radius: barFillRadius(fillInline: inline, thickness: thickness, pill: pill),
            filledInline: filled == 0 ? 0 : Double(filled) * inline + Double(filled - 1) * gap
        )
    }

    enum SegmentsKind: Equatable { case steps, continuous }

    /// The width the PLACE gives decides the kind, never the bar's own measure.
    static func segmentsKind(placeInline: Double, segments: Int, gap: Double) -> SegmentsKind {
        let inline = (placeInline - Double(segments - 1) * gap) / Double(segments)
        return inline.isFinite && inline >= minSegmentInline ? .steps : .continuous
    }

    /// The own minimum width is the gaps, in both kinds.
    static func segmentsMinInline(segments: Int, gap: Double) -> Double {
        Swift.max(0, Double(segments - 1) * gap)
    }

    // MARK: Steps during a transition (9.25.0)

    /// `U(from) + (U(to) − U(from)) × e`, `U` the whole steps at rest; both ends are pictures at rest.
    static func segmentUnits(fromRatio: Double, toRatio: Double, eased: Double, segments: Int) -> Double {
        let from = Double(filledSegments(ratio: fromRatio, segments: segments))
        let to = Double(filledSegments(ratio: toRatio, segments: segments))
        return from + (to - from) * Swift.min(1, Swift.max(0, eased))
    }

    static func segmentFills(units: Double, segments: Int) -> [Double] {
        (0..<segments).map { Swift.min(1, Swift.max(0, units - Double($0))) }
    }

    /// The first step that is not full; `nil` when every step is.
    static func segmentCurrent(_ fills: [Double]) -> Int? { fills.firstIndex { $0 < 1 } }

    /// The length of the gradient line along the drawn fill.
    static func segmentFillInline(units: Double, step: Double, gap: Double) -> Double {
        if units <= 0 { return 0 }
        return units * step + (units.rounded(.up) - 1) * gap
    }

    /// The eased share recovered from the shown value of the scale.
    static func transitionShare(from: Double, to: Double, shown: Double) -> Double {
        guard from != to, from.isFinite, to.isFinite, shown.isFinite else { return 1 }
        return Swift.min(1, Swift.max(0, (shown - from) / (to - from)))
    }

    // MARK: Round ends (9.21.0)

    enum RingCapKind: String { case none, dot, arc, full }

    struct RingCap: Equatable {
        var kind: RingCapKind
        var capAngle: Double
        var startDeg: Double
        var endDeg: Double
    }

    /// Half-circle ends whose centres stand θc = thickness / (diameter − thickness) inside the
    /// filled part from each edge.
    static func ringCap(ratio: Double, diameter: Double, thickness: Double) -> RingCap {
        let share = clamped(ratio)
        let stroke = Swift.min(thickness, diameter / 2)
        let capAngle = diameter - stroke > 0 ? stroke / (diameter - stroke) : Double.pi
        let capDeg = capAngle * 180 / Double.pi
        if share <= 0 || stroke <= 0 { return RingCap(kind: .none, capAngle: capAngle, startDeg: 0, endDeg: 0) }
        if share >= 1 { return RingCap(kind: .full, capAngle: capAngle, startDeg: 0, endDeg: 360) }
        let sweep = 360 * share
        if sweep <= 2 * capDeg { return RingCap(kind: .dot, capAngle: capAngle, startDeg: capDeg, endDeg: capDeg) }
        return RingCap(kind: .arc, capAngle: capAngle, startDeg: capDeg, endDeg: sweep - capDeg)
    }

    /// `max(thickness, ratio × track)`, at most the track; an empty scale draws nothing.
    static func barCapFillInline(trackInline: Double, thickness: Double, ratio: Double) -> Double {
        let share = clamped(ratio)
        if share <= 0 { return 0 }
        return Swift.min(trackInline, Swift.max(thickness, trackInline * share))
    }

    static func barCapRadius(thickness: Double) -> Double { Swift.max(0, thickness / 2) }

    // MARK: Glow (9.25.0)

    enum Glow: String {
        case soft, strong

        var sigma: Double { self == .soft ? 4 : 8 }
        var opacity: Double { self == .soft ? 0.55 : 0.9 }

        init?(_ value: JSONValue?) {
            guard let word = value?.stringValue, let glow = Glow(rawValue: word) else { return nil }
            self = glow
        }
    }

    enum GlowingStep: Equatable {
        case none
        case current(index: Int)
        case front(index: Int, fill: Double)
    }

    /// One step glows: the current one when `currentColor` paints it, else the last with any fill.
    static func glowingStep(fills: [Double], currentPainted: Bool) -> GlowingStep {
        let current = fills.firstIndex { $0 < 1 }
        if currentPainted, let current { return .current(index: current) }
        guard let front = fills.lastIndex(where: { $0 > 0 }) else { return .none }
        return .front(index: front, fill: fills[front])
    }
}
