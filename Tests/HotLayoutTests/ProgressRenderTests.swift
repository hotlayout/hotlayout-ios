import SwiftUI
import XCTest

@testable import HotLayout

/// The drawings read back pixel by pixel: where the arc starts, where the steps leave gaps,
/// what a round end and a glow add. The geometry itself is measured by `ProgressCasesTests`.
@MainActor
final class ProgressRenderTests: XCTestCase {
    private let fill = RGBA(hex: "#4f46e5")!
    private let track = RGBA(hex: "#eef0f6")!

    private func paint(_ fillColor: RGBA? = nil, thickness: Double = 10, gradient: [GradientValue.Stop]? = nil) -> ProgressPaint {
        ProgressPaint(thickness: thickness, track: track, fill: gradient.map { .gradient($0) } ?? .color(fillColor ?? fill))
    }

    private func ring(_ ratio: Double, paint: ProgressPaint, round: Bool = false, glow: ProgressRules.Glow? = nil) -> some View {
        ProgressRing(paint: paint, ratio: ratio, diameter: 100, thickness: paint.thickness, roundEnds: round, glow: glow).frame(width: 100, height: 100)
    }

    func testRingStartsAtTheTopAndRunsClockwise() {
        let image = ProgressPixels.render(ring(0.25, paint: paint()))
        XCTAssertTrue(ProgressPixels.color(image, x: 95, y: 45).isNear(fill), "just above three o'clock is filled")
        XCTAssertTrue(ProgressPixels.color(image, x: 55, y: 5).isNear(fill), "just after twelve is filled")
        XCTAssertTrue(ProgressPixels.color(image, x: 45, y: 5).isNear(track), "just before twelve is the track")
        XCTAssertTrue(ProgressPixels.color(image, x: 50, y: 95).isNear(track), "six o'clock is the track")
        XCTAssertEqual(ProgressPixels.color(image, x: 50, y: 50).alpha, 0, "the middle is empty")
        XCTAssertEqual(ProgressPixels.color(image, x: 2, y: 2).alpha, 0, "the corner is outside the circle")
    }

    func testRingArcLiesInsideTheCircle() {
        let image = ProgressPixels.render(ring(1, paint: paint(thickness: 10)))
        XCTAssertTrue(ProgressPixels.color(image, x: 98, y: 50).isNear(fill), "the outer edge is the diameter")
        XCTAssertGreaterThan(ProgressPixels.color(image, x: 92, y: 50).alpha, 0.99)
        XCTAssertEqual(ProgressPixels.color(image, x: 85, y: 50).alpha, 0, "inside the stroke is the hole")
    }

    func testRingGradientRunsAlongTheFilledArc() {
        let stops = [GradientValue.Stop(color: RGBA(hex: "#ff0000")!, position: 0), GradientValue.Stop(color: RGBA(hex: "#0000ff")!, position: 1)]
        let image = ProgressPixels.render(ring(0.5, paint: paint(gradient: stops)))
        let start = ProgressPixels.color(image, x: 52, y: 5)
        let end = ProgressPixels.color(image, x: 48, y: 94)
        XCTAssertGreaterThan(start.red, 0.8, "the arc starts in the first colour")
        XCTAssertGreaterThan(end.blue, 0.8, "the arc ends in the last colour, not at the end of the circle")
        XCTAssertTrue(ProgressPixels.color(image, x: 45, y: 94).isNear(track) || ProgressPixels.color(image, x: 45, y: 94).alpha > 0, "the pixel past the end exists")
    }

    func testRoundEndsAddHalfCirclesPastTheEdges() {
        let square = ProgressPixels.render(ring(0.5, paint: paint()))
        let round = ProgressPixels.render(ring(0.5, paint: paint(), round: true))
        XCTAssertTrue(ProgressPixels.color(square, x: 48, y: 5).isNear(track), "a square arc starts exactly at twelve")
        XCTAssertTrue(ProgressPixels.color(round, x: 48, y: 5).isNear(track), "the round end stays inside the filled part")
        XCTAssertTrue(ProgressPixels.color(square, x: 50, y: 0).isNear(fill, tolerance: 0.25), "the square corner at twelve is filled")
        XCTAssertTrue(ProgressPixels.color(round, x: 50, y: 0).isNear(track, tolerance: 0.1), "the corner is rounded off: the track shows")
        XCTAssertTrue(ProgressPixels.color(round, x: 54, y: 5).isNear(fill))
        XCTAssertTrue(ProgressPixels.color(round, x: 50, y: 95).isNear(fill) || ProgressPixels.color(round, x: 50, y: 94).isNear(fill), "the end at six o'clock")
    }

    func testFullRingHasNoSeam() {
        let image = ProgressPixels.render(ring(1, paint: paint(), round: true))
        XCTAssertTrue(ProgressPixels.color(image, x: 50, y: 5).isNear(fill))
        XCTAssertTrue(ProgressPixels.color(image, x: 48, y: 5).isNear(fill))
        XCTAssertTrue(ProgressPixels.color(image, x: 52, y: 5).isNear(fill))
    }

