import SwiftUI

/// How far the body of the layer is scrolled from its top. The scroll view of the screen body
/// reports it as the user scrolls (`reportsScrollTop`); the drag of a sheet asks (a drag moves
/// the sheet only at the top, `x-sheetDismiss.contentScrolled`).
final class ModalScrollSink {
    var scrolled: Double = 0
}

private struct ModalScrollSinkKey: EnvironmentKey {
    static let defaultValue: ModalScrollSink? = nil
}

extension EnvironmentValues {
    var modalScrollSink: ModalScrollSink? {
        get { self[ModalScrollSinkKey.self] }
        set { self[ModalScrollSinkKey.self] = newValue }
    }
}

/// Places its one subview as `ModalRules.box` says: a sheet at the bottom of the area, a window
/// in the middle. The height is that of the content, no taller than the room; taller content
/// scrolls inside (the subview is proposed the smaller height).
struct ModalBoxLayout: Layout {
    let placement: JSONValue?
    let margin: Double

    private func box(_ subviews: Subviews, in size: CGSize) -> ModalRules.Box {
        let width = WideChrome.modalLayerWidth(placement: placement, areaWidth: Double(size.width), margin: margin)
        let ideal = subviews.first?.sizeThatFits(ProposedViewSize(width: CGFloat(width), height: nil)).height ?? 0
        return WideChrome.modalLayerBox(
            placement: placement, width: Double(size.width), height: Double(size.height), contentHeight: Double(ideal), margin: margin
        ).box
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let rect = box(subviews, in: bounds.size)
        content.place(
            at: CGPoint(x: bounds.minX + CGFloat(rect.x), y: bounds.minY + CGFloat(rect.y)),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: CGFloat(rect.width), height: CGFloat(rect.height))
        )
    }
}

/// One modal layer: the scrim and the sheet or the window. The page and the layers below are
/// drawn by `ModalStack`; this view is only the layer itself.
struct ModalLayerView<Content: View>: View {
    let content: Content
    let shape: WideChrome.ModalShape
    let placement: JSONValue?
    let margin: Double
    let dismissible: Bool
    let isTop: Bool
    /// Blur of the layer's own picture: the layers above it blur it.
    let blurredBy: Double
    /// The same without the layer that comes or goes with the motion of the step, and the motion.
    var blurredByWithout: Double?
    var stepMotion: StackMotion?
    /// This layer comes or goes with the motion of the step.
    var layerMotion: LayerMotion?
    /// The layer has already left the stack and is drawn only while it goes: it takes no touch and no focus.
    var ghost = false
    /// What the host's window leaves of the area: the layer lies in the area below the top inset, a window also above the bottom one.
    let insets: ScreenInsets
    let dismiss: (_ animated: Bool) -> Void

