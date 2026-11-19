import Foundation

/// A carousel that advances by time (`carousel.autoAdvance`, block `x-carouselAutoAdvance`).
///
/// The optional field is an object `{intervalMs, loop?}`: its presence turns the timer on. The timer
/// counts the time the carousel stood on the current stop WITHOUT a pause; when the count reaches the
/// interval it takes the carousel to the next stop (a stop of the snap list, not the next card), as the
/// reader's own move, and writes the new stop number to `stopPath` when the carousel has one.
struct CarouselAutoAdvance: Equatable {
    /// The interval in milliseconds, already within its bounds.
    var intervalMs: Double
    /// After the last stop, back to the first.
    var loop = false

    static let field = "autoAdvance"
    static let minMs = 2000.0
    static let maxMs = 15000.0

    /// What pauses the timer, in the order of the artifact's list.
    enum Pause: String, CaseIterable {
        /// A finger or a pointer button is down on the carousel.
        case held
        /// Keyboard focus is inside the carousel.
        case keyboardFocus
        /// The scroll is still moving: a gesture, momentum or the animation of a step.
        case moving
        /// The screen is not the top of the stack, a layer covers it, the app is in the background.
        case notShown
        /// A screen reader is on: no timer while it runs.
        case screenReader
    }

    /// The interval a value names: clamped to its bounds; not a number is the lower bound.
    static func interval(_ value: JSONValue?) -> Double {
        guard let number = value?.numberValue, number.isFinite else { return minMs }
        return min(maxMs, max(minMs, number))
    }

    /// The timer a `carousel` object names, or `nil` when it names none: the field must be an object.
    /// `carousel` is the object of a node that is a carousel host.
    static func of(_ carousel: JSONValue?) -> CarouselAutoAdvance? {
        guard let object = carousel?.objectValue, let timer = object[Self.field]?.objectValue else { return nil }
        return CarouselAutoAdvance(intervalMs: interval(timer["intervalMs"]), loop: timer["loop"]?.boolValue == true)
    }

    /// The timer of a node: it must be a carousel host.
    static func of(_ node: DocumentNode) -> CarouselAutoAdvance? {
        guard CarouselRules.of(node) != nil else { return nil }
        return of(node.props["carousel"])
    }

    /// Whether the field with this node id, which has the keyboard, is inside the node.
    static func holdsFocus(_ node: DocumentNode, focus: String?) -> Bool {
        guard let focus else { return false }
        func contains(_ node: DocumentNode) -> Bool { node.id == focus || node.children.contains(where: contains) }
        return contains(node)
    }

    /// The stop the timer leads to from `active`: the next one; from the last, nowhere or (with `loop`)
    /// the first. With fewer than two stops there is no timer. An active stop out of range is clamped first.
    static func next(active: Int, stopCount: Int, loop: Bool) -> Int? {
        guard stopCount >= 2 else { return nil }
        let from = min(max(active, 0), stopCount - 1)
        if from + 1 < stopCount { return from + 1 }
        return loop ? 0 : nil
    }

    /// The state of the timer: the stop the count runs from and the time the carousel has stood on it
    /// without a pause.
    struct State: Equatable {
        var active: Int
        var elapsed: Double
    }

    /// One tick: the new state and where the timer leads the carousel (`nil`: nowhere).
    struct Tick: Equatable {
        var state: State
        var step: Int?
    }

