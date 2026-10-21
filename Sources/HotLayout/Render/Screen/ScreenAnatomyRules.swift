import Foundation

/// A band of a screen: its top edge from the top of the screen and its height.
struct ZoneBox: Equatable {
    var top: Double
    var height: Double
}

/// The box of the navigation bar in the bottom zone: `height` includes the safe inset under the
/// content, `contentHeight` does not.
struct NavZoneBox: Equatable {
    var top: Double
    var height: Double
    var contentHeight: Double
}

/// The heights the bottom zone is made of (`x-style.layout.bottomZone`).
struct BottomZoneInput: Equatable {
    var pinnedHeight: Double?
    var navBarHeight: Double?
    var safeBottom: Double?
}

/// The bottom zone with its parts measured from its own top.
struct BottomZoneBox: Equatable {
    var height: Double
    var pinned: ZoneBox?
    var navBar: NavZoneBox?
    var safeBottom: Double
}

/// The bottom zone in the coordinates of the screen.
struct AnatomyBottom: Equatable {
    var top: Double
    var height: Double
    var pinned: ZoneBox?
    var navBar: NavZoneBox?
    var safeBottom: Double
}

/// What decides the zones of one screen. Every number is in logical points.
struct AnatomyInput {
    /// The height the host gave the screen; for a modal layer, the available height.
    var height: Double
    /// A modal layer is as tall as its content, not taller than `height`.
    var shrink = false
    /// The height of the box of the app bar, WITHOUT the top safe inset; `nil` — no app bar zone.
    var appBarHeight: Double?
    var paddingTop: Double
    var paddingBottom: Double
    /// The gap of the screen (`Screen.props.gap`).
    var gap: Double
    /// The flow of the visible children of the body, the pull of the first one not counted yet;
    /// `nil` — the body has no visible child.
    var bodyContentHeight: Double?
    var firstPull: Double?
    var scrollTop: Double?
    var bottom: BottomZoneInput?
    /// The navigation bar floats over the body (`NavBar.float`).
    var navFloat = false
    /// The field `Screen.props.bodyTop` as it stands in the document.
    var bodyTop: JSONValue?
    /// The top inset the host gave.
    var safeTop: Double?
    /// The height of the screen keyboard over the bottom edge of the screen.
    var keyboard: Double = 0
}

struct AnatomyZones: Equatable {
    var height: Double
    /// The box of the app bar WITH the inset inside it; `nil` — no zone.
    var appBar: ZoneBox?
    /// Where the content of the bar starts (below the inset).
    var appBarContentTop: Double?
    var body: ZoneBox
    var contentTop: Double
    var contentHeight: Double
    var maxScroll: Double
    var scrollTop: Double
    var scrolls: Bool
    var bottom: AnatomyBottom?
    var float = false
    var bodyAtScreenTop = false
    var safeTop = 0.0
}

/// Who owns the zone at the top of the screen (`topZoneOwnerOf`).
enum TopZoneOwner: String {
    case appBar, navBar, none
}

/// The zones of a screen: app bar, body, bottom zone, and who takes a press where
/// (`x-style.layout.screen`, `bottomZone`, `bodyTop`, `safeTop`, `navFloat`, `topZone`).
enum ScreenAnatomy {
    // MARK: Words of the fields

    static let bottomPin = "bottom"
    static let topPin = "top"
    static let screenTopWord = "screenTop"

    /// The word of `Screen.props.bodyTop`; an unknown word and a value that is not a string are
    /// no field.
    static func bodyTopWord(_ value: JSONValue?) -> String? {
        value?.stringValue == screenTopWord ? screenTopWord : nil
    }

    /// The word of the `pin` field of a node, as the bottom zone reads it.
    static func pinOf(_ node: DocumentNode) -> String? {
        node.fields["pin"]?.stringValue == bottomPin ? bottomPin : nil
    }

    static func topPinOf(_ node: DocumentNode) -> Bool {
        node.fields["pin"]?.stringValue == topPin
    }

    /// `statusBarIcons`: a word the reader knows or nothing.
    static func statusBarIcons(_ value: JSONValue?) -> String? {
        guard let word = value?.stringValue, word == "light" || word == "dark" else { return nil }
        return word
    }

    /// Where a modal layer lies: `center` or `bottom`; anything else is `bottom`.
    static func modalPlacement(_ value: JSONValue?) -> String {
        value?.stringValue == "center" ? "center" : "bottom"
    }

    // MARK: Who is in which zone

