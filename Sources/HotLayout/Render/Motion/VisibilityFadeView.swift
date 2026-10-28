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
struct FadingNode<Content: View>: View {
    let shown: Bool
    /// The language and the width class the condition was read in: a change of either is not a transition.
    let context: String
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.visibilityFadeNowMs) private var fixedNow
    @State private var kept = Kept()

    /// What the view keeps between draws; made in the first draw, with the first condition.
    final class Kept {
        var holder: VisibilityFadeHolder?
    }

    static func now() -> Double { Date().timeIntervalSinceReferenceDate * 1000 }

    var body: some View {
        let at = fixedNow ?? Self.now()
        let holder = kept.holder ?? VisibilityFadeHolder(shown: shown, context: context, now: at)
        let _ = kept.holder = holder
        let _ = holder.sync(shown: shown, context: context, now: at, animate: !reduceMotion)
        // One timeline at rest as well as in motion: the node keeps its identity (and its state)
        // when a transition starts or ends.
        let end = max(at, holder.endsAt ?? at)
        TimelineView(FadeSchedule(start: date(at), end: date(end))) { timeline in
            drawn(holder.frame(at: fixedNow ?? timeline.date.timeIntervalSinceReferenceDate * 1000))
        }
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
