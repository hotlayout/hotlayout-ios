import XCTest

@testable import HotLayout

/// JSON has no integer type: `1e300` is a finite `Double`, so it passes `numberValue`, and it
/// equals its own `rounded()`. Several rule functions then feed such a value straight into
/// `Int(_:)`, whose argument must be within the representable range of `Int` or the conversion
/// is a fatal error that ends the whole process, not just the one screen. A document or a theme
/// comes over the network, so the number is attacker-chosen.
///
/// Each test here asserts the SAFE result (the value is out of range, so the field is ignored).
/// Without the fix the conversion is a fatal error that aborts the whole test process.
///
/// `huge` is built at run time so the optimizer cannot fold the conversion while compiling.
@MainActor
final class NumberTrapAdversarialTests: XCTestCase {
    private var huge: Double { Double(ProcessInfo.processInfo.arguments.count) * 1e300 }

    /// `ProgressBar.segments` (the widget is drawn): the guard is `isFinite` and `== rounded()`,
    /// then `segmentsRange.contains(Int(number))` converts before the range is checked.
    func testProgressSegments() {
        XCTAssertNil(ProgressRules.segmentsCount(.number(huge)), "a segments count out of Int range is the continuous bar")
    }

    /// `ListTile.titleMaxLines` / `subtitleMaxLines` (the widget is drawn):
    /// `linesRange.contains(Int(number))` converts before the range check.
    func testListTileLineLimit() {
        XCTAssertNil(ListTileRules.lineLimit(.number(huge)), "a line limit out of Int range means no limit")
    }

    /// `Row.carousel.perView` (the carousel is drawn): `perViewRange.contains(Int(number))`
    /// converts before the range check.
    func testCarouselPerView() {
        XCTAssertNil(CarouselRules.read(.object(["perView": .number(huge)]))?.perView, "a perView out of Int range is not read")
    }

    /// `node.layer.rotate` (layers are drawn): `rotateRange.contains(Int(number))` converts before
    /// the range check.
    func testLayerRotate() {
        XCTAssertEqual(LayerRead.read(.object(["rotate": .number(huge)]))?.rotate, 0, "a rotation out of Int range is no rotation")
    }

    /// A theme is network input too. `ThemeReader.readTheme` does `Int(fontWeight.numberValue ?? 400)`
    /// with no range check at all.
    func testThemeFontWeight() {
        let json: JSONValue = .object([
            "themeContractVersion": .string(HotlayoutVersions.theme), "defaultThemeId": "t",
            "themes": .object(["t": .object([
                "brightness": "light",
                "typography": .object(["bodyM": .object(["fontSize": 14, "lineHeight": 1.4, "fontWeight": .number(huge)])]),
            ])]),
        ])
        let set = HotlayoutThemeSet.read(json)
        XCTAssertNotNil(set, "a theme with an out-of-range font weight is still read, with a safe weight")
        let weight = set?.theme("t").typography["bodyM"]?.fontWeight ?? 0
        XCTAssertTrue((100...900).contains(weight), "the weight is held to the schema range, got \(weight)")
    }
}

/// Values next to the hostile ones that the rules handle correctly: these do not convert an
/// out-of-range number, so they run and pass in the ordinary suite.
@MainActor
final class NumberTrapGuardTests: XCTestCase {
    func testProgressSegmentsAdjacentValues() {
        XCTAssertEqual(ProgressRules.segmentsCount(.number(6)), 6)
        XCTAssertNil(ProgressRules.segmentsCount(.number(1)), "below the range")
        XCTAssertNil(ProgressRules.segmentsCount(.number(13)), "above the range")
        XCTAssertNil(ProgressRules.segmentsCount(.number(4.5)), "a fraction")
        XCTAssertNil(ProgressRules.segmentsCount(.string("6")), "a string")
    }