    /// `exiting` starts a layer that is already sliding out (`ModalStack` never does; a test does).
    init(
        content: Content, shape: WideChrome.ModalShape, placement: JSONValue?, margin: Double, dismissible: Bool, isTop: Bool, blurredBy: Double,
        insets: ScreenInsets = ScreenInsets(), exiting: Bool = false, blurredByWithout: Double? = nil, stepMotion: StackMotion? = nil,
        layerMotion: LayerMotion? = nil, ghost: Bool = false, dismiss: @escaping (_ animated: Bool) -> Void
    ) {
        self.content = content
        self.shape = shape
        self.placement = placement
        self.margin = margin
        self.dismissible = dismissible
        self.isTop = isTop
        self.blurredBy = blurredBy
        self.insets = insets
        self.blurredByWithout = blurredByWithout
        self.stepMotion = stepMotion
        self.layerMotion = layerMotion
        self.ghost = ghost
        self.dismiss = dismiss
        _exiting = State(initialValue: exiting)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var sheetHeight: CGFloat = 0
    @State private var dragging = false
    /// The sheet has been dragged away and slides out.
    @State private var exiting: Bool
    @State private var origin: (scrolled: Double, started: Bool)?
    @State private var samples: [(time: Double, y: Double)] = []
    @State private var sink = ModalScrollSink()
    /// How far the on-screen keyboard reaches into the layer's area: the sheet or window rides above it.
    @State private var keyboard = 0.0

    /// A window in the middle, whether the author asked for it or a sheet became one in a wide place.
    private var window: Bool { shape != .sheet }

    private var visibleShare: Double {
        offset <= 0 || sheetHeight <= 0 ? 1 : max(0, min(1, 1 - Double(offset / sheetHeight)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(ModalRules.scrimOpacity * visibleShare)
                .modifier(ScrimOpacity(motion: layerMotion?.motion ?? LayerMotion.rest.motion, resting: 1))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if dismissible { dismiss(true) } }
            ModalBoxLayout(placement: placement, margin: margin) {
                content
                    // The motion of the step: the sheet's own height, the window's own centre.
                    .modifier(FrameGeometry(motion: layerMotion ?? LayerMotion.rest, areaWidth: 0))
                    .modifier(FrameOpacity(motion: layerMotion ?? LayerMotion.rest))
                    .environment(\.modalScrollSink, sink)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.onAppear { sheetHeight = proxy.size.height }.onChange(of: proxy.size.height) { sheetHeight = $0 }
                        })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, CGFloat(insets.top))
            .padding(.bottom, keyboard > 0 ? CGFloat(keyboard) : window ? CGFloat(insets.bottom) : 0)
            .environment(\.layerAboveKeyboard, keyboard > 0)
            .modifier(StackBlur(without: blurredByWithout ?? blurredBy, with: blurredBy, motion: stepMotion))
            .offset(y: offset)
            .modifier(SheetDrag(enabled: !window && dismissible && isTop && !exiting && !ghost, gesture: dragGesture))
        }
        // Measured on the area of the layer, which the lift does not move.
        .keyboardOverlap($keyboard)
        .allowsHitTesting(isTop && !exiting && !ghost)
        .accessibilityAddTraits(isTop && !ghost ? .isModal : [])
        .accessibilityAction(.escape) {
            if ModalRules.escapeSteps(key: "Escape", repeating: false, modalOnTop: isTop, topDismissible: dismissible) > 0 { dismiss(true) }
        }
        .environment(\.screenInFront, isTop && !ghost)
        // Last: what is added to the layer after it would show it to a screen reader again.
        .accessibilityHidden(!isTop || ghost)
        // The layer goes once it has slid out; a layer that is gone first closes nothing.
        .task(id: exiting) { await leaveAfterExit() }
    }

    @MainActor
    private func leaveAfterExit() async {
        guard exiting else { return }
        let delay = reduceMotion ? 0 : Double(ModalRules.exitMotion.durationMs) / 1000
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        dismiss(false)
    }

    private func animation(_ motion: ModalRules.Motion) -> Animation? {
        reduceMotion ? nil : .timingCurve(motion.curve[0], motion.curve[1], motion.curve[2], motion.curve[3], duration: Double(motion.durationMs) / 1000)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let dy = Double(value.translation.height)
                if origin == nil {
                    origin = (sink.scrolled, false)
                    samples = []
                }
                guard let begin = origin else { return }
                if !begin.started {
                    guard
                        ModalRules.dragStarts(
                            sheet: true, dismissible: dismissible, scrolled: begin.scrolled, dy: dy, dx: Double(value.translation.width), onHandle: false)
                    else { return }
                    origin = (begin.scrolled, true)
                    dragging = true
                }
                offset = max(0, value.translation.height)
                samples.append((Date().timeIntervalSinceReferenceDate, Double(value.translation.height)))
            }
            .onEnded { _ in released() }
    }

    private func released() {
        defer {
            origin = nil
            samples = []
        }
        guard dragging else { return }
        dragging = false
        let outcome = ModalRules.dragOutcome(sheetHeight: Double(sheetHeight), dragged: Double(offset), velocity: ModalRules.velocity(samples: samples))
        switch outcome {
        case .return:
            withAnimation(animation(ModalRules.returnMotion)) { offset = 0 }
        case .dismiss:
            exiting = true
            withAnimation(animation(ModalRules.exitMotion)) { offset = sheetHeight }
        }
    }
}

