import Foundation

/// The bottom safe inset of a modal sheet (`x-style.layout.sheetSafeBottom`). A sheet reaches the
/// physical bottom of the area, and the home indicator or the gesture bar of the platform lies
/// over it, so the reader adds the inset INSIDE the box of the sheet, under its content: the
/// background and the radius extend under the inset, the last node stands above it. The inset is
/// added once: under the content of the bottom zone when the sheet shows a pinned block, else as
/// room under the content of the root. A window and a sheet shown as a window get none.
enum SheetSafeBottom {
    /// Where the inset lies: room under the content of the root, or under the content of the zone.
    struct Place: Equatable {
        var root: Double
        var zone: Double
    }

    /// The inset as the reader takes it: not a number, not finite or negative is zero. A host that
    /// accounted for the inset itself gives zero.
    static func inset(_ value: JSONValue?) -> Double {
        guard let number = value?.numberValue else { return 0 }
        return inset(number)
    }

    static func inset(_ number: Double) -> Double { number.isFinite && number > 0 ? number : 0 }

    /// For a layer already known to be a sheet: the zone when there is one, else the root; never both.
    static func place(inset value: Double, bottomZone: Bool) -> Place {
        let inset = Self.inset(value)
        if inset == 0 { return Place(root: 0, zone: 0) }
        return bottomZone ? Place(root: 0, zone: inset) : Place(root: inset, zone: 0)
    }

    /// Where the reader adds the inset of a screen. A page keeps the rule of the bottom zone.
    static func place(presentation: String?, placement: JSONValue?, areaWidth: Double, safeBottom: JSONValue?, bottomZone: Bool) -> Place {
        let value = inset(safeBottom)
        if presentation != "modal" { return bottomZone && value > 0 ? Place(root: 0, zone: value) : Place(root: 0, zone: 0) }
        guard WideChrome.modalShape(placement: placement, areaWidth: areaWidth) == .sheet else { return Place(root: 0, zone: 0) }
        return place(inset: value, bottomZone: bottomZone)
    }

    struct Box: Equatable {
        var y: Double
        var height: Double
        var contentBottom: Double
        var scrolls: Bool
    }

    /// The box of a sheet with the inset inside it: as tall as content plus inset, no taller than
    /// the area; taller content scrolls above the inset.
    static func box(areaHeight: Double, contentHeight: Double, safeBottom: JSONValue?) -> Box {
        let area = max(0, areaHeight)
        let inset = min(Self.inset(safeBottom), area)
        let natural = max(0, contentHeight) + inset
        let height = min(natural, area)
        return Box(y: area - height, height: height, contentBottom: height - inset, scrolls: natural > area)
    }
}
