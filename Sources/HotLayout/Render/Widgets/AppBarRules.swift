import Foundation

/// The rules of the app bar (`x-style.layout.appBar`, `appBarLeading`, `appBarTitle`,
/// `appBarScrolled`): three zones in reading order, the node of the leading zone, the actions
/// that are drawn, and the state «scrolled». Coordinates run from the START of the row in the
/// reading direction; whoever draws mirrors them for right-to-left text.
enum AppBarRules {
    /// How many actions the bar draws: the first two VISIBLE ones.
    static let maxDrawnActions = 2
    /// The widest share of the bar the node of the leading zone takes.
    static let leadingMaxShare = 0.5
    /// Step of spacing for the side of the back arrow, and the gaps between the zones.
    static let backSideToken = "xl"
    static let gapToken = "sm"
    static let actionGapToken = "xs"
    static let subtitleGapToken = "xs"

    // MARK: Children

    /// The words of `zone` the reader knows; only `leading`.
    static func zone(of node: DocumentNode) -> String? {
        node.fields["zone"]?.stringValue == "leading" ? "leading" : nil
    }

    static func canStandInLeadingZone(_ type: String) -> Bool { type == "Button" || type == "IconButton" }

    /// The index of the node of the leading zone: the first child with the field whose type may
    /// stand there. Visibility is not asked here.
    static func leadingIndex(_ children: [DocumentNode]) -> Int? {
        children.firstIndex { zone(of: $0) == "leading" && canStandInLeadingZone($0.type) }
    }

    /// The indexes of the actions: icon buttons WITHOUT the field, in document order.
    static func actionIndexes(_ children: [DocumentNode]) -> [Int] {
        children.indices.filter { children[$0].type == "IconButton" && zone(of: children[$0]) == nil }
    }

    /// Which actions are drawn, given which are visible: the first two visible ones.
    static func drawn(visible: [Bool]) -> [Bool] {
        var count = 0
        return visible.map { isVisible in
            if !isVisible || count >= maxDrawnActions { return false }
            count += 1
            return true
        }
    }

    enum LeadingShown: String { case node, back, none }

    /// What stands in the leading zone: a VISIBLE node replaces the arrow whatever `showBack`
    /// says; a hidden one leaves the decision to `showBack`.
    static func leadingShown(nodeVisible: Bool?, showBack: Bool) -> LeadingShown {
        if nodeVisible == true { return .node }
        return showBack ? .back : .none
    }

    /// The width of the leading node: natural, at most half of the bar.
    static func leadingWidth(natural: Double, barWidth: Double) -> Double {
        max(0, min(natural, barWidth * leadingMaxShare))
    }

    // MARK: Title

    enum TitleAlign: String { case start, center }

    static func titleAlign(_ value: JSONValue?) -> TitleAlign {
        value?.stringValue == "start" ? .start : .center
    }

    /// `titleShown: scrolled` — the title is drawn only while the body is scrolled. Another
    /// word and no field mean «always».
    static func titleShownOnlyWhenScrolled(_ props: JSONObject) -> Bool {
        props["titleShown"]?.stringValue == "scrolled"
    }

    // MARK: Zones

    struct ZonesInput {
        var width: Double
        var showBack: Bool
        var backSide: Double
        var actionSides: [Double]
        var gap: Double
        var actionGap: Double
        var titleNatural: Double
        /// The natural width of the visible node of the leading zone; `nil` — none.
        var leadingNatural: Double?
        var titleAlign: JSONValue?
    }

    struct Zones: Equatable {
        var leading: Double
        var trailing: Double
        var titleRoom: Double
        var titleWidth: Double
        var titleStart: Double
        var centered: Bool
        var truncated: Bool
        var actionStarts: [Double]
        var leadingShown: LeadingShown
        var leadingWidth: Double
    }

    static func zones(_ input: ZonesInput) -> Zones {
        let actions = input.actionSides.reduce(0, +) + Double(max(0, input.actionSides.count - 1)) * input.actionGap
        let shown = leadingShown(nodeVisible: input.leadingNatural == nil ? nil : true, showBack: input.showBack)
        let leadingWidth: Double
        switch shown {
        case .node: leadingWidth = Self.leadingWidth(natural: input.leadingNatural ?? 0, barWidth: input.width)
        case .back: leadingWidth = input.backSide
        case .none: leadingWidth = 0
        }
        let leading = shown == .none ? 0 : leadingWidth + input.gap
        let trailing = input.actionSides.isEmpty ? 0 : actions + input.gap
        let titleRoom = max(0, input.width - leading - trailing)
        let titleWidth = min(max(0, input.titleNatural), titleRoom)
        let ideal = (input.width - titleWidth) / 2
        // Shifted off a zone by exactly as much as needed; the leading zone is stronger when there is no room at all.
        let titleStart = titleAlign(input.titleAlign) == .start ? leading : max(leading, min(ideal, input.width - trailing - titleWidth))
        var cursor = input.width - actions
        let starts = input.actionSides.map { side -> Double in
            let start = cursor
            cursor += side + input.actionGap
            return start
        }
        return Zones(
            leading: leading, trailing: trailing, titleRoom: titleRoom, titleWidth: titleWidth, titleStart: titleStart,
            centered: titleStart == ideal, truncated: input.titleNatural > titleRoom, actionStarts: starts,
            leadingShown: shown, leadingWidth: leadingWidth
        )
    }

    // MARK: Scrolled

    /// The keys a scrolled layer may carry.
    static let scrolledKeys = ["background", "color", "shadow", "backdropBlur"]

    /// How far the body must be scrolled before the bar is «scrolled»: the part of the bar zone
    /// that lies below the top of the body area.
    static func scrolledThreshold(barBottom: Double, bodyTop: Double) -> Double {
        max(0, barBottom - bodyTop)
    }

    /// Strictly past the threshold; a scroll that is not finite is not scrolled.
    static func isScrolled(scrollTop: Double, barBottom: Double, bodyTop: Double) -> Bool {
        scrollTop.isFinite && scrollTop > scrolledThreshold(barBottom: barBottom, bodyTop: bodyTop)
    }

    /// The scrolled layer of the bar node: only the four keys the structure allows; `nil` when
    /// the field is absent or empty.
    static func scrolledStyle(_ node: DocumentNode) -> JSONObject? {
        guard let object = node.fields["styleScrolled"]?.objectValue else { return nil }
        var layer = JSONObject()
        for key in scrolledKeys {
            if let value = object[key], !value.isNull { layer[key] = value }
        }
        return layer.isEmpty ? nil : layer
    }

    /// The style while the bar is scrolled: the layer lies LAST, over the base style, the
    /// width-class layers and the state. A field whose token the theme does not know is dropped,
    /// and the field under it stays.
    static func withScrolledLayer(_ style: JSONObject, scrolled: JSONObject?, resolver: StyleResolver) -> JSONObject {
        guard let scrolled else { return style }
        var result = style
        for key in scrolledKeys {
            guard let value = scrolled[key], resolves(key, value, resolver: resolver) else { continue }
            result[key] = value
        }
        return result
    }

    private static func resolves(_ key: String, _ value: JSONValue, resolver: StyleResolver) -> Bool {
        switch key {
        case "color": return resolver.color(value) != nil
        case "shadow": return resolver.shadow(value) != nil
        case "background":
            switch value["kind"]?.stringValue {
            case "color": return resolver.color(value["color"]) != nil
            case "gradient": return resolver.gradient(value["gradient"]) != nil
            default: return true
            }
        default: return true
        }
    }
}