    /// ONE TICK. A pause changes nothing (the count is frozen and resumes with what was left). Then the
    /// stop: when it is not the one the count runs from, somebody else moved it (a person, the value of
    /// `stopPath`, fewer stops) and the count restarts from 0 there, with no step. Otherwise the count
    /// grows by the time since the last tick (a negative one is nothing) and is held at the interval; on
    /// the interval comes ONE step to the next stop (a long gap never catches up) and the count restarts
    /// from 0; with nowhere to go the count stands at the interval.
    static func tick(
        _ state: State, dtMs: Double, active: Int, stopCount: Int, paused: Bool, intervalMs: Double, loop: Bool
    ) -> Tick {
        if paused { return Tick(state: state, step: nil) }
        if active != state.active { return Tick(state: State(active: active, elapsed: 0), step: nil) }
        let dt = dtMs.isFinite && dtMs > 0 ? dtMs : 0
        let elapsed = min(intervalMs, max(0, state.elapsed + dt))
        if elapsed < intervalMs { return Tick(state: State(active: state.active, elapsed: elapsed), step: nil) }
        guard let next = next(active: state.active, stopCount: stopCount, loop: loop) else {
            return Tick(state: State(active: state.active, elapsed: elapsed), step: nil)
        }
        return Tick(state: State(active: next, elapsed: 0), step: next)
    }

    /// What the step writes to `stopPath`: the number of the new stop, unless the value already is it.
    static func write(step: Int, current: JSONValue?) -> Int? {
        guard step >= 0 else { return nil }
        return WriteActions.holdsWritten(current, .number(Double(step))) ? nil : step
    }

    /// How often the clock ticks. A tick counts exactly this much time: a timer that is late loses time
    /// rather than catching up, and a step is never made twice for one gap.
    static let tickMs = 100.0
}

/// The clock of one carousel that advances by time. It counts in `tickMs` steps and asks the carousel for the
/// stop it stands on; the carousel tells it what holds the count and carries out the steps.
///
/// The count starts at the show: the first tick after the stops are laid out only notes the stop. A pause
/// freezes the count, and it resumes with what was left. The clock of the host is injected: `tick()` is
/// all that moves it, so the tables drive it without a timer.
final class CarouselAutoAdvanceDriver {
    /// Starts a timer and returns what cancels it.
    typealias Later = CarouselStopController.Later

    /// The stop the carousel stands on and the number of stops; `nil` while the stops are not laid out.
    var view: () -> (active: Int, stopCount: Int)? = { nil }
    /// The timer takes the carousel to this stop.
    var onStep: (Int) -> Void = { _ in }

    private(set) var config: CarouselAutoAdvance?
    private var state: CarouselAutoAdvance.State?
    private var paused: Set<CarouselAutoAdvance.Pause> = []
    private var cancelMoving: (() -> Void)?
    private let later: Later

    init(later: @escaping Later = CarouselStopController.mainQueue) {
        self.later = later
    }

    /// How long a scroll stays quiet before it counts as no longer moving.
    static let quietSeconds = 0.15

    /// Sets the timer the carousel is configured with; `nil` stops the clock. A new timer counts from
    /// the next show of the stops.
    func configure(_ new: CarouselAutoAdvance?) {
        guard new != config else { return }
        config = new
        state = nil
    }

    /// Whether anything holds the count.
    var isPaused: Bool { !paused.isEmpty }

    /// Sets or clears one pause.
    func set(_ pause: CarouselAutoAdvance.Pause, _ on: Bool) {
        if on { paused.insert(pause) } else { paused.remove(pause) }
    }

    /// The scroll moved (a gesture, momentum, the animation of a step): the count waits until it has
    /// been quiet for a while.
    func scrollMoved() {
        paused.insert(.moving)
        cancelMoving?()
        cancelMoving = later(Self.quietSeconds) { [weak self] in
            self?.paused.remove(.moving)
            self?.cancelMoving = nil
        }
    }

    /// One tick of the clock.
    func tick() {
        guard let config, let seen = view() else { return }
        guard let current = state else {
            // The show: the count starts here.
            state = CarouselAutoAdvance.State(active: seen.active, elapsed: 0)
            return
        }
        let result = CarouselAutoAdvance.tick(
            current, dtMs: CarouselAutoAdvance.tickMs, active: seen.active, stopCount: seen.stopCount, paused: isPaused,
            intervalMs: config.intervalMs, loop: config.loop)
        state = result.state
        if let step = result.step { onStep(step) }
    }

    func cancel() {
        cancelMoving?()
        cancelMoving = nil
        paused.remove(.moving)
    }
}
