import SwiftUI
import XCTest

@testable import HotLayout

/// The rows of the zone tables through the REAL layout of a screen: children of the sizes the
/// table names stand where the table says, and the layout is as tall as the table says.
@MainActor
final class ScreenAnatomyLayoutTests: XCTestCase {
    struct Frames: PreferenceKey {
        static let defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
    }

    final class Box { var frames: [Int: CGRect] = [:] }

    static let order: [ScreenZone] = [.bar, .top, .body, .pinned, .nav]

    static func tag(_ view: some View, _ zone: ScreenZone) -> some View {
        view.layoutValue(key: ScreenZoneKey.self, value: zone)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: Frames.self, value: [order.firstIndex(of: zone) ?? 0: proxy.frame(in: .named("screen"))])
            })
    }

    struct Probe {
        var size: CGSize
        var frames: [ScreenZone: CGRect]
    }

    /// Draws the zones of a settings value with children of the given sizes.
    static func measure(
        settings: ScreenZonesSettings, width: Double, height: Double?, bar: Double? = nil, top: Double? = nil, bodyNatural: Double? = nil,
        pinned: Double? = nil, nav: Double? = nil, rightToLeft: Bool = false
    ) -> Probe? {
        let box = Box()
        let bodyIdeal = bodyNatural.map { CGFloat($0) }
        let content = ScreenZonesLayout(settings: settings) {
            if let bar { tag(Color.red.frame(height: CGFloat(bar)), .bar) }
            if let top { tag(Color.green.frame(height: CGFloat(top)), .top) }
            tag(Color.clear.frame(idealHeight: bodyIdeal), .body)
            if let pinned { tag(Color.blue.frame(height: CGFloat(pinned)), .pinned) }
            if let nav { tag(Color.orange.frame(height: CGFloat(nav)), .nav) }
        }
        .background(GeometryReader { proxy in Color.clear.preference(key: Frames.self, value: [99: proxy.frame(in: .named("screen"))]) })
        .frame(width: CGFloat(width), height: height.map { CGFloat($0) }, alignment: .top)
        .coordinateSpace(name: "screen")
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        .onPreferenceChange(Frames.self) { box.frames = $0 }
        let renderer = ImageRenderer(content: content)
        guard renderer.cgImage != nil else { return nil }
        var frames: [ScreenZone: CGRect] = [:]
        for (index, zone) in order.enumerated() { if let frame = box.frames[index] { frames[zone] = frame } }
        return Probe(size: box.frames[99]?.size ?? .zero, frames: frames)
    }

    static func settings(_ row: JSONObject) -> ScreenZonesSettings {
        let padding = row["padding"]?.objectValue ?? JSONObject()
        let bottom = row["bottom"]?.objectValue
        var settings = ScreenZonesSettings()
        settings.shrink = row["shrink"]?.boolValue == true
        settings.paddingTop = ScreenAnatomyCasesTests.number(padding["top"])
        settings.paddingBottom = ScreenAnatomyCasesTests.number(padding["bottom"])
        settings.gap = ScreenAnatomyCasesTests.number(row["gap"])
        settings.bodyEmpty = row["bodyContentHeight"]?.numberValue == nil
        settings.firstPull = ScreenAnatomyCasesTests.number(row["firstPull"])
        settings.bodyTop = row["bodyTop"]
        settings.safeTop = ScreenAnatomyCasesTests.number(row["safeTop"])
        settings.safeBottom = ScreenAnatomyCasesTests.number(bottom?["safeBottom"])
        settings.navFloat = row["navFloat"]?.boolValue == true && bottom?["navBarHeight"] != nil
        return settings
    }

    func testZoneRowsThroughTheLayout() throws {
        var rows: [JSONObject] = []
        rows += Contract.rows(ScreenAnatomyCasesTests.chrome, "zoneCases")
        rows += Contract.rows(ScreenAnatomyCasesTests.bottom, "zoneCases")
        rows += Contract.rows(ScreenAnatomyCasesTests.bottom, "floatZoneCases")
        rows += Contract.rows(ScreenAnatomyCasesTests.chrome, "screenTopZoneCases")
        var drawn = 0
        for row in rows {
            let name = ScreenAnatomyCasesTests.name(row)
            let expect = row["expect"] ?? .null
            let settings = Self.settings(row)
            let safeTop = ScreenAnatomy.safeTop(settings.safeTop, screenHeight: ScreenAnatomyCasesTests.number(row["height"]))
            let bottom = row["bottom"]?.objectValue
            let nav = bottom?["navBarHeight"]?.numberValue
            let bar = row["appBarHeight"]?.numberValue.map { $0 + safeTop }
            // Without an app bar the inset lies above the whole screen: the layout does that by itself.
            let natural = settings.shrink ? expect["contentHeight"]?.numberValue : nil
            let probe = Self.measure(
                settings: settings, width: 320, height: ScreenAnatomyCasesTests.number(row["height"]), bar: bar, bodyNatural: natural,
                pinned: bottom?["pinnedHeight"]?.numberValue, nav: nav.map { settings.navFloat ? $0 : $0 + settings.safeBottom }
            )
            let result = try XCTUnwrap(probe, name)
            drawn += 1
            func close(_ a: CGFloat?, _ b: Double?, _ what: String) {
                guard let a, let b else { return XCTAssertEqual(a == nil, b == nil, "\(name): \(what)") }
                XCTAssertEqual(Double(a), b, accuracy: 0.01, "\(name): \(what)")
            }
            close(result.size.height, expect["height"]?.numberValue, "height")
            if let appBar = expect["appBar"], !appBar.isNull {
                close(result.frames[.bar]?.minY, appBar["top"]?.numberValue, "bar top")
                close(result.frames[.bar]?.height, appBar["height"]?.numberValue, "bar height")
            }
            if let area = expect["body"] {
                close(result.frames[.body]?.minY, area["top"]?.numberValue, "body top")
                close(result.frames[.body]?.height, area["height"]?.numberValue, "body height")
            }
            if let zone = expect["bottom"], !zone.isNull {
                if let pinned = zone["pinned"], !pinned.isNull {
                    close(result.frames[.pinned]?.minY, pinned["top"]?.numberValue, "pinned top")
                    close(result.frames[.pinned]?.height, pinned["height"]?.numberValue, "pinned height")
                }
                if let navBar = zone["navBar"], !navBar.isNull {
                    close(result.frames[.nav]?.minY, navBar["top"]?.numberValue, "nav top")
                    close(result.frames[.nav]?.height, navBar["height"]?.numberValue, "nav height")
                }
            }
        }
        XCTAssertEqual(drawn, rows.count)
    }

    /// The root padding is shared: the bar and the pinned block stand inside the side padding, the
    /// body and the bar of navigation take the whole width; right-to-left text mirrors it.
    func testSidePaddingsAreShared() throws {
        var settings = ScreenZonesSettings()
        settings.paddingStart = 16
        settings.paddingEnd = 24
        settings.paddingTop = 8
        settings.paddingBottom = 8
        settings.gap = 12
        for rtl in [false, true] {
            let probe = try XCTUnwrap(Self.measure(settings: settings, width: 400, height: 800, bar: 40, bodyNatural: nil, pinned: 50, nav: 60, rightToLeft: rtl))
            let bar = try XCTUnwrap(probe.frames[.bar])
            XCTAssertEqual(bar.width, 360)
            XCTAssertEqual(bar.minX, rtl ? 24 : 16, "bar, rtl \(rtl)")
            XCTAssertEqual(probe.frames[.pinned]?.width, 360)
            XCTAssertEqual(probe.frames[.pinned]?.minX, rtl ? 24 : 16)
            XCTAssertEqual(probe.frames[.body]?.width, 400)
            XCTAssertEqual(probe.frames[.nav]?.width, 400)
            XCTAssertEqual(probe.frames[.nav]?.minX, 0)
        }
    }

    /// The top zone stands under the bar; the body starts under the zone and its lead is inside the scroll.
    func testTopZoneStandsUnderTheBar() throws {
        var settings = ScreenZonesSettings()
        settings.paddingTop = 8
        settings.gap = 20
        let probe = try XCTUnwrap(Self.measure(settings: settings, width: 320, height: 600, bar: 56, top: 68, bodyNatural: nil))
        XCTAssertEqual(probe.frames[.bar]?.minY, 8)
        XCTAssertEqual(probe.frames[.top]?.minY, 64)
        XCTAssertEqual(probe.frames[.body]?.minY, 64 + 68)
        XCTAssertEqual(probe.frames[.body]?.height, 600 - 64 - 68)
    }

    /// The keyboard raises the pinned block over itself and leaves the bar of navigation under it.
    func testKeyboardRaisesThePinnedBlockOnly() throws {
        var settings = ScreenZonesSettings()
        settings.paddingBottom = 16
        settings.keyboard = 300
        let probe = try XCTUnwrap(Self.measure(settings: settings, width: 320, height: 800, pinned: 48, nav: 60))
        // The pinned block ends at the top edge of the keyboard (padding under it included).
        XCTAssertEqual(try XCTUnwrap(probe.frames[.pinned]).maxY + 16, 800 - 300, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(probe.frames[.nav]).minY, 800 - 300, accuracy: 0.01)
        XCTAssertEqual(ScreenAnatomy.keyboardLift(keyboard: 300, navBarHeight: 60), 240)
        XCTAssertEqual(ScreenAnatomy.keyboardLift(keyboard: 40, navBarHeight: 60), 0)
    }
}
