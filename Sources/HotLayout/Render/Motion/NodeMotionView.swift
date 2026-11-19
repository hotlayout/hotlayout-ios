import SwiftUI

private struct NodeMotionClockKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// A fixed time (ms) for every moving node below, instead of the clock of the screen; the tests
    /// use it to read a real node at a chosen moment.
    var nodeMotionClockMs: Double? {
        get { self[NodeMotionClockKey.self] }
        set { self[NodeMotionClockKey.self] = newValue }
    }
}

/// Which kinds of a motion a modifier paints. A layer of a `Stack` paints the turning kinds inside
/// its own turn and the others outside it.
enum MotionPart {
    case all, turnsOnly, shiftsOnly

    func paints(_ motion: NodeMotion) -> Bool {
        switch self {
        case .all: return true
        case .turnsOnly: return motion.turns
        case .shiftsOnly: return !motion.turns
        }
    }
}

extension NodeMotion.Pivot {
    var unitPoint: UnitPoint {
        switch self {
        case .center: return .center
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

/// Paints the motion of a node over the box it has at rest: a shift along the screen axes, a
/// scale about the centre of the box, a turn about the centre or the middle of an edge and an
/// opacity that multiplies the node's own. Nothing here touches layout, so the neighbours stay
/// where they are. "Reduce motion" is rest.
struct NodeMotionModifier: ViewModifier {
    let motion: NodeMotion
    let rightToLeft: Bool
    /// A fixed time for the tests; the screen runs the clock of the node.
    var fixedElapsedMs: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.nodeMotionClockMs) private var clock
    @State private var appeared = Date()

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if let fixed = fixedElapsedMs ?? clock {
            painted(content, elapsedMs: fixed)
        } else {
            // The clock starts when the node appears; a node that appears again starts from zero.
            TimelineView(.animation) { timeline in
                painted(content, elapsedMs: timeline.date.timeIntervalSince(appeared) * 1000)
            }
            .onAppear { appeared = Date() }
        }
    }

    private func painted(_ content: Content, elapsedMs: Double) -> some View {
        // SwiftUI mirrors an offset in a right-to-left environment by itself: toward the end of the
        // line is then already the left. Mirror here only when the environment is not mirrored.
        let pose = motion.pose(at: elapsedMs, rightToLeft: rightToLeft && layoutDirection == .leftToRight)
        // SwiftUI mirrors a turn in a right-to-left environment as well: a sway has the mirrored sign
        // already, a spin has no direction of the line and gets the sign back.
        let turn = layoutDirection == .rightToLeft && !motion.turnsWithTheLine ? -pose.rotate : pose.rotate
        return
            content
            .rotationEffect(.degrees(turn), anchor: pose.pivot.unitPoint)
            .scaleEffect(pose.scale)
            .offset(x: pose.x, y: pose.y)
            .opacity(pose.opacity)
    }
}

extension View {
    /// The node's motion when it has a readable one.
    @ViewBuilder
    func nodeMotion(_ motion: NodeMotion?, rightToLeft: Bool, part: MotionPart = .all, fixedElapsedMs: Double? = nil) -> some View {
        if let motion, part.paints(motion) {
            modifier(NodeMotionModifier(motion: motion, rightToLeft: rightToLeft, fixedElapsedMs: fixedElapsedMs))
        } else {
            self
        }
    }
}
