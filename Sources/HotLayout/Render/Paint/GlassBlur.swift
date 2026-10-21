import SwiftUI

/// Glass (`style.backdropBlur`, 9.20.0): whatever lies under the box of a node is blurred within
/// the box and its radius; the node's own background and content lie over the blur and are never
/// blurred. The reader's own surface for it is the system's blur view: UIKit gives the blur
/// strength only as a fraction of its effect, so the radius (a standard deviation in points,
/// 1…40) is mapped onto that fraction; the area and the order are the contract's, the exact
/// sigma and the exact colour are not (see the platform notes).
#if canImport(UIKit)
import UIKit

private final class GlassEffectView: UIVisualEffectView {
    /// The strength of the blur is the opacity of the effect view. (A paused `UIViewPropertyAnimator`
    /// would give a true fraction of the blur, but it counts as an animation in flight: the screen
    /// is never idle for automation, and every tap waits the whole minute of its timeout.)
    func apply(radius: Int, dark: Bool) {
        // The material follows the brightness of the THEME, not of the device: a dark screen under a
        // light material would be washed out.
        overrideUserInterfaceStyle = dark ? .dark : .light
        effect = UIBlurEffect(style: GlassBlur.effectStyle(dark: dark))
        alpha = GlassBlur.strength(forRadius: radius)
    }
}

struct GlassBlurView: UIViewRepresentable {
    let radius: Int
    @Environment(\.glassOnDarkTheme) private var dark

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = GlassEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        view.apply(radius: radius, dark: dark)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        (view as? GlassEffectView)?.apply(radius: radius, dark: dark)
    }
}
#else
struct GlassBlurView: View {
    let radius: Int
    var body: some View { Rectangle().fill(.ultraThinMaterial) }
}
#endif

private struct GlassOnDarkThemeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the theme of the screen is dark: the material of the glass is dark with it.
    var glassOnDarkTheme: Bool {
        get { self[GlassOnDarkThemeKey.self] }
        set { self[GlassOnDarkThemeKey.self] = newValue }
    }
}

enum GlassBlur {
    #if canImport(UIKit)
    /// The system blur that adds the least colour of its own. Every system blur also lifts and
    /// greys what lies under it; of the ones that follow the brightness of the theme, the dark
    /// one moves the colour of a dark screen least, and the ultra thin material the colour of a
    /// light one.
    static func effectStyle(dark: Bool) -> UIBlurEffect.Style {
        dark ? .dark : .systemUltraThinMaterial
    }
    #endif

    /// The share of the system blur that stands for a radius: the whole effect at 40 points, the
    /// largest radius of the contract. The system blur cannot be had without its tint, and the tint
    /// weakens with the same opacity as the blur, so a small share is the price of a colour near
    /// the one under a plain blur.
    static func strength(forRadius radius: Int) -> CGFloat {
        CGFloat(min(1, Double(max(1, radius)) / 40))
    }
}

extension View {
    /// The blur under this view's box, clipped by the shape; lies behind everything the view draws.
    @ViewBuilder
    func glass(_ radius: Int?, shape: LogicalCornersShape) -> some View {
        if let radius {
            self.background(GlassBlurView(radius: radius).clipShape(shape).allowsHitTesting(false))
        } else {
            self
        }
    }
}