    private func bar(_ ratio: Double, segments: Int? = nil, current: RGBA? = nil, rtl: Bool = false, round: Bool = false, units: Double? = nil, glow: ProgressRules.Glow? = nil, paint barPaint: ProgressPaint? = nil) -> some View {
        ProgressBarScale(paint: barPaint ?? paint(thickness: 8), ratio: ratio, rightToLeft: rtl, pill: 72, roundEnds: round, segments: segments, gap: 4, currentColor: current, units: units, glow: glow)
            .frame(width: 320, height: 8)
    }

    func testStepsLeaveGapsWithNoTrackUnderThem() {
        let image = ProgressPixels.render(bar(0.5, segments: 6))
        XCTAssertTrue(ProgressPixels.color(image, x: 25, y: 4).isNear(fill), "the first step is filled")
        XCTAssertEqual(ProgressPixels.color(image, x: 52, y: 4).alpha, 0, "a gap shows what is behind")
        XCTAssertTrue(ProgressPixels.color(image, x: 160 + 20, y: 4).isNear(track), "the current step looks unfilled without a colour for it")
        XCTAssertTrue(ProgressPixels.color(image, x: 300, y: 4).isNear(track))
    }

    func testTheCurrentStepTakesItsColour() {
        let accent = RGBA(hex: "#0369a1")!
        let image = ProgressPixels.render(bar(0.5, segments: 6, current: accent))
        XCTAssertTrue(ProgressPixels.color(image, x: 160 + 20, y: 4).isNear(accent))
        XCTAssertTrue(ProgressPixels.color(image, x: 300, y: 4).isNear(track))
    }

    func testStepsAreMirroredInRightToLeft() {
        let image = ProgressPixels.render(bar(0.5, segments: 6, rtl: true))
        XCTAssertTrue(ProgressPixels.color(image, x: 320 - 25, y: 4).isNear(fill), "the first step is on the right")
        XCTAssertTrue(ProgressPixels.color(image, x: 25, y: 4).isNear(track))
    }

    func testAStepFillsPartlyDuringATransition() {
        let image = ProgressPixels.render(bar(0.5, segments: 6, units: 3.5))
        XCTAssertTrue(ProgressPixels.color(image, x: 162 + 10, y: 4).isNear(fill), "the fourth step is filled in its first half")
        XCTAssertTrue(ProgressPixels.color(image, x: 162 + 40, y: 4).isNear(track), "and open in its second half")
    }

    func testTheGradientRunsAlongTheFilledStepsAsAlongOneFill() {
        let stops = [GradientValue.Stop(color: RGBA(hex: "#ff0000")!, position: 0), GradientValue.Stop(color: RGBA(hex: "#0000ff")!, position: 1)]
        let image = ProgressPixels.render(bar(0.5, segments: 6, paint: paint(thickness: 8, gradient: stops)))
        XCTAssertGreaterThan(ProgressPixels.color(image, x: 3, y: 4).red, 0.9)
        XCTAssertGreaterThan(ProgressPixels.color(image, x: 155, y: 4).blue, 0.9, "the last filled step ends in the last colour")
    }

    func testRoundEndsOfTheBarAreHalfCirclesOfTheThickness() {
        let image = ProgressPixels.render(bar(0.5, round: true, paint: paint(thickness: 8)))
        XCTAssertEqual(ProgressPixels.color(image, x: 0, y: 0).alpha, 0, accuracy: 0.6, "the corner of the end is cut")
        XCTAssertTrue(ProgressPixels.color(image, x: 4, y: 4).isNear(fill))
        let dot = ProgressPixels.render(bar(0.01, round: true, paint: paint(thickness: 8)))
        XCTAssertTrue(ProgressPixels.color(dot, x: 4, y: 4).isNear(fill), "a tiny share is a dot of the thickness")
        XCTAssertTrue(ProgressPixels.color(dot, x: 12, y: 4).isNear(track))
    }

    func testAGlowLightsTheSpaceAroundTheFillAndNothingElse() {
        func padded(_ glow: ProgressRules.Glow?) -> ProgressPixels.Image {
            ProgressPixels.render(bar(0.5, glow: glow).padding(24))
        }
        let plain = padded(nil)
        let strong = padded(.strong)
        XCTAssertEqual(ProgressPixels.color(plain, x: 100, y: 24 - 6).alpha, 0)
        XCTAssertGreaterThan(ProgressPixels.color(strong, x: 100, y: 24 - 6).alpha, 0.05, "the glow spills above the bar")
        XCTAssertEqual(ProgressPixels.color(strong, x: 24 + 300, y: 24 - 6).alpha, 0, accuracy: 0.03, "no glow where nothing is filled")
        XCTAssertTrue(ProgressPixels.color(strong, x: 24 + 10, y: 24 + 4).isNear(fill, tolerance: 0.2), "the scale itself is on top")
    }

    func testNothingFilledGlowsNothing() {
        let image = ProgressPixels.render(bar(0, glow: .strong).padding(24))
        XCTAssertEqual(ProgressPixels.color(image, x: 100, y: 24 - 6).alpha, 0)
    }
}
