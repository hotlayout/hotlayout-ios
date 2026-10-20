import SwiftUI
import XCTest

@testable import HotLayout

/// The wide rows of the adaptive table through the real layouts: the row of the app bar with the items,
/// the row of a bar of its own, the zones of a screen with the bar at the top, the box of a modal layer.
/// The children are stand-ins of the natural sizes the table names, so that what is measured is the
/// layout, not the font of a machine.
@MainActor
final class AdaptiveWideLayoutTests: XCTestCase {
    struct Frames: PreferenceKey {
        static let defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
    }

    final class Box { var frames: [Int: CGRect] = [:] }

    static func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }

    static func tagged<V: View>(_ view: V, _ id: Int) -> some View {
        view.background(GeometryReader { proxy in Color.clear.preference(key: Frames.self, value: [id: proxy.frame(in: .named("probe"))]) })
    }

    /// Draws the content in a frame and returns the frames of the tagged children.
    static func probe<V: View>(_ content: V, width: Double, height: Double, rightToLeft: Bool) -> [Int: CGRect] {
        let box = Box()
        let view = content
            .frame(width: CGFloat(width), height: CGFloat(height), alignment: .topLeading)
            .coordinateSpace(name: "probe")
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
            .onPreferenceChange(Frames.self) { box.frames = $0 }
        let renderer = ImageRenderer(content: view)
        _ = renderer.cgImage
        return box.frames
    }

    // MARK: The app bar with the items

    func testAppBarWithItemsThroughTheRealRow() {
        for row in AdaptiveCasesTests.rows("wideAppBarCases") {
            let rtl = row["rtl"]?.boolValue == true
            let box = AdaptiveWideCasesTests.barBox(row)
            let input = AdaptiveWideCasesTests.appBarInput(row, width: box.width)
            let bar = input.bar
            let nav = AdaptiveWideCasesTests.navMetrics
            let fixed = 2 * nav.paddingInline + nav.iconWidth + nav.gap
            let content = AppBarRowLayout(
                backSide: CGFloat(bar.backSide), gap: CGFloat(bar.gap), actionGap: CGFloat(bar.actionGap), titleAlign: bar.titleAlign, nav: nav
            ) {
                if let natural = bar.leadingNatural {
                    Self.tagged(Color.clear.frame(minWidth: 0, idealWidth: CGFloat(natural), maxWidth: .infinity, minHeight: 30, maxHeight: 30), 0)
                        .layoutValue(key: AppBarPartKey.self, value: .leadingNode)
                } else if bar.showBack {
                    Self.tagged(Color.clear.frame(width: CGFloat(bar.backSide), height: CGFloat(bar.backSide)), 0).layoutValue(key: AppBarPartKey.self, value: .back)
                }
                Self.tagged(Color.clear.frame(minWidth: 0, idealWidth: CGFloat(bar.titleNatural), maxWidth: .infinity, minHeight: 20, maxHeight: 20), 1)
                    .layoutValue(key: AppBarPartKey.self, value: .title)
                ForEach(Array(bar.actionSides.enumerated()), id: \.offset) { index, side in
                    Self.tagged(Color.clear.frame(width: CGFloat(side), height: 40), 10 + index).layoutValue(key: AppBarPartKey.self, value: .action)
                }
                ForEach(Array(input.navLabels.enumerated()), id: \.offset) { index, label in
                    Self.tagged(Color.clear.frame(minWidth: 0, idealWidth: CGFloat(fixed + label), maxWidth: .infinity, minHeight: 40, maxHeight: 40), 20 + index)
                        .layoutValue(key: AppBarPartKey.self, value: .navItem)
                }
            }
            let frames = Self.probe(content, width: box.width, height: 60, rightToLeft: rtl)
            let expect = row["expect"]
            func check(_ id: Int, _ want: JSONValue?, _ what: String) {
                guard let want, !want.isNull else { return XCTAssertNil(frames[id], "\(AdaptiveCasesTests.name(row)): \(what) is not there") }
                guard let frame = frames[id] else { return XCTFail("\(AdaptiveCasesTests.name(row)): \(what) is not placed") }
                XCTAssertEqual(Double(frame.minX) + box.x, Self.number(want["x"]), accuracy: 0.01, "\(AdaptiveCasesTests.name(row)): \(what): x")
                XCTAssertEqual(Double(frame.width), Self.number(want["width"]), accuracy: 0.01, "\(AdaptiveCasesTests.name(row)): \(what): width")
            }
            check(0, expect?["leading"], "leading")
            check(1, expect?["title"], "title")
            for (index, item) in (expect?["items"]?.arrayValue ?? []).enumerated() { check(20 + index, item, "item \(index)") }
            for (index, action) in (expect?["actions"]?.arrayValue ?? []).enumerated() { check(10 + index, action, "action \(index)") }
        }
    }

    // MARK: A bar of its own

    func testOwnBarThroughTheRealRow() {
        for row in AdaptiveCasesTests.rows("wideNavBarCases") {
            let rtl = row["rtl"]?.boolValue == true
            let inset = row["navBarInset"]?.objectValue ?? JSONObject()
            let width = Self.number(row["width"])
            let box = WidthRules.contentRects(
                width: width, paddingStart: 0, paddingEnd: 0, maxWidth: WidthRules.contentMaxWidth(row["contentMaxWidth"]),
                navBarInset: (Self.number(inset["start"]), Self.number(inset["end"])), rightToLeft: rtl
            ).navBar
            let nav = AdaptiveWideCasesTests.navMetrics
            let fixed = 2 * nav.paddingInline + nav.iconWidth + nav.gap
            let labels = (row["labels"]?.arrayValue ?? []).compactMap(\.numberValue)
            let content = WideNavRowLayout(metrics: nav) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Self.tagged(Color.clear.frame(minWidth: 0, idealWidth: CGFloat(fixed + label), maxWidth: .infinity, minHeight: 40, maxHeight: 40), index)
                }
            }
            let frames = Self.probe(content, width: box.width, height: 40, rightToLeft: rtl)
            for (index, want) in (row["expect"]?["items"]?.arrayValue ?? []).enumerated() {
                guard let frame = frames[index] else { XCTFail("\(AdaptiveCasesTests.name(row)): item \(index)"); continue }
                XCTAssertEqual(Double(frame.minX) + box.x, Self.number(want["x"]), accuracy: 0.01, "\(AdaptiveCasesTests.name(row)): item \(index): x")
                XCTAssertEqual(Double(frame.width), Self.number(want["width"]), accuracy: 0.01, "\(AdaptiveCasesTests.name(row)): item \(index): width")
            }
        }
    }

    // MARK: Zones

    func testZonesWithTheBarAtTheTopThroughTheRealLayout() {
        for row in AdaptiveCasesTests.rows("wideZoneCases") {
            let name = AdaptiveCasesTests.name(row)
            let widthClass = AdaptiveCasesTests.widthClass(row["widthClass"])
            let chrome = WideChrome.screenChrome(AdaptiveWideCasesTests.zoneChildren(row), widthClass: widthClass)
            let zone = AdaptiveWideCasesTests.defaults["zone"]?.objectValue ?? JSONObject()
            let has = row["has"]?.objectValue ?? JSONObject()
            let padding = zone["padding"]?.objectValue ?? JSONObject()
            var settings = ScreenZonesSettings()
            settings.paddingTop = Self.number(padding["top"])
            settings.paddingBottom = Self.number(padding["bottom"])
            settings.gap = Self.number(zone["gap"])
            settings.safeBottom = Self.number(zone["safeBottom"])
            settings.bodyEmpty = row["bodyContentHeight"] == .null
            let content = ScreenZonesLayout(settings: settings) {
                if has["appBar"]?.boolValue == true { Self.tagged(Color.clear.frame(height: CGFloat(Self.number(zone["appBarHeight"]))), 0).layoutValue(key: ScreenZoneKey.self, value: .bar) }
                if chrome.navPlace == .top { Self.tagged(Color.clear.frame(height: CGFloat(Self.number(zone["navBarTopHeight"]))), 1).layoutValue(key: ScreenZoneKey.self, value: .topNav) }
                Self.tagged(Color.clear, 2).layoutValue(key: ScreenZoneKey.self, value: .body)
                if has["pinned"]?.boolValue == true { Self.tagged(Color.clear.frame(height: CGFloat(Self.number(zone["pinnedHeight"]))), 3).layoutValue(key: ScreenZoneKey.self, value: .pinned) }
                if chrome.navPlace == .bottom {
                    Self.tagged(Color.clear.frame(height: CGFloat(Self.number(zone["navBarBottomHeight"]) + settings.safeBottom)), 4).layoutValue(key: ScreenZoneKey.self, value: .nav)
                }
            }
            let height = Self.number(zone["height"])
            let frames = Self.probe(content, width: 320, height: height, rightToLeft: false)
            let expect = row["expect"]
            func check(_ id: Int, _ want: JSONValue?, _ what: String) {
                guard let want, !want.isNull else { return XCTAssertNil(frames[id], "\(name): \(what) is not there") }
                guard let frame = frames[id] else { return XCTFail("\(name): \(what) is not placed") }
                XCTAssertEqual(Double(frame.minY), Self.number(want["top"]), accuracy: 0.01, "\(name): \(what): top")
                XCTAssertEqual(Double(frame.height), Self.number(want["height"]), accuracy: 0.01, "\(name): \(what): height")
            }
            check(0, expect?["appBar"], "app bar")
            check(1, expect?["topNav"], "bar at the top")
            check(2, expect?["body"], "body")
            check(3, expect?["bottom"]?["pinned"], "pinned block")
            check(4, expect?["bottom"]?["navBar"], "bar at the bottom")
        }
    }

    // MARK: Modal layer

    func testModalBoxThroughTheRealLayout() {
        let margin = Self.number(AdaptiveWideCasesTests.defaults["modalMargin"])
        for row in AdaptiveCasesTests.rows("wideModalCases") {
            let name = AdaptiveCasesTests.name(row)
            let viewport = row["viewport"]?.objectValue ?? JSONObject()
            let height = Self.number(row["contentHeight"])
            let content = ModalBoxLayout(placement: row["placement"], margin: margin) {
                Self.tagged(Color.clear.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, idealHeight: CGFloat(height), maxHeight: .infinity), 0)
            }
            let frames = Self.probe(content, width: Self.number(viewport["width"]), height: Self.number(viewport["height"]), rightToLeft: false)
            guard let frame = frames[0] else { XCTFail(name); continue }
            let want = row["expect"]
            XCTAssertEqual(Double(frame.minX), Self.number(want?["x"]), accuracy: 0.01, "\(name): x")
            XCTAssertEqual(Double(frame.minY), Self.number(want?["y"]), accuracy: 0.01, "\(name): y")
            XCTAssertEqual(Double(frame.width), Self.number(want?["width"]), accuracy: 0.01, "\(name): width")
            XCTAssertEqual(Double(frame.height), Self.number(want?["height"]), accuracy: 0.01, "\(name): height")
        }
    }
}