    struct ChildrenByZone {
        var appBar: DocumentNode?
        var topPinned: [DocumentNode]
        var body: [DocumentNode]
        var pinned: DocumentNode?
        var navBar: DocumentNode?
    }

    /// The app bar zone: the first child of the root by the DOCUMENT, if it is an `AppBar`.
    static func appBarOf(_ children: [DocumentNode]) -> DocumentNode? {
        children.first?.widget == .appBar ? children.first : nil
    }

    /// The navigation bar: the last child of the root, if it is a `NavBar`.
    static func navBarOf(_ children: [DocumentNode]) -> DocumentNode? {
        children.last?.widget == .navBar ? children.last : nil
    }

    /// The pinned block: the last child of the root not counting the navigation bar, if its
    /// `pin` is `bottom`; never an app bar in the first place, never a navigation bar.
    static func pinnedOf(_ children: [DocumentNode]) -> DocumentNode? {
        let end = navBarOf(children) == nil ? children.count : children.count - 1
        let index = end - 1
        guard index >= 0, index < children.count else { return nil }
        let candidate = children[index]
        if pinOf(candidate) != bottomPin || candidate.widget == .navBar { return nil }
        if index == 0, candidate.widget == .appBar { return nil }
        return candidate
    }

    /// The nodes of the top zone: a run at the start, right after the app bar zone, whose `pin`
    /// is `top`. Not read with `bodyTop: screenTop`.
    static func topPinnedOf(_ children: [DocumentNode], rootProps: JSONObject) -> [DocumentNode] {
        if bodyTopWord(rootProps["bodyTop"]) != nil { return [] }
        var run: [DocumentNode] = []
        for child in children.dropFirst(children.first?.widget == .appBar ? 1 : 0) {
            if !topPinOf(child) || child.widget == .appBar || child.widget == .navBar { break }
            run.append(child)
        }
        return run
    }

    static func childrenByZone(_ children: [DocumentNode], rootProps: JSONObject = JSONObject()) -> ChildrenByZone {
        let appBar = appBarOf(children)
        let top = topPinnedOf(children, rootProps: rootProps)
        let nav = navBarOf(children)
        let pinned = pinnedOf(children)
        let from = (appBar == nil ? 0 : 1) + top.count
        let to = children.count - (nav == nil ? 0 : 1) - (pinned == nil ? 0 : 1)
        return ChildrenByZone(appBar: appBar, topPinned: top, body: from < to ? Array(children[from..<to]) : [], pinned: pinned, navBar: nav)
    }

    // MARK: The top of the screen

    /// The top inset the reader accounts for: what the host gave when it is a finite positive
    /// number, at most the height of the screen; anything else is zero.
    static func safeTop(_ value: Double?, screenHeight: Double) -> Double {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return min(value, max(0, screenHeight))
    }

    static func topZoneOwner(navBar: Bool, appBar: Bool) -> TopZoneOwner {
        if navBar { return .navBar }
        return appBar ? .appBar : .none
    }

    /// Whether the body starts at the top edge of the screen: the word is named and the zone is
    /// not an own navigation strip.
    static func bodyStartsAtScreenTop(bodyTop: JSONValue?, owner: TopZoneOwner) -> Bool {
        bodyTopWord(bodyTop) != nil && owner != .navBar
    }

    // MARK: The bottom zone

    /// The bottom zone: pinned block, then the navigation bar, then the safe inset. `nil` when
    /// there is neither a block nor a bar.
    static func bottomZone(_ input: BottomZoneInput, rootPaddingBottom: Double) -> BottomZoneBox? {
        let hasPinned = input.pinnedHeight != nil
        let hasNav = input.navBarHeight != nil
        if !hasPinned && !hasNav { return nil }
        let safe = max(0, input.safeBottom ?? 0)
        let pinnedHeight = max(0, input.pinnedHeight ?? 0)
        let pinnedRoom = hasPinned ? pinnedHeight + max(0, rootPaddingBottom) : 0
        let navContent = max(0, input.navBarHeight ?? 0)
        return BottomZoneBox(
            height: pinnedRoom + (hasNav ? navContent : 0) + safe,
            pinned: hasPinned ? ZoneBox(top: 0, height: pinnedHeight) : nil,
            navBar: hasNav ? NavZoneBox(top: pinnedRoom, height: navContent + safe, contentHeight: navContent) : nil,
            safeBottom: safe
        )
    }

    // MARK: Zones

