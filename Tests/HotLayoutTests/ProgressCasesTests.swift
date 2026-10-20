import SwiftUI
import XCTest

@testable import HotLayout

/// The shared progress table (`fixtures/progress/progress-cases.json`): the ratio, the ring box,
/// the arc, the bar, the paint, the steps, the label of the ring, round ends, the steps during
/// a transition and the glow — each group measured against the functions the views draw with.
@MainActor
final class ProgressCasesTests: XCTestCase {
    private static var table: JSONValue = { try! Contract.json("fixtures/progress/progress-cases.json") }()

    static func theme(_ json: JSONValue?) -> HotlayoutTheme {
        func map(_ key: String) -> [String: Double] { (json?[key]?.objectValue ?? JSONObject()).keys.reduce(into: [:]) { $0[$1] = json?[key]?[$1]?.numberValue } }
        var theme = HotlayoutTheme(id: "table", brightness: "light", spacing: map("spacing"), radius: map("radius"), color: [:], typography: [:], elevation: [:], gradient: [:], fontFamilies: [:], roles: [:])
        for (name, value) in json?["color"]?.objectValue ?? JSONObject() { theme.color[name] = value.stringValue.flatMap(RGBA.init(hex:)) }
        for (name, value) in json?["gradient"]?.objectValue ?? JSONObject() {
            let stops = (value["stops"]?.arrayValue ?? []).compactMap { stop -> GradientValue.Stop? in
                guard let color = stop["color"]?.stringValue.flatMap(RGBA.init(hex:)), let position = stop["position"]?.numberValue else { return nil }
                return GradientValue.Stop(color: color, position: position)
            }
            theme.gradient[name] = GradientValue(angle: value["angle"]?.numberValue ?? 0, stops: stops)
        }
        return theme
    }

    private var resolver: StyleResolver { StyleResolver(theme: Self.theme(Self.table["theme"])) }

    private func rows(_ group: String, expecting count: Int) -> [JSONObject] {
        let list = Contract.rows(Self.table, group)
        XCTAssertEqual(list.count, count, "\(group): the table has \(list.count) rows")
        return list
    }

    private func close(_ actual: Double, _ expected: Double?, _ message: String, tolerance: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        guard let expected else { return XCTFail("\(message): no expected number", file: file, line: line) }
        XCTAssertEqual(actual, expected, accuracy: tolerance, message, file: file, line: line)
    }

    private func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    // MARK: Ratio, ring, arc

    func testRatio() {
        for row in rows("ratioCases", expecting: 15) {
            let actual = ProgressRules.ratio(value: row["value"]?.numberValue, max: row["max"]?.numberValue)
            close(actual, row["expect"]?.numberValue, name(row), tolerance: 1e-12)
        }
    }

    /// The box of a ring as the table writes it: `padding` and `border` are one number for all sides.
    private func ringBox(_ row: JSONObject) -> ProgressRules.RingBox {
        let props = row["props"]?.objectValue ?? JSONObject()
        let style = row["style"]?.objectValue ?? JSONObject()
        let widthApplies = row["applied"]?["width"]?.boolValue != false
        let heightApplies = row["applied"]?["height"]?.boolValue != false
        let padding = (style["padding"]?.numberValue ?? 0) * 2
        return ProgressRules.RingBox(
            size: props["size"], unit: resolver.theme.spacing[ProgressRules.ringUnit] ?? 0,
            width: widthApplies ? style["width"]?.numberValue : nil, minWidth: widthApplies ? style["minWidth"]?.numberValue : nil, maxWidth: widthApplies ? style["maxWidth"]?.numberValue : nil,
            height: heightApplies ? style["height"]?.numberValue : nil, minHeight: heightApplies ? style["minHeight"]?.numberValue : nil, maxHeight: heightApplies ? style["maxHeight"]?.numberValue : nil,
            paddingInline: padding, paddingBlock: padding, border: style["border"]?.numberValue ?? 0,
            thickness: ProgressRules.paint(props, resolver: resolver).thickness
        )
    }

