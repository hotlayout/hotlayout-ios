import SwiftUI

/// The clock of the numbers a node leads. The node does not learn a second way to read numbers:
/// the engine hands back the node's data scope with the counted paths replaced by the number
/// shown at this frame, and the node formats it as it always does.
///
/// Two scopes come out: `stepped` for the label (the number moves in steps) and `smooth` for
/// the fill of a scale (no step). A change during a transition starts from the value shown at
/// that moment and runs the full duration.
final class ValueTransitionEngine {
    struct Run {
        var from: Double
        var to: Double
        var digits: Int
        var scale: Bool
        /// The time of the first frame; before it the old value stays.
        var start: Double?
    }

    struct Ends: Equatable {
        var from: Double
        var to: Double
        var shown: Double
    }

    /// What the node reads in place of its own data.
    struct Shown {
        var stepped: DataScope
        var smooth: DataScope
        /// The shown number of a LITERAL `value` of a scale while it grows.
        var literal: (stepped: Double, smooth: Double)?
        /// The ends of every scale run in progress, by path (`#value` for a literal).
        var ends: [String: Ends]

        static func plain(_ scope: DataScope) -> Shown { Shown(stepped: scope, smooth: scope, literal: nil, ends: [:]) }
    }

    private(set) var mounted = false
    private var localeKey: String?
    private var last: [String: JSONValue] = [:]
    private(set) var runs: [String: Run] = [:]
    private var time = 0.0

    var isRunning: Bool { !runs.isEmpty }
    private var justFinished = false

    /// True once after the last run ended.
    func takeFinished() -> Bool {
        defer { justFinished = false }
        return justFinished
    }

    func shownNow(_ path: String, smooth: Bool) -> Double? {
        guard let run = runs[path] else { return nil }
        let t = run.start.map { time - $0 } ?? 0
        return ValueTransition.value(from: run.from, to: run.to, t: t, digits: smooth ? nil : run.digits)
    }

    /// The appearance: every number of the node starts from zero at the moment it is shown.
    func appear(targets: [ValueTransition.Target], read: (String) -> JSONValue?, reducedMotion: Bool) {
        for target in targets {
            let raw = read(target.path)
            last[target.path] = raw ?? .null
            guard ValueTransition.appearDecision(animates: true, to: raw, reducedMotion: reducedMotion) == .grows, let end = raw?.numberValue else { continue }
            runs[target.path] = Run(
                from: ValueTransition.appearFrom, to: end,
                digits: ValueTransition.digits(from: ValueTransition.appearFrom, to: end, format: target.format, currency: target.currency),
                scale: target.scale, start: nil
            )
        }
    }

    /// Reads the data of this render. The first render of a node is its first show: no transition.
    func sync(targets: [ValueTransition.Target], read: (String) -> JSONValue?, leads: Bool, localeKey: String, reducedMotion: Bool) {
        let first = !mounted
        let localeChanged = !first && localeKey != self.localeKey
        mounted = true
        self.localeKey = localeKey
        // A language changed in the same step ends an appearance in progress.
        if localeChanged { runs.removeAll() }
        for target in targets {
            let raw = read(target.path)
            guard !first, let before = last[target.path] else {
                last[target.path] = raw ?? .null
                continue
            }
            if (raw ?? .null) == before { continue }
            last[target.path] = raw ?? .null
            if !leads {
                // Without `animateChanges` a change of the data ends the appearance.
                runs[target.path] = nil
                continue
            }
            let shown = runs[target.path].flatMap { shownNow(target.path, smooth: $0.scale) }
            let from: JSONValue = shown.map { .number($0) } ?? before
            let change = ValueTransition.Change(
                animates: true, shownBefore: true, from: from, to: raw, localeChanged: localeChanged, reducedMotion: reducedMotion)
            guard ValueTransition.decision(change) == .leads, let start = from.numberValue, let end = raw?.numberValue else {
                runs[target.path] = nil
                continue
            }
            runs[target.path] = Run(
                from: start, to: end,
                digits: ValueTransition.digits(from: start, to: end, format: target.format, currency: target.currency),
                scale: target.scale, start: nil
            )
        }
    }

