import SwiftUI

/// The look of the track, as `ButtonWidget` resolved it.
struct SwipeConfirmLook {
    var label: String
    var typography: TextStyleValue
    var theme: HotlayoutTheme
    /// The track (`background` of the node, else of the role).
    var trackFill: RGBA?
    var labelColor: RGBA
    /// The thumb: the background of the role, else `primary`.
    var thumbFill: RGBA
    var glyphColor: RGBA
    var borderColor: RGBA?
    var borderWidth: Double
    var dashedBorder: Bool
    var padding: Sides
    var shape: LogicalCornersShape
    var corners: Corners
    var shadow: [ShadowLayer]
    var fullWidth: Bool
    var icon: String?
}

/// `Button.confirm: 'swipe'`: a track with a thumb that is dragged along the line. A press
/// without a drag does nothing; the keyboard and assistive technology act at once. After the
/// action the thumb glides to the end and stays BUSY until the screen changes, the host's `async`
/// `onAction` returns, or eight seconds pass when the host's handler is not `async`.
struct SwipeConfirmButton: View {
    let node: DocumentNode
    let context: RenderContext
    let look: SwipeConfirmLook
    var disabled = false
    /// Fixed state for the tests and the frames of the fixtures (the thumb at this progress).
    var fixedProgress: Double?
    var fixedBusy = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    @State private var busy = false
    @State private var dragging = false
    @State private var captured: Bool?
    @State private var busyToken = 0

    private var action: JSONObject { node.props["action"]?.objectValue ?? ["type": "none"] }

    private var height: Double {
        look.typography.lineBox + look.padding.top + look.padding.bottom + 2 * look.borderWidth
    }

    private var track: SwipeConfirmRules.Track {
        SwipeConfirmRules.Track(height: height, width: 0, border: look.borderWidth, inset: look.theme.coreSpacing(SwipeConfirmRules.insetToken))
    }

    var body: some View {
        let geometry = SwipeConfirmRules.geometry(track)
        let shown = fixedProgress ?? progress
        let isBusy = busy || fixedBusy
        label(room: geometry.thumbRoom)
            .frame(height: height)
            .frame(maxWidth: look.fullWidth ? .infinity : nil)
            .background(look.shape.fill(look.trackFill?.color ?? .clear))
            .overlay {
                if look.borderWidth > 0, let color = look.borderColor {
                    if look.dashedBorder {
                        DashedBorderOverlay(width: look.borderWidth, color: color, radius: look.corners, rightToLeft: context.rightToLeft)
                    } else {
                        look.shape.inset(by: look.borderWidth / 2).stroke(color.color, lineWidth: look.borderWidth)
                    }
                }
            }
            .overlay { GeometryReader { proxy in thumb(width: Double(proxy.size.width), progress: shown, busy: isBusy) } }
            .shadowLayers(look.shadow, shape: look.shape)
            .contentShape(look.shape)
            .opacity(disabled ? 0.5 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(look.label)
            .accessibilityAddTraits(isBusy ? [.isButton, .updatesFrequently] : .isButton)
            .accessibilityAction { complete() }
            .modifier(SwipeKeyboard(act: { complete() }))
    }

    private func label(room: Double) -> some View {
        StyledText(text: look.label, style: look.typography, color: look.labelColor, theme: look.theme, alignment: .center)
            .padding(.horizontal, CGFloat(room))
            .frame(maxWidth: .infinity)
    }

    // MARK: Thumb

    private func thumb(width: Double, progress: Double, busy: Bool) -> some View {
        let t = SwipeConfirmRules.Track(height: height, width: width, border: look.borderWidth, inset: track.inset)
        let diameter = CGFloat(SwipeConfirmRules.geometry(t).diameter)
        let start = SwipeConfirmRules.thumbStart(t, progress: progress)
        // SwiftUI mirrors an offset in a right-to-left environment: `start` is from the inline start.
        return ZStack {
            Circle().fill(look.thumbFill.color)
            if busy {
                SwipeSpinner(size: look.typography.fontSize, color: look.glyphColor.color, still: reduceMotion)
            } else {
                IconGlyph(
                    name: look.icon ?? SwipeConfirmRules.thumbGlyph, glyph: look.typography.fontSize,
                    box: CGSize(width: look.typography.fontSize, height: look.typography.fontSize), color: look.glyphColor.color,
                    rightToLeft: context.rightToLeft)
            }
        }
        .frame(width: diameter, height: diameter)
        .offset(x: CGFloat(start), y: CGFloat((height - Double(diameter)) / 2))
        .animation(
            dragging || reduceMotion
                ? nil : .timingCurve(0.215, 0.61, 0.355, 1, duration: (busy ? SwipeConfirmRules.completeMs : SwipeConfirmRules.returnMs) / 1000),
            value: progress
        )
        .gesture(drag(travel: SwipeConfirmRules.geometry(t).travel))
    }

    private func drag(travel: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !disabled, !busy else { return }
                let dx = Double(value.translation.width)
                let dy = Double(value.translation.height)
                if captured == nil, max(abs(dx), abs(dy)) >= 4 { captured = SwipeConfirmRules.captures(dx: dx, dy: dy) }
                guard captured == true else { return }
                dragging = true
                progress = SwipeConfirmRules.progress(dx: dx, travel: travel, rightToLeft: context.rightToLeft)
            }
            .onEnded { _ in
                defer {
                    captured = nil
                    dragging = false
                }
                guard captured == true, !disabled, !busy else {
                    progress = busy ? 1 : 0
                    return
                }
                if SwipeConfirmRules.release(progress: progress, disabled: disabled) == .act {
                    complete()
                } else {
                    progress = 0
                }
            }
    }

    // MARK: Acting and the busy state

    /// The action runs at once; then the thumb stays at the end busy, or returns.
    private func complete() {
        guard !disabled, !busy else { return }
        let run = context.run(action, node)
        guard SwipeConfirmRules.afterRelease(run.runner) == .busy else {
            progress = 0
            return
        }
        dragging = false
        busy = true
        progress = 1
        busyToken += 1
        let token = busyToken
        let promise = run.task != nil
        if let task = run.task {
            Task { @MainActor in
                _ = await task.value
                end(token, on: .fulfilled, promise: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + SwipeConfirmRules.busyMaxMs / 1000) { end(token, on: .timeout, promise: promise) }
    }

    /// An event of the busy state; the thumb returns when the rule says so. The screen changing is
    /// the button leaving with its screen.
    private func end(_ token: Int, on event: SwipeConfirmRules.BusyEvent, promise: Bool) {
        guard token == busyToken, busy, SwipeConfirmRules.busyOutcome(event, promise: promise) == .giveBack else { return }
        busy = false
        progress = 0
    }
}

/// A ring of three quarters, turning once in 800 ms. It turns only while it is on the screen and the
/// person has not asked to reduce motion: otherwise it is drawn still, with no timeline at all (a
/// running timeline keeps automation, and the display, from ever seeing the app idle).
private struct SwipeSpinner: View {
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

/// Enter and Space act at once; a held key repeats nothing.
private struct SwipeKeyboard: ViewModifier {
    let act: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS) || os(macOS)
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .focusable()
                .onKeyPress(phases: [.down, .repeat]) { press in
                    guard press.key == .return || press.key == .space else { return .ignored }
                    if press.phase != .repeat { act() }
                    return .handled
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
