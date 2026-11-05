import SwiftUI

/// A ring of three quarters, turning once in 800 ms. It turns only while it is on the screen and the
/// person has not asked to reduce motion: otherwise it is drawn still, with no timeline at all (a
/// running timeline keeps automation, and the display, from ever seeing the app idle).
struct SwipeSpinner: View {
    let size: Double
    let color: Color
    let still: Bool

    @State private var onScreen = false

    var body: some View {
        Group {
            if still || !onScreen {
                ring(turn: 0)
            } else {
                TimelineView(.animation) { timeline in
                    ring(
                        turn: (timeline.date.timeIntervalSinceReferenceDate * 1000).truncatingRemainder(dividingBy: SwipeConfirmRules.spinnerTurnMs)
                            / SwipeConfirmRules.spinnerTurnMs)
                }
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }

    private func ring(turn: Double) -> some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: CGFloat(size / 8), lineCap: .butt))
            .frame(width: CGFloat(size - size / 8), height: CGFloat(size - size / 8))
            .rotationEffect(.degrees(turn * 360))
    }
}

/// The circle the button collapses into: the halo, the core with the ring of the border and the inset,
/// and the indicator at the centre. `elapsed` is the time of the collapse in milliseconds; it is animated
/// linearly and the curve of the collapse lies inside `SwipeMotion.collapse`.
struct SwipeCircleLayer: View, Animatable {
    var elapsed: Double
    let track: SwipeConfirmRules.Track
    let color: Color
    let glyphColor: Color
    let glyphSize: Double
    let still: Bool

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    var body: some View {
        let frame = SwipeMotion.collapse(track, elapsed: elapsed)
        let coreHeight = max(0, frame.height - 2 * frame.ring)
        let coreWidth = max(0, frame.width - 2 * frame.ring)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: CGFloat(frame.height / 2))
                .fill(color.opacity(frame.haloOpacity))
                .frame(width: CGFloat(frame.width), height: CGFloat(frame.height))
                .padding(.leading, CGFloat(frame.start))
            RoundedRectangle(cornerRadius: CGFloat(coreHeight / 2))
                .fill(color)
                .frame(width: CGFloat(coreWidth), height: CGFloat(coreHeight))
                .padding(.leading, CGFloat(frame.start + frame.ring))
                .padding(.top, CGFloat(frame.ring))
            SwipeSpinner(size: glyphSize, color: glyphColor, still: still)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The surface of the button (background, border, shadow) fades while it collapses.
struct SwipeSurfaceFade: ViewModifier, Animatable {
    var elapsed: Double

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(SwipeMotion.collapse(SwipeConfirmRules.Track(height: 0, width: 0, border: 0, inset: 0), elapsed: elapsed).surfaceOpacity)
    }
}
