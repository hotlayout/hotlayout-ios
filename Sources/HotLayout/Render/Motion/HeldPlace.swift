import SwiftUI

private struct PaintsTabularDigitsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The text below paints its digits at equal width: set on the number in between while a
    /// value runs, so that it does not shiver as the figures change.
    var paintsTabularDigits: Bool {
        get { self[PaintsTabularDigitsKey.self] }
        set { self[PaintsTabularDigitsKey.self] = newValue }
    }
}

/// A node whose value runs takes the place of its FINAL content: that content is laid out
/// (invisible), and the content with the value in between is painted over the same place, from
/// the same start. The layout changes once, when the data change, and never on a frame of the
/// motion. A longer text in between is not measured and may overflow the place for the frames of
/// the motion; the painted layer is out of the accessibility tree, so a screen reader hears the
/// final text.
struct HeldPlace<Final: View, Painted: View>: View {
    let held: Bool
    let final: Final
    let painted: Painted

    init(held: Bool, @ViewBuilder final: () -> Final, @ViewBuilder painted: () -> Painted) {
        self.held = held
        self.final = final()
        self.painted = painted()
    }

    var body: some View {
        // The same structure on every frame, so the final content keeps its identity when the
        // motion ends. Top-leading flips with the layout direction: in right-to-left it is the
        // start of the line.
        final
            .opacity(held ? 0 : 1)
            .overlay(alignment: .topLeading) {
                if held {
                    painted
                        .environment(\.paintsTabularDigits, true)
                        .accessibilityHidden(true)
                }
            }
    }
}
