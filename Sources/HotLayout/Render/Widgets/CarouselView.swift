import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Everything a carousel needs from the document and the theme, already in points.
struct CarouselSetup {
    var spec: CarouselSpec
    var peek: Double
    var gap: Double
    var padding: Sides
    var vertical: VerticalAlignment
    var rightToLeft: Bool
    var dotSize: Double
    var dotGap: Double
    var indicatorGap: Double
    var dotColor: Color
    /// Where the active stop is remembered; `nil` keeps nothing.
    var memory: CarouselMemory?
    var memoryKey: String
    /// The number data path the carousel tells its stop to (`carousel.stopPath`), the value under it
    /// now and the write of the screen (the session and the host at the same moment).
    var stopPath: String?
    var stopValue: JSONValue?
    var write: ((String, JSONValue) -> Void)?
    /// The timer that takes the carousel to the next stop (`carousel.autoAdvance`); `nil` is none.
    var autoAdvance: CarouselAutoAdvance?
    /// Keyboard focus is on a field inside the carousel: it holds the timer.
    var keyboardFocus = false
}

private struct ViewportKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

private struct OffsetKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

private struct CardWidthsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The notifications that tell whether the app is in front, by platform.
private enum AppActivity {
    #if canImport(UIKit)
    static let resigned = UIApplication.willResignActiveNotification
    static let became = UIApplication.didBecomeActiveNotification
    #else
    static let resigned = NSApplication.willResignActiveNotification
    static let became = NSApplication.didBecomeActiveNotification
    #endif
}

/// What the clock of the timer reads from the view: a plain object, kept up to date by every draw.
private final class AutoAdvanceLive {
    var stops: [Double] = [0]
    var ready = false
    var offset = 0.0
}

/// The offset (from the logical start) the scroll is at now; the scroll target behavior has no
/// way to ask for it.
private final class CurrentOffset {
    var value: Double = 0
}

/// Ends a scroll on a stop: a flick moves one stop on, a slower release goes to the nearest. The
/// stops are offsets from the logical start; a scroll view in right-to-left text counts its
/// offset from the other edge.
@available(iOS 17.0, macOS 14.0, *)
private struct CarouselSnap: ScrollTargetBehavior {
    var stops: [Double]
    var rightToLeft: Bool
    var scale: Double
    var current: CurrentOffset

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard stops.count > 1 else { return }
        let maxScroll = max(0, context.contentSize.width - context.containerSize.width)
        let physical = target.rect.origin.x
        let logical = rightToLeft ? maxScroll - physical : physical
        // The velocity is that of the offset, in points per millisecond: positive moves toward
        // larger physical offsets; in right-to-left those are earlier stops.
        let forwardPhysical = context.velocity.dx > 0
        let index = CarouselRules.releaseStop(
            stops, offset: current.value, landing: logical, speed: abs(Double(context.velocity.dx)) * 1000,
            forward: rightToLeft ? !forwardPhysical : forwardPhysical, threshold: CarouselRules.flickThreshold(scale: scale))
        let stop = stops[index]
        let clamped = min(stop, maxScroll)
        target.rect.origin.x = rightToLeft ? maxScroll - clamped : clamped
    }
}

extension View {
    @ViewBuilder
    fileprivate func carouselSnap(stops: [Double], rightToLeft: Bool, scale: Double, current: CurrentOffset) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            // On the scroll view itself: the behavior of a scroll view is read from the view it
            // modifies, and on the content inside it nothing reads it (the scroll never snapped).
            self.scrollTargetBehavior(CarouselSnap(stops: stops, rightToLeft: rightToLeft, scale: scale, current: current))
        } else {
            #if canImport(UIKit)
            self.background(LegacySnapInstaller(stops: stops, rightToLeft: rightToLeft, scale: scale))
            #else
            self
            #endif
        }
    }
}

/// A row of cards that scrolls sideways, snaps to the stops and shows the position as dots.
/// `card` draws the card `index` at a given box width (`nil`: its natural width).
struct CarouselView<Card: View>: View {
    let setup: CarouselSetup
    let count: Int
    /// A viewport the caller already knows (tests); the view measures its own otherwise.
    var knownViewport: CGFloat?
    @ViewBuilder let card: (Int, Double?) -> Card

