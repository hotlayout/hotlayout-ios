import Foundation

/// The rules of a modal layer, as numbers and words the shared tables check: the box of a sheet
/// or a window, the blur radius, the drag that closes a sheet, the Escape key.
enum ModalRules {
    /// Widest window in the middle (`modalLayer.center.maxWidth`).
    static let windowMaxWidth: Double = 400
    /// Opacity of the black scrim (`modalLayer.scrim.opacity`).
    static let scrimOpacity: Double = 0.45
    /// The scale a window grows from while it fades in.
    static let windowStartScale: Double = 0.96
    /// The margin of a window when the theme has no `xl` step.
    static let defaultMargin: Double = 24

    // MARK: Placement and box

    /// `center` is a window; every other word, and no field, is a sheet (`unknownModalPlacement`).
    static func isWindow(_ placement: JSONValue?) -> Bool { placement?.stringValue == "center" }

    /// The width of the layer: it is known before the content is measured.
    static func width(window: Bool, viewport: Double, margin: Double) -> Double {
        window ? max(0, min(viewport - 2 * margin, windowMaxWidth)) : viewport
    }

    struct Box: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var scrolls: Bool
    }

    /// The rectangle of the layer in the area: a sheet is as wide as the area and pressed to its
    /// bottom; a window is centred. The height follows the content, no taller than the room.
    static func box(window: Bool, viewportWidth: Double, viewportHeight: Double, contentHeight: Double, margin: Double) -> Box {
        let layerWidth = width(window: window, viewport: viewportWidth, margin: margin)
        let available = window ? max(0, viewportHeight - 2 * margin) : viewportHeight
        let height = min(max(0, contentHeight), available)
        let scrolls = contentHeight > available
        if window {
            return Box(x: (viewportWidth - layerWidth) / 2, y: (viewportHeight - height) / 2, width: layerWidth, height: height, scrolls: scrolls)
        }
        return Box(x: 0, y: viewportHeight - height, width: layerWidth, height: height, scrolls: scrolls)
    }

    // MARK: Blur

    /// The radius under the layer: a whole number 1…40, else no blur.
    static func blurRadius(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue, number == number.rounded(), number >= 1, number <= 40 else { return nil }
        return Int(number)
    }

    /// The blur applied to one layer of the stack: the blurs of the layers above it add up as the
    /// variances of Gaussian blurs do.
    static func combinedBlur(_ radii: [Int]) -> Double {
        sqrt(radii.reduce(0) { $0 + Double($1 * $1) })
    }

    // MARK: Drag down

    static let dismissShare: Double = 0.3
    static let flingVelocity: Double = 700
    static let velocityWindowMs: Double = 100
    static let touchSlop: Double = 10
    static let returnMotion = Motion(durationMs: 250, curve: [0.2, 0, 0, 1])
    static let exitMotion = Motion(durationMs: 200, curve: [0.4, 0, 1, 1])

    struct Motion: Equatable {
        let durationMs: Int
        let curve: [Double]
    }

    enum DragOutcome: String { case dismiss, `return` }

    /// What the released sheet does: a fling decides, otherwise the share of its height.
    static func dragOutcome(sheetHeight: Double, dragged: Double, velocity: Double) -> DragOutcome {
        if velocity <= -flingVelocity { return .return }
        if velocity >= flingVelocity { return .dismiss }
        if sheetHeight <= 0 { return .return }
        return dragged >= sheetHeight * dismissShare ? .dismiss : .return
    }

    /// Whether a finger's move drags the sheet instead of scrolling its body.
    static func dragStarts(sheet: Bool, dismissible: Bool, scrolled: Double, dy: Double, dx: Double, onHandle: Bool) -> Bool {
        if !sheet || !dismissible { return false }
        if dy <= touchSlop || abs(dx) >= dy { return false }
        return onHandle || scrolled <= 0
    }

    /// The speed at release, down positive, logical pixels per second: from the samples of the
    /// last `velocityWindowMs` (time in seconds, position of the finger).
    static func velocity(samples: [(time: Double, y: Double)]) -> Double {
        guard let last = samples.last else { return 0 }
        let recent = samples.filter { (last.time - $0.time) * 1000 <= velocityWindowMs }
        guard let first = recent.first, last.time > first.time else { return 0 }
        return (last.y - first.y) / (last.time - first.time)
    }

    // MARK: Keys

    /// Steps back made by a key: one for Escape pressed on a layer that may be closed.
    static func escapeSteps(key: String, repeating: Bool, modalOnTop: Bool, topDismissible: Bool) -> Int {
        key == "Escape" && !repeating && modalOnTop && topDismissible ? 1 : 0
    }
}