    func testRingGeometry() {
        for row in rows("ringCases", expecting: 33) {
            let geometry = ProgressRules.ringGeometry(ringBox(row))
            let expect = row["expect"]?.objectValue ?? JSONObject()
            close(geometry.diameter, expect["diameter"]?.numberValue, "\(name(row)): diameter")
            close(geometry.thickness, expect["thickness"]?.numberValue, "\(name(row)): thickness")
            if let inline = expect["boxInline"]?.numberValue { close(geometry.boxInline, inline, "\(name(row)): boxInline") }
            if let block = expect["boxBlock"]?.numberValue { close(geometry.boxBlock, block, "\(name(row)): boxBlock") }
            if let free = expect["freeInline"]?.numberValue { close(geometry.boxInline - geometry.diameter, free, "\(name(row)): freeInline") }
            if let free = expect["freeBlock"]?.numberValue { close(geometry.boxBlock - geometry.diameter, free, "\(name(row)): freeBlock") }
        }
    }

    func testRingArc() {
        for row in rows("arcCases", expecting: 5) {
            let arc = ProgressRules.ringArc(row["ratio"]?.numberValue ?? 0)
            close(arc.startDeg, row["expect"]?["startDeg"]?.numberValue, name(row))
            close(arc.sweepDeg, row["expect"]?["sweepDeg"]?.numberValue, name(row))
        }
    }

    // MARK: Bar

    func testBarGeometry() {
        for row in rows("barCases", expecting: 12) {
            let props = row["props"]?.objectValue ?? JSONObject()
            let thickness = ProgressRules.paint(props, resolver: resolver).thickness
            let geometry = ProgressRules.barGeometry(trackInline: row["trackInline"]?.numberValue ?? 0, thickness: thickness, ratio: row["ratio"]?.numberValue ?? 0, pill: resolver.theme.radius["pill"] ?? 0)
            let expect = row["expect"]?.objectValue ?? JSONObject()
            close(geometry.trackBlock, expect["trackBlock"]?.numberValue, "\(name(row)): trackBlock")
            close(geometry.fillInline, expect["fillInline"]?.numberValue, "\(name(row)): fillInline")
            close(geometry.trackRadius, expect["trackRadius"]?.numberValue, "\(name(row)): trackRadius")
            close(geometry.fillRadius, expect["fillRadius"]?.numberValue, "\(name(row)): fillRadius")
        }
    }

    /// The side the fill grows from, read off a real drawing: a bar at half, the pixel next to
    /// each end.
    func testBarFillGrowsFromTheLogicalStart() {
        let barRows = rows("barCases", expecting: 12).filter { $0["ratio"]?.numberValue == 0.5 && ($0["expect"]?["trackBlock"]?.numberValue ?? 0) > 0 && $0["expect"]?["fillInline"]?.numberValue == $0["trackInline"]?.numberValue.map { $0 / 2 } }
        XCTAssertGreaterThanOrEqual(barRows.count, 2)
        for row in barRows {
            let rtl = row["direction"]?.stringValue == "rtl"
            let props = row["props"]?.objectValue ?? JSONObject()
            let paint = ProgressRules.paint(props, resolver: resolver)
            let width = row["trackInline"]?.numberValue ?? 100
            let bar = ProgressBarScale(paint: paint, ratio: 0.5, rightToLeft: rtl, pill: 72, roundEnds: false, segments: nil, gap: 4, currentColor: nil, units: nil, glow: nil)
                .frame(width: width, height: paint.thickness)
            let image = ProgressPixels.render(bar)
            let middle = Int(paint.thickness / 2)
            let leftIsFill = ProgressPixels.color(image, x: 10, y: middle).isNear(paint.fillColor)
            let rightIsFill = ProgressPixels.color(image, x: Int(width) - 10, y: middle).isNear(paint.fillColor)
            XCTAssertEqual(leftIsFill, row["expect"]?["fillFrom"]?.stringValue == "left", "\(name(row)): left end")
            XCTAssertEqual(rightIsFill, row["expect"]?["fillFrom"]?.stringValue == "right", "\(name(row)): right end")
        }
    }

