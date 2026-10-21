import SwiftUI

/// The theme values the three input widgets are drawn from (`x-style.layout.inputs`): colours
/// and text styles are taken from the theme by name, not from the style of the node.
struct InputLook {
    let context: RenderContext

    private var theme: HotlayoutTheme { context.theme }
    func color(_ token: String) -> RGBA { theme.coreColor(token) }
    func spacing(_ token: String) -> Double { theme.coreSpacing(token) }
    var labelStyle: TextStyleValue { theme.coreTypography("bodyS") }
    var bodyStyle: TextStyleValue { theme.coreTypography("bodyM") }
    var radius: Double { theme.coreRadius(InputPartsRules.defaultRadius) }
    var counterStyle: TextStyleValue { theme.typography[InputPartsRules.counterTypography] ?? labelStyle }
    var affixStyle: TextStyleValue { theme.typography[InputPartsRules.affixTypography] ?? bodyStyle }
}

/// `TextField`: a label above the box, the box with the field, a line under it (the error that
/// can be heard, else the helper). The value is read from the data layers and written on every
/// change; what the person types is held until the layer value changes (`InputRules`).
struct InputTextFieldWidget: View {
    let node: DocumentNode
    let context: RenderContext

    @State private var state = InputRules.TextState()
    @State private var wasFocused = false
    /// Bumped on every report of the native control and handed to it: the control is made to show
    /// what the rules hold even when that is what it held before (a text cut to the limit).
    @State private var revision = 0
    @State private var localFocus: String?
    /// The stand-in field of macOS takes the focus from SwiftUI; the native control of iOS from UIKit.
    @FocusState private var standInFocus: String?

