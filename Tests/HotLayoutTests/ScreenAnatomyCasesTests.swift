import XCTest

@testable import HotLayout

/// The shared tables of the anatomy of a screen, as functions of the rules: the zones of the
/// screen (`media-chrome`, `bottom-zone`), the top zone (`top-zone`), the app bar, the
/// navigation bar and the dot on its items. The same rows run once more through the real
/// layout in `ScreenAnatomyLayoutTests`.
final class ScreenAnatomyCasesTests: XCTestCase {
    static let chrome = try! Contract.json("fixtures/media-chrome/media-chrome-cases.json")
    static let bottom = try! Contract.json("fixtures/bottom-zone/bottom-zone-cases.json")
    static let top = try! Contract.json("fixtures/top-zone/top-zone-cases.json")
    static let schema = try! Contract.json("screen-schema.json")

    // MARK: Helpers

    static func number(_ value: JSONValue?) -> Double { value?.numberValue ?? 0 }
    static func name(_ row: JSONObject) -> String { row["name"]?.stringValue ?? "?" }

    static func input(_ row: JSONObject) -> AnatomyInput {
        let padding = row["padding"]?.objectValue ?? JSONObject()
        let bottom = row["bottom"]?.objectValue
        return AnatomyInput(
            height: number(row["height"]), shrink: row["shrink"]?.boolValue == true, appBarHeight: row["appBarHeight"]?.numberValue,
            paddingTop: number(padding["top"]), paddingBottom: number(padding["bottom"]), gap: number(row["gap"]),
            bodyContentHeight: row["bodyContentHeight"]?.numberValue, firstPull: row["firstPull"]?.numberValue,
            scrollTop: row["scrollTop"]?.numberValue,
            bottom: bottom.map { BottomZoneInput(pinnedHeight: $0["pinnedHeight"]?.numberValue, navBarHeight: $0["navBarHeight"]?.numberValue, safeBottom: $0["safeBottom"]?.numberValue) },
            navFloat: row["navFloat"]?.boolValue == true, bodyTop: row["bodyTop"], safeTop: row["safeTop"]?.numberValue
        )
    }

    /// The zones as JSON, in the shape of the table.
    static func json(_ zones: AnatomyZones) -> JSONValue {
        func box(_ box: ZoneBox?) -> JSONValue { box.map { .object(JSONObject([("top", .number($0.top)), ("height", .number($0.height))])) } ?? .null }
        var appBar: JSONValue = .null
        if let bar = zones.appBar {
            appBar = .object(JSONObject([("top", .number(bar.top)), ("height", .number(bar.height)), ("contentTop", .number(zones.appBarContentTop ?? 0))]))
        }
        var bottom: JSONValue = .null
        if let zone = zones.bottom {
            let nav: JSONValue = zone.navBar.map { .object(JSONObject([("top", .number($0.top)), ("height", .number($0.height)), ("contentHeight", .number($0.contentHeight))])) } ?? .null
            bottom = .object(JSONObject([
                ("top", .number(zone.top)), ("height", .number(zone.height)), ("pinned", box(zone.pinned)), ("navBar", nav), ("safeBottom", .number(zone.safeBottom)),
            ]))
        }
        return .object(JSONObject([
            ("height", .number(zones.height)), ("appBar", appBar), ("body", box(zones.body)), ("contentTop", .number(zones.contentTop)),
            ("contentHeight", .number(zones.contentHeight)), ("maxScroll", .number(zones.maxScroll)), ("scrollTop", .number(zones.scrollTop)),
            ("scrolls", .bool(zones.scrolls)), ("bottom", bottom), ("float", .bool(zones.float)),
            ("bodyAtScreenTop", .bool(zones.bodyAtScreenTop)), ("safeTop", .number(zones.safeTop)),
        ]))
    }

    /// Every key the table names must be there with that value (numbers within a hundredth).
    static func assertSubset(_ actual: JSONValue?, _ expected: JSONValue, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        switch expected {
        case .object(let object):
            for (key, value) in object { assertSubset(actual?[key], value, "\(label).\(key)", file: file, line: line) }
        case .number(let number):
            XCTAssertEqual(actual?.numberValue ?? .nan, number, accuracy: 0.01, label, file: file, line: line)
        default:
            XCTAssertEqual(actual ?? .null, expected, label, file: file, line: line)
        }
    }

