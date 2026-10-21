import SwiftUI

/// A container (or a list row) that is a button as a whole: the press of `action`, the long
/// press of `longPress`, the pose of its feedback, and one element for assistive technology
/// named by `label` first and then by its content.
///
/// The gestures sit on the card; a control inside has its own and, being deeper, takes the
/// touch: the card then gets nothing (neither the action nor the analytics event).
struct PressableCard<Content: View>: View {
    let node: DocumentNode
    let context: RenderContext
    let content: Content

    @State private var pressing = false

    var body: some View {
        // A button on a finished screen exactly when the table of the contract says so.
        if PressTarget.actsOnPress(node) {
            card(press: PressTarget.press(of: node), long: PressTarget.longPress(node))
        } else {
            content
        }
    }

    private func card(press: JSONObject?, long: JSONObject?) -> some View {
        let name =
            node.widget == .listTile
            ? ["title", "subtitle"].filter { node.props[$0] != nil }.map { ShownText.of(context.text(node, field: $0)) }.filter { !$0.isEmpty }.joined(
                separator: ", ")
            : PressTarget.name(of: node, shown: { context.isShown($0) }, paintOf: { SilentText.paint(chain: $0, context: context) }) {
                context.text($0, field: $1)
            }
        let longLabel = ShownText.of(context.text(node, field: "longPressLabel"))
        let runPress = { if let press { context.press(press, node) } }
        let runLong = { if let long { context.press(long, node) } }
        return PressablePose(kind: PressFeedbackRules.kind(node), pressed: pressing) {
            content.contentShape(Rectangle())
        }
        .onTapGesture { runPress() }
        .onLongPressGesture(
            minimumDuration: long == nil ? 3600 : LongPressRules.thresholdMs / 1000,
            maximumDistance: LongPressRules.touchSlop,
            perform: { runLong() },
            onPressingChanged: { pressing = $0 }
        )
        .accessibilityElement(children: PressTarget.containsControl(node) ? .contain : .ignore)
        .modifier(CardName(name: name))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { runPress() }
        .modifier(LongPressAction(label: TextHeard.isSilent(longLabel) ? nil : longLabel, run: long == nil ? nil : runLong))
        .modifier(KeyboardPress(onPress: press == nil ? nil : runPress, onLongPress: long == nil ? nil : runLong))
    }
}

private struct CardName: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        if name.isEmpty { content } else { content.accessibilityLabel(name) }
    }
}

/// The long press for a screen reader: a custom action named by `longPressLabel`.
private struct LongPressAction: ViewModifier {
    let label: String?
    let run: (() -> Void)?

    func body(content: Content) -> some View {
        if let label, let run {
            content.accessibilityAction(named: Text(label)) { run() }
        } else {
            content
        }
    }
}

/// Enter and Space press at once, the context menu key and Shift+F10 perform the long press at
/// once; a held key repeats nothing (`keyAutoRepeat`).
private struct KeyboardPress: ViewModifier {
    let onPress: (() -> Void)?
    let onLongPress: (() -> Void)?

    func body(content: Content) -> some View {
        #if os(iOS) || os(macOS)
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .focusable()
                .onKeyPress(phases: [.down, .repeat]) { press in
                    let repeating = press.phase == .repeat
                    if press.key == .return || press.key == .space {
                        if !repeating { onPress?() }
                        return onPress == nil ? .ignored : .handled
                    }
                    let name = Self.keyName(press)
                    if let name, onLongPress != nil, LongPressRules.isLongPressKey(name, shift: press.modifiers.contains(.shift)) {
                        if LongPressRules.keyPerforms(name, shift: press.modifiers.contains(.shift), repeating: repeating) { onLongPress?() }
                        return .handled
                    }
                    return .ignored
                }
        } else {
            content
        }
        #else
        content
        #endif
    }

    /// `F10` and the context menu key arrive as private-use characters of the function keys.
    @available(iOS 17.0, macOS 14.0, *)
    private static func keyName(_ press: KeyPress) -> String? {
        switch press.characters.unicodeScalars.first?.value {
        case 0xF70D: return "F10"
        case 0xF735: return "ContextMenu"
        default: return nil
        }
    }
}
