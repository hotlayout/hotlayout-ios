import SwiftUI
import XCTest

@testable import HotLayout

#if canImport(UIKit)
import UIKit

/// The glass is the blur alone: the system material also lightens and greys what lies under it
/// (a luminance curve, a saturation boost and a tint layer), which turned a violet card grey.
@MainActor
final class GlassTintTests: XCTestCase {
    private func effectViews(in view: UIView) -> [UIVisualEffectView] {
        (view as? UIVisualEffectView).map { [$0] } ?? view.subviews.flatMap { effectViews(in: $0) }
    }

    func testGlassOnTheScreenKeepsOnlyTheGaussianBlur() throws {
        let box = Color.clear.frame(width: 120, height: 80).glass(16, shape: LogicalCornersShape(corners: Corners(), rightToLeft: false))
        let held = showScreen(box)
        let window = try XCTUnwrap(held as? UIWindow)
        let views = effectViews(in: window)
        XCTAssertEqual(views.count, 1)
        let backdrops = try XCTUnwrap(views.first).subviews.filter { $0.layer.filters?.isEmpty == false }
        XCTAssertFalse(backdrops.isEmpty, "the backdrop of the blur is there")
        for sub in backdrops {
            let names = (sub.layer.filters ?? []).compactMap { ($0 as AnyObject).value(forKey: "name") as? String }
            XCTAssertEqual(names, ["gaussianBlur"], "no luminance curve and no saturation boost over the blur")
        }
        for sub in views[0].subviews where sub.layer.filters?.isEmpty != false {
            XCTAssertTrue(sub.isHidden, "no tint layer over the blur")
        }
    }
}
#endif
