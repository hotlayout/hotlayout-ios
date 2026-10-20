import Foundation

/// The rules of the navigation bar (`x-style.layout.navBar`, `navBadge`, `navBadgeMotion`):
/// its height, the shares of the items, which one is active, the dot on an item.
enum NavBarRules {
    static let maxItems = 5
    static let dotDiameter = 8.0
    static let appearMs = 320.0
    static let disappearMs = 200.0
    static let peakScale = 1.25
    static let peakAt = 0.6

    struct Metrics {
        var paddingBlock: Double
        var iconBox: Double
        var gap: Double
        var labelLine: Double
        var borderTop: Double
    }

    /// The height of the bar: top line, padding, icon box, gap, one label line, padding.
    static func height(_ metrics: Metrics) -> Double {
        metrics.borderTop + metrics.paddingBlock + metrics.iconBox + metrics.gap + metrics.labelLine + metrics.paddingBlock
    }

    /// The items that are drawn: the first five visible ones.
    static func drawn(visible: [Bool]) -> [Bool] {
        var count = 0
        return visible.map { isVisible in
            if !isVisible || count >= maxItems { return false }
            count += 1
            return true
        }
    }

    /// The share of the bar width of each item: equal parts among the drawn items, the first at
    /// the start of the reading direction; a hidden item has none.
    static func shares(barWidth: Double, visible: [Bool], rightToLeft: Bool) -> [(start: Double, width: Double)?] {
        let flags = drawn(visible: visible)
        let count = flags.filter { $0 }.count
        if count == 0 { return visible.map { _ in nil } }
        let width = max(0, barWidth) / Double(count)
        var position = 0
        return flags.map { isDrawn in
            guard isDrawn else { return nil }
            let index = position
            position += 1
            return (rightToLeft ? barWidth - width * Double(index + 1) : width * Double(index), width)
        }
    }

    // MARK: Sections

    /// The target of a `navigate.section` action: a non-empty `screenId` parameter.
    static func sectionTarget(_ action: JSONObject?) -> String? {
        guard action?["type"]?.stringValue == "navigate.section", let target = action?["params"]?["screenId"]?.stringValue, !target.isEmpty else { return nil }
        return target
    }

    /// An item is active when it switches to the screen that is shown.
    static func isActive(_ action: JSONObject?, shown: String) -> Bool {
        sectionTarget(action) == shown
    }

    /// The stack after a section switch: the target alone; `nil` when it already is the only
    /// screen of the stack.
    static func sectionStack(_ stack: [String], target: String) -> [String]? {
        if stack.count == 1, stack[0] == target { return nil }
        return [target]
    }

    // MARK: The dot

    /// Whether an item shows its dot: a condition the reader understands, and it holds. An
    /// operator the reader does not know, or a condition of another shape, is no dot.
    static func badgeShown(_ props: JSONObject, scope: DataScope) -> Bool {
        guard let condition = props["badgeWhen"] else { return false }
        return Conditions.understoodHolds(condition, scope: scope)
    }

    /// The box of the dot: its centre on the top inline-end corner of the glyph.
    static func badgeBox(glyphLeft: Double, glyphTop: Double, glyphSize: Double, rightToLeft: Bool) -> (left: Double, top: Double, size: Double) {
        let corner = rightToLeft ? glyphLeft : glyphLeft + glyphSize
        return (corner - dotDiameter / 2, glyphTop - dotDiameter / 2, dotDiameter)
    }

    enum BadgeChange: String { case appear, disappear, none }

    /// Whether the dot moves: only when its condition changes its answer on a shown screen, and
    /// not with reduced motion.
    static func badgeChange(shownBefore: Bool, before: Bool, after: Bool, reducedMotion: Bool) -> BadgeChange {
        if !shownBefore || reducedMotion || before == after { return .none }
        return after ? .appear : .disappear
    }

    private static func share(_ t: Double, _ duration: Double) -> Double { min(1, max(0, t / duration)) }

    /// The scale of the dot `t` milliseconds into the appearance: a point, the peak at six
    /// tenths, then settles at one.
    static func appearScale(at t: Double) -> Double {
        let p = share(t, appearMs)
        if p <= peakAt { return peakScale * (p / peakAt) }
        return peakScale + (1 - peakScale) * ((p - peakAt) / (1 - peakAt))
    }

    static func disappearOpacity(at t: Double) -> Double { 1 - share(t, disappearMs) }

    // MARK: Float

    /// Whether the bar floats: it stands in the bottom zone and names `float: true`.
    static func floats(place: String, props: JSONObject) -> Bool {
        place == "bottom" && props["float"]?.boolValue == true
    }

}
