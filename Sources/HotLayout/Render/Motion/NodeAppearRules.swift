import Foundation

/// The one-time appearance of a node when its screen is shown (`appear`, block `x-appear`).
///
/// The field is `{kind: 'fade', duration, delay?}` or `{kind: 'rise', distance, duration, delay?}`.
/// The curve is the one a node uses when its condition makes it appear (`x-visibilityFade.in.curve`):
/// the same act, one tempo.
struct NodeAppear: Equatable {
    enum Kind: String { case fade, rise }

    let kind: Kind
    /// `rise` only: the shift down at the start, points.
    let distance: Int
    /// Length of the appearance, milliseconds.
    let duration: Int
    /// The time the node waits, invisible and in its place, before it starts to appear.
    let delay: Int

    static let field = "appear"
    static let durationRange = 100...2000
    static let distanceRange = 1...48

    /// The appearance in a value, or `nil` when it is not one this reader can draw: an unknown kind,
    /// a missing or surplus field or a number out of bounds means NO appearance, and the node stands at once.
    static func read(_ value: JSONValue?) -> NodeAppear? {
        guard let object = value?.objectValue, let kind = object["kind"]?.stringValue.flatMap(Kind.init(rawValue:)) else { return nil }
        let own: Set<String> = kind == .rise ? ["kind", "distance", "duration", "delay"] : ["kind", "duration", "delay"]
        guard object.keys.allSatisfy(own.contains),
            let duration = ContractShapes.wholeNumber(object["duration"], below: 1e9), durationRange.contains(duration)
        else { return nil }
        var delay = 0
        if object["delay"] != nil {
            guard let read = ContractShapes.wholeNumber(object["delay"], below: 1e9), NodeMotion.delayRange.contains(read) else { return nil }
            delay = read
        }
        var distance = 0
        if kind == .rise {
            guard let read = ContractShapes.wholeNumber(object["distance"], below: 1e9), distanceRange.contains(read) else { return nil }
            distance = read
        }
        return NodeAppear(kind: kind, distance: distance, duration: duration, delay: delay)
    }

    /// Where a node stands at a moment of its appearance: the shift down and the opacity factor.
    struct Pose: Equatable {
        var y = 0.0
        var opacity = 1.0

        static let rest = Pose()
    }

    /// The moment the appearance is over, milliseconds after the show.
    var endsAt: Double { Double(delay + duration) }

    /// The pose `elapsedMs` after the screen was shown: `p = clamp((t - delay) / duration, 0, 1)`,
    /// `e = cubic-bezier(0, 0, 0.2, 1)(p)`, opacity `e`, a `rise` shifts down by `distance * (1 - e)`.
    /// While the delay runs the node stands in the START pose (invisible, fully shifted), so a cascade
    /// does not flash. "Reduce motion" is rest.
    func pose(at elapsedMs: Double, reducedMotion: Bool = false) -> Pose {
        if reducedMotion { return .rest }
        let elapsed = elapsedMs - Double(delay)
        let share = elapsed.isFinite ? min(1, max(0, elapsed / Double(duration))) : 0
        let eased = VisibilityFade.bezier(VisibilityFade.inCurve, at: share)
        return Pose(y: (kind == .rise ? Double(distance) * (1 - eased) : 0) + 0, opacity: eased)
    }

    /// The moments of a flow the table names.
    enum Moment: String {
        case firstShow, forward, back
        case `switch`
        case modalClosed, conditionMet, widthClassChanged, newRecord
    }

    /// Whether the appearance plays at a moment: a show of the screen does; closing a layer above is
    /// not a show, and a node that appears on a screen already shown (its condition, the width class,
    /// a new record) follows `visibilityTransition` or stands at once.
    static func plays(on moment: Moment) -> Bool {
        switch moment {
        case .firstShow, .forward, .back, .switch: return true
        case .modalClosed, .conditionMet, .widthClassChanged, .newRecord: return false
        }
    }

    /// Whether the appearance is read on a node: not on the root, not on a zone of the screen.
    static func reads(_ node: DocumentNode, isScreenZone: Bool) -> Bool {
        node.widget != .screen && !isScreenZone && !VisibilityFade.isZoneNode(node, parent: nil)
    }
}