    static func node(_ object: JSONObject) -> DocumentNode {
        var fields = JSONObject()
        if let pin = object["pin"] { fields["pin"] = pin }
        return DocumentNode(id: object["id"]?.stringValue ?? "", type: object["type"]?.stringValue ?? "", fields: fields)
    }

    static func rule(_ block: String, _ path: String) -> JSONValue? {
        layoutRule(path.isEmpty ? block : "\(block).\(path)")
    }

    /// A dotted path from `x-style.layout` of the artifact.
    static func layoutRule(_ dotted: String) -> JSONValue? {
        var value = schema["x-style"]?["layout"]
        for key in dotted.split(separator: ".") { value = value?[String(key)] }
        return value
    }

    // MARK: Shapes of the tables

    func testTableShape() {
        let expected: [(JSONValue, [String: Int])] = [
            (Self.chrome, ["screenAppBarCases": 7, "zoneCases": 19, "appBarCases": 15, "appBarDrawnCases": 7, "appBarLeadingCases": 48, "appBarLeadingShownCases": 6,
                "appBarChildrenCases": 10, "screenRuleCases": 16, "placementCases": 7, "statusBarCases": 7, "shownCases": 11, "bodyTopCases": 7, "topZoneCases": 11,
                "screenTopZoneCases": 22, "screenTopPressCases": 25, "safeTopValueCases": 10, "scrolledThresholdCases": 9, "scrolledLayerCases": 4,
                "screenTopRuleCases": 27, "appBar916RuleCases": 19]),
            (Self.bottom, ["childrenCases": 14, "pinCases": 8, "zoneCases": 18, "navHeightCases": 4, "navShareCases": 12, "activeCases": 8, "sectionCases": 5,
                "ruleCases": 45, "floatZoneCases": 9, "floatPlaceCases": 7, "navBadgeCases": 9, "navBadgeBoxCases": 4, "nav922RuleCases": 12,
                "navBadgeMotionCases": 6, "navBadgeAppearScaleCases": 6, "navBadgeDisappearOpacityCases": 4]),
            (Self.top, ["childrenCases": 10, "pinCases": 5, "geometryCases": 6, "documentCases": 5, "ruleCases": 8]),
        ]
        for (table, groups) in expected {
            for (group, count) in groups { XCTAssertEqual(Contract.rows(table, group).count, count, group) }
        }
    }

    // MARK: Who is in which zone

    func testBottomChildrenCases() {
        for row in Contract.rows(Self.bottom, "childrenCases") {
            let zones = ScreenAnatomy.childrenByZone((row["children"]?.arrayValue ?? []).compactMap(\.objectValue).map(Self.node))
            Self.assertSubset(Self.childrenJSON(zones, withTop: false), row["expect"] ?? .null, Self.name(row))
        }
    }

    func testTopChildrenCases() {
        for row in Contract.rows(Self.top, "childrenCases") {
            let zones = ScreenAnatomy.childrenByZone((row["children"]?.arrayValue ?? []).compactMap(\.objectValue).map(Self.node), rootProps: row["rootProps"]?.objectValue ?? JSONObject())
            Self.assertSubset(Self.childrenJSON(zones, withTop: true), row["expect"] ?? .null, Self.name(row))
        }
    }

    static func childrenJSON(_ zones: ScreenAnatomy.ChildrenByZone, withTop: Bool) -> JSONValue {
        func ids(_ nodes: [DocumentNode]) -> JSONValue { .array(nodes.map { .string($0.id) }) }
        func id(_ node: DocumentNode?) -> JSONValue { node.map { .string($0.id) } ?? .null }
        var object = JSONObject([("appBar", id(zones.appBar)), ("body", ids(zones.body)), ("pinned", id(zones.pinned)), ("navBar", id(zones.navBar))])
        if withTop { object["topPinned"] = ids(zones.topPinned) }
        return .object(object)
    }

