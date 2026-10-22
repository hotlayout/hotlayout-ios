import SwiftUI
import XCTest

@testable import HotLayout

#if canImport(UIKit)
import UIKit

/// The glass is a blur under the node's own background. The system blur also lifts or darkens what
/// lies under it, so the reader picks the material by the brightness of the picture around the
/// glass and spends only the share of the effect whose tint the background leaves showing; these
/// tests pin that choice. (The colour itself is measured on the real
/// screen: the system draws a blur view only on screen, so an off-screen render of it is empty.)
@MainActor
final class GlassTintTests: XCTestCase {
    private func effectViews(in view: UIView) -> [UIVisualEffectView] {
        (view as? UIVisualEffectView).map { [$0] } ?? view.subviews.flatMap { effectViews(in: $0) }
    }

    private let square = LogicalCornersShape(corners: Corners(), rightToLeft: false)

    func testStyleFollowsTheBrightnessUnderTheGlass() {
        XCTAssertEqual(GlassBlur.effectStyle(dark: true), .dark)
        XCTAssertEqual(GlassBlur.effectStyle(dark: false), .systemUltraThinMaterialLight)
    }

    func testStrengthGrowsWithTheRadiusAndStopsAtTheLargest() {
        XCTAssertEqual(GlassBlur.strength(forRadius: 20), 0.5, accuracy: 0.001)
        XCTAssertEqual(GlassBlur.strength(forRadius: 40), 1, accuracy: 0.001)
        XCTAssertEqual(GlassBlur.strength(forRadius: 400), 1, accuracy: 0.001)
        XCTAssertLessThan(GlassBlur.strength(forRadius: 12), GlassBlur.strength(forRadius: 24))
    }

    func testABackgroundOverTheGlassLetsMoreOfTheEffectThrough() {
        // A bar with a background of 0.78 at radius 20: the tint that shows is 0.5 either way.
        XCTAssertEqual(GlassBlur.strength(forRadius: 20, cover: 0.78), 1, accuracy: 0.001)
        XCTAssertEqual(GlassBlur.strength(forRadius: 16, cover: 0.2), 0.5, accuracy: 0.001)
        XCTAssertEqual(GlassBlur.strength(forRadius: 16, cover: 1), 1, accuracy: 0.001)
        XCTAssertEqual(GlassBlur.strength(forRadius: 16, cover: -1), GlassBlur.strength(forRadius: 16), accuracy: 0.001)
    }

    func testGlassIsOneBlurViewWithTheStrengthOfItsRadius() throws {
        let box = Color.clear.frame(width: 120, height: 80).glass(24, shape: square)
        let window = try XCTUnwrap(showScreen(box) as? UIWindow)
        let views = effectViews(in: window)
        XCTAssertEqual(views.count, 1)
        let view = try XCTUnwrap(views.first)
        XCTAssertTrue(view.effect is UIBlurEffect)
        XCTAssertEqual(view.alpha, GlassBlur.strength(forRadius: 24), accuracy: 0.001)
        XCTAssertFalse(view.isUserInteractionEnabled)
    }

    func testNoRadiusMeansNoBlurView() throws {
        let box = Color.clear.frame(width: 120, height: 80).glass(nil, shape: square)
        let window = try XCTUnwrap(showScreen(box) as? UIWindow)
        XCTAssertTrue(effectViews(in: window).isEmpty)
    }
}
#endif