    @State private var measuredViewport: CGFloat?
    @State private var widths: [Int: CGFloat] = [:]
    @State private var offset: CGFloat = 0
    @State private var restored = false
    @State private var current = CurrentOffset()
    @State private var stopController = CarouselStopController()
    @State private var driver = CarouselAutoAdvanceDriver()
    @State private var live = AutoAdvanceLive()
    /// True while a finger drags the row; it falls back to false when the gesture is cancelled as well.
    @GestureState private var dragging = false
    @Environment(\.displayScale) private var displayScale
    /// True while a finger or a pointer button is down on the row, even without moving.
    @GestureState private var touching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// The app is in front: it leaves that on a call, the lock screen and the app switcher.
    @State private var appActive = true
    @Environment(\.screenInFront) private var screenInFront

    private static var space: String { "hotlayout.carousel" }

    private var viewport: CGFloat? { knownViewport ?? measuredViewport }

    private var cardWidth: Double? {
        guard let viewport, let perView = setup.spec.perView else { return nil }
        return CarouselRules.cardWidth(viewport: Double(viewport), paddingStart: setup.padding.start, gap: setup.gap, peek: setup.peek, perView: perView)
    }

    private var stops: CarouselRules.Stops {
        let measured = (0..<count).map { widths[$0].map(Double.init) }
        guard let viewport, !measured.contains(where: { $0 == nil }) else {
            return CarouselRules.stops(viewport: 0, paddingStart: 0, paddingEnd: 0, gap: 0, cards: [])
        }
        return CarouselRules.stops(
            viewport: Double(viewport), paddingStart: setup.padding.start, paddingEnd: setup.padding.end,
            gap: setup.gap, cards: measured.compactMap { $0 }
        )
    }

    private var activeStop: Int {
        let stops = stops.stops
        if !restored, setup.stopPath != nil { return CarouselStop.shownStop(setup.stopValue, stopCount: stops.count) }
        if !restored, let remembered = setup.memory?.stop(for: setup.memoryKey) { return min(remembered, stops.count - 1) }
        return CarouselRules.activeStop(stops, offset: Double(offset))
    }

    var body: some View {
        let plan = stops
        let _ = configureStop(plan)
        let dots =
            viewport.map {
                CarouselRules.dotCount(
                    indicator: setup.spec.indicator, stops: plan.stops.count, viewport: Double($0), dotSize: setup.dotSize, dotGap: setup.dotGap)
            } ?? 0
        VStack(spacing: setup.indicatorGap) {
            scroller(plan)
            if dots > 0 { dotRow(count: dots, active: activeStop) }
        }
        .accessibilityElement(children: .contain)
    }

    /// What the controller of the stop reads on every draw (a plain object: no state changes here).
    private func configureStop(_ plan: CarouselRules.Stops) {
        stopController.path = setup.stopPath
        stopController.current = setup.stopValue
        stopController.write = setup.write
        stopController.reducedMotion = reduceMotion
        configureTimer(plan)
    }

    /// What the clock of the timer reads and what holds it.
    private func configureTimer(_ plan: CarouselRules.Stops) {
        driver.configure(setup.autoAdvance)
        live.stops = plan.stops
        live.ready = restored && plan.stops.count > 1
        driver.set(.keyboardFocus, setup.keyboardFocus)
        driver.set(.notShown, !screenInFront || !appActive)
        driver.set(.screenReader, voiceOver)
    }