    // MARK: Paint

    private func assertColor(_ color: RGBA?, _ expected: JSONValue?, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let color, let expected else { return XCTFail("\(message): missing colour", file: file, line: line) }
        XCTAssertEqual(color.hex, expected["hex"]?.stringValue, message, file: file, line: line)
        XCTAssertEqual(color.alpha, expected["opacity"]?.numberValue ?? 1, accuracy: 1e-6, "\(message): opacity", file: file, line: line)
    }

    func testPaint() {
        for row in rows("paintCases", expecting: 21) {
            let props = row["props"]?.objectValue ?? JSONObject()
            let ratio = row["ratio"]?.numberValue ?? 0
            let paint = ProgressRules.paint(props, resolver: resolver)
            let expect = row["expect"]
            assertColor(paint.track, expect?["track"], "\(name(row)): track")
            let fill = expect?["fill"]
            switch paint.fill {
            case .color(let color):
                XCTAssertEqual(fill?["kind"]?.stringValue, "color", name(row))
                assertColor(color, fill, "\(name(row)): fill")
            case .gradient(let stops):
                XCTAssertEqual(fill?["kind"]?.stringValue, "gradient", name(row))
                let expectedStops = fill?["stops"]?.arrayValue ?? []
                XCTAssertEqual(stops.count, expectedStops.count, name(row))
                for (stop, expected) in zip(ProgressRules.gradientStops(stops, ratio: ratio), expectedStops) {
                    assertColor(stop.color, expected, "\(name(row)): stop")
                    close(stop.at, expected["at"]?.numberValue, "\(name(row)): stop position")
                }
            }
        }
    }

    // MARK: Steps

    func testSegments() {
        for row in rows("segmentCases", expecting: 21) {
            let props = row["props"]?.objectValue ?? JSONObject()
            let theme = resolver.theme
            let paint = ProgressRules.paint(props, resolver: resolver)
            let ratio = ProgressRules.ratio(value: row["value"]?.numberValue, max: row["max"]?.numberValue)
            let geometry = ProgressRules.readSegmentsGeometry(props: props, track: row["trackInline"]?.numberValue ?? 0, thickness: paint.thickness, ratio: ratio, gap: theme.spacing[ProgressRules.segmentGap] ?? 0, pill: theme.radius["pill"] ?? 0)
            guard let expect = row["expect"]?.objectValue else {
                XCTAssertNil(geometry, "\(name(row)): the bar is continuous")
                continue
            }
            guard let geometry else { XCTFail("\(name(row)): steps expected"); continue }
            close(geometry.boxes.first?.inline ?? -1, expect["inline"]?.numberValue, "\(name(row)): inline")
            if let starts = expect["starts"]?.arrayValue {
                XCTAssertEqual(geometry.boxes.count, starts.count, name(row))
                for (box, start) in zip(geometry.boxes, starts) { close(box.start, start.numberValue, "\(name(row)): start") }
            }
            XCTAssertEqual(geometry.filled, Int(expect["filled"]?.numberValue ?? -1), "\(name(row)): filled")
            XCTAssertEqual(geometry.current, expect["current"]?.numberValue.map(Int.init), "\(name(row)): current")
            XCTAssertEqual(geometry.states, expect["states"]?.stringValue, "\(name(row)): states")
            close(geometry.radius, expect["radius"]?.numberValue, "\(name(row)): radius")
            close(geometry.filledInline, expect["filledInline"]?.numberValue, "\(name(row)): filledInline")
        }
    }

