import Foundation

/// The feedback of a pressable node to the finger (`x-pressFeedback`): which kind, which pose.
enum PressFeedbackRules {
    enum Kind: String, Equatable { case card, button, fade }

    struct Pose: Equatable {
        var scale: Double
        var opacity: Double
    }

    static let fadeOpacity = 0.7
    static let downMs = 80.0
    static let upMs = 160.0
    static let downCurve = [0.2, 0, 0, 1.0]
    static let upCurve = [0.34, 1.56, 0.64, 1.0]
    /// The only word of the node field `pressFeedback`.
    static let offWord = "none"

    /// The kind of feedback of a node that performs the action of a press, or `nil`.
    static func kind(_ node: DocumentNode, disabled: Bool = false, swipe: Bool = false) -> Kind? {
        if node.fields["pressFeedback"]?.stringValue == offWord || disabled || swipe { return nil }
        switch node.type {
        case "Button": return node.props["variant"]?.stringValue == "ghost" ? .fade : .button
        case "IconButton", "NavItem": return .fade
        default: return .card
        }
    }

    /// "Reduce motion" keeps only the fade.
    static func pose(_ kind: Kind, reduceMotion: Bool = false) -> Pose {
        if reduceMotion { return Pose(scale: 1, opacity: fadeOpacity) }
        switch kind {
        case .card: return Pose(scale: 0.97, opacity: 1)
        case .button: return Pose(scale: 0.96, opacity: 1)
        case .fade: return Pose(scale: 1, opacity: fadeOpacity)
        }
    }
}