    /// The zones of a screen in coordinates from its PHYSICAL top.
    static func zones(_ input: AnatomyInput) -> AnatomyZones {
        let safeTop = Self.safeTop(input.safeTop, screenHeight: input.height)
        let hasBar = input.appBarHeight != nil
        let barBox = hasBar ? ZoneBox(top: input.paddingTop, height: safeTop + max(0, input.appBarHeight ?? 0)) : nil
        if bodyStartsAtScreenTop(bodyTop: input.bodyTop, owner: hasBar ? .appBar : .none) {
            var bare = input
            bare.appBarHeight = nil
            bare.paddingTop = hasBar ? 0 : input.paddingTop
            let natural = base(bare)
            let floor = barBox.map { min($0.top + $0.height, max(0, input.height)) } ?? 0
            var body = natural
            if input.shrink, natural.height < floor {
                var grown = bare
                grown.shrink = false
                grown.height = floor
                body = base(grown)
            }
            body.appBar = barBox
            body.appBarContentTop = barBox == nil ? nil : input.paddingTop + safeTop
            body.bodyAtScreenTop = true
            body.safeTop = safeTop
            return body
        }
        if let barBox {
            var withBar = input
            withBar.appBarHeight = barBox.height
            var result = base(withBar)
            result.appBar = barBox
            result.appBarContentTop = input.paddingTop + safeTop
            result.safeTop = safeTop
            return result
        }
        var lowered = input
        lowered.height = max(0, input.height - safeTop)
        var result = base(lowered)
        result.lower(by: safeTop)
        result.safeTop = safeTop
        return result
    }

    /// The zones without the top inset and the word `bodyTop`: the base rule of the screen, with
    /// a floating navigation bar and the keyboard.
    static func base(_ input: AnatomyInput) -> AnatomyZones {
        let hasBar = input.appBarHeight != nil
        let barZone = hasBar ? input.paddingTop + max(0, input.appBarHeight ?? 0) : 0
        let empty = input.bodyContentHeight == nil
        // What lies above the first child INSIDE the scroll: the gap under the app bar, or the top padding without one.
        let lead = hasBar ? (empty ? 0 : input.gap) : input.paddingTop
        let pull = empty ? 0 : max(0, input.firstPull ?? 0)
        // Without an app bar a pulled first child goes into the top padding and beyond: nothing to raise.
        let raise = hasBar ? min(max(0, pull - lead), barZone) : 0
        let areaTop = barZone - raise
        let restTop = barZone + lead - pull
        var bottomInput = input.bottom
        if input.keyboard > 0, bottomInput?.navBarHeight == nil { bottomInput?.safeBottom = 0 }
        let zone = bottomInput.flatMap { bottomZone($0, rootPaddingBottom: input.paddingBottom) }
        let tail = zone?.pinned != nil ? (empty ? 0 : input.gap) : input.paddingBottom
        let contentHeight = max(0, restTop + (input.bodyContentHeight ?? 0) + tail - areaTop)
        let zoneHeight = zone?.height ?? 0
        let lowHeight = zone?.navBar?.height ?? 0
        let lift = input.shrink ? 0 : keyboardLift(keyboard: input.keyboard, navBarHeight: lowHeight)
        let natural = areaTop + contentHeight + zoneHeight
        let height = input.shrink ? min(natural, max(0, input.height)) : max(0, input.height)
        let zoneTop = max(areaTop, height - zoneHeight - lift)
        let areaHeight = max(0, zoneTop - areaTop)
        let maxScroll = max(0, contentHeight - areaHeight)
        let scrollTop = min(max(0, input.scrollTop ?? 0), maxScroll)
        var result = AnatomyZones(
            height: height,
            appBar: hasBar ? ZoneBox(top: input.paddingTop, height: max(0, input.appBarHeight ?? 0)) : nil,
            body: ZoneBox(top: areaTop, height: areaHeight),
            contentTop: restTop - scrollTop,
            contentHeight: contentHeight,
            maxScroll: maxScroll,
            scrollTop: scrollTop,
            scrolls: maxScroll > 0,
            bottom: zone.map {
                AnatomyBottom(
                    top: zoneTop, height: zoneHeight,
                    pinned: $0.pinned.map { ZoneBox(top: zoneTop + $0.top, height: $0.height) },
                    navBar: $0.navBar.map { NavZoneBox(top: zoneTop + $0.top, height: $0.height, contentHeight: $0.contentHeight) },
                    safeBottom: $0.safeBottom
                )
            }
        )
        if input.navFloat, input.keyboard == 0, let bar = result.bottom?.navBar { result = floated(result, input: input, bar: bar) }
        return result
    }

