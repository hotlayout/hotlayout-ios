import Foundation

/// A node that fades in and out when its `visibleIf` changes (`visibilityTransition: 'fade'`,
/// block `x-visibilityFade`).
///
/// Every node follows its own timeline, with no pairing: a leaving node stays in the layout and
/// fades for `out`, then leaves it; an appearing node waits `out` out of the layout, then enters
/// it transparent and fades in for `in`. A change during a transition goes to the new goal from
/// the current opacity, the time scaled by the distance. The clock is given by the caller.
enum VisibilityFade {
    static let field = "visibilityTransition"

    /// A cubic Bezier through (0,0) and (1,1): `x1, y1, x2, y2`.
    struct Curve: Equatable {
        let x1: Double, y1: Double, x2: Double, y2: Double
    }

    static let outMs = 120.0
    static let outCurve = Curve(x1: 0.4, y1: 0, x2: 1, y2: 1)
    static let inMs = 160.0
    static let inCurve = Curve(x1: 0, y1: 0, x2: 0.2, y2: 1)
    /// How long an appearing node waits out of the layout: the time the other one needs to leave.
    static let delayMs = outMs

    /// The word of the field: only `fade` is read, anything else is no field.
    static func word(of node: DocumentNode) -> String? {
        node.fields[field]?.stringValue == "fade" ? "fade" : nil
    }

    /// The zones of the screen read no fade: they follow their condition at once. A navigation bar
    /// and its items, a node with a `pin` (of any value), and an app bar that is the first child of
    /// the root of a screen.
    static func isZoneNode(_ node: DocumentNode, parent: DocumentNode?) -> Bool {
        if node.widget == .navBar || node.widget == .navItem { return true }
        if node.fields["pin"] != nil { return true }
        guard node.widget == .appBar, parent?.widget == .screen else { return false }
        return parent?.children.first?.id == node.id
    }

    /// Whether the node fades: it names the word and has a condition to change. `inZone` is true
    /// for the app bar the screen draws as its zone.
    static func reads(_ node: DocumentNode, inZone: Bool = false) -> Bool {
        word(of: node) != nil && node.visibleIf != nil && !inZone && !isZoneNode(node, parent: nil)
    }

    // MARK: Timeline

    enum Phase: String, Equatable { case shown, leaving, hidden, waiting, entering }

    struct State: Equatable {
        var phase: Phase
        /// The moment the phase began, milliseconds (the caller's clock).
        var since: Double
        /// The opacity at the start of the phase.
        var from: Double
    }

    struct Frame: Equatable {
        var phase: Phase
        var inLayout: Bool
        var opacity: Double
        var interactive: Bool
    }

    /// The state of rest: how a node stands at the first show and after any change made "at once".
    static func rest(shown: Bool, now: Double = 0) -> State {
        State(phase: shown ? .shown : .hidden, since: now, from: shown ? 1 : 0)
    }

    /// The cubic Bezier through (0,0) and (1,1): y for x, by bisection on the curve parameter.
    static func bezier(_ curve: Curve, at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func coordinate(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * a * t * pow(1 - t, 2) + 3 * b * pow(t, 2) * (1 - t) + pow(t, 3)
        }
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<40 {
            let value = coordinate(t, curve.x1, curve.x2) - x
            if abs(value) < 1e-9 { break }
            if value > 0 { high = t } else { low = t }
            t = (low + high) / 2
        }
        return coordinate(t, curve.y1, curve.y2)
    }

    private static func leavingSpan(_ state: State) -> Double { outMs * state.from }
    private static func enteringSpan(_ state: State) -> Double { inMs * (1 - state.from) }

    /// The moment the phase ends by itself; `nil` for a phase of rest.
    static func endsAt(_ state: State) -> Double? {
        switch state.phase {
        case .leaving: return state.since + leavingSpan(state)
        case .waiting: return state.since + delayMs
        case .entering: return state.since + enteringSpan(state)
        case .shown, .hidden: return nil
        }
    }

