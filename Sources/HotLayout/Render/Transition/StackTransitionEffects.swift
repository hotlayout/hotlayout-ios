import SwiftUI

private struct ScreenInFrontKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// The screen is the one in front of the person: the top of the stack, not covered by a layer and not
    /// moving away. Whatever runs by time (a carousel that advances) waits when it is not.
    var screenInFront: Bool {
        get { self[ScreenInFrontKey.self] }
        set { self[ScreenInFrontKey.self] = newValue }
    }
}

/// A motion of a step in play: the plan and how far it has gone. `elapsedMs` is the value the stack
/// animates (linearly): the curve of the contract is applied by the frame function, not by SwiftUI.
struct StackMotion: Equatable {
    var plan: ScreenTransitionPlan
    var elapsedMs: Double
    var rightToLeft = false
}

/// A layer that comes or goes with the motion of its step.
struct LayerMotion: Equatable {
    var motion: StackMotion
    /// The layer comes (`false`: it goes, drawn after the stack no longer holds it).
    var incoming: Bool

    /// A layer that stands where it stands: no motion.
    static let rest = LayerMotion(motion: StackMotion(plan: .still(.start), elapsedMs: 0), incoming: true)

    var layerFrame: TransitionLayerFrame {
        let frame = ScreenTransition.frame(motion.plan, at: motion.elapsedMs)
        return incoming ? frame.incoming : frame.outgoing
    }
}

/// The shift and the scale of a screen or a layer, as the frame of the contract gives them: `x` as a
/// share of the width of the area (mirrored in right-to-left writing), `y` as a share of the layer's own
/// height, the scale about the centre of the layer.
struct FrameGeometry: GeometryEffect {
    var motion: LayerMotion
    /// The width the share `x` is of: the area the host gave the stack.
    var areaWidth: Double

    var animatableData: Double {
        get { motion.motion.elapsedMs }
        set { motion.motion.elapsedMs = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let frame = motion.layerFrame
        let mirror = motion.motion.rightToLeft ? -1.0 : 1.0
        var transform = CGAffineTransform(translationX: CGFloat(frame.x * areaWidth * mirror), y: CGFloat(frame.y) * size.height)
        if frame.scale != 1 {
            transform = transform.translatedBy(x: size.width / 2, y: size.height / 2)
                .scaledBy(x: CGFloat(frame.scale), y: CGFloat(frame.scale))
                .translatedBy(x: -size.width / 2, y: -size.height / 2)
        }
        return ProjectionTransform(transform)
    }
}

/// The opacity of a screen or a layer at a moment of its motion, times the opacity it has anyway.
struct FrameOpacity: ViewModifier, Animatable {
    var motion: LayerMotion
    var base = 1.0

    var animatableData: Double {
        get { motion.motion.elapsedMs }
        set { motion.motion.elapsedMs = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(base * motion.layerFrame.opacity)
    }
}

/// The scrim under a layer: its resting opacity times the share the frame of the motion gives.
struct ScrimOpacity: ViewModifier, Animatable {
    var motion: StackMotion
    var resting: Double

    var animatableData: Double {
        get { motion.elapsedMs }
        set { motion.elapsedMs = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(resting * ScreenTransition.frame(motion.plan, at: motion.elapsedMs).scrim)
    }
}

/// The blur of what lies under a layer: it comes and goes with the layer (the share of the scrim) between
/// what the layers that stay give and what they give with the layer that comes or goes.
struct StackBlur: ViewModifier, Animatable {
    /// The radius with the layer that moves left out, and with it.
    var without: Double
    var with: Double
    var motion: StackMotion?
    var opaque = false

    var animatableData: Double {
        get { motion?.elapsedMs ?? 0 }
        set { motion?.elapsedMs = newValue }
    }

    private var radius: Double {
        guard let motion else { return with }
        let share = ScreenTransition.frame(motion.plan, at: motion.elapsedMs).scrim
        return without + (with - without) * share
    }

    func body(content: Content) -> some View {
        content.blur(radius: radius, opaque: opaque)
    }
}

/// A whole stack that comes or goes with a page motion (`push`, `pop`, `crossfade`).
struct PageFrame: ViewModifier {
    var motion: LayerMotion
    var areaWidth: Double

    func body(content: Content) -> some View {
        content.modifier(FrameGeometry(motion: motion, areaWidth: areaWidth)).modifier(FrameOpacity(motion: motion))
    }
}
