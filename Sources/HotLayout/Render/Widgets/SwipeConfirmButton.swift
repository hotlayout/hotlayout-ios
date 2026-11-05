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
/// without a drag does nothing; the keyboard and assistive technology act at once.
///
/// While the thumb is dragged a fill of the thumb's colour follows it and the label fades with the
/// travel. Released past the threshold the action runs at once, the thumb glides to the end and the
/// button collapses into a circle holding the busy indicator: that circle is the look of BUSY, and it
/// lasts until the screen changes, the host's `async` `onAction` returns, or eight seconds pass when
/// the host's handler is not `async`. The circle then expands back and the thumb returns.
///
/// With `confirmTransition: 'ripple'`, after a swipe on a `navigate` or `navigate.back` action the
/// circle grows over the whole screen and only then does the action run, under the fill
/// (`SwipeRippleStore`). The keyboard, assistive technology and «reduce motion» skip the circle and
/// the fill.
struct SwipeConfirmButton: View {
    let node: DocumentNode
    let context: RenderContext
    let look: SwipeConfirmLook
    var disabled = false
    /// Fixed state for the tests and the frames of the fixtures (the thumb at this progress).
    var fixedProgress: Double?
    var fixedBusy = false
    /// Fixed state: the collapse at this time in milliseconds (the circle is drawn from it).
    var fixedCollapse: Double?

