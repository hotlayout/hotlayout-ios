import SwiftUI
import XCTest

@testable import HotLayout

/// The wide places of the adaptive table (schema 9.18, step 2): where the bar of navigation stands,
/// the items at the top, the zones with the bar at the top, a sheet that becomes a window. The rows
/// run through the rules and, where they are about geometry, through the real layouts.
@MainActor
final class AdaptiveWideCasesTests: XCTestCase {
    static var table: JSONValue { AdaptiveCasesTests.table }
    static func rows(_ group: String) -> [JSONObject] { AdaptiveCasesTests.rows(group) }
    static func name(_ row: JSONObject) -> String { AdaptiveCasesTests.name(row) }
    static func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }

    static var defaults: JSONObject { table["wideDefaults"]?.objectValue ?? JSONObject() }

    static var navMetrics: WideChrome.NavMetrics {
        let nav = defaults["nav"]?.objectValue ?? JSONObject()
        return WideChrome.NavMetrics(paddingInline: number(nav["paddingInline"]), iconWidth: number(nav["iconWidth"]), gap: number(nav["gap"]), between: number(nav["between"]))
    }

    // MARK: Who stands where

    func testChromeCases() {
        for row in Self.rows("chromeCases") {
            let widthClass = AdaptiveCasesTests.widthClass(row["widthClass"])
            let scope = AdaptiveCasesTests.met(row["met"])
            let children = (row["children"]?.arrayValue ?? []).map { AdaptiveCasesTests.node($0) }
            let chrome = WideChrome.screenChrome(children, widthClass: widthClass, isShown: { WidthRules.isShown($0, widthClass, scope: scope) })
            func id(_ node: DocumentNode?) -> JSONValue { node.map { .string($0.id) } ?? .null }
            let expect = row["expect"]
            XCTAssertEqual(chrome.navPlace.map { JSONValue.string($0.rawValue) } ?? .null, expect?["navPlace"], Self.name(row))
            XCTAssertEqual(id(chrome.zones.appBar), expect?["appBar"], Self.name(row))
            XCTAssertEqual(id(chrome.zones.pinned), expect?["pinned"], Self.name(row))
            XCTAssertEqual(id(chrome.zones.navBar), expect?["navBar"], Self.name(row))
            XCTAssertEqual(chrome.zones.body.map { JSONValue.string($0.id) }, expect?["body"]?.arrayValue, Self.name(row))
            // A bar shown on other classes is drawn nowhere here.
            if let navShown = expect?["navShown"]?.boolValue, let nav = chrome.zones.navBar {
                XCTAssertEqual(WidthRules.isShown(nav, widthClass, scope: scope), navShown, Self.name(row))
            }
            // The editor keeps the hidden app bar a bar; a reader that knows the data does not.
            if let editor = expect?["editor"]?.stringValue {
                let editing = WideChrome.screenChrome(children, widthClass: widthClass)
                XCTAssertEqual(editing.navPlace?.rawValue, editor, Self.name(row))
            }
        }
    }

    /// The owner of the top zone follows the place of the bar: only an own bar at the top is the owner.
    func testTopZoneOwnerFollowsThePlace() {
        let scope: DataScope = [:]
        for row in Self.rows("chromeCases") {
            let widthClass = AdaptiveCasesTests.widthClass(row["widthClass"])
            let children = (row["children"]?.arrayValue ?? []).map { AdaptiveCasesTests.node($0) }
            let chrome = WideChrome.screenChrome(children, widthClass: widthClass, isShown: { WidthRules.isShown($0, widthClass, scope: scope) })
            let barShown = chrome.zones.appBar.map { WidthRules.isShown($0, widthClass, scope: scope) } ?? false
            let owner = ScreenAnatomy.topZoneOwner(navBar: chrome.navPlace == .top, appBar: barShown)
            XCTAssertEqual(owner == .navBar, chrome.navPlace == .top, Self.name(row))
        }
    }

    // MARK: Items at the top

    func testNavItemAndHeightCases() {
        for row in Self.rows("wideNavItemCases") {
            let mode = WideChrome.NavMode(rawValue: row["mode"]?.stringValue ?? "labels") ?? .labels
            XCTAssertEqual(WideChrome.navItemWidth(labelWidth: Self.number(row["labelWidth"]), Self.navMetrics, mode), Self.number(row["expect"]), Self.name(row))
        }
        for row in Self.rows("wideNavHeightCases") {
            let item = WideChrome.navItemHeight(paddingBlock: Self.number(row["paddingBlock"]), iconBox: Self.number(row["iconBox"]), labelLine: Self.number(row["labelLine"]))
            let bar = WideChrome.navBarHeight(paddingBlock: Self.number(row["paddingBlock"]), iconBox: Self.number(row["iconBox"]), labelLine: Self.number(row["labelLine"]), borderBottom: Self.number(row["borderBottom"]))
            XCTAssertEqual(item, Self.number(row["expect"]?["item"]), Self.name(row))
            XCTAssertEqual(bar, Self.number(row["expect"]?["bar"]), Self.name(row))
        }
    }

    /// The numbers of the table are the numbers of the default theme: the reader reads them from the theme.
    func testDefaultsAreTheThemeOfTheReader() {
        let theme = HotlayoutThemeSet.builtIn.theme(nil)
        let metrics = WideChrome.metrics(theme: theme)
        XCTAssertEqual(metrics, Self.navMetrics)
        let bar = Self.defaults["bar"]?.objectValue ?? JSONObject()
        XCTAssertEqual(theme.spacing[AppBarRules.gapToken], Self.number(bar["gap"]))
        XCTAssertEqual(theme.spacing[AppBarRules.actionGapToken], Self.number(bar["actionGap"]))
        XCTAssertEqual(theme.spacing[AppBarRules.backSideToken], Self.number(bar["backSide"]))
        XCTAssertEqual(theme.spacing["xl"], Self.number(Self.defaults["modalMargin"]))
        XCTAssertEqual(WideChrome.labelMax, Self.number(Self.schema("wideNav.item.labelMaxWidth")))
        XCTAssertEqual(WideChrome.titleKeeps, Self.number(Self.schema("wideNav.overflow.titleKeeps")))
        XCTAssertEqual(WideChrome.windowMaxWidth, Self.number(Self.schema("wideModal.window.maxWidth")))
        XCTAssertEqual(WideChrome.windowMaxHeightShare, Self.number(Self.schema("wideModal.window.maxHeightShare")))
    }

    static func schema(_ dotted: String) -> JSONValue? {
        var value = ScreenAnatomyCasesTests.schema["x-style"]?["layout"]
        for key in dotted.split(separator: ".") { value = value?[String(key)] }
        return value
    }

    static func appBarInput(_ row: JSONObject, width: Double) -> WideChrome.WideAppBarInput {
        let bar = row["bar"]?.objectValue ?? JSONObject()
        let defaults = Self.defaults["bar"]?.objectValue ?? JSONObject()
        return WideChrome.WideAppBarInput(
            bar: AppBarRules.ZonesInput(
                width: width, showBack: bar["showBack"]?.boolValue == true, backSide: number(defaults["backSide"]),
                actionSides: (bar["actionSides"]?.arrayValue ?? []).compactMap(\.numberValue), gap: number(defaults["gap"]), actionGap: number(defaults["actionGap"]),
                titleNatural: number(bar["titleNatural"]), leadingNatural: bar["leadingNatural"]?.numberValue, titleAlign: bar["titleAlign"]
            ),
            navLabels: (row["labels"]?.arrayValue ?? []).compactMap(\.numberValue), nav: navMetrics
        )
    }

    /// The box of the content of the app bar on the screen: from the left edge.
    static func barBox(_ row: JSONObject) -> WidthRules.InlineRect {
        let padding = row["padding"]?.objectValue ?? JSONObject()
        return WidthRules.contentRects(
            width: number(row["width"]), paddingStart: number(padding["start"]), paddingEnd: number(padding["end"]),
            maxWidth: WidthRules.contentMaxWidth(row["contentMaxWidth"]), rightToLeft: row["rtl"]?.boolValue == true
        ).appBar
    }

    /// A part of the row from its start in reading order, as a rectangle from the left edge of the screen.
    static func fromLeft(_ box: WidthRules.InlineRect, start: Double, width: Double, rtl: Bool) -> JSONValue {
        .object(JSONObject([("x", .number(rtl ? box.x + box.width - start - width : box.x + start)), ("width", .number(width))]))
    }

    func testAppBarWithNavItemsCases() {
        for row in Self.rows("wideAppBarCases") {
            let rtl = row["rtl"]?.boolValue == true
            let box = Self.barBox(row)
            let input = Self.appBarInput(row, width: box.width)
            let result = WideChrome.appBarZones(input)
            let zones = result.zones
            func rect(_ start: Double, _ width: Double) -> JSONValue { Self.fromLeft(box, start: start, width: width, rtl: rtl) }
            let actual: JSONValue = .object(JSONObject([
                ("mode", .string(result.navMode.rawValue)), ("clipped", .bool(result.clipped)), ("truncated", .bool(zones.truncated)), ("centered", .bool(zones.centered)),
                ("leading", zones.leadingShown == .none ? .null : rect(0, zones.leadingWidth)),
                ("title", rect(zones.titleStart, zones.titleWidth)),
                ("items", .array(result.navItemStarts.indices.map { rect(result.navItemStarts[$0], result.navItemWidths[$0]) })),
                ("actions", .array(zones.actionStarts.indices.map { rect(zones.actionStarts[$0], input.bar.actionSides[$0]) })),
            ]))
            XCTAssertEqual(actual, row["expect"], Self.name(row))
        }
    }

    /// Without items the bar is exactly the bar of before the wide places.
    func testBarWithoutItemsIsTheOldBar() {
        for row in Self.rows("wideAppBarCases") {
            let input = Self.appBarInput(row, width: Self.barBox(row).width)
            var bare = input
            bare.navLabels = []
            let plain = AppBarRules.zones(input.bar)
            let wide = WideChrome.appBarZones(bare)
            XCTAssertEqual(wide.zones, plain, Self.name(row))
            XCTAssertFalse(wide.clipped && plain.leading + plain.trailing <= input.bar.width, Self.name(row))
        }
    }

    func testOwnBarCases() {
        for row in Self.rows("wideNavBarCases") {
            let rtl = row["rtl"]?.boolValue == true
            let width = Self.number(row["width"])
            let inset = row["navBarInset"]?.objectValue ?? JSONObject()
            let rects = WidthRules.contentRects(
                width: width, paddingStart: 0, paddingEnd: 0, maxWidth: WidthRules.contentMaxWidth(row["contentMaxWidth"]),
                navBarInset: (Self.number(inset["start"]), Self.number(inset["end"])), rightToLeft: rtl
            )
            let box = rects.navBar
            let labels = (row["labels"]?.arrayValue ?? []).compactMap(\.numberValue)
            let result = WideChrome.navBar(width: box.width, labels: labels, Self.navMetrics)
            let actual: JSONValue = .object(JSONObject([
                ("mode", .string(result.navMode.rawValue)), ("clipped", .bool(result.clipped)),
                ("items", .array(result.navItemStarts.indices.map { Self.fromLeft(box, start: result.navItemStarts[$0], width: result.navItemWidths[$0], rtl: rtl) })),
            ]))
            XCTAssertEqual(actual, row["expect"], Self.name(row))
        }
    }

    // MARK: Zones

    static func zoneChildren(_ row: JSONObject) -> [DocumentNode] {
        let has = row["has"]?.objectValue ?? JSONObject()
        var nodes: [JSONValue] = []
        if has["appBar"]?.boolValue == true { nodes.append(.object(JSONObject([("id", "bar"), ("type", "AppBar")]))) }
        nodes.append(.object(JSONObject([("id", "list"), ("type", "Column")])))
        if has["pinned"]?.boolValue == true { nodes.append(.object(JSONObject([("id", "cta"), ("type", "Button"), ("pin", "bottom")]))) }
        if has["navBar"]?.boolValue == true {
            var props = JSONObject()
            if let place = row["widePlacement"] { props["widePlacement"] = place }
            nodes.append(.object(JSONObject([("id", "nav"), ("type", "NavBar"), ("props", .object(props))])))
        }
        return nodes.map { AdaptiveCasesTests.node($0) }
    }

    static func zoneInput(_ row: JSONObject, navPlace: NavPlace?) -> (input: AnatomyInput, navHeight: Double?) {
        let zone = defaults["zone"]?.objectValue ?? JSONObject()
        let has = row["has"]?.objectValue ?? JSONObject()
        let padding = zone["padding"]?.objectValue ?? JSONObject()
        let body = row["bodyContentHeight"]
        let bodyHeight: Double? = body == .null ? nil : (body?.numberValue ?? number(zone["bodyContentHeight"]))
        let pinned = has["pinned"]?.boolValue == true ? number(zone["pinnedHeight"]) : nil
        let navHeight = navPlace == .bottom ? number(zone["navBarBottomHeight"]) : navPlace == .top ? number(zone["navBarTopHeight"]) : nil
        let input = AnatomyInput(
            height: number(zone["height"]), appBarHeight: has["appBar"]?.boolValue == true ? number(zone["appBarHeight"]) : nil,
            paddingTop: number(padding["top"]), paddingBottom: number(padding["bottom"]), gap: number(zone["gap"]),
            bodyContentHeight: bodyHeight, scrollTop: row["scrollTop"]?.numberValue,
            bottom: BottomZoneInput(pinnedHeight: pinned, navBarHeight: nil, safeBottom: number(zone["safeBottom"]))
        )
        return (input, navHeight)
    }

    func testWideZoneCases() {
        for row in Self.rows("wideZoneCases") {
            let widthClass = AdaptiveCasesTests.widthClass(row["widthClass"])
            let chrome = WideChrome.screenChrome(Self.zoneChildren(row), widthClass: widthClass)
            let (input, navHeight) = Self.zoneInput(row, navPlace: chrome.navPlace)
            let result = WideChrome.zones(input, navPlace: chrome.navPlace, navBarHeight: navHeight)
            var actual = ScreenAnatomyCasesTests.json(result.zones)
            guard var object = actual.objectValue else { return XCTFail(Self.name(row)) }
            object["navPlace"] = chrome.navPlace.map { .string($0.rawValue) } ?? .null
            object["topNav"] = result.topNav.map { .object(JSONObject([("top", .number($0.top)), ("height", .number($0.height))])) } ?? .null
            if let appBar = result.zones.appBar { object["appBar"] = .object(JSONObject([("top", .number(appBar.top)), ("height", .number(appBar.height))])) }
            actual = .object(object)
            ScreenAnatomyCasesTests.assertSubset(actual, row["expect"] ?? .null, Self.name(row))
            XCTAssertEqual(result.zones.height, Self.number(Self.defaults["zone"]?["height"]), Self.name(row))
        }
    }

    /// A place at the bottom and a screen without a bar are exactly the zones of before: the numbers do not change.
    func testBottomPlaceIsTheOldZones() {
        for row in Self.rows("wideZoneCases") where ["bottom", nil].contains(row["expect"]?["navPlace"]?.stringValue) {
            let place: NavPlace? = row["expect"]?["navPlace"]?.stringValue.flatMap(NavPlace.init(rawValue:))
            let (input, navHeight) = Self.zoneInput(row, navPlace: place)
            var old = input
            let pinned = old.bottom?.pinnedHeight
            old.bottom = pinned == nil && navHeight == nil ? nil : BottomZoneInput(pinnedHeight: pinned, navBarHeight: navHeight, safeBottom: input.bottom?.safeBottom)
            XCTAssertEqual(WideChrome.zones(input, navPlace: place, navBarHeight: navHeight).zones, ScreenAnatomy.zones(old), Self.name(row))
        }
    }

    // MARK: Modal layer

    func testWideModalCases() {
        let margin = Self.number(Self.defaults["modalMargin"])
        for row in Self.rows("wideModalCases") {
            let viewport = row["viewport"]?.objectValue ?? JSONObject()
            let layer = WideChrome.modalLayerBox(
                placement: row["placement"], width: Self.number(viewport["width"]), height: Self.number(viewport["height"]),
                contentHeight: Self.number(row["contentHeight"]), margin: margin
            )
            let actual: JSONValue = .object(JSONObject([
                ("shape", .string(layer.shape.rawValue)), ("x", .number(layer.box.x)), ("y", .number(layer.box.y)), ("width", .number(layer.box.width)),
                ("height", .number(layer.box.height)), ("scrolls", .bool(layer.box.scrolls)), ("contentWidthClass", .string(layer.contentWidthClass.rawValue)),
            ]))
            ScreenAnatomyCasesTests.assertSubset(actual, row["expect"] ?? .null, Self.name(row))
            XCTAssertEqual(
                WideChrome.modalLayerWidth(placement: row["placement"], areaWidth: Self.number(viewport["width"]), margin: margin), layer.box.width, accuracy: 1e-9, Self.name(row))
        }
    }

    func testWideModalRadiusCases() {
        for row in Self.rows("wideModalRadiusCases") {
            XCTAssertEqual(WideChrome.sheetWindowRadius(row["radius"]) ?? .null, row["expect"] ?? .null, Self.name(row))
        }
    }

    func testWideModalContentCases() {
        for row in Self.rows("wideModalContentCases") {
            let presentation: ScreenPresentation = row["presentation"]?.stringValue == "modal" ? .modal : .page
            let area = WidthClass.of(width: Self.number(row["areaWidth"]))
            XCTAssertEqual(area.rawValue, row["areaClass"]?.stringValue, Self.name(row))
            let expect = row["expect"]
            XCTAssertEqual(WideChrome.contentWidthClass(presentation: presentation, area: area).rawValue, expect?["contentWidthClass"]?.stringValue, Self.name(row))
            XCTAssertEqual(presentation == .modal, expect?["alwaysCompact"]?.boolValue, Self.name(row))
        }
    }

    // MARK: Data of the artifact

    func testWideRuleCases() {
        for row in Self.rows("wideRuleCases") {
            XCTAssertEqual(Self.schema(row["rule"]?.stringValue ?? ""), row["expect"], Self.name(row))
        }
        let wide = Self.schema("wideNav")
        XCTAssertEqual(wide?["values"]?.arrayValue?.compactMap(\.stringValue), ["top", "bottom"])
        XCTAssertEqual(wide?["classes"]?.arrayValue?.compactMap(\.stringValue), WidthClass.allCases.filter(\.isWide).map(\.rawValue))
        XCTAssertEqual(wide?["default"]?.stringValue, "top")
    }

    func testPlacementWords() {
        XCTAssertTrue(WideChrome.keepsBottom(["widePlacement": "bottom"]))
        for props in [JSONObject(), ["widePlacement": "top"], ["widePlacement": "side"], ["widePlacement": 3], ["widePlacement": .null]] as [JSONObject] {
            XCTAssertFalse(WideChrome.keepsBottom(props))
        }
    }
}