    /// The state at `now`: phases that ended pass on (`leaving → hidden`, `waiting → entering → shown`).
    static func settle(_ state: State, at now: Double) -> State {
        var current = state
        while let end = endsAt(current), now >= end {
            switch current.phase {
            case .leaving: current = State(phase: .hidden, since: end, from: 0)
            case .waiting: current = State(phase: .entering, since: end, from: 0)
            default: current = State(phase: .shown, since: end, from: 1)
            }
        }
        return current
    }

    /// The frame at `now`: the phase, whether the node is in the layout, its opacity and whether it is a control.
    static func frame(_ state: State, at now: Double) -> Frame {
        let settled = settle(state, at: now)
        switch settled.phase {
        case .shown: return Frame(phase: .shown, inLayout: true, opacity: 1, interactive: true)
        case .hidden: return Frame(phase: .hidden, inLayout: false, opacity: 0, interactive: false)
        case .waiting: return Frame(phase: .waiting, inLayout: false, opacity: 0, interactive: false)
        case .leaving:
            let span = leavingSpan(settled)
            let share = span <= 0 ? 1 : (now - settled.since) / span
            return Frame(phase: .leaving, inLayout: true, opacity: settled.from * (1 - bezier(outCurve, at: share)), interactive: false)
        case .entering:
            let span = enteringSpan(settled)
            let share = span <= 0 ? 1 : (now - settled.since) / span
            return Frame(phase: .entering, inLayout: true, opacity: settled.from + (1 - settled.from) * bezier(inCurve, at: share), interactive: true)
        }
    }

    /// The condition of the node became `shown` at `now`. With `animate` false the change is
    /// "at once": the state of rest of the new goal.
    static func change(_ state: State, shown: Bool, at now: Double, animate: Bool) -> State {
        if !animate { return rest(shown: shown, now: now) }
        let settled = settle(state, at: now)
        let opacity = frame(settled, at: now).opacity
        if shown {
            if settled.phase == .hidden { return State(phase: .waiting, since: now, from: 0) }
            if settled.phase == .leaving { return State(phase: .entering, since: now, from: opacity) }
            return settled
        }
        if settled.phase == .shown || settled.phase == .entering { return State(phase: .leaving, since: now, from: opacity) }
        if settled.phase == .waiting { return rest(shown: false, now: now) }
        return settled
    }
}

/// What a node with the field remembers between draws: its state, what its condition said, and in
/// which language and width class that was said. A change of the language or of the width class
/// is not a transition of the condition: the node goes to the new goal at once.
final class VisibilityFadeHolder {
    private(set) var state: VisibilityFade.State
    private var shown: Bool
    private var context: String

    init(shown: Bool, context: String, now: Double) {
        state = VisibilityFade.rest(shown: shown, now: now)
        self.shown = shown
        self.context = context
    }

    /// Takes the condition of this draw. `animate` is false under Reduce Motion.
    func sync(shown newShown: Bool, context newContext: String, now: Double, animate: Bool) {
        guard newShown != shown || newContext != context else { return }
        let sameContext = newContext == context
        state = VisibilityFade.change(state, shown: newShown, at: now, animate: animate && sameContext)
        shown = newShown
        context = newContext
    }

    func frame(at now: Double) -> VisibilityFade.Frame { VisibilityFade.frame(state, at: now) }

    /// The next moment the phase changes by itself after `now` (a leaving node leaves the layout, a
    /// waiting one enters it, an entering one comes to rest); `nil` at rest.
    func nextBoundary(after now: Double) -> Double? {
        VisibilityFade.endsAt(VisibilityFade.settle(state, at: now))
    }

    /// When the running transition ends altogether (a wait and the fade after it); `nil` at rest.
    var endsAt: Double? {
        var end: Double?
        var current = state
        while let next = VisibilityFade.endsAt(current) {
            end = next
            current = VisibilityFade.settle(current, at: next)
        }
        return end
    }
}