    func testPinCases() {
        for row in Contract.rows(Self.bottom, "pinCases") {
            let node = DocumentNode(id: "n", type: "Text", fields: row["pin"].map { JSONObject([("pin", $0)]) } ?? JSONObject())
            XCTAssertEqual(ScreenAnatomy.pinOf(node).map(JSONValue.string) ?? .null, row["expect"] ?? .null, Self.name(row))
        }
        for row in Contract.rows(Self.top, "pinCases") {
            let node = DocumentNode(id: "n", type: "Text", fields: row["node"]?.objectValue ?? JSONObject())
            XCTAssertEqual(ScreenAnatomy.topPinOf(node), row["expect"]?.boolValue, Self.name(row))
        }
    }

    /// A node in the run is read as a node of the top zone; a word after a child without it is
    /// read as an ordinary child (the validator refuses to publish it, the reader does not guess).
    func testTopDocumentCases() {
        for row in Contract.rows(Self.top, "documentCases") {
            let zones = ScreenAnatomy.childrenByZone((row["children"]?.arrayValue ?? []).compactMap(\.objectValue).map(Self.node), rootProps: row["rootProps"]?.objectValue ?? JSONObject())
            let id = row["node"]?.stringValue ?? ""
            // The zone exists only among the children of a screen root; the word anywhere else is not read.
            let inRun = (row["parentType"]?.stringValue ?? "Screen") == "Screen" && zones.topPinned.contains { $0.id == id }
            XCTAssertEqual(inRun, row["expect"]?.isNull != false, Self.name(row))
        }
    }

    // MARK: Zones

    func testZoneCases() {
        for row in Contract.rows(Self.chrome, "zoneCases") + Contract.rows(Self.bottom, "zoneCases") + Contract.rows(Self.bottom, "floatZoneCases") + Contract.rows(Self.chrome, "screenTopZoneCases") {
            Self.assertSubset(Self.json(ScreenAnatomy.zones(Self.input(row))), row["expect"] ?? .null, Self.name(row))
        }
    }

    func testTopZoneGeometry() {
        for row in Contract.rows(Self.top, "geometryCases") {
            let input = row["input"]?.objectValue ?? JSONObject()
            let zone = ScreenAnatomy.topZone(ScreenAnatomy.TopZoneInput(
                appBarHeight: input["appBarHeight"]?.numberValue,
                pinned: (input["pinned"]?.arrayValue ?? []).compactMap(\.objectValue).map { (Self.number($0["height"]), $0["pull"]?.numberValue) },
                rootPaddingTop: Self.number(input["rootPaddingTop"]), gap: Self.number(input["gap"]), safeTop: input["safeTop"]?.numberValue
            ))
            let json: JSONValue = .object(JSONObject([
                ("height", .number(zone.height)),
                ("appBar", zone.appBar.map { .object(JSONObject([("top", .number($0.top)), ("height", .number($0.height))])) } ?? .null),
                ("pinned", .array(zone.pinned.map { .object(JSONObject([("top", .number($0.top)), ("height", .number($0.height))])) })),
                ("bodyTop", .number(zone.bodyTop)),
            ]))
            Self.assertSubset(json, row["expect"] ?? .null, Self.name(row))
        }
    }

    func testPressCases() {
        for row in Contract.rows(Self.chrome, "screenTopPressCases") {
            let screen = row["screen"]?.objectValue ?? JSONObject()
            let side = screen["sidePadding"]?.objectValue ?? JSONObject()
            let rtl = screen["direction"]?.stringValue == "rtl"
            let zones = ScreenAnatomy.zones(Self.input(screen))
            let point = row["point"]?.objectValue ?? JSONObject()
            let inline = (left: Self.number(rtl ? side["end"] : side["start"]), width: Self.number(screen["width"]) - Self.number(side["start"]) - Self.number(side["end"]))
            let zone = ScreenAnatomy.pressZone(zones, x: point["x"]?.numberValue, y: Self.number(point["y"]), barInline: inline)
            XCTAssertEqual(zone.rawValue, row["expect"]?.stringValue, Self.name(row))
        }
    }