    private func scroller(_ plan: CarouselRules.Stops) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: setup.vertical, spacing: setup.gap) {
                    ForEach(0..<count, id: \.self) { index in
                        card(index, cardWidth)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(key: CardWidthsKey.self, value: [index: geometry.size.width])
                                })
                    }
                }
                .padding(EdgeInsets(top: setup.padding.top, leading: setup.padding.start, bottom: setup.padding.bottom, trailing: setup.padding.end))
                .background(alignment: .leading) {
                    GeometryReader { geometry in
                        let frame = geometry.frame(in: .named(Self.space))
                        Color.clear.preference(key: OffsetKey.self, value: setup.rightToLeft ? (viewport ?? 0) - frame.maxX : -frame.minX)
                    }
                }
                .overlay(alignment: .leading) { anchors(plan) }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { _ in stopController.personBegan() }
                    .onEnded { _ in stopController.personReleased() },
                including: setup.stopPath == nil ? .subviews : .all
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($touching) { _, state, _ in state = true },
                including: setup.autoAdvance == nil ? .subviews : .all
            )
            .carouselSnap(stops: plan.stops, rightToLeft: setup.rightToLeft, scale: Double(displayScale), current: current)
            .coordinateSpace(name: Self.space)
            .background(GeometryReader { geometry in Color.clear.preference(key: ViewportKey.self, value: geometry.size.width) })
            .onPreferenceChange(ViewportKey.self) { measuredViewport = $0 }
            .onPreferenceChange(CardWidthsKey.self) { widths = $0 }
            .onPreferenceChange(OffsetKey.self) { value in
                guard let value else { return }
                offset = value
                current.value = Double(value)
                live.offset = Double(value)
                if setup.autoAdvance != nil { driver.scrollMoved() }
                stopController.scrolled(to: Double(value))
                if restored { remember(CarouselRules.activeStop(plan.stops, offset: Double(value))) }
            }
            .onChange(of: plan) {
                if restored { stopController.updateStops($0.stops) }
                restore($0, proxy: proxy)
            }
            // The value comes in as the argument: this form of `onChange` calls the closure of the
            // previous draw, whose `setup` still holds the value before the change (the row then
            // followed the stop before, a step behind every write).
            .onChange(of: setup.stopValue) { value in stopController.update(value: value) }
            .onAppear {
                stopController.scrollToStop = { stop, animated in scrollToStop(stop, animated: animated, proxy: proxy) }
                driver.view = { [live] in
                    live.ready ? (active: CarouselRules.activeStop(live.stops, offset: live.offset), stopCount: live.stops.count) : nil
                }
                driver.onStep = { step in autoStep(step, proxy: proxy) }
                restore(plan, proxy: proxy)
            }
            .onChange(of: dragging) { held in if !held { stopController.personReleased() } }
            .onChange(of: touching) { held in driver.set(.held, held) }
            .onReceive(NotificationCenter.default.publisher(for: AppActivity.resigned)) { _ in appActive = false }
            .onReceive(NotificationCenter.default.publisher(for: AppActivity.became)) { _ in appActive = true }
            .task(id: setup.autoAdvance) { await runClock() }
            .onDisappear {
                stopController.cancel()
                driver.cancel()
            }
            .opacity(viewport == nil ? 0 : 1)
        }
    }

    /// The clock of the timer: a tick every 100 ms while the carousel has the field.
    private func runClock() async {
        guard setup.autoAdvance != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(CarouselAutoAdvance.tickMs * 1_000_000))
            if Task.isCancelled { return }
            driver.tick()
        }
    }

    /// The timer takes the row to a stop. What the controller holds is as of the last draw; this closure was
    /// made at the first one.
    private func autoStep(_ step: Int, proxy: ScrollViewProxy) {
        driver.scrollMoved()
        stopController.timerStep(to: step) { stop, animated in scrollToStop(stop, animated: animated, proxy: proxy) }
    }

    /// Empty marks at the stops, so that the scroll can be put back on a remembered stop.
    private func anchors(_ plan: CarouselRules.Stops) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(plan.stops.enumerated()), id: \.offset) { index, stop in
                Color.clear.frame(width: 1, height: 1)
                    .offset(x: setup.rightToLeft ? -stop : stop)
                    .id(index)
            }
        }
        .allowsHitTesting(false)
    }

    private func remember(_ stop: Int) {
        setup.memory?.set(stop, for: setup.memoryKey)
    }

    /// Once the stops are known, puts the scroll on the stop the frame remembers (no animation).
    private func restore(_ plan: CarouselRules.Stops, proxy: ScrollViewProxy) {
        guard !restored, viewport != nil, widths.count == count, count > 0 else { return }
        if setup.stopPath != nil {
            // The value under the path decides where the carousel stands; the memory of the frame
            // does not (the content under the carousel reads the same value).
            if plan.stops.count <= 1 && count > 1 { return }
            restored = true
            stopController.observe(stops: plan.stops)
            return
        }
        let remembered = setup.memory?.stop(for: setup.memoryKey) ?? 0
        // The stops of a plan made before every card was measured are just [0]: wait for the real ones.
        if remembered >= plan.stops.count && plan.stops.count <= 1 { return }
        restored = true
        guard remembered > 0, remembered < plan.stops.count else { return }
        let stop = remembered
        // After the layout pass that measured the cards: a jump made inside it finds no content.
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(stop, anchor: .leading) }
        }
    }

    /// A move of the reader to a stop of the plan; a jump is made after the layout pass that measured the cards.
    private func scrollToStop(_ stop: Int, animated: Bool, proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(stop, anchor: .leading) }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(stop, anchor: .leading) }
            }
        }
    }

    private func dotRow(count: Int, active: Int) -> some View {
        HStack(spacing: setup.dotGap) {
            ForEach(0..<count, id: \.self) { index in
                Circle().fill(setup.dotColor).frame(width: setup.dotSize, height: setup.dotSize)
                    .opacity(index == active ? 1 : CarouselRules.inactiveDotOpacity)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

extension CarouselSetup {
    /// The setup of the carousel of `node`, from the theme the context carries.
    static func make(spec: CarouselSpec, node: DocumentNode, gap: Double, padding: Sides, vertical: VerticalAlignment, context: RenderContext) -> CarouselSetup
    {
        let resolver = context.resolver
        func spacing(_ token: String) -> Double? { resolver.spacing(.string(token)) }
        let stopPath = CarouselStop.path(of: node)
        let autoAdvance = CarouselAutoAdvance.of(node)
        let key = CarouselMemory.key(
            frame: context.frameIndex, screenId: context.screenId,
            state: CarouselRules.stateKey(nodeId: node.id, instancePath: context.instancePath)
        )
        return CarouselSetup(
            spec: spec, peek: CarouselRules.peekPixels(spec.peek, spacing: spacing), gap: gap, padding: padding, vertical: vertical,
            rightToLeft: context.rightToLeft,
            dotSize: spacing(CarouselRules.dotSizeToken) ?? 8, dotGap: spacing(CarouselRules.dotGapToken) ?? 8,
            indicatorGap: spacing(CarouselRules.indicatorGapToken) ?? 8,
            dotColor: (context.theme.coreColor(CarouselRules.dotColorToken)).color,
            memory: context.carousels, memoryKey: key,
            stopPath: stopPath, stopValue: stopPath.flatMap { context.scope[$0] }, write: context.write,
            autoAdvance: autoAdvance, keyboardFocus: autoAdvance != nil && CarouselAutoAdvance.holdsFocus(node, focus: context.form?.focus?.wrappedValue)
        )
    }
}

extension RowView {
    /// The placement of a card: natural, or the box width `perView` gave it.
    static func cardPlacement(width: Double?) -> Placement {
        var placement = Placement.natural
        placement.cardWidth = width
        return placement
    }
}

#if canImport(UIKit)
import UIKit

/// iOS 16 has no scroll target behavior. A hidden view finds the `UIScrollView` SwiftUI built
/// around it and, when a finger lifts, ends the deceleration on the stop the throw would reach.
private struct LegacySnapInstaller: UIViewRepresentable {
    var stops: [Double]
    var rightToLeft: Bool
    var scale: Double

    func makeCoordinator() -> LegacySnap { LegacySnap() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.stops = stops
        context.coordinator.rightToLeft = rightToLeft
        context.coordinator.scale = scale
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
    }
}

private final class LegacySnap: NSObject {
    var stops: [Double] = []
    var rightToLeft = false
    var scale = 1.0
    private weak var scrollView: UIScrollView?

    func attach(from view: UIView) {
        guard scrollView == nil else { return }
        var ancestor = view.superview
        while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
        guard let found = ancestor as? UIScrollView else { return }
        scrollView = found
        found.decelerationRate = .fast
        found.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
    }

    @objc private func pan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled, stops.count > 1, let scrollView else { return }
        let maxScroll = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let velocity = pan.velocity(in: scrollView).x
        // Offset from the logical start; a right-to-left scroll view counts from the other edge
        // in this reader (its content is mirrored, the offset is physical).
        let physical = scrollView.contentOffset.x - scrollView.adjustedContentInset.left
        let logical = rightToLeft ? maxScroll - physical : physical
        // The finger moves with the content, so a leftward drag (negative velocity) advances.
        let direction = rightToLeft ? -1.0 : 1.0
        let projected = logical - direction * Double(velocity) * 0.12
        // The finger moves with the content: a leftward drag (negative velocity) advances.
        let index = CarouselRules.releaseStop(
            stops, offset: logical, landing: projected, speed: abs(Double(velocity)), forward: direction * Double(velocity) < 0,
            threshold: CarouselRules.flickThreshold(scale: scale))
        let stop = min(stops[index], maxScroll)
        let target = rightToLeft ? maxScroll - stop : stop
        scrollView.setContentOffset(CGPoint(x: target + scrollView.adjustedContentInset.left, y: scrollView.contentOffset.y), animated: true)
    }
}
#endif