    var body: some View {
        let look = InputLook(context: context)
        let numeric = InputRules.isNumber(valueType: node.props["valueType"])
        let path = InputRules.path(of: node.props["value"])
        let bound = path.flatMap { context.scope[$0] }
        let boundText = numeric ? "" : InputRules.text(of: bound)
        let shown = numeric ? InputRules.shownNumber(state, bound: bound) : InputRules.shownText(state, bound: boundText)
        let disabled = InputRules.isDisabled(node.props["disabledIf"], scope: context.scope)
        let errorText = InputRules.error(node.props["error"] == nil ? nil : context.text(node, field: "error"))
        let helper = node.props["helper"] == nil ? "" : context.text(node, field: "helper")
        let invalid = errorText != nil || (numeric && InputRules.numberInvalid(state, bound: bound))
        let label = context.text(node, field: "label")
        let required = InputRules.isLiteralTrue(node.props["required"])
        let lines = InputRules.effectiveLines(node.props["lines"], numeric: numeric)
        let focus = context.form?.focus ?? $localFocus
        let focused = focus.wrappedValue == node.id
        let xs = look.spacing("xs")
        let note = errorText ?? helper
        let counter = InputPartsRules.counterText(counter: node.props["counter"], maxLength: node.props["maxLength"], shown: shown)

        VStack(alignment: .leading, spacing: xs) {
            labelRow(label: label, required: required, look: look)
            box(
                look: look, shown: shown, lines: lines, numeric: numeric, focus: focus, focused: focused, invalid: invalid, disabled: disabled, label: label,
                note: note, counter: counter)
            noteRow(note: note, isError: errorText != nil, counter: counter, look: look)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(disabled ? InputRules.disabledOpacity : 1)
        .onChange(of: boundText) { new in
            if !numeric { state = InputRules.sync(state, bound: new) }
        }
        .onChange(of: disabled) { nowDisabled in
            guard nowDisabled else { return }
            state = InputRules.step(state, .blur, bound: boundText, disabled: true).state
            if focus.wrappedValue == node.id { focus.wrappedValue = nil }
        }
        .onChange(of: focused) { now in
            guard now != wasFocused else { return }
            wasFocused = now
            apply(now ? .focus : .blur, numeric: numeric, bound: bound, boundText: boundText, path: path, disabled: disabled)
        }
        .id(node.id)
    }

    // MARK: Parts

    @ViewBuilder
    private func labelRow(label: String, required: Bool, look: InputLook) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: look.spacing("xs")) {
            StyledText(text: label, style: look.labelStyle, color: look.color("muted"), theme: context.theme)
            if required {
                StyledText(text: "*", style: look.labelStyle, color: look.color("danger"), theme: context.theme)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// The row under the box: the note (helper or error) from the start takes the rest and wraps; the
    /// counter stands at the end, one line that does not shrink. Without a note the row holds the counter.
    @ViewBuilder
    private func noteRow(note: String, isError: Bool, counter: String?, look: InputLook) -> some View {
        if !note.isEmpty || counter != nil {
            let gap = look.spacing(InputPartsRules.gapToken)
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                if note.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    StyledText(text: note, style: look.labelStyle, color: look.color(isError ? "danger" : "muted"), theme: context.theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }
                if let counter {
                    // One string in the direction of the screen; the spaces around the slash stay.
                    Text(verbatim: counter)
                        .font(look.counterStyle.font(family: context.theme.fontFamilies["body"]))
                        .foregroundColor(look.color(InputPartsRules.quietColor).color)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                        .environment(\.layoutDirection, context.rightToLeft ? .rightToLeft : .leftToRight)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The text of a mark as the field shows it: translated and filled from the data, cut to eight code points.
    private func markText(_ value: JSONValue?, field: String) -> String {
        InputPartsRules.affixText(
            ShownText.of(
                BindableText.text(
                    value, language: context.language(node: node, field: field), environment: context.textEnvironment, sink: context.sink,
                    location: "screen “\(context.screenId)”: node “\(node.id)”: \(field)"
                )))
    }

    /// A mark that is drawn: a text that is not empty, or an icon (a name outside the set is an empty box).
    private enum Mark: Equatable {
        case text(String)
        case icon(String)
    }

    private func mark(_ prop: String) -> Mark? {
        switch InputPartsRules.affix(node.props[prop]) {
        case .text(let value)?:
            let text = markText(value, field: "\(prop).text")
            return text.isEmpty ? nil : .text(text)
        case .icon(let name)?: return .icon(name)
        case nil: return nil
        }
    }

    private func markView(_ mark: Mark, look: InputLook, focus: Binding<String?>, disabled: Bool) -> some View {
        let body = look.affixStyle
        let color = look.color(InputPartsRules.quietColor)
        return Group {
            switch mark {
            case .text(let text):
                styledRun(text, style: body, family: context.theme.fontFamilies["body"], italic: false, rightToLeft: context.rightToLeft, leadsParagraph: true)
                    .foregroundColor(color.color)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: CGFloat(body.lineBox))
            case .icon(let name):
                IconGlyph(
                    name: name, glyph: body.fontSize, box: CGSize(width: body.fontSize, height: body.lineBox), color: color.color,
                    rightToLeft: context.rightToLeft)
            }
        }
        .layoutPriority(1)
        // A press on a mark puts the focus in the field; a mark has no action.
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { focus.wrappedValue = node.id } }
        .accessibilityHidden(true)
    }

    private func box(
        look: InputLook, shown: String, lines: Int, numeric: Bool, focus: Binding<String?>, focused: Bool, invalid: Bool, disabled: Bool, label: String,
        note: String, counter: String?
    ) -> some View {
        let md = look.spacing("md")
        let resolver = context.resolver
        let radius = resolver.radius(node.props["fieldRadius"]) ?? look.radius
        let shape = RoundedRectangle(cornerRadius: radius)
        let body = look.bodyStyle
        let borderWidth = InputPartsRules.borderWidth(node.props["fieldBorderWidth"])
        let named = InputPartsRules.namedHeight(node.props["fieldHeight"], lines: lines) != nil
        let boxHeight = InputPartsRules.boxHeight(
            textLine: body.lineBox, paddingBlock: md, lines: lines, height: node.props["fieldHeight"], borderWidth: node.props["fieldBorderWidth"])
        let numericPath = InputRules.path(of: node.props["value"])
        let bound = numericPath.flatMap { context.scope[$0] }
        let boundText = numeric ? "" : InputRules.text(of: bound)
        let contentLeftToRight = InputRules.contentIsLeftToRight(node.props["keyboard"], lines: node.props["lines"], numeric: numeric)
        let fill = resolver.color(node.props["fieldBackground"]) ?? look.color(InputPartsRules.defaultBackground)
        let ownBorder = resolver.color(node.props["fieldBorderColor"]) ?? look.color(InputPartsRules.defaultBorderColor)
        let borderColor: RGBA = invalid ? look.color("danger") : focused ? look.color("primary") : ownBorder
        let prefix = mark("prefix")
        let suffix = mark("suffix")
        let heard =
            ([prefix, suffix].compactMap { value -> String? in if case .text(let text)? = value { return text } else { return nil } } + [note, counter ?? ""])
            .filter { !$0.isEmpty }.joined(separator: ", ")
        let screenDirection: LayoutDirection = context.rightToLeft ? .rightToLeft : .leftToRight
        let apply = { (event: InputRules.Event) in
            var event = event
            // Text that arrives before the person touched the field is filled in by the platform:
            // it is neither kept nor written.
            if case .input(let new) = event, !state.composing, !(state.touched || focused) { event = .platformFill(new) }
            self.apply(event, numeric: numeric, bound: bound, boundText: boundText, path: numericPath, disabled: disabled)
            revision += 1
        }
        let binding = Binding<String>(get: { shown }, set: { apply(.input($0)) })
        return HStack(alignment: lines > 1 ? .top : .center, spacing: look.spacing(InputPartsRules.gapToken)) {
            if let prefix { markView(prefix, look: look, focus: focus, disabled: disabled) }
            field(
                binding: binding, shown: shown, label: label, hint: heard, lines: lines, numeric: numeric, focus: focus, focused: focused, disabled: disabled,
                look: look, revision: revision, onEvent: apply
            )
            .environment(\.layoutDirection, contentLeftToRight ? .leftToRight : screenDirection)
            .frame(maxWidth: .infinity)
            if let suffix { markView(suffix, look: look, focus: focus, disabled: disabled) }
        }
        .padding(.horizontal, md + borderWidth)
        // A named height is the whole box: the content is centred and the block padding is not applied.
        .padding(.vertical, named ? 0 : md + borderWidth)
        .frame(height: CGFloat(boxHeight), alignment: named ? .center : .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(fill.color))
        .overlay {
            // The border keeps its width in every state; the focus ring is one more point INSIDE it,
            // so the geometry of the box does not change.
            shape.strokeBorder(borderColor.color, lineWidth: focused && !invalid ? borderWidth + 1 : borderWidth)
        }
        .environment(\.layoutDirection, screenDirection)
        #if !os(iOS)
        .accessibilityLabel(label)
        .accessibilityHint(heard)
        #endif
    }

    /// The field itself; `revision` reaches the native control of iOS (the stand-in of macOS is
    /// drawn again with the body it belongs to).
    @ViewBuilder
    private func field(
        binding: Binding<String>, shown: String, label: String, hint: String, lines: Int, numeric: Bool, focus: Binding<String?>, focused: Bool, disabled: Bool,
        look: InputLook, revision: Int, onEvent: @escaping (InputRules.Event) -> Void
    ) -> some View {
        let placeholder = node.props["placeholder"] == nil ? "" : context.text(node, field: "placeholder")
        let action = keyAction()
        let body = look.bodyStyle
        #if os(iOS)
        let keyboard = InputRules.effectiveKeyboard(node.props["keyboard"], lines: node.props["lines"], numeric: numeric)
        let hints = context.form?.autofill ?? true
        InputTextControl(
            text: shown, placeholder: placeholder, placeholderColor: UIColor(look.color("muted").color),
            textColor: UIColor(look.color("onSurface").color), tint: UIColor(look.color("primary").color),
            font: body.uiFont(family: context.theme.fontFamilies["body"]), lineBox: CGFloat(body.lineBox), lines: lines,
            keyboard: Self.keyboardType(keyboard), capitalization: keyboard == .text ? .sentences : .none,
            autocorrect: !(keyboard != .text && keyboard != nil), contentType: hints ? Self.contentType(keyboard) : nil,
            returnKey: action == .next ? .next : .done, screenRightToLeft: context.rightToLeft,
            contentLeftToRight: InputRules.contentIsLeftToRight(node.props["keyboard"], lines: node.props["lines"], numeric: numeric),
            enabled: !disabled, focused: focused, label: label, hint: hint, revision: revision,
            onChange: { change in
                switch change {
                case .focus(let now):
                    if now { focus.wrappedValue = node.id } else if focus.wrappedValue == node.id { focus.wrappedValue = nil }
                case .events(let events): events.forEach(onEvent)
                case .submit: submit(action)
                }
            }
        )
        // SwiftUI drives `isEnabled` of a native control from its environment.
        .disabled(disabled)
        #else
        let prompt = Text(placeholder).foregroundColor(look.color("muted").color)
        let alignment: TextAlignment = alignmentOfContent(numeric: numeric)
        let configured = Group {
            if lines > 1 {
                TextField(label, text: binding, prompt: prompt, axis: .vertical)
                    .lineLimit(lines, reservesSpace: true)
            } else {
                TextField(label, text: binding, prompt: prompt)
                    .lineLimit(1)
            }
        }
        .font(body.font(family: context.theme.fontFamilies["body"]))
        .foregroundColor(look.color("onSurface").color)
        .tint(look.color("primary").color)
        .labelsHidden()
        .textFieldStyle(.plain)
        .multilineTextAlignment(alignment)
        .focused($standInFocus, equals: node.id)
        .onChange(of: standInFocus) { new in
            if new == node.id { focus.wrappedValue = node.id } else if focus.wrappedValue == node.id { focus.wrappedValue = nil }
        }
        .onChange(of: focused) { now in standInFocus = now ? node.id : nil }
        .submitLabel(action == .next ? .next : .done)
        .onSubmit { submit(action) }
        .frame(height: CGFloat(Double(lines) * body.lineBox), alignment: .top)
        configured
        #endif
    }

    /// The alignment is always from the start of the SCREEN, whatever the direction of the content.
    private func alignmentOfContent(numeric: Bool) -> TextAlignment {
        let leftToRight = InputRules.contentIsLeftToRight(node.props["keyboard"], lines: node.props["lines"], numeric: numeric)
        if leftToRight && context.rightToLeft { return .trailing }
        return .leading
    }

    // MARK: Keyboard

    private func keyAction() -> InputRules.KeyAction {
        guard let form = context.form, let index = form.order.firstIndex(where: { $0.nodeId == node.id }) else {
            return InputRules.effectiveLines(node.props["lines"], numeric: InputRules.isNumber(valueType: node.props["valueType"])) > 1 ? .newline : .done
        }
        return InputRules.keyAction(form.order.map(\.focusable), at: index)
    }

    /// The key of the keyboard: «next» moves focus to the next reachable field, «done» removes it.
    /// It never performs an action.
    private func submit(_ action: InputRules.KeyAction) {
        guard action != .newline, let form = context.form, let focus = form.focus else { return }
        let fields = form.order.map(\.focusable)
        guard let index = form.order.firstIndex(where: { $0.nodeId == node.id }), let next = InputRules.nextIndex(fields, after: index) else {
            focus.wrappedValue = nil
            return
        }
        focus.wrappedValue = form.order[next].nodeId
    }

    #if os(iOS)
    static func keyboardType(_ keyboard: InputRules.Keyboard?) -> UIKeyboardType {
        switch keyboard {
        case .email?: return .emailAddress
        case .number?: return .decimalPad
        case .phone?: return .phonePad
        case .url?: return .URL
        default: return .default
        }
    }

    /// Autofill hints come only from the keyboard intent: never credentials, payment, a postal
    /// address or a one-time code.
    static func contentType(_ keyboard: InputRules.Keyboard?) -> UITextContentType? {
        switch keyboard {
        case .email?: return .emailAddress
        case .phone?: return .telephoneNumber
        case .url?: return .URL
        default: return nil
        }
    }
    #endif

    // MARK: Events

    private func apply(_ event: InputRules.Event, numeric: Bool, bound: JSONValue?, boundText: String, path: String?, disabled: Bool) {
        let maxLength = node.props["maxLength"]
        if numeric {
            let result = InputRules.stepNumber(state, event, bound: bound, maxLength: maxLength, disabled: disabled, hasPath: path != nil)
            state = result.state
            if let write = result.write, let path { context.write?(path, write) }
        } else {
            let result = InputRules.step(state, event, bound: boundText, maxLength: maxLength, disabled: disabled, hasPath: path != nil)
            state = result.state
            if let write = result.write, let path { context.write?(path, .string(write)) }
        }
    }
}
