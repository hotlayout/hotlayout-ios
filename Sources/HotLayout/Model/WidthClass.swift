import Foundation

/// The width class of a screen (`x-style.layout.widthClass`). There are three and no fourth: a
/// very wide box is still `expanded`.
enum WidthClass: String, CaseIterable, Sendable {
    case compact, medium, expanded

    /// Where each class starts, in logical points. The numbers are data of the artifact, not a
    /// setting: a theme cannot move them (`customisable: 'no'`).
    var from: Double {
        switch self {
        case .compact: return 0
        case .medium: return 600
        case .expanded: return 1024
        }
    }

    /// The class while the width is unknown (`unknownWidth`).
    static let unknown = WidthClass.compact

    /// The class of the box the screen is drawn in. The width is NOT rounded: 599.9 is `compact`,
    /// 600 is `medium`. A width that is not a finite non-negative number is «unknown».
    static func of(width: Double?) -> WidthClass {
        guard let width, width.isFinite, width >= 0 else { return unknown }
        if width >= WidthClass.expanded.from { return .expanded }
        return width >= WidthClass.medium.from ? .medium : .compact
    }

    /// The layers of `styleOn` / `propsOn` that act in this class, in the order they are laid on:
    /// the cascade runs from narrow to wide.
    var layers: [WidthClass] {
        switch self {
        case .compact: return []
        case .medium: return [.medium]
        case .expanded: return [.medium, .expanded]
        }
    }

    /// Whether the class is wide (a place for the navigation bar at the top and a window for a sheet).
    var isWide: Bool { self != .compact }
}

/// The rules of the width classes that are not about one widget: who is shown where, which props a
/// class may override, how wide the content of a screen is.
enum WidthRules {
    // MARK: Visibility

    /// The classes a node NAMED in `showOn`. `nil`: no field, a field of another shape (not a list,
    /// empty), or no known word (classes of a newer minor): the node is shown everywhere.
    static func showOn(_ fields: JSONObject) -> [WidthClass]? {
        guard let list = fields["showOn"]?.arrayValue, !list.isEmpty else { return nil }
        let known = list.compactMap { $0.stringValue.flatMap(WidthClass.init(rawValue:)) }
        return known.isEmpty ? nil : known
    }

    static func showsOn(_ node: DocumentNode, _ widthClass: WidthClass) -> Bool {
        showOn(node.fields)?.contains(widthClass) ?? true
    }

    /// Whether a node is shown: the class is listed AND `visibleIf` holds. THE one question every
    /// place of the contract that asks «visible» puts (zones, bar actions, nav items, numbering,
    /// forms, tabs, layers, weights, carousel cards).
    static func isShown(_ node: DocumentNode, _ widthClass: WidthClass, scope: DataScope) -> Bool {
        showsOn(node, widthClass) && Conditions.isVisible(node.visibleIf, scope: scope)
    }

    // MARK: Props

    /// The closed list of props each widget lets a width class override (`widthClass.props.byWidget`).
    /// A widget that is not here has none: its `propsOn` is not read.
    static let responsiveProps: [String: [String]] = [
        "Screen": ["gap", "align", "justify", "contentMaxWidth"],
        "Column": ["gap", "align", "justify"],
        "Row": ["gap", "align", "justify", "carousel"],
        "Container": ["direction", "gap", "align", "justify"],
        "Grid": ["columns", "gap"],
        "Repeater": ["direction", "columns", "gap", "carousel"],
    ]

    /// The props a layer may REMOVE with `unset`: those whose absence is a state of its own.
    static let unsettableProps: [String: [String]] = ["Screen": ["contentMaxWidth"]]

    /// The names `unset` lists for a layer. A carrier or a list of another shape removes nothing;
    /// an entry that is not a string is skipped.
    static func unsetNames(_ carrier: JSONValue?, layer: WidthClass) -> [String] {
        guard let list = carrier?["unset"]?[layer.rawValue]?.arrayValue else { return [] }
        return list.compactMap(\.stringValue)
    }

    /// The object without the named keys (only those in `allowed`, when given).
    static func without(_ object: JSONObject, names: [String], allowed: [String]? = nil) -> JSONObject {
        var result = object
        for name in names where allowed?.contains(name) ?? true { result[name] = nil }
        return result
    }

    /// The layer of a carrier (`styleOn`, `propsOn`) for a class: an object, or nothing.
    static func layer(_ carrier: JSONValue?, _ widthClass: WidthClass) -> JSONObject? {
        carrier?.objectValue?[widthClass.rawValue]?.objectValue
    }

    struct EffectiveProps {
        var props: JSONObject
        /// `columns` came from a layer: its bounds are 1…6, not the base's 2…4.
        var columnsFromOverride = false
    }

