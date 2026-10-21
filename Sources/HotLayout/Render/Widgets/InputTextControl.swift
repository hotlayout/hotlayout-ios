#if os(iOS)
import SwiftUI
import UIKit

extension TextStyleValue {
    /// The UIKit font of a theme text style (the system font stands in for a family the device lacks).
    func uiFont(family: String?) -> UIFont {
        let weight = Self.uiWeight(Font.Weight(cssWeight: fontWeight))
        if let family, Self.isInstalled(family) {
            let descriptor = UIFontDescriptor(fontAttributes: [.family: family, .traits: [UIFontDescriptor.TraitKey.weight: weight]])
            return UIFont(descriptor: descriptor, size: fontSize)
        }
        return UIFont.systemFont(ofSize: fontSize, weight: weight)
    }
}

/// What the native control tells the field.
enum InputControlChange {
    case focus(Bool)
    case events([InputRules.Event])
    case submit
}

/// The text of a `TextField` as a native control: a `UITextField` for one line and a `UITextView`
/// for several. SwiftUI's `TextField` does not say whether a character is still being composed
/// (IME), so every intermediate text of a composition would be written; the control reports
/// `markedTextRange` and `CompositionTracker` turns it into the composition events of the rules.
struct InputTextControl: UIViewRepresentable {
    var text: String
    var placeholder: String
    var placeholderColor: UIColor
    var textColor: UIColor
    var tint: UIColor
    var font: UIFont
    var lineBox: CGFloat
    var lines: Int
    var keyboard: UIKeyboardType
    var capitalization: UITextAutocapitalizationType
    var autocorrect: Bool
    var contentType: UITextContentType?
    var returnKey: UIReturnKeyType
    /// The alignment is from the start of the SCREEN, whatever the direction of the content.
    var screenRightToLeft: Bool
    var contentLeftToRight: Bool
    var enabled: Bool
    var focused: Bool
    var label: String
    var hint: String
    /// Grows with every report of the control, so that a report the rules answer with the same
    /// text (one cut to the limit) still updates the control.
    var revision = 0
    var onChange: (InputControlChange) -> Void

    func makeCoordinator() -> InputTextCoordinator { InputTextCoordinator() }

    func makeUIView(context: Context) -> UIView {
        let view: UIView
        if lines > 1 {
            let textView = UITextView()
            textView.delegate = context.coordinator
            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.isScrollEnabled = true
            let label = UILabel()
            label.numberOfLines = 1
            label.isAccessibilityElement = false
            label.autoresizingMask = .flexibleWidth
            textView.addSubview(label)
            context.coordinator.placeholderLabel = label
            view = textView
        } else {
            let field = UITextField()
            field.delegate = context.coordinator
            field.addTarget(context.coordinator, action: #selector(InputTextCoordinator.editingChanged(_:)), for: .editingChanged)
            field.borderStyle = .none
            field.clearButtonMode = .never
            view = field
        }
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 10, height: CGFloat(lines) * lineBox)
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let alignment: NSTextAlignment = screenRightToLeft ? .right : .left
        let semantic: UISemanticContentAttribute = contentLeftToRight ? .forceLeftToRight : (screenRightToLeft ? .forceRightToLeft : .forceLeftToRight)
        view.semanticContentAttribute = semantic
        view.tintColor = tint
        view.isAccessibilityElement = true
        view.accessibilityLabel = label
        view.accessibilityHint = hint.isEmpty ? nil : hint
        if let field = view as? UITextField {
            configure(field, alignment: alignment)
        } else if let textView = view as? UITextView {
            configure(textView, alignment: alignment, coordinator: coordinator)
        }
        coordinator.applyFocus(focused, to: view)
    }

    private func configure(_ field: UITextField, alignment: NSTextAlignment) {
        field.font = font
        field.textColor = textColor
        field.textAlignment = alignment
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor, .font: font])
        field.keyboardType = keyboard
        field.autocapitalizationType = capitalization
        field.autocorrectionType = autocorrect ? .default : .no
        field.spellCheckingType = autocorrect ? .default : .no
        field.textContentType = contentType
        field.returnKeyType = returnKey
        field.isEnabled = enabled
        // A composition in progress owns the text of the control: it is not replaced.
        if field.markedTextRange == nil, field.text != text { field.text = text }
    }

    private func configure(_ textView: UITextView, alignment: NSTextAlignment, coordinator: InputTextCoordinator) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineBox
        style.maximumLineHeight = lineBox
        style.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: style]
        textView.typingAttributes = attributes
        textView.keyboardType = keyboard
        textView.autocapitalizationType = capitalization
        textView.autocorrectionType = autocorrect ? .default : .no
        textView.spellCheckingType = autocorrect ? .default : .no
        textView.textContentType = contentType
        textView.isEditable = enabled
        textView.textAlignment = alignment
        if textView.markedTextRange == nil, textView.text != text {
            textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        }
        if let label = coordinator.placeholderLabel {
            label.attributedText = NSAttributedString(
                string: placeholder, attributes: [.foregroundColor: placeholderColor, .font: font, .paragraphStyle: style])
            label.frame = CGRect(x: 0, y: 0, width: max(0, textView.bounds.width), height: lineBox)
            label.isHidden = !textView.text.isEmpty
        }
    }
}

final class InputTextCoordinator: NSObject, UITextFieldDelegate, UITextViewDelegate {
    var onChange: (InputControlChange) -> Void = { _ in }
    var tracker = CompositionTracker()
    var placeholderLabel: UILabel?
    /// The focus the view last asked for: the native control is told only when the ask CHANGES. A
    /// change that began in the control (a tap, the system) does not move it, so an update drawn
    /// before the view has heard of that change does not undo it.
    private var askedFocus = false

    func applyFocus(_ focused: Bool, to view: UIView) {
        guard focused != askedFocus else { return }
        askedFocus = focused
        DispatchQueue.main.async {
            if focused, !view.isFirstResponder { view.becomeFirstResponder() }
            if !focused, view.isFirstResponder { view.resignFirstResponder() }
        }
    }

    private func report(text: String, marked: Bool) {
        onChange(.events(tracker.changed(text: text, marked: marked)))
    }

    private func begin() {
        onChange(.focus(true))
    }

    private func finish(text: String) {
        let rest = tracker.ended(text: text)
        if !rest.isEmpty { onChange(.events(rest)) }
        onChange(.focus(false))
    }

    // MARK: Single line

    @objc func editingChanged(_ field: UITextField) {
        report(text: field.text ?? "", marked: field.markedTextRange != nil)
    }

    func textFieldDidBeginEditing(_ field: UITextField) { begin() }
    func textFieldDidEndEditing(_ field: UITextField) { finish(text: field.text ?? "") }

    func textFieldShouldReturn(_ field: UITextField) -> Bool {
        onChange(.submit)
        return false
    }

    // MARK: Several lines

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel?.isHidden = !textView.text.isEmpty
        report(text: textView.text ?? "", marked: textView.markedTextRange != nil)
    }

    func textViewDidBeginEditing(_ textView: UITextView) { begin() }
    func textViewDidEndEditing(_ textView: UITextView) { finish(text: textView.text ?? "") }
}
#endif