private struct SheetDrag<G: Gesture>: ViewModifier {
    let enabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if enabled { content.simultaneousGesture(gesture) } else { content }
    }
}

/// One modal layer of the stack: how it stands and closes; its content comes from `ModalStack.layer`.
struct ModalStackLayer: Identifiable {
    /// The index of the frame in the stack.
    let id: Int
    let shape: WideChrome.ModalShape
    let placement: JSONValue?
    let blur: Int?
    let dismissible: Bool
    /// The layer has already left the stack and is drawn only while it goes (the stack lists it last).
    var ghost = false
}

/// The page and the modal layers over it. Every layer is its own stacking context and the page
/// and the layers below it are inert: the touch and the screen reader reach only the top layer.
/// Under a layer the picture is blurred by the layer's `backdropBlur`, the scrim lies over the blur.
///
/// While a step of the stack moves a layer (`motion`), the layer that comes is the top one, and the
/// one that goes is listed last as a `ghost`: it keeps its place in the list so that it goes as the view it was.
struct ModalStack<Page: View, Layer: View>: View {
    let layers: [ModalStackLayer]
    let margin: Double
    var insets = ScreenInsets()
    var motion: StackMotion?
    /// The whole stack has gone (it is drawn only while a page motion plays): it takes no touch and is
    /// hidden from assistive technology. Said by each part and not by the stack as a whole: an explicit
    /// "not hidden" on the stack would stand over what a layer inside it hides.
    var gone = false
    /// `animated` is false after the sheet has already left by a drag.
    let dismiss: (_ animated: Bool) -> Void
    @ViewBuilder let page: () -> Page
    @ViewBuilder let layer: (ModalStackLayer) -> Layer

    private var real: [ModalStackLayer] { layers.filter { !$0.ghost } }

    /// The layer that comes or goes with the motion of the step.
    private var movingId: Int? {
        guard let plan = motion?.plan, plan.motion.isLayer else { return nil }
        return plan.motion.isLayerIn ? real.last?.id : layers.first { $0.ghost }?.id
    }

    private func blur(of entries: some Sequence<ModalStackLayer>) -> Double {
        ModalRules.combinedBlur(entries.compactMap(\.blur))
    }

    var body: some View {
        let moving = movingId
        let stayed = layers.filter { $0.id != moving }
        let realCount = real.count
        ZStack {
            page()
                .modifier(StackBlur(without: blur(of: stayed), with: blur(of: layers), motion: moving == nil ? nil : motion, opaque: true))
                .allowsHitTesting(realCount == 0 && !gone)
                .accessibilityHidden(realCount > 0 || gone)
                .environment(\.screenInFront, realCount == 0 && !gone)
            ForEach(Array(layers.enumerated()), id: \.element.id) { index, entry in
                let above = layers.dropFirst(index + 1)
                ModalLayerView(
                    content: layer(entry),
                    shape: entry.shape,
                    placement: entry.placement,
                    margin: margin,
                    dismissible: entry.dismissible,
                    isTop: !gone && !entry.ghost && index == realCount - 1,
                    blurredBy: blur(of: above),
                    insets: insets,
                    blurredByWithout: blur(of: above.filter { $0.id != moving }),
                    stepMotion: moving == nil ? nil : motion,
                    layerMotion: entry.id == moving ? motion.map { LayerMotion(motion: $0, incoming: $0.plan.motion.isLayerIn) } : nil,
                    ghost: entry.ghost,
                    dismiss: dismiss
                )
                .zIndex(Double(index + 1))
            }
        }
    }
}

private struct LayerAboveKeyboardKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The layer around the screen has been lifted above the keyboard: the screen needs no bottom inset of the platform.
    var layerAboveKeyboard: Bool {
        get { self[LayerAboveKeyboardKey.self] }
        set { self[LayerAboveKeyboardKey.self] = newValue }
    }
}
