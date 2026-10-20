import Foundation

/// The tree as the reader sees it in a width class.
///
/// `propsOn` and `styleOn` are overrides, not a second layout: everything the contract says about a
/// node (who accepts weights, where the main axis is, how many columns) it says about the EFFECTIVE
/// props and style. So the reader does not teach every rule the word «class»: it resolves the tree
/// for its class first and then draws an ordinary document. `showOn` stays a field of the node
/// (whether a node is shown also depends on the data) and is answered by `WidthRules.isShown`.
extension DocumentNode {
    /// The node with its subtree in a class: effective props, a base style with the width layers,
    /// no `propsOn` / `styleOn`. `compact` is the node itself: the base of the document is the phone.
    func inWidthClass(_ widthClass: WidthClass) -> DocumentNode {
        if widthClass == .compact { return self }
        let effective = WidthRules.effectiveProps(type: type, props: props, propsOn: fields["propsOn"], widthClass: widthClass)
        var resolved = fields
        resolved["propsOn"] = nil
        resolved["styleOn"] = nil
        resolved["style"] = WidthRules.baseStyle(fields: fields, widthClass: widthClass).map(JSONValue.object)
        return DocumentNode(
            id: id, type: type, props: effective.props, fields: resolved,
            children: children.map { $0.inWidthClass(widthClass) }, columnsFromOverride: effective.columnsFromOverride
        )
    }
}