    /// A frame at `milliseconds`: the first frame of a run fixes its start, a run past the
    /// duration ends.
    func tick(_ milliseconds: Double) {
        time = milliseconds
        let was = !runs.isEmpty
        defer { if was, runs.isEmpty { justFinished = true } }
        for (path, var run) in runs {
            if run.start == nil { run.start = milliseconds }
            if milliseconds - (run.start ?? milliseconds) >= ValueTransition.durationMs {
                runs[path] = nil
            } else {
                runs[path] = run
            }
        }
    }

    func shown(_ scope: DataScope) -> Shown {
        if runs.isEmpty { return .plain(scope) }
        var result = Shown.plain(scope)
        for (path, run) in runs {
            let step = shownNow(path, smooth: false)
            let flow = run.scale ? shownNow(path, smooth: true) : step
            if run.scale { result.ends[path] = Ends(from: run.from, to: run.to, shown: flow ?? run.to) }
            if path == ValueTransition.literalKey {
                result.literal = (step ?? run.to, flow ?? run.to)
                continue
            }
            if let step { result.stepped[path] = .number(step) }
            if let flow { result.smooth[path] = .number(flow) }
        }
        return result
    }
}

private struct ValueClockKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// Milliseconds since the first frame of every number run below, instead of the real clock;
    /// the tests read a real node at a chosen moment of a transition.
    var valueTransitionElapsedMs: Double? {
        get { self[ValueClockKey.self] }
        set { self[ValueClockKey.self] = newValue }
    }
}

/// Hosts a node that may lead its numbers: without `animateChanges` and `animateIn` the content
/// gets the data untouched; with them it is redrawn on every frame of the runs in progress.
struct ValueTransitioned<Content: View>: View {
    let node: DocumentNode
    let context: RenderContext
    let content: (ValueTransitionEngine.Shown) -> Content

    @State private var engine: ValueTransitionEngine
    @State private var finishes = 0
    @Environment(\.valueTransitionElapsedMs) private var fixedElapsed

    /// `engine` lets a test hand in an engine that has already read the data before.
    init(node: DocumentNode, context: RenderContext, engine: ValueTransitionEngine? = nil, content: @escaping (ValueTransitionEngine.Shown) -> Content) {
        self.node = node
        self.context = context
        self.content = content
        _engine = State(initialValue: engine ?? ValueTransitionEngine())
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let leads = ValueTransition.animatesChanges(node.props)
        let appears = ValueTransition.animatesIn(node.props)
        if !leads && !appears {
            content(.plain(context.scope))
        } else {
            let _ = update(leads: leads, appears: appears)
            let _ = finishes
            TimelineView(.animation(paused: !engine.isRunning)) { timeline in
                let _ = tick(timeline.date)
                let _ = pauseWhenFinished()
                content(engine.shown(context.scope))
            }
        }
    }

    private func tick(_ date: Date) {
        if let fixedElapsed {
            // The first frame fixes the start of a run; the second is the chosen moment.
            engine.tick(0)
            engine.tick(fixedElapsed)
        } else {
            engine.tick(date.timeIntervalSinceReferenceDate * 1000)
        }
    }

    /// The timeline pauses only when the node is drawn again, so the end of the last run asks for it.
    private func pauseWhenFinished() {
        guard engine.takeFinished() else { return }
        DispatchQueue.main.async { finishes += 1 }
    }

    private func update(leads: Bool, appears: Bool) {
        let scope = context.scope
        let literal = node.props["value"]?["kind"]?.stringValue == "literal" ? node.props["value"]?["value"] : nil
        let read: (String) -> JSONValue? = { path in
            let value = path == ValueTransition.literalKey ? literal : scope[path]
            return value?.isNull == true ? nil : value
        }
        if appears, !engine.mounted {
            engine.appear(targets: ValueTransition.appearTargets(node.props), read: read, reducedMotion: reduceMotion)
        }
        let targets = leads ? ValueTransition.targets(node.props) : ValueTransition.appearTargets(node.props)
        let key = "\(context.locale.translation ?? "")|\(context.locale.formatting ?? "")"
        engine.sync(targets: targets, read: read, leads: leads, localeKey: key, reducedMotion: reduceMotion)
    }
}