    func testSegmentsKindIsDecidedByThePlace() {
        for row in rows("segmentPlaceCases", expecting: 6) {
            let props = row["props"]?.objectValue ?? JSONObject()
            guard let segments = ProgressRules.segmentsCount(props["segments"]) else { XCTFail(name(row)); continue }
            let gap = resolver.theme.spacing[ProgressRules.segmentGap] ?? 0
            let place = row["placeInline"]?.numberValue ?? 0
            let expect = row["expect"]
            let kind = ProgressRules.segmentsKind(placeInline: place, segments: segments, gap: gap)
            XCTAssertEqual(kind == .steps ? "steps" : "continuous", expect?["kind"]?.stringValue, name(row))
            close(ProgressRules.segmentsMinInline(segments: segments, gap: gap), expect?["ownMinInline"]?.numberValue, "\(name(row)): own minimum")
            if let inline = expect?["inline"]?.numberValue { close((place - Double(segments - 1) * gap) / Double(segments), inline, "\(name(row)): step") }
        }
    }

    func testSegmentPaint() {
        for row in rows("segmentPaintCases", expecting: 6) {
            let props = row["props"]?.objectValue ?? JSONObject()
            let expect = row["expect"]
            let paint = ProgressRules.paint(props, resolver: resolver)
            assertColor(paint.track, expect?["unfilled"], "\(name(row)): unfilled")
            let current = ProgressRules.currentColor(props, resolver: resolver)
            if let expected = expect?["current"], !expected.isNull {
                assertColor(current, expected, "\(name(row)): current")
            } else {
                XCTAssertNil(current, "\(name(row)): the current step looks unfilled")
            }
        }
    }

    func testSegmentGradientRunsAlongTheFilledSteps() {
        for row in rows("segmentGradientCases", expecting: 3) {
            let props = row["props"]?.objectValue ?? JSONObject()
            let theme = resolver.theme
            let paint = ProgressRules.paint(props, resolver: resolver)
            let ratio = ProgressRules.ratio(value: row["value"]?.numberValue, max: row["max"]?.numberValue)
            guard let geometry = ProgressRules.readSegmentsGeometry(props: props, track: row["trackInline"]?.numberValue ?? 0, thickness: paint.thickness, ratio: ratio, gap: theme.spacing[ProgressRules.segmentGap] ?? 0, pill: theme.radius["pill"] ?? 0),
                case .gradient(let stops) = paint.fill
            else { XCTFail(name(row)); continue }
            let expect = row["expect"]
            close(0, expect?["lineFrom"]?.numberValue, name(row))
            close(geometry.filledInline, expect?["lineTo"]?.numberValue, "\(name(row)): line end")
            for (stop, expected) in zip(stops, expect?["stops"]?.arrayValue ?? []) {
                XCTAssertEqual(stop.color.hex, expected["hex"]?.stringValue, name(row))
                close(stop.position * geometry.filledInline, expected["at"]?.numberValue, "\(name(row)): stop")
            }
            XCTAssertEqual(expect?["gapsCutOut"]?.boolValue, true, name(row))
        }
    }

    // MARK: Label of the ring

