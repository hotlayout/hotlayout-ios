import SwiftUI

/// What the fields and controls of one screen share: the root of the screen (its form), the data
/// layers of the screen without a list instance's record, the order of the text fields for the
/// «next» key, and which field has the keyboard.
struct ScreenForm {
    let root: DocumentNode
    let scope: DataScope
    let order: [InputOrder.Entry]
    /// The host turned autofill hints off.
    var autofill = true
    /// Which text field has focus (by node id); `nil` when the screen has none.
    var focus: Binding<String?>?
    /// The width class of the screen: a field hidden by it is not counted.
    var widthClass = WidthClass.compact

    /// Whether the form of the screen is filled.
    var isFilled: Bool { FormRules.isFormFilled(root: root, scope: scope, widthClass: widthClass) }
}

/// The choice owned by a choice group, as the rows inside it see it.
struct ChoiceScope {
    /// The name of the selected option; `nil` for «nothing selected», a legal state.
    let selected: String?
    let select: (String) -> Void
}

extension RenderContext {
    /// The value under a path in the data scope of this node, for a write action.
    func value(at path: String) -> JSONValue? { scope[path] }
}

/// What a node with a write action is on the finished screen: an option that is selected, or a
/// toggle that is on (the state is recomputed from the action and the data on every draw). The
/// look of «selected» is the node's own `styleWhen`; the reader adds none.
struct WriteControlTraits: ViewModifier {
    let node: DocumentNode
    let context: RenderContext

    func body(content: Content) -> some View {
        if let action = WriteActions.pressAction(of: node), WriteActions.isWriteType(action["type"]?.stringValue),
            let control = WriteActions.control(of: action, read: { context.scope[$0] })
        {
            content.accessibilityAddTraits(control.on ? .isSelected : [])
        } else {
            content
        }
    }
}

private struct FieldTailKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// What the body of the screen keeps under its last child: the gap of the screen above a pinned
    /// block, the bottom padding of the root without one. A focused field is brought into view with
    /// this much room under it (and under the line below it), not flush with the edge of the area.
    var fieldTail: CGFloat {
        get { self[FieldTailKey.self] }
        set { self[FieldTailKey.self] = newValue }
    }
}
