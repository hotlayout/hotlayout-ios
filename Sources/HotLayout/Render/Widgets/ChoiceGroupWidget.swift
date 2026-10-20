import SwiftUI

/// `ChoiceGroup`: the rows inside it that carry a `radio` slot choose one option. The group owns
/// the state; a group with a BOUND `value` also writes the choice under that path (to the
/// session and the host at the same moment). A literal `value` has nowhere to write: the tap
/// stays local.
struct ChoiceGroupWidget: View {
    let node: DocumentNode
    let context: RenderContext
    let depth: Int

    @State private var selected: String?
    @State private var seen: String?

    /// The name of the option the document says is selected. Not translated and not trimmed: it
    /// is compared with the `optionValue` of a row, not shown to a person.
    private var documentValue: String {
        BindableText.text(
            node.props["value"], language: context.language(node: node, field: "value"), environment: context.textEnvironment,
            sink: context.sink, location: "screen “\(context.screenId)”: node “\(node.id)”: value"
        )
    }

    var body: some View {
        let value = documentValue
        let path = InputRules.path(of: node.props["value"])
        let shownNow: String? = seen == value ? selected : (value.isEmpty ? nil : value)
        let scope = ChoiceScope(selected: shownNow, select: { choose($0, shown: shownNow, path: path, document: value) })
        var inner = context
        inner.choice = scope
        return ColumnView(
            children: node.children, gap: context.resolver.spacing(node.props["gap"] ?? "none") ?? 0,
            node: nil, space: HostSpace(), context: inner, depth: depth
        )
        .accessibilityElement(children: .contain)
    }

    private func choose(_ option: String, shown: String?, path: String?, document: String) {
        selected = option
        seen = document
        // The write goes after the local state. An option already SHOWN as selected (also by the
        // fallback text of the binding) is not written a second time.
        if let write = FormRules.choiceWrite(path: path, picked: option, shown: shown) {
            context.write?(write.path, .string(write.value))
        }
    }
}

/// The mark of a choice option: a ring, and a dot when selected. Painted, not an icon of the set.
struct ChoiceOptionMark: View {
    let selected: Bool
    let size: Double
    let selectedColor: Color
    let mutedColor: Color

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 24
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let color = selected ? selectedColor : mutedColor
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - 9 * unit, y: center.y - 9 * unit, width: 18 * unit, height: 18 * unit)), with: .color(color),
                lineWidth: 2 * unit)
            if selected {
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5 * unit, y: center.y - 5 * unit, width: 10 * unit, height: 10 * unit)), with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