    /// A floating navigation bar: the body area reaches the bottom of the screen and the
    /// content scrolls under the zone, which adds its own height to the end of the content.
    private static func floated(_ base: AnatomyZones, input: AnatomyInput, bar: NavZoneBox) -> AnatomyZones {
        guard let zone = base.bottom else { return base }
        let restTop = base.contentTop + base.scrollTop
        let bodyHeight = max(0, base.height - base.body.top)
        let contentHeight = base.contentHeight + zone.height
        let maxScroll = max(0, contentHeight - bodyHeight)
        let scrollTop = min(max(0, input.scrollTop ?? 0), maxScroll)
        var result = base
        result.body = ZoneBox(top: base.body.top, height: bodyHeight)
        result.contentTop = restTop - scrollTop
        result.contentHeight = contentHeight
        result.maxScroll = maxScroll
        result.scrollTop = scrollTop
        result.scrolls = maxScroll > 0
        var floating = zone
        floating.navBar = NavZoneBox(top: bar.top, height: bar.contentHeight, contentHeight: bar.contentHeight)
        result.bottom = floating
        result.float = true
        return result
    }

    // MARK: Who takes a press

    enum PressZone: String {
        case appBar, body, bottom, none
    }

    /// The zone that takes a press at a point (y from the top of the screen). With the body
    /// from the top edge the bar lies over it and takes the presses of its own box only.
    static func pressZone(_ zones: AnatomyZones, x: Double? = nil, y: Double, barInline: (left: Double, width: Double)? = nil) -> PressZone {
        if y < 0 || y >= zones.height { return .none }
        if let bottom = zones.bottom, y >= bottom.top { return .bottom }
        var inBar = false
        if let bar = zones.appBar {
            var inline = true
            if let x, let barInline { inline = x >= barInline.left && x < barInline.left + barInline.width }
            inBar = y >= bar.top && y < bar.top + bar.height && inline
        }
        let inBody = y >= zones.body.top && y < zones.body.top + zones.body.height
        if zones.bodyAtScreenTop { return inBar ? .appBar : inBody ? .body : .none }
        if inBody { return .body }
        return inBar ? .appBar : .none
    }

    // MARK: The top zone

    struct TopZoneInput {
        var appBarHeight: Double?
        var pinned: [(height: Double, pull: Double?)]
        var rootPaddingTop: Double
        var gap: Double
        var safeTop: Double?
    }

    struct TopZoneBox {
        var height: Double
        var appBar: ZoneBox?
        var pinned: [ZoneBox]
        var bodyTop: Double
    }

    /// The top zone: root padding, the bar, then the nodes with the gap of the screen between
    /// them; the first node's pull is not read.
    static func topZone(_ input: TopZoneInput) -> TopZoneBox {
        let gap = max(0, input.gap)
        let padding = max(0, input.rootPaddingTop)
        let hasBar = input.appBarHeight != nil
        let barHeight = max(0, input.appBarHeight ?? 0)
        let safe = hasBar ? 0 : max(0, input.safeTop ?? 0)
        let appBar = hasBar ? ZoneBox(top: padding, height: barHeight) : nil
        var cursor = hasBar ? padding + barHeight : safe
        var boxes: [ZoneBox] = []
        for (index, entry) in input.pinned.enumerated() {
            let lead = index == 0 ? (hasBar ? gap : padding) : gap - max(0, entry.pull ?? 0)
            let top = cursor + lead
            let height = max(0, entry.height)
            cursor = top + height
            boxes.append(ZoneBox(top: top, height: height))
        }
        return TopZoneBox(height: cursor, appBar: appBar, pinned: boxes, bodyTop: cursor)
    }

    // MARK: The keyboard

    /// How far the keyboard lifts the bottom zone: only by the part by which it is taller than
    /// the navigation bar, which stays under it; the pinned block rides above the keyboard.
    static func keyboardLift(keyboard: Double, navBarHeight: Double) -> Double {
        max(0, keyboard - max(0, navBarHeight))
    }
}

extension AnatomyZones {
    /// The same zones, moved down: the inset the reader accounts for lies above them.
    mutating func lower(by distance: Double) {
        if distance == 0 { return }
        height += distance
        body.top += distance
        contentTop += distance
        if var zone = bottom {
            zone.top += distance
            zone.pinned?.top += distance
            zone.navBar?.top += distance
            bottom = zone
        }
    }
}
