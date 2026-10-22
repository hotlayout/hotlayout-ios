import CoreGraphics
import XCTest

@testable import HotLayout

/// The choice of the glass material: the brightness of a band around the glass, with a margin
/// against flicker, and the theme only until the screen has been read.
final class GlassMaterialRulesTests: XCTestCase {
    func testThemeStandsInUntilThePictureIsRead() {
        XCTAssertTrue(GlassBlur.darkMaterial(lightUnder: nil, darkTheme: true))
        XCTAssertFalse(GlassBlur.darkMaterial(lightUnder: nil, darkTheme: false))
        // A light picture under glass on a dark theme takes the light material, and the reverse.
        XCTAssertFalse(GlassBlur.darkMaterial(lightUnder: true, darkTheme: true))
        XCTAssertTrue(GlassBlur.darkMaterial(lightUnder: false, darkTheme: false))
    }

    func testBrightnessHasAMarginAgainstFlicker() {
        XCTAssertTrue(GlassBlur.isLight(luma: 0.63, was: false))
        XCTAssertFalse(GlassBlur.isLight(luma: 0.05, was: true))
        XCTAssertTrue(GlassBlur.isLight(luma: 0.48, was: true))
        XCTAssertFalse(GlassBlur.isLight(luma: 0.52, was: false))
        XCTAssertTrue(GlassBlur.isLight(luma: 0.52, was: nil))
    }

    func testBandLumaSkipsTheBoxAndTransparentPixels() {
        // 4 x 4: a white box in the middle 2 x 2, a pink band, one transparent pixel.
        var rgba = [UInt8]()
        for y in 0..<4 {
            for x in 0..<4 {
                let inner = (1...2).contains(x) && (1...2).contains(y)
                if x == 0 && y == 0 { rgba += [0, 0, 0, 0] } else if inner { rgba += [255, 255, 255, 255] } else { rgba += [244, 114, 182, 255] }
            }
        }
        let luma = GlassBlur.bandLuma(rgba: rgba, width: 4, height: 4, excluding: CGRect(x: 1, y: 1, width: 2, height: 2))
        let pink = (0.299 * 244 + 0.587 * 114 + 0.114 * 182) / 255
        XCTAssertEqual(luma ?? -1, pink, accuracy: 0.0001)
        XCTAssertNil(GlassBlur.bandLuma(rgba: rgba, width: 4, height: 4, excluding: CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    func testOnlyAColourBackgroundCovers() {
        XCTAssertEqual(GlassBlur.cover(.color(RGBA(red: 1, green: 1, blue: 1, alpha: 0.1))), 0.1, accuracy: 0.0001)
        XCTAssertEqual(GlassBlur.cover(nil), 0)
    }
}