    func testListTileLineLimitAdjacentValues() {
        XCTAssertEqual(ListTileRules.lineLimit(.number(3)), 3)
        XCTAssertNil(ListTileRules.lineLimit(.number(0)))
        XCTAssertNil(ListTileRules.lineLimit(.number(6)))
        XCTAssertNil(ListTileRules.lineLimit(.number(1.5)))
    }

    func testCarouselPerViewAdjacentValues() {
        XCTAssertEqual(CarouselRules.read(.object(["perView": .number(2)]))?.perView, 2)
        XCTAssertNil(CarouselRules.read(.object(["perView": .number(2.5)]))?.perView, "a fraction is not read")
    }

    func testLayerRotateAdjacentValues() {
        XCTAssertEqual(LayerRead.read(.object(["rotate": .number(90)]))?.rotate, 90)
        XCTAssertEqual(LayerRead.read(.object(["rotate": .number(200)]))?.rotate, 0, "out of the degree range")
    }

    func testThemeFontWeightAdjacentValue() {
        let json: JSONValue = .object([
            "themeContractVersion": .string(HotlayoutVersions.theme), "defaultThemeId": "t",
            "themes": .object(["t": .object([
                "brightness": "light",
                "typography": .object(["bodyM": .object(["fontSize": 14, "lineHeight": 1.4, "fontWeight": 600])]),
            ])]),
        ])
        XCTAssertEqual(HotlayoutThemeSet.read(json)?.theme("t").typography["bodyM"]?.fontWeight, 600)
    }
}

/// Every other conversion of a document, theme or data number to an integer, with hostile values
/// (out of range, infinite, NaN) that would end the process in an unchecked `Int(_:)`.
@MainActor
final class NumberConversionSweepTests: XCTestCase {
    private var huge: Double { Double(ProcessInfo.processInfo.arguments.count) * 1e300 }

    func testSafeIntHelper() {
        XCTAssertNil(SafeInt.exactly(huge))
        XCTAssertNil(SafeInt.exactly(.infinity))
        XCTAssertNil(SafeInt.exactly(.nan))
        XCTAssertNil(SafeInt.exactly(1.5))
        XCTAssertEqual(SafeInt.exactly(-3), -3)
        XCTAssertEqual(SafeInt.clamped(huge), 1 << 53)
        XCTAssertEqual(SafeInt.clamped(-huge), -(1 << 53))
        XCTAssertEqual(SafeInt.clamped(.nan), 0)
    }

    func testRepeaterLimitAndGridColumns() {
        XCTAssertEqual(RepeaterPlan.limit(["limit": .number(huge)]), RepeaterPlan.maxItems)
        XCTAssertEqual(RepeaterPlan.limit(["limit": .number(-huge)]), 1)
        XCTAssertEqual(gridColumns(.number(huge), overridden: false), 4)
        XCTAssertEqual(gridColumns(.number(-huge)), 1)
    }

    func testNumericFieldTextOfAHugeNumber() {
        XCTAssertEqual(InputRules.numberText(.number(huge)), "")
        XCTAssertEqual(InputRules.numberText(.number(-huge)), "")
    }

    func testLayerOffsetPixelsOutOfRange() {
        XCTAssertNotNil(LayerRead.read(.object(["offset": .object(["x": .number(huge), "y": .number(-huge)])])))
    }

    func testFilledSegmentsOfHostileRatio() {
        XCTAssertEqual(ProgressRules.filledSegments(ratio: .nan, segments: 6), 0)
        XCTAssertEqual(ProgressRules.filledSegments(ratio: huge, segments: 6), 6)
    }

    func testProgressLabelOfHostileRatio() {
        XCTAssertNotNil(ProgressRules.labelText(format: "percent", value: huge, max: huge, ratio: .nan))
        XCTAssertNotNil(ProgressRules.labelText(format: "percent", value: 1, max: 1, ratio: huge))
    }

    func testDashedBorderWithATinyBorder() {
        let line = DashedBorderRules.line(.init(width: 1e9, height: 1e9, border: 1e-300, radii: .init()))
        XCTAssertLessThanOrEqual(line.count, 100_000)
    }
}