    func testRingLabel() throws {
        let labelTheme = Self.table["labelTheme"]
        var theme = resolver.theme
        for (name, value) in labelTheme?["typography"]?.objectValue ?? JSONObject() {
            theme.typography[name] = TextStyleValue(fontSize: value["fontSize"]?.numberValue ?? 0, lineHeight: value["lineHeight"]?.numberValue ?? 1, fontWeight: Int(value["fontWeight"]?.numberValue ?? 400))
        }
        for (name, value) in labelTheme?["color"]?.objectValue ?? JSONObject() { theme.color[name] = value.stringValue.flatMap(RGBA.init(hex:)) }
        let labelResolver = StyleResolver(theme: theme)
        for row in rows("ringLabelCases", expecting: 20) {
            let props = row["props"]?.objectValue ?? JSONObject()
            let expect = row["expect"]
            let value = row["value"]?.numberValue ?? 0
            let max = row["max"]?.numberValue ?? 100
            let ratio = ProgressRules.ratio(value: value, max: max)
            XCTAssertEqual(ProgressRules.labelText(format: props["labelFormat"]?.stringValue, value: value, max: max, ratio: ratio), expect?["text"]?.stringValue, "\(name(row)): text")
            var box = ringBox(row)
            box.unit = theme.spacing[ProgressRules.ringUnit] ?? 0
            let geometry = ProgressRules.ringGeometry(box)
            close(geometry.diameter, expect?["diameter"]?.numberValue, "\(name(row)): diameter")
            close(geometry.boxInline, expect?["boxInline"]?.numberValue, "\(name(row)): the label does not size the ring")
            close(geometry.boxBlock, expect?["boxBlock"]?.numberValue, "\(name(row)): the label does not size the ring")
            let style = ProgressRules.labelStyle(props, resolver: labelResolver)
            let typography = expect?["typography"]
            XCTAssertEqual(style.token, typography?["token"]?.stringValue, "\(name(row)): token")
            close(style.typography.fontSize, typography?["fontSize"]?.numberValue, "\(name(row)): size")
            XCTAssertEqual(Double(style.typography.fontWeight), typography?["fontWeight"]?.numberValue, "\(name(row)): weight")
            close(style.typography.lineHeight, typography?["lineHeight"]?.numberValue, "\(name(row)): line height")
            close(style.typography.lineBox, typography?["lineBlock"]?.numberValue, "\(name(row)): line block", tolerance: 1e-3)
            assertColor(style.color, expect?["color"], "\(name(row)): colour")
        }
        for row in rows("ringLabelNoneCases", expecting: 2) {
            let props = row["props"]?.objectValue ?? JSONObject()
            XCTAssertNil(ProgressRules.labelText(format: props["labelFormat"]?.stringValue, value: 74, max: 119, ratio: 0.62), name(row))
            close(ProgressRules.ringGeometry(ringBox(row)).diameter, row["expect"]?["diameter"]?.numberValue, name(row))
        }
    }

    // MARK: Round ends

    func testRoundEnds() {
        for row in rows("capCases", expecting: 20) {
            let expected = row["expected"]
            let ratio = row["ratio"]?.numberValue ?? 0
            if row["widget"]?.stringValue == "CircularProgress" {
                let cap = ProgressRules.ringCap(ratio: ratio, diameter: row["diameter"]?.numberValue ?? 0, thickness: row["thickness"]?.numberValue ?? 0)
                XCTAssertEqual(cap.kind.rawValue, expected?["kind"]?.stringValue, name(row))
                close(cap.startDeg, expected?["startDeg"]?.numberValue, "\(name(row)): start")
                close(cap.endDeg, expected?["endDeg"]?.numberValue, "\(name(row)): end")
                close(cap.capAngle, expected?["capAngle"]?.numberValue, "\(name(row)): thetaC")
            } else {
                let thickness = row["thickness"]?.numberValue ?? 0
                close(ProgressRules.barCapFillInline(trackInline: row["track"]?.numberValue ?? 0, thickness: thickness, ratio: ratio), expected?["fillInline"]?.numberValue, "\(name(row)): fill")
                close(ProgressRules.barCapRadius(thickness: thickness), expected?["radius"]?.numberValue, "\(name(row)): radius")
            }
        }
    }

    // MARK: Steps during a transition, glow

