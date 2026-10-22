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
    private var radius = 1
    private var cover = 0.0
    private var darkTheme = false
    /// Whether what lies around the box is light, once read from the screen; nil until then.
    private var lightUnder: Bool?
    private var appliedDark: Bool?
    private var sampledBox: CGRect = .null

    /// The strength of the blur is the opacity of the effect view. (A paused `UIViewPropertyAnimator`
    /// would give a true fraction of the blur, but it counts as an animation in flight: the screen
    /// is never idle for automation, and every tap waits the whole minute of its timeout.)
    func apply(radius: Int, cover: Double, dark: Bool) {
        self.radius = radius
        self.cover = cover
        darkTheme = dark
        refresh()
    }

    private func refresh() {
        // The system blur cannot be had without a tint of its own, so the tint has to agree with
        // what lies under the glass: a dark tint greys a light picture, a light one washes out a
        // dark one. Until the screen has been read, the brightness of the theme stands in.
        let dark = GlassBlur.darkMaterial(lightUnder: lightUnder, darkTheme: darkTheme)
        if dark != appliedDark {
            appliedDark = dark
            overrideUserInterfaceStyle = dark ? .dark : .light
            effect = UIBlurEffect(style: GlassBlur.effectStyle(dark: dark))
        }
        alpha = GlassBlur.strength(forRadius: radius, cover: cover)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        sampledBox = .null
        scheduleSample()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window else { return }
        if convert(bounds, to: window) != sampledBox { scheduleSample() }
    }

    /// The screen is read once it has been drawn, and again once an entry transition has settled.
    private func scheduleSample() {
        for delay in GlassBlur.sampleDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sample() }
        }
    }

    /// Reads the brightness of a band around the box from what is on the screen now. The band lies
    /// outside the box, so the blur of this view never takes part in its own choice.
    private func sample() {
        guard let window, !bounds.isEmpty else { return }
        let box = convert(bounds, to: window)
        let band = GlassBlur.sampleBand
        let area = box.insetBy(dx: -band, dy: -band).intersection(window.bounds).integral
        guard !area.isEmpty else { return }
        let width = Int(area.width), height = Int(area.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }
            let whole = CGRect(origin: CGPoint(x: -area.minX, y: -area.minY), size: window.bounds.size)
            return window.drawHierarchy(in: whole, afterScreenUpdates: false)
        }
        guard drawn else { return }
        let inner = box.offsetBy(dx: -area.minX, dy: -area.minY)
        guard let luma = GlassBlur.bandLuma(rgba: pixels, width: width, height: height, excluding: inner)
        else { return }
        sampledBox = box
        let light = GlassBlur.isLight(luma: luma, was: lightUnder)
        if light != lightUnder {
            lightUnder = light
            refresh()
        }
    }
}

struct GlassBlurView: UIViewRepresentable {
    let radius: Int
    /// The opacity of the node's own background colour over the blur (0 for a gradient or an image).
    var cover: Double = 0
    @Environment(\.glassOnDarkTheme) private var dark

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = GlassEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        view.apply(radius: radius, cover: cover, dark: dark)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        (view as? GlassEffectView)?.apply(radius: radius, cover: cover, dark: dark)
    }
}
#else
struct GlassBlurView: View {
    let radius: Int
    var cover: Double = 0
    var body: some View { Rectangle().fill(.ultraThinMaterial) }
}
#endif

private struct GlassOnDarkThemeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the theme of the screen is dark: the glass takes a dark material with it until the
    /// picture under the glass has been read.
    var glassOnDarkTheme: Bool {
        get { self[GlassOnDarkThemeKey.self] }
        set { self[GlassOnDarkThemeKey.self] = newValue }
    }
}

enum GlassBlur {
    #if canImport(UIKit)
    /// The system blur that adds the least colour of its own over a picture of that brightness:
    /// the dark blur over a dark picture, the ultra thin light material over a light one.
    static func effectStyle(dark: Bool) -> UIBlurEffect.Style {
        dark ? .dark : .systemUltraThinMaterialLight
    }
    #endif

    /// The opacity of a background colour that lies over the glass; a gradient or an image counts
    /// as none, its opacity varies over the box.
    static func cover(_ background: BackgroundValue?) -> Double {
        if case .color(let color)? = background { return color.alpha }
        return 0
    }

    /// The material is dark when the picture under the glass is dark; before the picture has been
    /// read, when the theme is.
    static func darkMaterial(lightUnder: Bool?, darkTheme: Bool) -> Bool {
        lightUnder.map { !$0 } ?? darkTheme
    }

    /// The share of the system blur that stands for a radius: the whole effect at 40 points, the
    /// largest radius of the contract. The system blur cannot be had without its tint, and the tint
    /// weakens with the same opacity as the blur, so only a share is spent. What shows of the tint
    /// is that share less what the node's own background covers: under a background of opacity `c`
    /// the effect may be `1 / (1 − c)` times stronger for the same tint showing through, so a bar
    /// with a nearly opaque background blurs fully while a faint glass card keeps its colour.
    static func strength(forRadius radius: Int, cover: Double = 0) -> CGFloat {
        let share = min(1, Double(max(1, radius)) / 40)
        let showing = 1 - min(max(cover, 0), 1)
        return CGFloat(showing <= share ? 1 : share / showing)
    }

    /// The width of the band around the box whose brightness chooses the material, in points.
    static let sampleBand: CGFloat = 8
    /// When the screen is read after the glass appears or moves, in seconds.
    static let sampleDelays: [Double] = [0.05, 0.4, 1.0]

    /// Light above this luma, dark below the lower bound; between them the last answer stands, so
    /// a picture near the middle does not make the glass flicker.
    static let lightAbove = 0.55
    static let darkBelow = 0.45

    static func isLight(luma: Double, was: Bool?) -> Bool {
        if luma >= lightAbove { return true }
        if luma <= darkBelow { return false }
        return was ?? (luma >= 0.5)
    }

    /// The mean luma (Rec. 601 weights over the stored sRGB values, 0…1) of the opaque pixels of
    /// an RGBA picture outside `inner`; nil when no such pixel is left.
    static func bandLuma(rgba: [UInt8], width: Int, height: Int, excluding inner: CGRect) -> Double? {
        var sum = 0.0
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                if inner.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) { continue }
                let i = (y * width + x) * 4
                let alpha = Double(rgba[i + 3])
                guard alpha > 0 else { continue }
                // Premultiplied over black: the luma of what is drawn.
                sum += (0.299 * Double(rgba[i]) + 0.587 * Double(rgba[i + 1]) + 0.114 * Double(rgba[i + 2])) / 255
                count += 1
            }
        }
        return count == 0 ? nil : sum / Double(count)
    }
}

extension View {
    /// The blur under this view's box, clipped by the shape; lies behind everything the view draws.
    @ViewBuilder
    /// `cover` is the opacity of the node's own background colour that lies over the blur.
    func glass(_ radius: Int?, shape: LogicalCornersShape, cover: Double = 0) -> some View {
        if let radius {
            self.background(GlassBlurView(radius: radius, cover: cover).clipShape(shape).allowsHitTesting(false))
        } else {
            self
        }
    }
}