    /// What the button is doing after a release.
    enum Phase: Equatable { case idle, gliding, collapsing, busy, expanding, returning, rippling }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.swipeRipple) private var ripples
    @Environment(\.swipeProbe) private var probe
    @State private var progress = 0.0
    @State private var phase = Phase.idle
    /// The collapse in milliseconds, animated linearly.
    @State private var collapse = 0.0
    /// The circle stands where the thumb was.
    @State private var circle = false
    @State private var dragging = false
    @State private var captured: Bool?
    @State private var busyToken = 0
    /// The host's `async` answer to the action of the busy state in progress.
    @State private var hostTask: Task<Void, Never>?
    /// The timed steps of the motion: the glide, the collapse, the expansion.
    @State private var stage: Task<Void, Never>?
    @State private var endPending = false
    @State private var ripplePending = false
    @State private var fill: SwipeRippleHandle?
    @State private var frame = FrameBox()

    private var action: JSONObject { node.props["action"]?.objectValue ?? ["type": .string(ActionType.none.rawValue)] }

    private var height: Double {
        look.typography.lineBox + look.padding.top + look.padding.bottom + 2 * look.borderWidth
    }

    private var track: SwipeConfirmRules.Track {
        SwipeConfirmRules.Track(height: height, width: 0, border: look.borderWidth, inset: look.theme.coreSpacing(SwipeConfirmRules.insetToken))
    }

    private var busy: Bool { phase != .idle && phase != .returning }

    var body: some View {
        let geometry = SwipeConfirmRules.geometry(track)
        let shown = fixedProgress ?? progress
        let isBusy = busy || fixedBusy
        let showsCircle = circle || fixedCollapse != nil || (fixedBusy && !reduceMotion)
        let elapsed = fixedCollapse ?? (fixedBusy && !circle ? SwipeMotion.collapseMs : collapse)
        label(room: geometry.thumbRoom)
            .opacity(SwipeMotion.labelOpacity(shown))
            .frame(height: height)
            .frame(maxWidth: look.fullWidth ? .infinity : nil)
            .background { surface.modifier(SwipeSurfaceFade(elapsed: showsCircle ? elapsed : 0)) }
            .overlay { GeometryReader { proxy in layers(width: Double(proxy.size.width), progress: shown, busy: isBusy, circle: showsCircle, elapsed: elapsed) } }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frame.global = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { frame.global = $0 }
                })
            .contentShape(look.shape)
            .opacity(disabled ? 0.5 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(look.label)
            .accessibilityAddTraits(isBusy ? [.isButton, .updatesFrequently] : .isButton)
            .accessibilityAction { complete(.keyboard) }
            .modifier(SwipeKeyboard(act: { complete(.keyboard) }))
            // Ends with the busy state it waits for, and with the button when its screen goes.
            .task(id: busyToken) { await holdBusy() }
            // A fill that has not covered the screen yet goes with the button and the action never runs.
            .onDisappear {
                stage?.cancel()
                fill?.cancel()
            }
            .onAppear { probe?.buttons[node.id] = { way in complete(way) } }
    }

    private func label(room: Double) -> some View {
        StyledText(text: look.label, style: look.typography, color: look.labelColor, theme: look.theme, alignment: .center)
            .padding(.horizontal, CGFloat(room))
            .frame(maxWidth: .infinity)
    }

    /// The background, the border and the shadow of the track.
    private var surface: some View {
        look.shape.fill(look.trackFill?.color ?? .clear)
            .overlay {
                if look.borderWidth > 0, let color = look.borderColor {
                    if look.dashedBorder {
                        DashedBorderOverlay(width: look.borderWidth, color: color, radius: look.corners, rightToLeft: context.rightToLeft)
                    } else {
                        look.shape.inset(by: look.borderWidth / 2).stroke(color.color, lineWidth: look.borderWidth)
                    }
                }
            }
            .shadowLayers(look.shadow, shape: look.shape)
    }

    // MARK: Thumb

    private func layers(width: Double, progress: Double, busy: Bool, circle: Bool, elapsed: Double) -> some View {
        let t = SwipeConfirmRules.Track(height: height, width: width, border: look.borderWidth, inset: track.inset)
        return ZStack(alignment: .topLeading) {
            if circle {
                SwipeCircleLayer(
                    elapsed: elapsed, track: t, color: look.thumbFill.color, glyphColor: look.glyphColor.color, glyphSize: look.typography.fontSize,
                    still: reduceMotion)
            } else {
                thumbAndTrail(t, progress: progress, busy: busy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(circle ? .linear(duration: SwipeMotion.collapseMs / 1000) : nil, value: elapsed)
    }

    /// The fill behind the thumb and the thumb: both have the radius of the thumb, concentric with the track.
    private func thumbAndTrail(_ t: SwipeConfirmRules.Track, progress: Double, busy: Bool) -> some View {
        let diameter = CGFloat(SwipeConfirmRules.geometry(t).diameter)
        let start = SwipeConfirmRules.thumbStart(t, progress: progress)
        let strip = SwipeMotion.trail(t, progress: progress)
        let corner = CGFloat(SwipeMotion.thumbRadius(t, radius: look.corners.topStart))
        let top = CGFloat(max(0, t.border) + max(0, t.inset))
        // Placed from the inline start with a leading padding: it mirrors in right-to-left text.
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: corner)
                .fill(look.thumbFill.color)
                .frame(width: CGFloat(strip.width), height: diameter)
                .padding(.leading, CGFloat(strip.start))
                .padding(.top, top)
            ZStack {
                RoundedRectangle(cornerRadius: corner).fill(look.thumbFill.color)
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
            .padding(.leading, CGFloat(start))
            .padding(.top, top)
            .gesture(drag(travel: SwipeConfirmRules.geometry(t).travel))
        }
        .animation(
            dragging || reduceMotion
                ? nil : .timingCurve(0.215, 0.61, 0.355, 1, duration: (busy ? SwipeConfirmRules.completeMs : SwipeConfirmRules.returnMs) / 1000),
            value: progress
        )
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
                    complete(.swipe)
                } else {
                    progress = 0
                }
            }
    }

    // MARK: Acting and the busy state

    /// Runs the action; the thumb then goes to the end and waits, or returns. After a swipe that asks for
    /// the fill the action waits for it instead (`SwipeMotion.sequence`).
    private func complete(_ way: SwipeMotion.Way) {
        guard !disabled, !busy else { return }
        if playsRipple(way) {
            beginRipple()
            return
        }
        let run = context.run(action, node)
        guard SwipeConfirmRules.afterRelease(run.runner) == .busy else {
            progress = 0
            return
        }
        dragging = false
        endPending = false
        phase = .gliding
        progress = 1
        hostTask = run.task
        busyToken += 1
        glideThenCollapse()
    }

    private func playsRipple(_ way: SwipeMotion.Way) -> Bool {
        guard SwipeMotion.readsRipple(node.props), ripples != nil else { return false }
        let type = action["type"]?.stringValue ?? ActionType.none.rawValue
        let handed = ActionCatalog.handed(action, scope: context.scope)
        return SwipeMotion.sequence(
            runner: SwipeConfirmRules.intendedRunner(of: handed), actionType: type, ripple: true, way: way, reducedMotion: reduceMotion
        ).contains(.ripple)
    }

    /// The thumb goes to the end, the button collapses into a circle, and the circle grows over the screen.
    private func beginRipple() {
        dragging = false
        endPending = false
        ripplePending = true
        phase = .gliding
        progress = 1
        glideThenCollapse()
    }

    /// The thumb reaches the end (200 ms), then the button collapses into a circle (600 ms). Under «reduce
    /// motion» the thumb jumps and waits at the end busy.
    private func glideThenCollapse() {
        stage?.cancel()
        stage = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(nanoseconds: UInt64(SwipeConfirmRules.completeMs * 1_000_000))
                guard !Task.isCancelled else { return }
                circle = true
                phase = .collapsing
                collapse = 0
                withAnimation(.linear(duration: SwipeMotion.collapseMs / 1000)) { collapse = SwipeMotion.collapseMs }
                try? await Task.sleep(nanoseconds: UInt64(SwipeMotion.collapseMs * 1_000_000))
                guard !Task.isCancelled else { return }
            }
            if ripplePending {
                ripplePending = false
                launchRipple()
            } else {
                phase = .busy
                if endPending {
                    endPending = false
                    giveBack()
                }
            }
        }
    }

    @MainActor
    private func launchRipple() {
        let global = frame.global
        guard let ripples, global.width > 0 else {
            covered()
            return
        }
        let ring = SwipeMotion.collapse(SwipeConfirmRules.Track(height: height, width: Double(global.width), border: look.borderWidth, inset: track.inset), elapsed: 0).ring
        let spec = SwipeRippleSpec(
            center: CGPoint(x: global.midX, y: global.midY), halo: Double(global.height), core: max(0, Double(global.height) - 2 * ring),
            color: look.thumbFill.color, indicatorColor: look.glyphColor.color, indicatorSize: look.typography.fontSize,
            onCovered: { covered() })
        guard let handle = ripples.start(spec) else {
            covered()
            return
        }
        fill = handle
        phase = .rippling
    }

    /// The screen is covered: the action runs now, with its `track`, once. The button usually leaves with the
    /// screen; one that stays is at rest again under the fading fill.
    private func covered() {
        _ = context.run(action, node)
        fill = nil
        circle = false
        collapse = 0
        phase = .idle
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 0 }
    }

    /// Waits for what ends the busy state: the host's task when it gave one, else the longest wait.
    @MainActor
    private func holdBusy() async {
        guard busy, phase != .rippling else { return }
        let token = busyToken
        if let task = hostTask {
            await task.value
            guard !Task.isCancelled else { return }
            end(token, on: .fulfilled, promise: true)
        } else {
            try? await Task.sleep(nanoseconds: UInt64(SwipeConfirmRules.busyMaxMs * 1_000_000))
            guard !Task.isCancelled else { return }
            end(token, on: .timeout, promise: false)
        }
    }

    /// An event of the busy state; the circle expands and the thumb returns when the rule says so. The
    /// screen changing is the button leaving with its screen.
    private func end(_ token: Int, on event: SwipeConfirmRules.BusyEvent, promise: Bool) {
        guard token == busyToken, busy, SwipeConfirmRules.busyOutcome(event, promise: promise) == .giveBack else { return }
        hostTask = nil
        switch phase {
        case .gliding, .collapsing: endPending = true
        case .busy: giveBack()
        default: break
        }
    }

    /// «Busy» is over: the circle expands back (a thumb that never collapsed has nothing to expand), then the
    /// thumb returns to the start and the button acts again.
    private func giveBack() {
        stage?.cancel()
        guard circle, !reduceMotion else {
            circle = false
            collapse = 0
            phase = .returning
            progress = 0
            return
        }
        phase = .expanding
        withAnimation(.linear(duration: SwipeMotion.collapseMs / 1000)) { collapse = 0 }
        stage = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SwipeMotion.collapseMs * 1_000_000))
            guard !Task.isCancelled else { return }
            circle = false
            phase = .returning
            progress = 0
        }
    }
}

/// Lets a test let go of the thumb of the button below it, as a finger would (a synthesized mouse drag does
/// not reach the gesture of a view hosted off screen).
final class SwipeProbe {
    /// The way to let go of the button, by the id of its node.
    var buttons: [String: (SwipeMotion.Way) -> Void] = [:]

    func release(_ id: String, _ way: SwipeMotion.Way) { buttons[id]?(way) }
}

private struct SwipeProbeKey: EnvironmentKey {
    static let defaultValue: SwipeProbe? = nil
}

extension EnvironmentValues {
    var swipeProbe: SwipeProbe? {
        get { self[SwipeProbeKey.self] }
        set { self[SwipeProbeKey.self] = newValue }
    }
}

/// The frame of the button in global coordinates, kept as the layout reports it.
private final class FrameBox {
    var global = CGRect.zero
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
