import SwiftUI

private struct VisibilityFadeNowKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// A fixed moment (ms, on the clock of `VisibilityFadeView.now`) for every fading node below,
    /// instead of the running clock; the tests use it to read a real node at a chosen moment.
    var visibilityFadeNowMs: Double? {
        get { self[VisibilityFadeNowKey.self] }
        set { self[VisibilityFadeNowKey.self] = newValue }
    }
}

extension RenderContext {
    /// The language and the width class a condition is read in: a change of either is no transition.
    var fadeContext: String { "\(widthClass.rawValue)|\(locale.translation ?? "")" }
}

/// Set on the cell of a grid that may be empty (a node fading in or out): the grid leaves a cell
/// of no size out of its rows.
struct CellMayBeAbsent: LayoutValueKey {
    static let defaultValue = false
}

/// Frames at the display rate from `start` until `end`, then one more at `end`, and the schedule is over.
private struct FadeSchedule: TimelineSchedule {
    let start: Date
    let end: Date

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(upcoming: max(startDate, start), end: end)
    }

    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date?
        let end: Date
        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            upcoming = current >= end ? nil : Swift.min(end, current.addingTimeInterval(1.0 / 60))
            return current
        }
    }
}

/// Draws a node whose condition fades it in and out. The node is in the layout only while its
/// phase says so; a leaving node catches no press and is not heard, an entering one is a control.
///
/// Out of the layout the node draws NOTHING (no view at all, not an empty one): a column counts
/// every view it is given, and an empty view there takes its gap. The body is drawn again at every
/// boundary of a phase (a leaving node leaves, a waiting one enters, an entering one is at rest),
/// by a timer of its own: the last frame of the timeline is not one to rely on, and a node that
/// stopped short of it stayed in the layout, nearly transparent, for good.
struct FadingNode<Content: View>: View {
    let shown: Bool
    /// The language and the width class the condition was read in: a change of either is not a transition.
    let context: String
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.visibilityFadeNowMs) private var fixedNow
    @State private var kept = Kept()
    /// Bumped by the timer at a boundary of a phase: the body reads it, so it is drawn again.
    @State private var tick = 0

    /// What the view keeps between draws; made in the first draw, with the first condition.
    final class Kept {
        var holder: VisibilityFadeHolder?
        /// The boundary the timer waits for, and what cancels it.
        var wake: Double?
        var cancel: (() -> Void)?
        deinit { cancel?() }
    }

    static func now() -> Double { Date().timeIntervalSinceReferenceDate * 1000 }

    var body: some View {
        let _ = tick
        let at = fixedNow ?? Self.now()
        let holder = kept.holder ?? VisibilityFadeHolder(shown: shown, context: context, now: at)
        let _ = kept.holder = holder
        let _ = holder.sync(shown: shown, context: context, now: at, animate: !reduceMotion)
        let _ = fixedNow == nil ? schedule(holder.nextBoundary(after: at)) : ()
        if holder.frame(at: at).inLayout {
            // One timeline at rest as well as in motion: the node keeps its identity (and its state)
            // while it is in the layout.
            let end = max(at, holder.endsAt ?? at)
            TimelineView(FadeSchedule(start: date(at), end: date(end))) { timeline in
                drawn(holder.frame(at: fixedNow ?? max(at, timeline.date.timeIntervalSinceReferenceDate * 1000)))
            }
        }
    }

    /// Draws the body again at `wake` (the next boundary of a phase); `nil` cancels the wait.
    private func schedule(_ wake: Double?) {
        guard wake != kept.wake else { return }
        kept.cancel?()
        kept.cancel = nil
        kept.wake = wake
        guard let wake else { return }
        let item = DispatchWorkItem { [tick = $tick, kept] in
            kept.wake = nil
            kept.cancel = nil
            tick.wrappedValue &+= 1
        }
        // A little after the boundary, so that the draw finds the phase over.
        let delay = max(0, (wake - Self.now()) / 1000) + 0.001
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        kept.cancel = { item.cancel() }
    }

    private func date(_ ms: Double) -> Date { Date(timeIntervalSinceReferenceDate: ms / 1000) }

    @ViewBuilder
    private func drawn(_ frame: VisibilityFade.Frame) -> some View {
        if frame.inLayout {
            content()
                .opacity(frame.opacity)
                .allowsHitTesting(frame.interactive)
                .accessibilityHidden(!frame.interactive)
        }
    }
}