    /// The props of a node in a class: the base with the `propsOn` layers laid on, from narrow to
    /// wide. A layer replaces only the keys it names, and only keys of the closed list of the
    /// widget; `null` does not override; a carousel is overridden by `perView` alone, and only where
    /// the base already has one.
    static func effectiveProps(type: String, props: JSONObject, propsOn: JSONValue?, widthClass: WidthClass) -> EffectiveProps {
        guard let allowed = responsiveProps[type], !widthClass.layers.isEmpty else { return EffectiveProps(props: props) }
        var result = props
        var columns = false
        for layer in widthClass.layers {
            // What the layer removes goes first, what it names after: named and removed means named.
            result = without(result, names: unsetNames(propsOn, layer: layer), allowed: unsettableProps[type] ?? [])
            guard let override = Self.layer(propsOn, layer) else { continue }
            for key in allowed {
                guard let value = override[key], let next = overlaid(key, below: result[key], value: value) else { continue }
                result[key] = next
                if key == "columns" { columns = true }
            }
        }
        return EffectiveProps(props: result, columnsFromOverride: columns)
    }

    /// One value laid over the current one; `nil` — the layer does not override this key.
    private static func overlaid(_ key: String, below: JSONValue?, value: JSONValue) -> JSONValue? {
        if value.isNull { return nil }
        guard key == "carousel" else { return value }
        guard var base = below?.objectValue, let perView = value.objectValue?["perView"], !perView.isNull else { return nil }
        base["perView"] = perView
        return .object(base)
    }

    // MARK: Style

    /// The base style of a node in a class: `style` with the `styleOn` layers laid on (fields of
    /// the top level are replaced whole), WITHOUT the states. `nil` when nothing is left.
    static func baseStyle(fields: JSONObject, widthClass: WidthClass) -> JSONObject? {
        var result = fields["style"]?.objectValue
        let carrier = fields["styleOn"]
        for layer in widthClass.layers {
            if let current = result {
                let kept = without(current, names: unsetNames(carrier, layer: layer))
                result = kept.isEmpty ? nil : kept
            }
            guard let overlay = Self.layer(carrier, layer) else { continue }
            var merged = result ?? JSONObject()
            for (key, value) in overlay { merged[key] = value }
            result = merged
        }
        guard let result, !result.isEmpty else { return nil }
        return result
    }

    // MARK: Content column

    static let contentMaxWidthRange = 320.0...1920.0

    /// The largest content width as the reader reads it: a whole number, clamped into the bounds of
    /// the schema; any other value is no field.
    static func contentMaxWidth(_ value: JSONValue?) -> Double? {
        guard let number = value?.numberValue, number == number.rounded() else { return nil }
        return min(contentMaxWidthRange.upperBound, max(contentMaxWidthRange.lowerBound, number))
    }

    struct ContentBox: Equatable {
        var start: Double
        var width: Double
    }

    /// The column of the content: no wider than the number, centred; half of the remainder is not
    /// rounded. A screen narrower than the number is unchanged.
    static func contentBox(available: Double, maxWidth: Double?) -> ContentBox {
        let space = max(0, available)
        guard let maxWidth, maxWidth < space else { return ContentBox(start: 0, width: space) }
        return ContentBox(start: (space - maxWidth) / 2, width: maxWidth)
    }

    struct InlineRect: Equatable {
        var x: Double
        var width: Double
    }

    struct ContentRects: Equatable {
        var body: InlineRect
        var pinned: InlineRect
        var appBar: InlineRect
        var navBar: InlineRect
    }

    /// Where the content of each zone stands along the width, from the LEFT edge of the root box in
    /// either direction: body and pinned block are a column in the root box without its inline
    /// padding; the app bar keeps its box between the paddings and its content is a column in its
    /// own content box; the bar of navigation runs edge to edge and its items are such a column.
    static func contentRects(
        width: Double, paddingStart: Double, paddingEnd: Double, maxWidth: Double?,
        appBarInset: (start: Double, end: Double) = (0, 0), navBarInset: (start: Double, end: Double) = (0, 0), rightToLeft: Bool
    ) -> ContentRects {
        func column(outer: Double, inset: (start: Double, end: Double), before: Double) -> InlineRect {
            let box = contentBox(available: outer - inset.start - inset.end, maxWidth: maxWidth)
            let start = before + inset.start + box.start
            return InlineRect(x: rightToLeft ? width - start - box.width : start, width: box.width)
        }
        let inside = width - paddingStart - paddingEnd
        let body = column(outer: width, inset: (paddingStart, paddingEnd), before: 0)
        return ContentRects(
            body: body, pinned: body,
            appBar: column(outer: inside, inset: appBarInset, before: paddingStart),
            navBar: column(outer: width, inset: navBarInset, before: 0)
        )
    }
}
