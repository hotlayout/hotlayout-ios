import Foundation

/// The carousel tells the active stop (`carousel.stopPath`, block `x-carouselStop`).
///
/// The optional `stopPath` names a number data path. A swipe of a person, once the scroll has
/// settled on a stop, writes the number of the stop there (the write of an input field: the
/// session of the screen and the host at the same moment, under `writablePaths`). The carousel
/// stands on the stop the value names when it is shown and moves to it when the number changes.
/// The value is the number of a STOP, counted from 0, not of a card.
enum CarouselStop {
    /// The longest path: the common bound of a data path.
    static let pathMax = 128
    /// Quiet time of a scroll, in seconds, after which it counts as settled when nothing else says so.
    static let settleSeconds = 0.15

    /// The path as the reader sees it: a non-empty string within the bound, on a carousel host.
    /// Anything else means there is no path: the carousel scrolls as without the field and writes nothing.
    static func path(of node: DocumentNode) -> String? {
        guard CarouselRules.of(node) != nil, let text = node.props["carousel"]?.objectValue?["stopPath"]?.stringValue else { return nil }
        return !text.isEmpty && text.count <= pathMax ? text : nil
    }

    /// The stop number a value names: a number with a whole value (`1` and `1.0` alike); otherwise none.
    static func number(of value: JSONValue?) -> Int? {
        guard let number = InputRules.readNumber(value), number == number.rounded() else { return nil }
        return SafeInt.exactly(number)
    }

    /// The stop to show for a value: its number clamped to `0…stopCount − 1`; no number is the first.
    static func shownStop(_ value: JSONValue?, stopCount: Int) -> Int {
        let last = max(0, stopCount - 1)
        guard let number = number(of: value) else { return 0 }
        return min(last, max(0, number))
    }

    /// Where to go when the value changed. The event is a change of the NUMBER, not a comparison of
    /// what is shown with the data at draw time: a write the host refused leaves the carousel where
    /// the person put it. `nil` means nowhere.
    static func follow(previous: JSONValue?, next: JSONValue?, stopCount: Int, active: Int) -> Int? {
        if number(of: previous) == number(of: next) { return nil }
        let target = shownStop(next, stopCount: stopCount)
        return target == active ? nil : target
    }

    /// What to write when the scroll settled: the number of the stop, only after a move of a person
    /// and only when it is not already there.
    static func write(settled: Int, byPerson: Bool, current: JSONValue?) -> Int? {
        guard byPerson, settled >= 0 else { return nil }
        return WriteActions.holdsWritten(current, .number(Double(settled))) ? nil : settled
    }
}

/// The glue between a carousel and its path: what is a person's move, when it has settled, what to
/// write, where to stand at the show and where to go when the value changes. The view feeds it the
/// events of the scroll; the moves and the write go out through closures, and the clock is injected.
///
/// A move of the READER (the show, following the value) never writes: it clears the mark that a
/// person is moving the row.
final class CarouselStopController {
    /// Starts a timer and returns what cancels it.
    typealias Later = (_ seconds: Double, _ action: @escaping () -> Void) -> () -> Void

    var path: String?
    /// The value under the path as of the last draw.
    var current: JSONValue?
    var reducedMotion = false
    var write: ((String, JSONValue) -> Void)?
    /// Scrolls to a stop of the current plan; `animated` is false for a jump.
    var scrollToStop: ((Int, Bool) -> Void)?

    private(set) var stops: [Double] = [0]
    private(set) var offset = 0.0
    private var shown = false
    private var previous: JSONValue?
    private var person = false
    private var holding = false
    private var dirty = false
    private var cancelTimer: (() -> Void)?
    private let later: Later

    init(later: @escaping Later = CarouselStopController.mainQueue) {
        self.later = later
    }

    static let mainQueue: Later = { seconds, action in
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return { item.cancel() }
    }

    /// The row was measured. The first time, the carousel stands on the stop the value names,
    /// without animation, and writes nothing. Returns that stop, or `nil` when the carousel has no path.
    @discardableResult
    func observe(stops measured: [Double], measured isMeasured: Bool = true) -> Int? {
        stops = measured
        guard !shown, path != nil, isMeasured else { return nil }
        shown = true
        previous = current
        let stop = CarouselStop.shownStop(current, stopCount: measured.count)
        move(to: stop, animated: false)
        return stop
    }

    /// The stops of the plan changed after the first measure.
    func updateStops(_ measured: [Double]) { stops = measured }

    /// The value under the path as of a draw. When the number it names changed, the carousel goes
    /// to its stop (not while a finger holds the row; without animation under «reduce motion»).
    func update(value: JSONValue?) {
        current = value
        guard shown else { return }
        let before = previous
        previous = value
        guard !holding else { return }
        let active = CarouselRules.activeStop(stops, offset: offset)
        if let target = CarouselStop.follow(previous: before, next: value, stopCount: stops.count, active: active) {
            move(to: target, animated: !reducedMotion)
        }
    }

    /// A move by the reader: it never writes.
    private func move(to index: Int, animated: Bool) {
        guard index >= 0, index < stops.count, abs(offset - stops[index]) >= 0.5 else { return }
        person = false
        dirty = false
        cancelTimer?()
        cancelTimer = nil
        scrollToStop?(index, animated)
    }

    // MARK: Events of the scroll

    /// A finger (or a pointer) took the row.
    func personBegan() {
        guard path != nil else { return }
        person = true
        holding = true
    }

    /// A person moves the row without holding it (a wheel, a key): the next settled stop is theirs.
    func personMoved() {
        guard path != nil else { return }
        person = true
    }

    /// The finger lifted. A release where the scroll already stands gives no more offsets, so the
    /// release starts the quiet time.
    func personReleased() {
        guard holding else { return }
        holding = false
        if dirty { quiet() }
    }

    /// The offset of the scroll, from the logical start, changed.
    func scrolled(to newOffset: Double) {
        offset = newOffset
        guard path != nil, person else { return }
        dirty = true
        quiet()
    }

    /// The scroll came to rest by itself (the platform said so).
    func settle() {
        cancelTimer?()
        cancelTimer = nil
        guard path != nil, dirty, person, !holding else { return }
        dirty = false
        person = false
        let settled = CarouselRules.activeStop(stops, offset: offset)
        if let value = CarouselStop.write(settled: settled, byPerson: true, current: current), let path {
            write?(path, .number(Double(value)))
        }
    }

    private func quiet() {
        cancelTimer?()
        cancelTimer = later(CarouselStop.settleSeconds) { [weak self] in self?.settle() }
    }

    func cancel() {
        cancelTimer?()
        cancelTimer = nil
        holding = false
    }
}
