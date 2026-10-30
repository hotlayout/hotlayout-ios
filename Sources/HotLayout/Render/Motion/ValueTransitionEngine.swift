import SwiftUI

/// The clock of the numbers a node leads. The node does not learn a second way to read numbers:
/// the engine hands back the node's data scope with the counted paths replaced by the number
/// shown at this frame, and the node formats it as it always does.
///
/// Two scopes come out: `stepped` for the label (the number moves in steps) and `smooth` for
/// the fill of a scale (no step). A change during a transition starts from the value shown at
/// that moment and runs the full duration.
///
/// A value: the view keeps the engine it has committed and draws each frame from a copy brought
/// up to the data and the moment of that frame.
struct ValueTransitionEngine {
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
        /// A run is in progress: the node is measured with its data as they are (the final
        /// values) and the stepped or smooth numbers are only painted over that place.
        var held = false

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
    mutating func takeFinished() -> Bool {
        defer { justFinished = false }
        return justFinished
    }

    func shownNow(_ path: String, smooth: Bool) -> Double? {
        guard let run = runs[path] else { return nil }
        let t = run.start.map { time - $0 } ?? 0
        return ValueTransition.value(from: run.from, to: run.to, t: t, digits: smooth ? nil : run.digits)
    }

    /// The appearance: every number of the node starts from zero at the moment it is shown.
    mutating func appear(targets: [ValueTransition.Target], read: (String) -> JSONValue?, reducedMotion: Bool) {
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
    mutating func sync(targets: [ValueTransition.Target], read: (String) -> JSONValue?, leads: Bool, localeKey: String, reducedMotion: Bool) {
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
    mutating func tick(_ milliseconds: Double) {
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

    /// The moment the last run in progress ends; `nil` when none runs or a run has not had its first frame.
    var endsAt: Double? {
        let ends = runs.values.map { $0.start.map { $0 + ValueTransition.durationMs } }
        guard !ends.isEmpty, !ends.contains(where: { $0 == nil }) else { return nil }
        return ends.compactMap { $0 }.max()
    }

    /// Every run starts again at its first frame (the tests' fixed moment counts from there).
    mutating func rewind() {
        for path in runs.keys { runs[path]?.start = nil }
    }

    func shown(_ scope: DataScope) -> Shown {
        if runs.isEmpty { return .plain(scope) }
        var result = Shown.plain(scope)
        result.held = true
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
///
/// Each frame is drawn from a copy of the committed engine brought up to the data of this update
/// and the moment of the frame, so the frame that brings a change already shows its start. The
/// engine itself changes only after the update: when the node appears, when its data change and
/// when the last run ends.
struct ValueTransitioned<Content: View>: View {
    let node: DocumentNode
    let context: RenderContext
    let content: (ValueTransitionEngine.Shown) -> Content

    @State private var engine: ValueTransitionEngine
    @Environment(\.valueTransitionElapsedMs) private var fixedElapsed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `engine` lets a test hand in an engine that has already read the data before.
    init(node: DocumentNode, context: RenderContext, engine: ValueTransitionEngine? = nil, content: @escaping (ValueTransitionEngine.Shown) -> Content) {
        self.node = node
        self.context = context
        self.content = content
        _engine = State(initialValue: engine ?? ValueTransitionEngine())
    }

    /// Everything the engine reads from one update. The commit after an update works from this
    /// value alone: the action of `onChange` sees the view as it was before the update.
    private struct Inputs: Equatable {
        var leads: Bool
        var appears: Bool
        var targets: [ValueTransition.Target]
        var appearTargets: [ValueTransition.Target]
        var values: [String: JSONValue]
        var localeKey: String
        var reducedMotion: Bool

        func read(_ path: String) -> JSONValue? { values[path] }
    }

    var body: some View {
        let leads = ValueTransition.animatesChanges(node.props)
        let appears = ValueTransition.animatesIn(node.props)
        if !leads && !appears {
            content(.plain(context.scope))
        } else {
            let inputs = inputs(leads: leads, appears: appears)
            TimelineView(.animation(paused: !frame(inputs, at: Date()).isRunning)) { timeline in
                content(frame(inputs, at: timeline.date).shown(context.scope))
            }
            .onAppear { commit(inputs) }
            .onChange(of: inputs) { commit($0) }
            .task(id: engine.endsAt) { await finishRuns() }
        }
    }

    private func inputs(leads: Bool, appears: Bool) -> Inputs {
        let appearTargets = ValueTransition.appearTargets(node.props)
        let targets = leads ? ValueTransition.targets(node.props) : appearTargets
        let literal = node.props["value"]?["kind"]?.stringValue == "literal" ? node.props["value"]?["value"] : nil
        var values: [String: JSONValue] = [:]
        for path in Set((targets + appearTargets).map(\.path)) {
            // A literal `value` of a scale stands under its own key.
            let value = path == ValueTransition.literalKey ? literal : context.scope[path]
            if let value, !value.isNull { values[path] = value }
        }
        return Inputs(
            leads: leads, appears: appears, targets: targets, appearTargets: appearTargets, values: values,
            localeKey: "\(context.locale.translation ?? "")|\(context.locale.formatting ?? "")", reducedMotion: reduceMotion)
    }

    /// The committed engine brought up to the data of an update.
    private func synced(_ inputs: Inputs) -> ValueTransitionEngine {
        var next = engine
        if inputs.appears, !next.mounted {
            next.appear(targets: inputs.appearTargets, read: inputs.read, reducedMotion: inputs.reducedMotion)
        }
        next.sync(targets: inputs.targets, read: inputs.read, leads: inputs.leads, localeKey: inputs.localeKey, reducedMotion: inputs.reducedMotion)
        return next
    }

    /// The engine as the frame at `date` sees it; nothing is stored.
    private func frame(_ inputs: Inputs, at date: Date) -> ValueTransitionEngine {
        var shown = synced(inputs)
        if let fixedElapsed {
            // The first frame fixes the start of a run; the second is the chosen moment.
            shown.rewind()
            shown.tick(0)
            shown.tick(fixedElapsed)
        } else {
            shown.tick(Self.milliseconds(date))
        }
        return shown
    }

    /// Keeps what the frames have read: the data seen and the start of every new run.
    private func commit(_ inputs: Inputs) {
        var next = synced(inputs)
        next.tick(Self.milliseconds(Date()))
        engine = next
    }

    /// Waits for the end of the last run and lets it go, so that the timeline pauses.
    private func finishRuns() async {
        guard let end = engine.endsAt else { return }
        let wait = max(0, end - Self.milliseconds(Date()))
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000))
        guard !Task.isCancelled else { return }
        var next = engine
        next.tick(max(end, Self.milliseconds(Date())))
        engine = next
    }

    private static func milliseconds(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate * 1000 }
}
