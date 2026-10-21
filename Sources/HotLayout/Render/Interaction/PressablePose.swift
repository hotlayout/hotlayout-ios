import SwiftUI

/// Sinks a control under the finger and brings it back (`x-pressFeedback`): the scale is paint
/// only, so the neighbours do not move. A press shorter than the way down still reaches the
/// pressed pose before it returns. The same view serves the card (gesture) and the buttons
/// (`ButtonStyle`).
struct PressablePose<Content: View>: View {
    let kind: PressFeedbackRules.Kind?
    let pressed: Bool
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sunk = false
    @State private var downAt: Date?

    var body: some View {
        let pose = kind.map { PressFeedbackRules.pose($0, reduceMotion: reduceMotion) }
        content
            .scaleEffect(sunk ? (pose?.scale ?? 1) : 1)
            .opacity(sunk ? (pose?.opacity ?? 1) : 1)
            .onChange(of: pressed) { isPressed in
                guard kind != nil, isPressed else { return }
                downAt = Date()
                withAnimation(Self.curve(PressFeedbackRules.downCurve, ms: PressFeedbackRules.downMs)) { sunk = true }
            }
            // A new press cancels the return of the one before.
            .task(id: pressed) { await rise() }
    }

    /// After a release: the rest of the way down, then back up.
    @MainActor
    private func rise() async {
        guard kind != nil, !pressed, sunk else { return }
        let elapsed = downAt.map { Date().timeIntervalSince($0) * 1000 } ?? PressFeedbackRules.downMs
        let wait = max(0, PressFeedbackRules.downMs - elapsed)
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000))
        guard !Task.isCancelled else { return }
        withAnimation(Self.curve(PressFeedbackRules.upCurve, ms: PressFeedbackRules.upMs)) { sunk = false }
    }

    static func curve(_ points: [Double], ms: Double) -> Animation {
        .timingCurve(points[0], points[1], points[2], points[3], duration: ms / 1000)
    }
}

/// The style of a button: the pose of its kind while it is pressed.
struct PressFeedbackStyle: ButtonStyle {
    let kind: PressFeedbackRules.Kind?

    func makeBody(configuration: Configuration) -> some View {
        PressablePose(kind: kind, pressed: configuration.isPressed) { configuration.label }
    }
}
