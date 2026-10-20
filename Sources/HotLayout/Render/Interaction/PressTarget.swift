import Foundation

/// Who takes a press (`x-style.layout.composition.pressable`) and what a long press is
/// (`x-longPress`): the rules that need no view, so that the shared tables can drive them.
enum PressTarget {
    /// The widgets that hold children and take the field `action` (and `longPress`).
    static let containerTypes: Set<String> = ["Column", "Row", "Container", "Stack"]
    /// Widgets whose own part is a control: the strip of the tabs, the header of an accordion.
    static let ownControlWidgets: Set<String> = ["Tabs", "Accordion"]
    /// Widgets whose own text is the text of their control, which does not name a card around.
    static let ownControlTextWidgets: Set<String> = ["Accordion", "Tab"]
    /// Widgets that take the press as inputs (`input-value` fields).
    static let inputWidgets: Set<String> = ["TextField", "Switch", "Checkbox"]
    /// Widgets that take the field `action` without holding children: the leaves that are buttons.
    static let actionLeaves: Set<String> = ["Button", "IconButton", "NavItem", "ListTile"]

    /// An action does something: a type that is not `none`, or `none` with `track`.
    static func acts(_ action: JSONObject) -> Bool {
        guard let type = action["type"]?.stringValue else { return false }
        return type != "none" || !(action["track"]?.isNull ?? true)
    }

    // MARK: Press

    /// The action of a pressable container, or `nil` when the node is no such control.
    static func pressAction(_ node: DocumentNode) -> JSONObject? {
        guard containerTypes.contains(node.type), let action = node.props["action"]?.objectValue, acts(action) else { return nil }
        return action
    }

    /// The action a node takes on a press: a pressable container, or a list row with an action
    /// (a choice option is not a button of its own).
    static func press(of node: DocumentNode) -> JSONObject? {
        guard node.type == "ListTile" else { return pressAction(node) }
        // An option row belongs to its choice: its press selects, its action is not run.
        guard !isChoiceOption(node), let action = node.props["action"]?.objectValue, acts(action) else { return nil }
        return action
    }

    /// The long press of a container or a list row that does something, or `nil`.
    static func longPress(_ node: DocumentNode) -> JSONObject? {
        // Write actions are not published on a long press, and the reader does not run one there.
        guard acceptsLongPress(node.type), let action = node.props["longPress"]?.objectValue, acts(action),
            !WriteActions.isWriteType(action["type"]?.stringValue)
        else { return nil }
        return action
    }

    /// Whether the widget accepts the field `longPress` at all (a button, an icon button and a
    /// navigation item have one action; a text has none).
    static func acceptsLongPress(_ type: String) -> Bool {
        containerTypes.contains(type) || type == "ListTile"
    }

    /// A container made a control by its action or by its long press.
    static func isPressHost(_ node: DocumentNode) -> Bool {
        pressAction(node) != nil || (containerTypes.contains(node.type) && longPress(node) != nil)
    }

    /// The `value` of a choice option: a list row whose trailing slot is a radio.
    static func isChoiceOption(_ node: DocumentNode) -> Bool {
        node.type == "ListTile" && node.props["trailing"]?["kind"]?.stringValue == "radio"
    }

    /// Whether the node takes the press for itself, so that the cards around get nothing.
    static func ownsPress(_ node: DocumentNode) -> Bool {
        if containerTypes.contains(node.type) { return isPressHost(node) }
        if ownControlWidgets.contains(node.type) { return true }
        if isChoiceOption(node) || inputWidgets.contains(node.type) { return true }
        return hasActionField(node) || longPress(node) != nil
    }

    private static func hasActionField(_ node: DocumentNode) -> Bool {
        actionLeaves.contains(node.type) && node.props["action"]?.objectValue != nil
    }

    /// Whether the node is a button on a finished screen (role and name from its content).
    static func actsOnPress(_ node: DocumentNode) -> Bool {
        if containerTypes.contains(node.type) { return isPressHost(node) }
        return hasActionField(node) || longPress(node) != nil
    }

    /// A widget with an own control takes the press in its own part only, not in its children.
    private static func ownsOnlyItsBox(_ node: DocumentNode) -> Bool {
        ownControlWidgets.contains(node.type) && !isPressHost(node)
    }

    /// The node that takes a press at a point: the innermost control of the chain from the root
    /// to the node under the point.
    static func receiver(chain: [DocumentNode]) -> DocumentNode? {
        guard !chain.isEmpty else { return nil }
        let innermost = chain.count - 1
        for index in stride(from: innermost, through: 0, by: -1) {
            let node = chain[index]
            guard ownsPress(node) else { continue }
            if index < innermost, ownsOnlyItsBox(node) { continue }
            return node
        }
        return nil
    }

    // MARK: Name

    /// Fields of a widget that say something to a person; they name a card around them.
    private static let heardFields: [String: [String]] = [
        "Text": ["content"], "Badge": ["label"], "ListTile": ["title", "subtitle"], "Image": ["alt"], "Icon": ["alt"],
    ]

