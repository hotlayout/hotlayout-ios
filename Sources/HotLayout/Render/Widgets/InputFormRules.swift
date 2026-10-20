import Foundation

/// The form of a screen: a «required» field, whether the form is filled, and a button that is
/// disabled until the form is filled or while a condition holds (`x-style.layout.form`).
///
/// «Filled» is a question about the value UNDER the path of the field, read through the data
/// layers, not about the state of a widget: the field writes on every change, so the session and
/// the field say the same thing, and the answer is a function of the document and the layers.
enum FormRules {
    /// What «filled» asks about. There is no switch here: it always has a value, so a «required
    /// switch» would require nothing.
    enum Kind: String { case text, number, flag, choice }

    static func isFilled(_ kind: Kind, value: JSONValue?) -> Bool {
        switch kind {
        case .text, .choice: return !TextHeard.isSilent(InputRules.text(of: value))
        case .number: return InputRules.readNumber(value) != nil
        case .flag: return InputRules.flag(of: value)
        }
    }

    /// A required field of a screen: just enough to answer «is it filled and does it count».
    struct Field: Equatable {
        var nodeId: String
        var kind: Kind
        /// `nil`: a field without a path is never filled.
        var path: String?
        /// The `visibleIf` of the node and of all its ancestors; one that fails hides the field.
        var visibleIf: [JSONValue]
        var disabledIf: JSONValue?
        /// The node or an ancestor is not shown on the width class of the screen (`showOn`).
        var hiddenByClass = false
        /// The fallback text of a choice group's binding: with no data the group shows the option
        /// of that name as selected, so "filled" has to see it too.
        var fallback: String?
    }

    /// The required fields of a screen in document order. A screen is the root of one `screens[]`
    /// entry (app bar, body, pinned block and navigation bar together); a modal layer is a
    /// separate entry. The subtree of a list from data is not included; a field in a tab that is
    /// not open IS included.
    static func requiredFields(of root: DocumentNode, widthClass: WidthClass = .compact) -> [Field] {
        var found: [Field] = []
        func walk(_ node: DocumentNode, inherited: [JSONValue], hidden: Bool) {
            let hidden = hidden || !WidthRules.showsOn(node, widthClass)
            var own = inherited
            if let condition = node.visibleIf, !condition.isNull { own.append(condition) }
            switch node.type {
            case "TextField" where InputRules.isLiteralTrue(node.props["required"]):
                let numeric = InputRules.isNumber(valueType: node.props["valueType"])
                found.append(
                    Field(
                        nodeId: node.id, kind: numeric ? .number : .text, path: InputRules.path(of: node.props["value"]), visibleIf: own,
                        disabledIf: node.props["disabledIf"], hiddenByClass: hidden))
            case "Checkbox" where InputRules.isLiteralTrue(node.props["required"]):
                found.append(
                    Field(
                        nodeId: node.id, kind: .flag, path: InputRules.path(of: node.props["value"]), visibleIf: own, disabledIf: node.props["disabledIf"],
                        hiddenByClass: hidden))
            case "ChoiceGroup" where InputRules.isLiteralTrue(node.props["required"]):
                found.append(
                    Field(
                        nodeId: node.id, kind: .choice, path: InputRules.path(of: node.props["value"]), visibleIf: own, disabledIf: nil, hiddenByClass: hidden,
                        fallback: InputRules.fallback(of: node.props["value"])))
            default: break
            }
            if node.type == "Repeater" { return }
            for child in node.children { walk(child, inherited: own, hidden: hidden) }
        }
        walk(root, inherited: [], hidden: false)
        return found
    }

    /// The value «filled» asks about. For a choice group an empty string and an absent value give
    /// the binding's fallback text, which is exactly the option the group shows as selected.
    private static func shownValue(of field: Field, _ value: JSONValue?) -> JSONValue? {
        guard field.kind == .choice, let fallback = field.fallback else { return value }
        return InputRules.text(of: value).isEmpty ? .string(fallback) : value
    }

    /// Whether the form of the screen is filled. `scope` is the data layers of THIS screen
    /// (the record it was opened with, session, host, data), without a list instance's record.
    /// With no required fields at all the form is filled.
    static func isFormFilled(root: DocumentNode, scope: DataScope, widthClass: WidthClass = .compact) -> Bool {
        for field in requiredFields(of: root, widthClass: widthClass) {
            let shown = !field.hiddenByClass && field.visibleIf.allSatisfy { Conditions.isVisible($0, scope: scope) }
            if !shown || InputRules.isDisabled(field.disabledIf, scope: scope) { continue }
            guard let path = field.path else { return false }
            if !isFilled(field.kind, value: shownValue(of: field, scope[path])) { return false }
        }
        return true
    }

    /// Whether a button is disabled: at least one of two holds — `disabledIf`, or `requiresFilled`
    /// on an unfilled form. The form is computed only for a button that asks about it.
    static func isPressDisabled(requiresFilled: Bool, disabledIf: JSONValue?, scope: DataScope, formFilled: () -> Bool) -> Bool {
        if InputRules.isDisabled(disabledIf, scope: scope) { return true }
        return requiresFilled && !formFilled()
    }

    /// What a choice in a group writes: the value at the binding's path. A group whose value is
    /// not a binding writes nowhere; an option already SHOWN as selected is not written again.
    static func choiceWrite(path: String?, picked: String, shown: String?) -> (path: String, value: String)? {
        guard let path, picked != shown else { return nil }
        return (path, picked)
    }
}

/// The text fields of a screen in document order, for the key of the keyboard («next» / «done»).
enum InputOrder {
    struct Entry: Equatable {
        var nodeId: String
        var focusable: InputRules.Focusable
    }

    /// The shown text fields of a screen: reachable means shown and not disabled. A field inside
    /// a list from data is not part of the order.
    static func fields(of root: DocumentNode, scope: DataScope, widthClass: WidthClass = .compact) -> [Entry] {
        var found: [Entry] = []
        func walk(_ node: DocumentNode, visible: Bool) {
            let shown = visible && WidthRules.isShown(node, widthClass, scope: scope)
            if node.type == "TextField" {
                let numeric = InputRules.isNumber(valueType: node.props["valueType"])
                let multiline = InputRules.effectiveLines(node.props["lines"], numeric: numeric) > 1
                found.append(
                    Entry(
                        nodeId: node.id,
                        focusable: .init(multiline: multiline, reachable: shown && !InputRules.isDisabled(node.props["disabledIf"], scope: scope))))
            }
            if node.type == "Repeater" { return }
            for child in node.children { walk(child, visible: shown) }
        }
        walk(root, visible: true)
        return found
    }
}
