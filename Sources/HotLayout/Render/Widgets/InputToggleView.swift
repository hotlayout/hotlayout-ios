import SwiftUI

/// `Switch` and `Checkbox`: one row, the whole row is the press area. The geometry and the
/// colours are data of the contract (`x-style.layout.inputs`), not the platform's control. The
/// value is read from the layers (`true` is on), a press flips the SHOWN value and writes it at
/// once; the screen reader gets a real toggle.
struct InputToggleWidget: View {
    enum Kind { case toggle, checkbox }

    let node: DocumentNode
    let context: RenderContext
    let kind: Kind

    @State private var state = InputRules.ToggleState()

    var body: some View {
        let look = InputLook(context: context)
        let path = InputRules.path(of: node.props["value"])
        let bound = InputRules.flag(of: path.flatMap { context.scope[$0] })
        let on = InputRules.shownToggle(state, bound: bound)
        let disabled = InputRules.isDisabled(node.props["disabledIf"], scope: context.scope)
        let label = context.text(node, field: "label")
        let required = kind == .checkbox && InputRules.isLiteralTrue(node.props["required"])

        let row = Group {
            switch kind {
            case .toggle: switchRow(look: look, label: label, on: on)
            case .checkbox: checkboxRow(look: look, label: label, on: on, required: required)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { press(bound: bound, path: path, disabled: disabled) }

        row
            .opacity(disabled ? InputRules.disabledOpacity : 1)
            .accessibilityRepresentation {
                Toggle(label, isOn: Binding(get: { on }, set: { _ in press(bound: bound, path: path, disabled: disabled) }))
                    .disabled(disabled)
            }
            .onChange(of: bound) { new in state = InputRules.syncToggle(state, bound: new) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func press(bound: Bool, path: String?, disabled: Bool) {
        let result = InputRules.pressToggle(state, bound: bound, disabled: disabled, hasPath: path != nil)
        state = result.state
        if let write = result.write, let path { context.write?(path, .bool(write)) }
    }

    // MARK: Switch

    private func switchRow(look: InputLook, label: String, on: Bool) -> some View {
        let body = look.bodyStyle
        let trackColor = look.color(on ? "primary" : "muted")
        let thumbColor = look.color(on ? "onPrimary" : "surface")
        return HStack(alignment: .center, spacing: look.spacing("md")) {
            StyledText(text: label, style: body, color: look.color("onSurface"), theme: context.theme)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor.color)
                Circle()
                    .fill(thumbColor.color)
                    .frame(width: InputRules.switchThumbSize, height: InputRules.switchThumbSize)
                    .offset(x: InputRules.thumbOffset(on: on))
            }
            .frame(width: InputRules.switchTrackWidth, height: InputRules.switchTrackHeight)
            .animation(.easeOut(duration: 0.15), value: on)
        }
        .frame(minHeight: InputRules.switchTrackHeight)
    }

    // MARK: Checkbox

    private func checkboxRow(look: InputLook, label: String, on: Bool, required: Bool) -> some View {
        let body = look.bodyStyle
        let side = InputRules.checkboxBoxSize
        let shape = RoundedRectangle(cornerRadius: InputRules.checkboxBoxRadius)
        let accent = look.color(on ? "primary" : "muted")
        let box = ZStack {
            if on { shape.fill(look.color("primary").color) }
            shape.strokeBorder(accent.color, lineWidth: InputRules.checkboxBorderWidth)
            if on {
                // The check mark is not mirrored in right-to-left text.
                IconGlyph(
                    name: "check", glyph: InputRules.checkboxMarkSize, box: CGSize(width: side, height: side), color: look.color("onPrimary").color,
                    rightToLeft: false)
            }
        }
        .frame(width: side, height: side)
        .padding(.top, InputRules.checkboxBoxOffset(labelLine: body.lineBox))
        return HStack(alignment: .top, spacing: look.spacing("sm")) {
            box
            HStack(alignment: .firstTextBaseline, spacing: look.spacing("xs")) {
                StyledText(text: label, style: body, color: look.color("onSurface"), theme: context.theme)
                if required {
                    StyledText(text: "*", style: look.labelStyle, color: look.color("danger"), theme: context.theme)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: side)
    }
}