    /// The accessible name of a pressable container: its `label` first, then the texts of its
    /// content in document order. A control inside names itself; the own text of an accordion
    /// or a tab, and a list from data (no data, no text), are not part of it. Only what is SHOWN
    /// is named: a child that `shown` refuses (a failed `visibleIf`, a width class that does not
    /// list it) is not part of the name, as it is not part of the drawn card. The default asks
    /// the empty data scope and the compact class.
    static func name(
        of node: DocumentNode, shown: (DocumentNode) -> Bool = PressTarget.shownWithoutData, paintOf: ([DocumentNode]) -> SilentText.Paint? = { _ in nil },
        text: (DocumentNode, String) -> String
    ) -> String {
        var parts: [String] = []
        if node.props["label"] != nil {
            let label = ShownText.of(text(node, "label"))
            if !TextHeard.isSilent(label) { parts.append(label) }
        }
        collect(node.children, above: [], shown: shown, paintOf: paintOf, text: text, into: &parts)
        return parts.joined(separator: ", ")
    }

    /// `above` is the nodes between the card and `nodes`: a text that paints nothing (`paintOf` gives
    /// the paint of a chain of nodes) is not said, as a hidden one is not; a node at opacity 0 silences
    /// everything under it, a transparent colour only the text it reaches.
    private static func collect(
        _ nodes: [DocumentNode], above: [DocumentNode], shown: (DocumentNode) -> Bool, paintOf: ([DocumentNode]) -> SilentText.Paint?,
        text: (DocumentNode, String) -> String, into parts: inout [String]
    ) {
        for node in nodes {
            if !shown(node) { continue }
            if ownsPress(node), !ownsOnlyItsBox(node) { continue }
            if node.type == "Repeater" { continue }
            let chain = above + [node]
            let paint = paintOf(chain)
            if let paint, paint.opacityIsZero { continue }
            // A picture is painted with no text colour: a transparent colour does not silence its description.
            let silent = paint.map { node.type == "Image" ? false : SilentText.paintsNothing($0) } ?? false
            if !ownControlTextWidgets.contains(node.type), !silent {
                for field in heardFields[node.type] ?? [] where node.props[field] != nil {
                    // A description (`alt`) may be a plain string, a title is always a bindable one.
                    let value = ShownText.of(node.props[field]?.stringValue ?? text(node, field))
                    if !TextHeard.isSilent(value) { parts.append(value) }
                }
            }
            collect(node.children, above: chain, shown: shown, paintOf: paintOf, text: text, into: &parts)
        }
    }

    static let shownWithoutData: (DocumentNode) -> Bool = { WidthRules.isShown($0, .compact, scope: [:]) }


    /// Whether a container has a control inside (then its children stay separate elements).
    static func containsControl(_ node: DocumentNode) -> Bool {
        node.children.contains { child in ownsPress(child) || containsControl(child) }
    }
}

/// The text that paints nothing (`x-silentText`): the resolved `style.opacity` is exactly 0 on the text
/// or on a node between the card and it, or the colour the text is painted in resolves with opacity 0.
/// Zero only: 0.01 is seen.
enum SilentText {
    /// The resolved `style.opacity` of each node from the first inside the card to the text, and the
    /// opacity of the text's colour (`nil`: it did not resolve).
    struct Paint: Equatable {
        let opacities: [Double?]
        let colorOpacity: Double?

        var opacityIsZero: Bool { opacities.contains { $0 == 0 } }
    }

    /// The rule as a function of the resolved paint.
    static func paintsNothing(_ paint: Paint) -> Bool { paint.opacityIsZero || paint.colorOpacity == 0 }

    static func paintsNothing(opacities: [Double?], colorOpacity: Double?) -> Bool {
        paintsNothing(Paint(opacities: opacities, colorOpacity: colorOpacity))
    }

    /// The paint of a text from the resolved style of the nodes between the card and it; `look` is the
    /// look the card already passes down, so the card itself is not judged.
    static func paint(chain: [DocumentNode], context: RenderContext) -> Paint {
        var look = context.inherited
        let opacities = chain.map { node -> Double? in
            let style = NodeStyle.effective(node, scope: context.scope)
            look = NodeStyle.inherited(look, style: style, resolver: context.resolver)
            return style["opacity"]?.numberValue.map { StyleResolver.clamp($0, 0, 1) }
        }
        return Paint(opacities: opacities, colorOpacity: look.color.alpha)
    }
}

/// The long press (`x-longPress`): threshold, slop, what a hold came to, the keys.
enum LongPressRules {
    static let thresholdMs = 450.0
    static let touchSlop = 10.0
    /// A click that follows the release of a gesture that fired is the same touch (ms).
    static let clickAfterFireWindowMs = 400.0
    static let order = ["haptic", "track", "action"]

    enum Outcome: String, Equatable { case longPress, press, none }

    static func outcome(heldMs: Double, moved: Double, cancelled: Bool, hasLongPress: Bool, hasAction: Bool) -> Outcome {
        if cancelled || moved > touchSlop { return .none }
        if hasLongPress, heldMs >= thresholdMs { return .longPress }
        return hasAction ? .press : .none
    }

    /// The keys that perform the long press at once on the focused node.
    static func isLongPressKey(_ key: String, shift: Bool) -> Bool {
        key == "ContextMenu" || (key == "F10" && shift)
    }

    /// A held key performs it once: the auto-repeat does nothing.
    static func keyPerforms(_ key: String, shift: Bool, repeating: Bool) -> Bool {
        !repeating && isLongPressKey(key, shift: shift)
    }

    /// Whether a click swallowed because it is the click of the release of a gesture that fired.
    static func swallowsClick(fired: Bool, released: Bool, sinceReleaseMs: Double, newPointerDown: Bool) -> Bool {
        fired && released && !newPointerDown && sinceReleaseMs <= clickAfterFireWindowMs
    }
}
