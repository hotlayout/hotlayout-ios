import SwiftUI

/// The window a screen opens while it is built for its show: a node that is built inside it plays its
/// appearance, a node that finds it closed (it came later: its condition, a width class, a new record
/// of a list) stands at once. A screen closes it right after its first build.
final class AppearWindow {
    private(set) var isOpen = true

    func close() { isOpen = false }
}

private struct AppearWindowKey: EnvironmentKey {
    static let defaultValue: AppearWindow? = nil
}

private struct AppearClockKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// The window of the screen the node is drawn in. A node drawn with no screen around it plays.
    var appearWindow: AppearWindow? {
        get { self[AppearWindowKey.self] }
        set { self[AppearWindowKey.self] = newValue }
    }

    /// A fixed time (ms after the show) for every appearing node below, instead of the clock; the tests
    /// use it to read a real node at a chosen moment.
    var appearClockMs: Double? {
        get { self[AppearClockKey.self] }
        set { self[AppearClockKey.self] = newValue }
    }
}

/// What each node decided when it was built (by its id: it played, or it stood at once); the tests read it
/// to tell a screen that played from one that did not. Nothing in the reader reads it.
enum AppearTally {
    static var decisions: [(id: String, played: Bool)] = []
}

/// What one node decided when it was built, and when its clock began.
private final class AppearRun {
    var plays: Bool?
    var started: Date?

    func decide(_ open: Bool, id: String) -> Bool {
        if let plays { return plays }
        plays = open
        AppearTally.decisions.append((id, open))
        return open
    }
}

/// Paints the one-time appearance of a node: the opacity multiplies the node's own, a `rise` shifts it
/// down, along the screen vertical, after its own place. Nothing here touches layout: the box stands at
/// its place from the first frame, invisible while the delay runs.
struct NodeAppearModifier: ViewModifier {
    let appear: NodeAppear
    let id: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearWindow) private var window
    @Environment(\.appearClockMs) private var clock
    @State private var run = AppearRun()
    @State private var finished = false

    func body(content: Content) -> some View {
        let plays = run.decide(window?.isOpen ?? true, id: id)
        if reduceMotion || !plays {
            content
        } else if let clock {
            painted(content, elapsedMs: clock)
        } else {
            TimelineView(.animation(paused: finished)) { timeline in
                painted(content, elapsedMs: run.started.map { timeline.date.timeIntervalSince($0) * 1000 } ?? 0)
            }
            .onAppear {
                guard run.started == nil else { return }
                run.started = Date()
                let end = appear.endsAt / 1000
                DispatchQueue.main.asyncAfter(deadline: .now() + end + 0.05) { finished = true }
            }
        }
    }

    private func painted(_ content: Content, elapsedMs: Double) -> some View {
        let pose = appear.pose(at: elapsedMs)
        return content.offset(y: pose.y).opacity(pose.opacity)
    }
}

extension View {
    /// The node's appearance when it has a readable one.
    @ViewBuilder
    func nodeAppear(_ appear: NodeAppear?, id: String) -> some View {
        if let appear {
            modifier(NodeAppearModifier(appear: appear, id: id))
        } else {
            self
        }
    }
}