    func testBodyTopAndSafeTopCases() {
        for row in Contract.rows(Self.chrome, "bodyTopCases") {
            XCTAssertEqual(ScreenAnatomy.bodyTopWord(row["value"]).map(JSONValue.string) ?? .null, row["expect"] ?? .null, Self.name(row))
        }
        for row in Contract.rows(Self.chrome, "safeTopValueCases") {
            // A value that is not a number is zero, like a value JSON cannot carry.
            XCTAssertEqual(ScreenAnatomy.safeTop(row["safeTop"]?.numberValue, screenHeight: Self.number(row["height"])), Self.number(row["effective"]), accuracy: 1e-9, Self.name(row))
        }
        let thresholds = [1.0e300, .infinity, .nan]
        for value in thresholds { XCTAssertEqual(ScreenAnatomy.safeTop(value, screenHeight: 600), value == 1.0e300 ? 600 : 0, Self.name(["name": "a number JSON cannot carry"])) }
    }

    func testTopZoneOwnerCases() {
        for row in Contract.rows(Self.chrome, "topZoneCases") {
            // The place the screen draws: `WideChrome.screenChrome`, as `ScreenZonesModel` asks it.
            let types = (row["children"]?.arrayValue ?? []).compactMap(\.stringValue)
            let hidden = Set((row["hidden"]?.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) })
            let nodes = types.enumerated().map { index, type in
                DocumentNode(id: "n\(index)", type: type, props: type == "NavBar" && row["widePlacement"] != nil ? ["widePlacement": row["widePlacement"]!] : [:])
            }
            let shown: (DocumentNode) -> Bool = { node in !hidden.contains(nodes.firstIndex { $0.id == node.id } ?? -1) }
            let widthClass: WidthClass = WidthClass(rawValue: row["widthClass"]?.stringValue ?? "compact") ?? .compact
            let chrome = WideChrome.screenChrome(nodes, widthClass: widthClass, isShown: shown)
            let appBarShown = chrome.zones.appBar.map(shown) ?? false
            let navShown = chrome.zones.navBar.map(shown) ?? false
            let owner = ScreenAnatomy.topZoneOwner(navBar: navShown && chrome.navPlace == .top, appBar: appBarShown)
            XCTAssertEqual(owner.rawValue, row["owner"]?.stringValue, Self.name(row))
            XCTAssertEqual(ScreenAnatomy.bodyStartsAtScreenTop(bodyTop: "screenTop", owner: owner), row["atScreenTop"]?.boolValue, Self.name(row))
        }
    }

    func testScreenAppBarCases() {
        for row in Contract.rows(Self.chrome, "screenAppBarCases") {
            let nodes = (row["children"]?.arrayValue ?? []).compactMap(\.stringValue).enumerated().map { DocumentNode(id: "n\($0.offset)", type: $0.element) }
            let bar = ScreenAnatomy.appBarOf(nodes)
            XCTAssertEqual(bar.flatMap { node in nodes.firstIndex { $0.id == node.id } }.map { JSONValue.number(Double($0)) } ?? .null, row["expect"] ?? .null, Self.name(row))
        }
    }

    // MARK: Status bar, placement

    func testPlacementAndStatusBarCases() {
        for row in Contract.rows(Self.chrome, "placementCases") {
            XCTAssertEqual(ScreenAnatomy.modalPlacement(row["value"]), row["expect"]?.stringValue, Self.name(row))
        }
        for row in Contract.rows(Self.chrome, "statusBarCases") {
            XCTAssertEqual(ScreenAnatomy.statusBarIcons(row["value"]).map(JSONValue.string) ?? .null, row["expect"] ?? .null, Self.name(row))
        }
    }

    // MARK: The app bar

    static func zonesInput(_ row: JSONObject) -> AppBarRules.ZonesInput {
        AppBarRules.ZonesInput(
            width: number(row["width"]), showBack: row["showBack"]?.boolValue == true, backSide: 24,
            actionSides: (row["actionSides"]?.arrayValue ?? []).map { number($0) }, gap: 8, actionGap: 4,
            titleNatural: number(row["titleNatural"]), leadingNatural: row["leadingNatural"]?.numberValue, titleAlign: row["titleAlign"]
        )
    }

    func testAppBarZoneCases() {
        for row in Contract.rows(Self.chrome, "appBarCases") + Contract.rows(Self.chrome, "appBarLeadingCases") {
            let zones = AppBarRules.zones(Self.zonesInput(row))
            let json: JSONValue = .object(JSONObject([
                ("leading", .number(zones.leading)), ("trailing", .number(zones.trailing)), ("titleRoom", .number(zones.titleRoom)),
                ("titleWidth", .number(zones.titleWidth)), ("titleStart", .number(zones.titleStart)), ("centered", .bool(zones.centered)),
                ("truncated", .bool(zones.truncated)), ("actionStarts", .array(zones.actionStarts.map { .number($0) })),
                ("leadingShown", .string(zones.leadingShown.rawValue)), ("leadingWidth", .number(zones.leadingWidth)),
            ]))
            let expected = row["expect"]?.objectValue ?? JSONObject()
            for (key, value) in expected {
                if case .array(let items) = value {
                    let actual = json[key]?.arrayValue ?? []
                    XCTAssertEqual(actual.count, items.count, "\(Self.name(row)).\(key)")
                    for (a, b) in zip(actual, items) { Self.assertSubset(a, b, "\(Self.name(row)).\(key)") }
                } else {
                    Self.assertSubset(json[key], value, "\(Self.name(row)).\(key)")
                }
            }
        }
    }

    func testAppBarDrawnCases() {
        for row in Contract.rows(Self.chrome, "appBarDrawnCases") {
            let visible = (row["visible"]?.arrayValue ?? []).map { $0.boolValue == true }
            let drawn = AppBarRules.drawn(visible: visible)
            XCTAssertEqual(drawn, (row["expect"]?["drawn"]?.arrayValue ?? []).map { $0.boolValue == true }, Self.name(row))
            let sides = drawn.filter { $0 }.map { _ in Self.number(row["actionSide"]) }
            var input = Self.zonesInput(row)
            input.actionSides = sides
            XCTAssertEqual(AppBarRules.zones(input).titleRoom, Self.number(row["expect"]?["titleRoom"]), accuracy: 0.01, Self.name(row))
        }
    }

    func testAppBarLeadingShownAndChildrenCases() {
        for row in Contract.rows(Self.chrome, "appBarLeadingShownCases") {
            let shown = AppBarRules.leadingShown(nodeVisible: row["nodeVisible"]?.boolValue, showBack: row["showBack"]?.boolValue == true)
            XCTAssertEqual(shown.rawValue, row["expect"]?.stringValue, Self.name(row))
        }
        for row in Contract.rows(Self.chrome, "appBarChildrenCases") {
            let nodes = (row["children"]?.arrayValue ?? []).compactMap(\.objectValue).map { child -> DocumentNode in
                var fields = JSONObject()
                if let zone = child["zone"] { fields["zone"] = zone }
                return DocumentNode(id: "n", type: child["type"]?.stringValue ?? "", fields: fields)
            }
            XCTAssertEqual(AppBarRules.leadingIndex(nodes).map { JSONValue.number(Double($0)) } ?? .null, row["leading"] ?? .null, Self.name(row))
            XCTAssertEqual(AppBarRules.actionIndexes(nodes).map { JSONValue.number(Double($0)) }, row["actions"]?.arrayValue ?? [], Self.name(row))
        }
    }

    // MARK: Scrolled

    func testScrolledCases() {
        for row in Contract.rows(Self.chrome, "scrolledThresholdCases") {
            let threshold = AppBarRules.scrolledThreshold(barBottom: Self.number(row["barBottom"]), bodyTop: Self.number(row["bodyTop"]))
            XCTAssertEqual(threshold, Self.number(row["threshold"]), Self.name(row))
            XCTAssertEqual(AppBarRules.isScrolled(scrollTop: Self.number(row["scrollTop"]), barBottom: Self.number(row["barBottom"]), bodyTop: Self.number(row["bodyTop"])), row["expected"]?.boolValue, Self.name(row))
        }
        XCTAssertFalse(AppBarRules.isScrolled(scrollTop: .nan, barBottom: 0, bodyTop: 0))
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme())
        for row in Contract.rows(Self.chrome, "scrolledLayerCases") {
            var base = row["base"]?.objectValue ?? JSONObject()
            // The state of `styleWhen` is laid over the base before the layer.
            for (key, value) in row["state"]?.objectValue ?? JSONObject() { base[key] = value }
            let node = DocumentNode(id: "b", type: "AppBar", fields: JSONObject([("styleScrolled", row["scrolled"] ?? .null)]))
            let result = AppBarRules.withScrolledLayer(base, scrolled: AppBarRules.scrolledStyle(node), resolver: resolver)
            XCTAssertEqual(JSONValue.object(result), row["expected"], Self.name(row))
        }
    }

    func testScrolledLayerKeepsWhatItCannotRead() {
        let resolver = StyleResolver(theme: HotlayoutThemeSet.builtIn.theme())
        let node = DocumentNode(id: "b", type: "AppBar", fields: JSONObject([("styleScrolled", ["color": "noSuchToken", "shadow": "low", "padding": "md"])]))
        let layer = AppBarRules.scrolledStyle(node)
        XCTAssertNil(layer?["padding"], "a box key is not a key of the layer")
        let result = AppBarRules.withScrolledLayer(["color": "onSurface"], scrolled: layer, resolver: resolver)
        XCTAssertEqual(result["color"], "onSurface", "a token the theme does not know is dropped and the field under it stays")
        XCTAssertEqual(result["shadow"], "low")
        XCTAssertNil(AppBarRules.scrolledStyle(DocumentNode(id: "b", type: "AppBar", fields: JSONObject([("styleScrolled", .object(JSONObject()))]))))
    }

    // MARK: The navigation bar

    func testNavHeightAndShareCases() {
        for row in Contract.rows(Self.bottom, "navHeightCases") {
            let m = row["metrics"]?.objectValue ?? JSONObject()
            let metrics = NavBarRules.Metrics(paddingBlock: Self.number(m["paddingBlock"]), iconBox: Self.number(m["iconBox"]), gap: Self.number(m["gap"]), labelLine: Self.number(m["labelLine"]), borderTop: Self.number(m["borderTop"]))
            XCTAssertEqual(NavBarRules.height(metrics), Self.number(row["expect"]), accuracy: 1e-9, Self.name(row))
        }
        for row in Contract.rows(Self.bottom, "navShareCases") {
            let shares = NavBarRules.shares(barWidth: Self.number(row["width"]), visible: (row["visible"]?.arrayValue ?? []).map { $0.boolValue == true }, rightToLeft: row["rtl"]?.boolValue == true)
            let expected = row["expect"]?.arrayValue ?? []
            XCTAssertEqual(shares.count, expected.count, Self.name(row))
            for (share, want) in zip(shares, expected) {
                XCTAssertEqual(share?.start, want["start"]?.numberValue, Self.name(row))
                XCTAssertEqual(share?.width, want["width"]?.numberValue, Self.name(row))
                if want.isNull { XCTAssertNil(share, Self.name(row)) }
            }
        }
    }

    func testActiveAndSectionCases() {
        for row in Contract.rows(Self.bottom, "activeCases") {
            XCTAssertEqual(NavBarRules.isActive(row["action"]?.objectValue, shown: row["shown"]?.stringValue ?? ""), row["expect"]?.boolValue, Self.name(row))
        }
        for row in Contract.rows(Self.bottom, "sectionCases") {
            let stack = (row["stack"]?.arrayValue ?? []).compactMap(\.stringValue)
            let result = NavBarRules.sectionStack(stack, target: row["target"]?.stringValue ?? "")
            XCTAssertEqual(result.map { JSONValue.array($0.map(JSONValue.string)) } ?? .null, row["expect"] ?? .null, Self.name(row))
            // The flow does the same: one screen, cause `switch`, no event when nothing changes.
            let screens = Set(stack + [row["target"]?.stringValue ?? ""]).sorted()
            var flow = Flow(document: FlowDocument(documentId: "d", screens: screens.map { .init(screenId: $0, presentation: .page) }, initialScreenId: stack.first, entryPoints: [:]), entry: nil)
            for screen in stack.dropFirst() { _ = flow.press(["type": "navigate", "params": ["screenId": .string(screen)]]) }
            let outcome = flow.press(["type": "navigate.section", "params": ["screenId": .string(row["target"]?.stringValue ?? "")]])
            XCTAssertEqual(flow.stack.map(\.screenId), result ?? stack, Self.name(row))
            XCTAssertEqual(outcome.shown == nil, result == nil, Self.name(row))
            if result != nil { XCTAssertEqual(outcome.shown?.cause, .switch, Self.name(row)) }
        }
    }

    func testFloatPlaceCases() {
        for row in Contract.rows(Self.bottom, "floatPlaceCases") {
            XCTAssertEqual(NavBarRules.floats(place: row["navPlace"]?.stringValue ?? "", props: row["props"]?.objectValue ?? JSONObject()), row["expect"]?.boolValue, Self.name(row))
        }
    }

    func testBadgeCases() {
        for row in Contract.rows(Self.bottom, "navBadgeCases") {
            XCTAssertEqual(NavBarRules.badgeShown(row["props"]?.objectValue ?? JSONObject(), scope: Contract.scope(row["data"])), row["expect"]?.boolValue, Self.name(row))
        }
        for row in Contract.rows(Self.bottom, "navBadgeBoxCases") {
            let glyph = row["glyph"]?.objectValue ?? JSONObject()
            let box = NavBarRules.badgeBox(glyphLeft: Self.number(glyph["left"]), glyphTop: Self.number(glyph["top"]), glyphSize: Self.number(glyph["size"]), rightToLeft: row["rtl"]?.boolValue == true)
            XCTAssertEqual([box.left, box.top, box.size], [Self.number(row["expect"]?["left"]), Self.number(row["expect"]?["top"]), Self.number(row["expect"]?["size"])], Self.name(row))
        }
        for row in Contract.rows(Self.bottom, "navBadgeMotionCases") {
            let input = row["input"]?.objectValue ?? JSONObject()
            let change = NavBarRules.badgeChange(shownBefore: input["shownBefore"]?.boolValue == true, before: input["before"]?.boolValue == true, after: input["after"]?.boolValue == true, reducedMotion: input["reducedMotion"]?.boolValue == true)
            XCTAssertEqual(change.rawValue, row["expect"]?.stringValue, Self.name(row))
        }
        for row in Contract.rows(Self.bottom, "navBadgeAppearScaleCases") {
            XCTAssertEqual(NavBarRules.appearScale(at: Self.number(row["t"])), Self.number(row["expect"]), accuracy: 1e-9, Self.name(row))
        }
        for row in Contract.rows(Self.bottom, "navBadgeDisappearOpacityCases") {
            XCTAssertEqual(NavBarRules.disappearOpacity(at: Self.number(row["t"])), Self.number(row["expect"]), accuracy: 1e-9, Self.name(row))
        }
    }

    // MARK: The data of the artifact

    func testRuleCases() {
        for row in Contract.rows(Self.chrome, "screenRuleCases") { XCTAssertEqual(Self.rule("screen", row["rule"]?.stringValue ?? ""), row["expect"], Self.name(row)) }
        for row in Contract.rows(Self.chrome, "screenTopRuleCases") { XCTAssertEqual(Self.layoutRule(row["rule"]?.stringValue ?? ""), row["expect"], Self.name(row)) }
        for row in Contract.rows(Self.chrome, "appBar916RuleCases") { XCTAssertEqual(Self.layoutRule(row["rule"]?.stringValue ?? ""), row["expect"], Self.name(row)) }
        for row in Contract.rows(Self.bottom, "ruleCases") + Contract.rows(Self.bottom, "nav922RuleCases") {
            XCTAssertEqual(Self.rule(row["block"]?.stringValue ?? "", row["rule"]?.stringValue ?? ""), row["expect"], Self.name(row))
        }
        for row in Contract.rows(Self.top, "ruleCases") { XCTAssertEqual(Self.rule("topZone", row["rule"]?.stringValue ?? ""), row["expect"], Self.name(row)) }
    }

    /// The numbers the reader keeps are the numbers of the artifact.
    func testConstantsMirrorTheArtifact() {
        XCTAssertEqual(Self.rule("appBarLeading", "maxShare")?.numberValue, AppBarRules.leadingMaxShare)
        XCTAssertEqual(Self.rule("appBar", "maxDrawnActions")?.numberValue, Double(AppBarRules.maxDrawnActions))
        XCTAssertEqual(Self.rule("navBar", "items.max")?.numberValue, Double(NavBarRules.maxItems))
        XCTAssertEqual(Self.rule("navBadge", "diameter")?.numberValue, NavBarRules.dotDiameter)
        XCTAssertEqual(Self.rule("navBadgeMotion", "appear.durationMs")?.numberValue, NavBarRules.appearMs)
        XCTAssertEqual(Self.rule("navBadgeMotion", "disappear.durationMs")?.numberValue, NavBarRules.disappearMs)
        XCTAssertEqual(Self.rule("appBar", "backSide")?.stringValue, AppBarRules.backSideToken)
        XCTAssertEqual(Self.rule("appBar", "gap")?.stringValue, AppBarRules.gapToken)
        XCTAssertEqual(Self.rule("appBar", "actionGap")?.stringValue, AppBarRules.actionGapToken)
    }

    // MARK: Groups of the tables that this reader does not run, with the reason

    /// Every group of the three tables is run above or is named here with its reason. A new
    /// group in a table fails this test until somebody decides which it is.
    func testEveryGroupIsRunOrNamed() {
        let chromeRun: Set<String> = [
            "screenAppBarCases", "zoneCases", "appBarCases", "appBarDrawnCases", "appBarLeadingCases", "appBarLeadingShownCases", "appBarChildrenCases",
            "screenRuleCases", "placementCases", "statusBarCases", "bodyTopCases", "topZoneCases", "screenTopZoneCases", "screenTopPressCases",
            "safeTopValueCases", "scrolledThresholdCases", "scrolledLayerCases", "screenTopRuleCases", "appBar916RuleCases", "shownCases",
            // The picture groups run in ImageCasesTests.
            "ratioCases", "imageBoxCases", "paintCases", "radiusCases", "circleCases",
            // The own glyph size runs in LayoutFixTests.
            "glyphCases",
        ]
        let chromeNotRun: [String: String] = [
            "ratioDocumentCases": "validator rule of the image ratio",
            "modalCases": "the geometry of the modal layer: run in ModalCasesTests", "modalAreaCases": "the geometry of the modal layer: run in ModalCasesTests",
            "modalRuleCases": "the data of the modal layer block: run in ModalCasesTests",
            "documentCases": "validator rule", "appBarPlaceCases": "where the editor puts a dropped child: not a reader's rule",
            "appBar916DocumentCases": "validator rule",
            "screenTopDocumentCases": "schema acceptance of the field: the validator; the word itself is run by bodyTopCases",
            "scrolledDocumentCases": "schema acceptance: the validator; what the reader reads is run by scrolledLayerCases",
        ]
        let bottomRun: Set<String> = [
            "childrenCases", "pinCases", "zoneCases", "navHeightCases", "navShareCases", "activeCases", "sectionCases", "ruleCases", "floatZoneCases",
            "floatPlaceCases", "navBadgeCases", "navBadgeBoxCases", "nav922RuleCases", "navBadgeMotionCases", "navBadgeAppearScaleCases", "navBadgeDisappearOpacityCases",
        ]
        let bottomNotRun: [String: String] = ["documentCases": "sentences of the validator about a bar that is not at the end of the root"]
        let topRun: Set<String> = ["childrenCases", "pinCases", "geometryCases", "documentCases", "ruleCases"]
        for (name, table, run, notRun) in [("media-chrome", Self.chrome, chromeRun, chromeNotRun), ("bottom-zone", Self.bottom, bottomRun, bottomNotRun), ("top-zone", Self.top, topRun, [:])] {
            for (key, value) in table.objectValue ?? JSONObject() where key.hasSuffix("Cases") {
                XCTAssertNotNil(value.arrayValue, "\(name).\(key)")
                XCTAssertTrue(run.contains(key) || notRun[key] != nil, "\(name).\(key) is neither run nor named")
                XCTAssertFalse(run.contains(key) && notRun[key] != nil, "\(name).\(key) is both")
            }
            for key in run.union(notRun.keys) { XCTAssertNotNil(table[key], "\(name).\(key) is named but not in the table") }
        }
    }
}
