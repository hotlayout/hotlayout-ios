import SwiftUI

private struct TickClockKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

private struct ClockPinnedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The host gave the moment («now»): it owns the clock, and no countdown ticks.
    var countdownClockPinned: Bool {
        get { self[ClockPinnedKey.self] }
        set { self[ClockPinnedKey.self] = newValue }
    }

    /// Whole seconds a countdown below has ticked, instead of the real clock; the tests read a real
    /// node at a chosen second.
    var countdownTickedSeconds: Double? {
        get { self[TickClockKey.self] }
        set { self[TickClockKey.self] = newValue }
    }
}

enum CountdownRules {
    /// Whether the text shows a part of a time left: a binding with `format: countdownPart`, alone or
    /// inside a template.
    static func ticks(_ props: JSONObject) -> Bool {
        guard let content = props["content"]?.objectValue else { return false }
        if content["kind"]?.stringValue == "template" {
            guard let values = content["values"]?.objectValue else { return false }
            return values.contains { isCountdown($0.value) }
        }
        return isCountdown(.object(content))
    }

    private static func isCountdown(_ value: JSONValue) -> Bool {
        guard let record = value.objectValue else { return false }
        return record["kind"]?.stringValue == "binding" && record["format"]?.stringValue == "countdownPart"
    }

    enum Clock: Equatable { case still, fixed, running }

    /// What the clock of a text does: a text without a countdown, and any text under a host that gave the
    /// moment («now»), stands still; the tests may fix the ticked seconds; otherwise it runs.
    static func clock(_ props: JSONObject, pinned: Bool, fixedSeconds: Double?) -> Clock {
        guard ticks(props) else { return .still }
        if fixedSeconds != nil { return .fixed }
        return pinned ? .still : .running
    }

    /// The moment `seconds` whole seconds later: the fraction of the sample moment stays, so the
    /// parts of the time left go down by whole seconds.
    static func now(_ base: Double, ticked seconds: Double) -> Double { base + seconds.rounded(.down) * 1000 }
}

/// Hosts a text whose time left counts down: once a second, from the moment the reader already uses
/// as «now». The clock runs only while the node is on screen, so a screen under another one or a
/// scrolled-away node does not keep the app awake.
struct CountdownTicking<Content: View>: View {
    let node: DocumentNode
    let context: RenderContext
    let content: (RenderContext) -> Content

    @State private var start = Date()
    @State private var onScreen = false
    @Environment(\.countdownTickedSeconds) private var fixedSeconds
    @Environment(\.countdownClockPinned) private var pinned

    var body: some View {
        let clock = CountdownRules.clock(node.props, pinned: pinned, fixedSeconds: fixedSeconds)
        if clock == .still {
            content(context)
        } else if let fixedSeconds {
            content(at(fixedSeconds))
        } else {
            Group {
                if onScreen {
                    TimelineView(.periodic(from: start, by: 1)) { timeline in
                        content(at(timeline.date.timeIntervalSince(start) + 0.05))
                    }
                } else {
                    content(context)
                }
            }
            .onAppear {
                start = Date()
                onScreen = true
            }
            .onDisappear { onScreen = false }
        }
    }

    private func at(_ seconds: Double) -> RenderContext {
        var ticked = context
        ticked.now = CountdownRules.now(context.now, ticked: seconds)
        return ticked
    }
}
