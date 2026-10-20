import Foundation

/// What a press of a node with a write action does, in the order the host sees it: the request
/// for haptic feedback, the analytics event, then the write.
struct WritePressEffects: Equatable {
    var haptic: HapticFeedback?
    var track: TrackEvent?
    var step: WriteActions.Step
}

enum WritePress {
    /// The effects of a press of `action`, or `nil` when it is not a write action (the screen
    /// goes on with the flow). `read` gives the value under a path with the data scope of the node.
    /// An action that is not usable writes nothing and hands nothing to the host; the reason goes
    /// to the report, the analytics event still goes (once per press).
    static func effects(of action: JSONObject, read: (String) -> JSONValue?, sink: ReportSink? = nil, location: String = "action") -> WritePressEffects? {
        guard let step = WriteActions.step(of: action, read: read) else { return nil }
        if case .invalid(let problem) = step {
            sink?.add(.ignoredInput, location, "a write action that cannot be used (\(problem.rawValue)); nothing was written")
        }
        return WritePressEffects(haptic: ActionCatalog.haptic(action), track: ActionCatalog.track(action, sink: sink, location: location), step: step)
    }

    /// Whether a `Button` or an `IconButton` is disabled: `requiresFilled` on an unfilled form of
    /// its screen, or a `disabledIf` that holds. Other nodes are never disabled.
    static func isDisabled(_ node: DocumentNode, scope: DataScope, screenRoot: DocumentNode?, screenScope: DataScope, widthClass: WidthClass = .compact) -> Bool
    {
        guard node.type == "Button" || node.type == "IconButton" else { return false }
        return FormRules.isPressDisabled(
            requiresFilled: InputRules.isLiteralTrue(node.props["requiresFilled"]),
            disabledIf: node.props["disabledIf"],
            scope: scope,
            formFilled: { screenRoot.map { FormRules.isFormFilled(root: $0, scope: screenScope, widthClass: widthClass) } ?? true }
        )
    }

    /// The nodes from the root to the node with this id (inclusive), or `nil` when there is none.
    static func path(to id: String, in node: DocumentNode) -> [DocumentNode]? {
        if node.id == id { return [node] }
        for child in node.children {
            if let found = path(to: id, in: child) { return [node] + found }
        }
        return nil
    }
}