    func testStepsDuringATransition() {
        for row in rows("segmentFillCases", expecting: 12) {
            let segments = Int(row["segments"]?.numberValue ?? 0)
            let units = ProgressRules.segmentUnits(fromRatio: row["fromRatio"]?.numberValue ?? 0, toRatio: row["toRatio"]?.numberValue ?? 0, eased: row["eased"]?.numberValue ?? 0, segments: segments)
            let expected = row["expected"]
            close(units, expected?["units"]?.numberValue, "\(name(row)): units", tolerance: 1e-9)
            let fills = ProgressRules.segmentFills(units: units, segments: segments)
            let wanted = (expected?["fills"]?.arrayValue ?? []).compactMap(\.numberValue)
            XCTAssertEqual(fills.count, wanted.count, name(row))
            for (fill, want) in zip(fills, wanted) { close(fill, want, "\(name(row)): fill", tolerance: 1e-9) }
            XCTAssertEqual(ProgressRules.segmentCurrent(fills), expected?["current"]?.numberValue.map(Int.init), "\(name(row)): current")
        }
        for row in rows("segmentFillInlineCases", expecting: 4) {
            close(ProgressRules.segmentFillInline(units: row["units"]?.numberValue ?? 0, step: row["step"]?.numberValue ?? 0, gap: row["gap"]?.numberValue ?? 0), row["expected"]?.numberValue, name(row), tolerance: 1e-9)
        }
        for row in rows("transitionShareCases", expecting: 5) {
            close(ProgressRules.transitionShare(from: row["from"]?.numberValue ?? 0, to: row["to"]?.numberValue ?? 0, shown: row["shown"]?.numberValue ?? 0), row["expected"]?.numberValue, name(row), tolerance: 1e-9)
        }
    }

    func testGlow() {
        for row in rows("glowStepCases", expecting: 7) {
            let fills = (row["fills"]?.arrayValue ?? []).compactMap(\.numberValue)
            let step = ProgressRules.glowingStep(fills: fills, currentPainted: row["currentPainted"]?.boolValue ?? false)
            let expected = row["expected"]
            switch step {
            case .none: XCTAssertEqual(expected?["kind"]?.stringValue, "none", name(row))
            case .current(let index):
                XCTAssertEqual(expected?["kind"]?.stringValue, "current", name(row))
                XCTAssertEqual(index, Int(expected?["index"]?.numberValue ?? -1), name(row))
            case .front(let index, let fill):
                XCTAssertEqual(expected?["kind"]?.stringValue, "front", name(row))
                XCTAssertEqual(index, Int(expected?["index"]?.numberValue ?? -1), name(row))
                close(fill, expected?["fill"]?.numberValue, name(row))
            }
        }
        for row in rows("glowRuleCases", expecting: 6) {
            let expect = row["expect"]
            switch row["rule"]?.stringValue {
            case "strength.soft.sigma": close(ProgressRules.Glow.soft.sigma, expect?.numberValue, name(row))
            case "strength.soft.opacity": close(ProgressRules.Glow.soft.opacity, expect?.numberValue, name(row))
            case "strength.strong.sigma": close(ProgressRules.Glow.strong.sigma, expect?.numberValue, name(row))
            case "strength.strong.opacity": close(ProgressRules.Glow.strong.opacity, expect?.numberValue, name(row))
            case "on": XCTAssertEqual(Set(expect?.arrayValue?.compactMap(\.stringValue) ?? []), ["ProgressBar", "CircularProgress"], name(row))
            case "segments.others": XCTAssertEqual(expect?.stringValue, "no glow"); XCTAssertEqual(ProgressRules.glowingStep(fills: [1, 0, 0], currentPainted: false), .front(index: 0, fill: 1))
            default: XCTFail("rule not read: \(name(row))")
            }
        }
        XCTAssertNil(ProgressRules.Glow(.string("blinding")))
        XCTAssertNil(ProgressRules.Glow(nil))
    }
}

extension ProgressRules {
    /// The steps of a bar from its props: `nil` when the field does not name 2…12 whole steps
    /// or a step would be narrower than one point.
    static func readSegmentsGeometry(props: JSONObject, track: Double, thickness: Double, ratio: Double, gap: Double, pill: Double) -> SegmentGeometry? {
        guard let segments = segmentsCount(props["segments"]) else { return nil }
        return segmentGeometry(trackInline: track, thickness: thickness, ratio: ratio, segments: segments, gap: gap, pill: pill)
    }
}

extension ProgressPaint {
    var fillColor: RGBA {
        switch fill {
        case .color(let color): return color
        case .gradient(let stops): return stops.first?.color ?? track
        }
    }
}
